.PHONY: format test

format:
	./scripts/format.sh

test:
	xcodebuild test -skipMacroValidation -project Fitfluence.xcodeproj -scheme FitfluenceApp -configuration Dev -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
