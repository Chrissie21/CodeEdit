# Testing Ventura compatibility

The app targets macOS 13 while retaining the newer-system UI paths. Build with modern Xcode; Xcode 15.2 on Ventura cannot read this project or compile its current Swift dependencies. The manual workflow uses Xcode 26.1.1 on GitHub's `macos-15-intel` runner to produce an Intel development app for testing here.

## Run the build in a fork

After reviewing and publishing the compatibility branch to your fork:

1. Enable GitHub Actions in the fork.
2. Ensure `.github/workflows/ventura-build.yml` exists on the fork's default branch. GitHub requires this for manual dispatch. For an isolated testing fork, the compatibility branch can be its default branch; upstream is unaffected.
3. Under **Actions → Build for Ventura testing → Run workflow**, select the compatibility branch.
4. Download the run's artifact. It contains a second ZIP preserving the app's executable permissions and framework symlinks, build logs, test results and a SHA-256 checksum.

The workflow only reads repository contents. It needs no signing certificate or deployment credentials and does not publish a release. Artifacts expire after seven days. Standard public-repository runners are free; artifact storage still follows account limits.

The workflow first makes a clean app build and saves a copy before Xcode injects its test frameworks into the host app. It then compiles the test targets, runs `OnChangeCompatibilityTests` and `TerminalScrollerLayoutTests` on the newer runner, and verifies each bundled Mach-O in the saved app has an Intel slice, a deployment minimum no newer than macOS 13.0, and no reference to the known missing generic Dispatch `asyncAndWait` symbol. Those checks do not replace testing on Ventura or prove every imported API is available there. Logs are uploaded even if the build fails.

The four observation tests and three terminal layout tests also run in isolation on Ventura using the exact production sources, XCTest files and pinned SwiftTerm source. They verify the older-system observation path and that resizing does not repeatedly reattach the frontmost scrollbar while preserving its geometry and genuine reordering. This is not the full app test suite.

## Verify the app on Ventura

Extract into a separate test directory. Keep the installed release intact. The artifact is unsigned and not notarized; local development signing or launch approval may be needed before testing. Record any signing/entitlement differences, since a development launch does not establish signed-release permission behavior.

Check launch, folder/file opening, editing/saving, highlighting, completion and jump-to-definition, find/replace, tab ordering/history/restoration, terminal/tasks, source control, notifications, settings, and navigator/inspector controls. Restart and reopen the workspace to check persistence. Repeat relevant checks on newer macOS to verify its existing UI behavior.

In particular, verify extension selection after the first extension appears and tab-count animations; these observers use both previous and new values. Check that observers do not fire merely because views appear or unrelated state redraws them.

SourceEditor temporarily points to the compatibility branch in the user fork. It includes upstream PR #356 (the missing Dispatch symbol) plus the programmatic-view fix for issue #362: editor/find/suggestion controllers create their own views, and scroll/find layout is configured before constraints are activated. The pipeline runs the dependency's three `ViewLoadingTests` separately, covering automatic controller loading and nonzero editor layout. Prefer an upstream tagged release containing these fixes when one is available; the temporary fork reference is an integration dependency, not an upstream release.

## Build locally on a suitable modern Mac

Select Xcode 26.1.1 (or validate another suitable version), then run from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode_26.1.1.app/Contents/Developer \
  bash .github/scripts/build_ventura.sh /tmp/codeedit-ventura-artifacts
```

GitHub runner software changes over time. If the selected Xcode path is removed, choose an installed version and repeat build and runtime verification rather than silently switching toolchains.
