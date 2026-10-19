# One obvious command per question (spec §9.3). Targets marked [linux] also run in the Linux cloud sessions.

CORE_PACKAGE := Packages/ScratchCore

# App build settings. Every xcodebuild call uses the same DerivedData folder, so the built app is always at
# $(DERIVED_DATA)/Build/Products/Debug/Scratch.app.
APP_PROJECT := App/Scratch.xcodeproj
DERIVED_DATA := build/DerivedData
DESTINATION := platform=macOS,arch=arm64

.PHONY: core-test lint format script-test ci-wait project app-build app-test screenshots run perf perf-baseline

# [linux] Run the ScratchCore tests.
core-test:
	swift test --package-path $(CORE_PACKAGE)

# [linux] Check formatting. Fails on any difference.
lint:
	swift format lint --strict --recursive Packages App

# [linux] Rewrite files to the house format.
format:
	swift format format --in-place --recursive Packages App

# [linux] Run the tests for the scripts in scripts/ (the ci-results loop and the performance scripts). Needs bash, git
# and python3.
script-test:
	bash scripts/tests/test-ci-scripts.sh
	bash scripts/tests/test-perf-check.sh
	bash scripts/tests/test-perf-extract.sh

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

# [macOS] Run the performance tests (the ScratchPerf scheme, Release build): launch, keystroke, scrolling and note
# switching on the huge-note and typical fixtures (spec §7). The result bundle is build/results/perf.xcresult. Turn it
# into numbers with `python3 scripts/perf-extract.py build/results/perf.xcresult build/results/perf.json`, and compare
# them with the stored baseline using scripts/perf-check.py. TEXTKIT=1|2 starts the app on that TextKit
# (-ScratchTextKit, passed by the tests through the TEST_RUNNER_SCRATCH_TEXTKIT environment variable). Without it the
# app picks its own. The flag is only passed when TEXTKIT is not empty: an empty value is a launch error.
# The test time allowances are wide because a test types or scrolls through a 10,000-line note.
perf: project
	rm -rf build/results/perf.xcresult
	mkdir -p build/results
	$(if $(TEXTKIT),TEST_RUNNER_SCRATCH_TEXTKIT=$(TEXTKIT)) xcodebuild test -project $(APP_PROJECT) -scheme ScratchPerf \
	  -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) -resultBundlePath build/results/perf.xcresult \
	  -parallel-testing-enabled NO -test-timeouts-enabled YES \
	  -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 600

# [macOS] Record this machine's numbers as the new baseline (perf/baseline.json). CI compares every run with that file,
# and a result more than 20% slower fails the job, so record it from a CI run (ci-results/<sha>/macos/perf/results.json)
# and not from a laptop. See AGENTS.md.
perf-baseline: perf
	python3 scripts/perf-extract.py build/results/perf.xcresult perf/baseline.json
