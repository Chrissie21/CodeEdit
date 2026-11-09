#!/bin/bash
# Build with modern Xcode; the resulting app still needs testing on Ventura.
set -euo pipefail

OUTPUT_DIR="${1:?Usage: build_ventura.sh OUTPUT_DIR}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
BUILD_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/codeedit-ventura-derived-data"

{
    git rev-parse HEAD
    sw_vers
    xcodebuild -version
    xcrun swift --version
    shasum -a 256 CodeEdit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
} > "$OUTPUT_DIR/build-environment.txt"

XCODEBUILD_ARGS=(
    -project CodeEdit.xcodeproj
    -scheme CodeEdit
    -configuration Debug
    -destination 'platform=macOS,arch=x86_64'
    -derivedDataPath "$BUILD_DIR"
    -onlyUsePackageVersionsFromResolvedFile
    -skipPackagePluginValidation
    ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
    CODE_SIGNING_ALLOWED=NO
)

# Clean normal build products so a local rerun cannot retain injected test
# frameworks. Preserve this app before the test action modifies its host bundle.
xcodebuild "${XCODEBUILD_ARGS[@]}" clean build 2>&1 | tee "$OUTPUT_DIR/build.log"
APP_DIR="$(mktemp -d "$BUILD_DIR/ventura-product.XXXXXX")"
APP_PATH="$APP_DIR/CodeEdit.app"
ditto "$BUILD_DIR/Build/Products/Debug/CodeEdit.app" "$APP_PATH"

xcodebuild "${XCODEBUILD_ARGS[@]}" \
    -resultBundlePath "$OUTPUT_DIR/compatibility-tests.xcresult" \
    -only-testing:CodeEditTests/OnChangeCompatibilityTests \
    -only-testing:CodeEditTests/TerminalScrollerLayoutTests \
    test 2>&1 | tee "$OUTPUT_DIR/tests.log"

# Exercise the dependency's programmatic view loading, including private find
# and suggestion controllers, in its own test target on the modern build host.
SOURCE_EDITOR_PATH="$BUILD_DIR/SourcePackages/checkouts/CodeEditSourceEditor"
if [[ ! -f "$SOURCE_EDITOR_PATH/Package.swift" ]]; then
    SOURCE_EDITOR_PATH="$BUILD_DIR/SourcePackages/checkouts/codeeditsourceeditor"
fi
xcrun swift test \
    --package-path "$SOURCE_EDITOR_PATH" \
    --scratch-path "$BUILD_DIR/source-editor-tests" \
    --skip-update \
    --filter ViewLoadingTests 2>&1 | tee "$OUTPUT_DIR/source-editor-tests.log"

# Check every bundled Mach-O, not just the main executable: a framework can
# independently require a newer macOS or import the missing Dispatch symbol.
python3 - "$APP_PATH" <<'PY' 2>&1 | tee "$OUTPUT_DIR/binary-checks.log"
import pathlib
import re
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
if not app.is_dir():
    raise SystemExit(f"Missing app: {app}")
magics = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe",
    "cafebabe", "bebafeca", "cafebabf", "bfbafeca"
)}
missing_symbol = "_$sSo17OS_dispatch_queueC8DispatchE12asyncAndWait7executexxyKXE_tKlF"
checked = 0
for binary in sorted(app.rglob("*")):
    if not binary.is_file() or binary.is_symlink():
        continue
    with binary.open("rb") as stream:
        if stream.read(4) not in magics:
            continue
    subprocess.run(["lipo", str(binary), "-verify_arch", "x86_64"], check=True)
    build = subprocess.check_output(
        ["xcrun", "vtool", "-arch", "x86_64", "-show-build", str(binary)], text=True
    )
    # LC_BUILD_VERSION also reports the linker tool's version; only minos is
    # the deployment minimum. Older Mach-O files use LC_VERSION_MIN_MACOSX.
    field = "minos" if "LC_BUILD_VERSION" in build else "version"
    versions = re.findall(rf"^\s*{field}\s+(\d+)\.(\d+)", build, re.MULTILINE)
    if not versions or any(tuple(map(int, version)) > (13, 0) for version in versions):
        raise SystemExit(f"Unsupported deployment version: {binary}\n{build}")
    imports = subprocess.check_output(["nm", "-arch", "x86_64", "-u", str(binary)], text=True)
    if missing_symbol in imports:
        raise SystemExit(f"Unavailable Dispatch import remains: {binary}")
    checked += 1
    print(f"PASS {binary.relative_to(app)}: Intel, minimum OS <= 13.0, no known bad Dispatch import")
if not checked:
    raise SystemExit("No Mach-O binaries were checked")
print(f"Checked {checked} binaries. Runtime verification on Ventura is still required.")
PY

# Preserve executable permissions and framework symlinks inside the artifact.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_DIR/CodeEdit-Ventura-x86_64.zip"
shasum -a 256 "$OUTPUT_DIR/CodeEdit-Ventura-x86_64.zip" > "$OUTPUT_DIR/app-sha256.txt"
printf '%s\n' 'Unsigned development build; not notarized. Test on Ventura before claiming compatibility.' \
    > "$OUTPUT_DIR/README.txt"
