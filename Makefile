# One obvious command per question (spec §9.3). Targets marked [linux] also run in the Linux cloud sessions.

CORE_PACKAGE := Packages/ScratchCore
CODE_PACKAGE := Packages/ScratchCode

# App build settings. Every xcodebuild call uses the same DerivedData folder, so the built app is always at
# $(DERIVED_DATA)/Build/Products/Debug/Scratch.app.
APP_PROJECT := App/Scratch.xcodeproj
DERIVED_DATA := build/DerivedData
DESTINATION := platform=macOS,arch=arm64

.PHONY: core-test lint format script-test ci-wait project app-build app-test screenshots run perf perf-baseline release-zip release-dmg

# [linux] Run the tests of both packages: ScratchCore, then ScratchCode (tree-sitter highlighting and code detection).
# The first run of ScratchCode fetches its dependencies from GitHub and compiles the grammars.
core-test:
	swift test --package-path $(CORE_PACKAGE)
	swift test --package-path $(CODE_PACKAGE)

# [linux] Check formatting. Fails on any difference.
lint:
	swift format lint --strict --recursive Packages App

# [linux] Rewrite files to the house format.
format:
	swift format format --in-place --recursive Packages App

# [linux] Run the tests for the scripts in scripts/ (the ci-results loop, the performance scripts, the version bump
# check, the release notes and the release DMG check). Needs bash, git and python3.
script-test:
	bash scripts/tests/test-ci-scripts.sh
	bash scripts/tests/test-perf-check.sh
	bash scripts/tests/test-perf-extract.sh
	bash scripts/tests/test-version-bump.sh
	bash scripts/tests/test-release-notes.sh
	bash scripts/tests/test-release-dmg.sh

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
SCREENSHOT_NAMES := typical-light typical-dark empty-light huge-note-light search-light recently-deleted-light \
  formatting-light formatting-dark code-light code-dark

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
# make run FIXTURE=<empty|typical|huge-note|many-notes|recently-deleted|formatting|code|attachments>. It never touches real data.
run:
	@test -n "$(FIXTURE)" || { echo 'usage: make run FIXTURE=<empty|typical|huge-note|many-notes|recently-deleted|formatting|code|attachments>' >&2; exit 64; }
	$(MAKE) app-build
	open -n $(DERIVED_DATA)/Build/Products/Debug/Scratch.app --args -ScratchFixture $(FIXTURE)

# [macOS] Run the performance tests (the ScratchPerf scheme, Release build): launch, keystroke, scrolling and note
# switching on the huge-note and typical fixtures (spec §7). The result bundle is build/results/perf.xcresult. Turn it
# into numbers with `python3 scripts/perf-extract.py build/results/perf.xcresult build/results/perf.json`, and compare
# them with the stored baseline using scripts/perf-check.py (CI does both). The test time allowances are wide because
# a test types or scrolls through a 10,000-line note.
perf: project
	rm -rf build/results/perf.xcresult
	mkdir -p build/results
	xcodebuild test -project $(APP_PROJECT) -scheme ScratchPerf \
	  -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) -resultBundlePath build/results/perf.xcresult \
	  -parallel-testing-enabled NO -test-timeouts-enabled YES \
	  -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 600

# [macOS] Record this machine's numbers as the new baseline (perf/baseline.json). CI compares every run with that file,
# and a result more than 20% slower fails the job, so record it from a CI run (ci-results/<sha>/macos/perf/results.json)
# and not from a laptop. See AGENTS.md.
perf-baseline: perf
	python3 scripts/perf-extract.py build/results/perf.xcresult perf/baseline.json

# The release zip is named after VERSION (spec section 9.6). It lands in build/release/.
RELEASE_DIR := build/release
RELEASE_VERSION := $(strip $(shell cat VERSION))

# [macOS] Build the Release app into build/release/Scratch.app and zip it to build/release/Scratch-<VERSION>.zip, the
# file the release workflow attaches to a GitHub Release (.github/workflows/release.yml). The build is ad-hoc signed
# (CODE_SIGN_IDENTITY "-" in App/project.yml, docs/decisions/0002). scripts/check-release-zip.sh then unpacks the zip
# and checks what a user would get: the version, the bundle identifier, arm64 only, and a valid ad-hoc signature. CI
# runs this on every push, so that a broken release shows up on the branch and not on the first merge to main.
release-zip: project
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	xcodebuild build -project $(APP_PROJECT) -scheme Scratch -configuration Release -destination '$(DESTINATION)' \
	  -derivedDataPath $(DERIVED_DATA)
	ditto $(DERIVED_DATA)/Build/Products/Release/Scratch.app $(RELEASE_DIR)/Scratch.app
	ditto -c -k --keepParent $(RELEASE_DIR)/Scratch.app $(RELEASE_DIR)/Scratch-$(RELEASE_VERSION).zip
	bash scripts/check-release-zip.sh $(RELEASE_DIR)/Scratch-$(RELEASE_VERSION).zip $(RELEASE_VERSION)

# [macOS] Make build/release/Scratch-<VERSION>.dmg from the app that `make release-zip` left in build/release: a disk
# image whose window shows Scratch.app and an Applications link to drag it onto (docs/decisions/0005). The app is copied
# with ditto, which keeps its ad-hoc signature. When build/release/Scratch.app is not there yet, release-zip runs first.
# scripts/check-release-dmg.sh then attaches the image read-only and checks what a user would get. The release workflow
# attaches this file next to the zip, and CI runs this after release-zip. hdiutil create fails now and then on GitHub's
# Macs ("Resource busy"), so it is tried up to three times.
release-dmg:
	@test -d $(RELEASE_DIR)/Scratch.app || $(MAKE) release-zip
	rm -rf $(RELEASE_DIR)/dmg-staging $(RELEASE_DIR)/Scratch-$(RELEASE_VERSION).dmg
	mkdir -p $(RELEASE_DIR)/dmg-staging
	ditto $(RELEASE_DIR)/Scratch.app $(RELEASE_DIR)/dmg-staging/Scratch.app
	ln -s /Applications $(RELEASE_DIR)/dmg-staging/Applications
	attempt=1; \
	until hdiutil create -volname "Scratch $(RELEASE_VERSION)" -srcfolder $(RELEASE_DIR)/dmg-staging -ov -format UDZO \
	  $(RELEASE_DIR)/Scratch-$(RELEASE_VERSION).dmg; do \
	  test $$attempt -lt 3 || exit 1; \
	  attempt=$$((attempt + 1)); echo "hdiutil create failed, trying again ($$attempt of 3)" >&2; sleep 5; \
	done
	rm -rf $(RELEASE_DIR)/dmg-staging
	bash scripts/check-release-dmg.sh $(RELEASE_DIR)/Scratch-$(RELEASE_VERSION).dmg $(RELEASE_VERSION)
