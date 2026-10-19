# One obvious command per question (spec §9.3). Targets marked [linux] also run in the Linux cloud sessions.

CORE_PACKAGE := Packages/ScratchCore

# App build settings. Every xcodebuild call uses the same DerivedData folder, so the built app is always at
# $(DERIVED_DATA)/Build/Products/Debug/Scratch.app.
APP_PROJECT := App/Scratch.xcodeproj
DERIVED_DATA := build/DerivedData
DESTINATION := platform=macOS,arch=arm64

.PHONY: core-test lint format script-test ci-wait project app-build app-test screenshots run

# [linux] Run the ScratchCore tests.
core-test:
	swift test --package-path $(CORE_PACKAGE)

# [linux] Check formatting. Fails on any difference.
lint:
	swift format lint --strict --recursive Packages App

# [linux] Rewrite files to the house format.
format:
	swift format format --in-place --recursive Packages App

# [linux] Run the tests for the scripts in scripts/ (the ci-results loop). Needs bash, git and python3.
script-test:
	bash scripts/tests/test-ci-scripts.sh

# [linux] Wait for CI results on the ci-results branch: make ci-wait SHA=<sha> [JOBS="linux macos"].
# CI_WAIT_TIMEOUT (seconds) bounds one wait. make exits 2 on any failure, so read the last line of output to tell a
# failed job from a timeout (see scripts/ci-wait.sh).
ci-wait:
	@test -n "$(SHA)" || { echo 'usage: make ci-wait SHA=<sha> [JOBS="linux macos"]' >&2; exit 64; }
	scripts/ci-wait.sh $(SHA) $(JOBS)

# [macOS] Generate App/Scratch.xcodeproj from App/project.yml (needs XcodeGen: brew install xcodegen). The project is
# generated, never committed. VERSION feeds the app's marketing version.
project:
	cd App && SCRATCH_VERSION=$$(cat ../VERSION) xcodegen

# [macOS] Build the app (Debug) into build/DerivedData.
app-build: project
	xcodebuild build -project $(APP_PROJECT) -scheme Scratch -destination '$(DESTINATION)' \
	  -derivedDataPath $(DERIVED_DATA)

# [macOS] Build the app and run its hosted unit tests and UI tests. The result bundle is build/results/app.xcresult.
# Tests get a time limit each, so that a stuck UI test fails instead of hanging the job. The screenshot tests are
# skipped: `make screenshots` runs them, once per CI job.
app-test: project
	rm -rf build/results/app.xcresult
	mkdir -p build/results
	xcodebuild test -project $(APP_PROJECT) -scheme Scratch -destination '$(DESTINATION)' \
	  -derivedDataPath $(DERIVED_DATA) -resultBundlePath build/results/app.xcresult \
	  -parallel-testing-enabled NO -test-timeouts-enabled YES \
	  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 \
	  -skip-testing:ScratchUITests/ScreenshotTests

# The screenshots `make screenshots` writes, one PNG each into build/screenshots/. These names are the ones in
# ScreenshotTests (a test attaches its screenshot under its name) and CI publishes them to ci-results.
SCREENSHOT_NAMES := typical-light typical-dark empty-light huge-note-light

# [macOS] Render the key screens to PNG files in build/screenshots/<name>.png (SCREENSHOT_NAMES): run ScreenshotTests
# only, export the attachments from the result bundle (build/results/screenshots.xcresult) into build/screenshots/raw,
# then name each file from the exported manifest.json. Look at the PNGs to check a visual change.
screenshots: project
	rm -rf build/results/screenshots.xcresult build/screenshots
	mkdir -p build/results build/screenshots
	xcodebuild test -project $(APP_PROJECT) -scheme Scratch -destination '$(DESTINATION)' \
	  -derivedDataPath $(DERIVED_DATA) -resultBundlePath build/results/screenshots.xcresult \
	  -parallel-testing-enabled NO -test-timeouts-enabled YES \
	  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 \
	  -only-testing:ScratchUITests/ScreenshotTests
	xcrun xcresulttool export attachments --path build/results/screenshots.xcresult \
	  --output-path build/screenshots/raw
	python3 scripts/name-screenshots.py build/screenshots/raw build/screenshots $(SCREENSHOT_NAMES)

# [macOS] Build the app and open it on a named fixture in a throwaway data directory:
# make run FIXTURE=<empty|typical|huge-note|many-notes>. It never touches real data.
run:
	@test -n "$(FIXTURE)" || { echo 'usage: make run FIXTURE=<empty|typical|huge-note|many-notes>' >&2; exit 64; }
	$(MAKE) app-build
	open -n $(DERIVED_DATA)/Build/Products/Debug/Scratch.app --args -ScratchFixture $(FIXTURE)
