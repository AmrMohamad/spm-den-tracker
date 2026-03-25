SWIFT ?= swift
XCODEBUILD ?= xcodebuild
APP_PROJECT := DependencyTrackerApp/DependencyTrackerApp.xcodeproj
APP_SCHEME := DependencyTrackerApp

.PHONY: build test run app-build setup-hooks

build:
	$(SWIFT) build

test:
	$(SWIFT) test

run:
	$(SWIFT) run spm-dep-tracker --help

app-build:
	$(XCODEBUILD) -project $(APP_PROJECT) -scheme $(APP_SCHEME) -configuration Debug build

setup-hooks:
	git config core.hooksPath .githooks
	@echo "Configured git hooks path to .githooks"
