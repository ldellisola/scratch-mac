# One obvious command per question (spec §9.3). Targets marked [linux] also run in the Linux cloud sessions.

CORE_PACKAGE := Packages/ScratchCore

.PHONY: core-test lint format script-test ci-wait

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
