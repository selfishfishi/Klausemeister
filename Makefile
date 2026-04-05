.PHONY: lint format

lint:
	swiftlint lint --strict

format:
	swiftformat .
