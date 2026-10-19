# One obvious command per question (spec §9.3). Targets marked [linux] also run in the Linux cloud sessions.

CORE_PACKAGE := Packages/ScratchCore

.PHONY: core-test lint format

# [linux] Run the ScratchCore tests.
core-test:
	swift test --package-path $(CORE_PACKAGE)

# [linux] Check formatting. Fails on any difference.
lint:
	swift format lint --strict --recursive Packages App

# [linux] Rewrite files to the house format.
format:
	swift format format --in-place --recursive Packages App
