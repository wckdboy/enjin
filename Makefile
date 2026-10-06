SIM ?= iPad Pro 11-inch (M5)

.PHONY: setup web fixtures project app test test-web test-swift e2e ui bump archive

setup:            ## Install tools and deps
	brew list xcodegen >/dev/null || brew install xcodegen
	cd canvas-web && npm install && npx playwright install webkit

web:              ## Build canvas-web into Enjin/Resources/canvas-web
	cd canvas-web && npm run build

fixtures:         ## Regenerate shared bridge fixtures from the zod schema
	cd canvas-web && npm run fixtures

project:          ## Regenerate Enjin.xcodeproj from project.yml
	xcodegen generate

app: web project  ## Build the iPad app for the simulator
	xcodebuild -project Enjin.xcodeproj -scheme Enjin -destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath build/dd build

test: test-web test-swift e2e

ui: web project   ## XCUITest smoke flow on the simulator
	xcodebuild -project Enjin.xcodeproj -scheme Enjin -destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath build/dd \
	  -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test

test-web:
	cd canvas-web && npx tsc --noEmit && npx vitest run

test-swift:
	cd EnjinKit && swift test

e2e:              ## Playwright (WebKit, iPad viewport) against the dev host
	cd canvas-web && npx playwright test

bump:             ## Next build number for an App Store Connect upload
	@n=$$(sed -n 's/.*CURRENT_PROJECT_VERSION: \([0-9]*\)/\1/p' project.yml); sed -i '' "s/CURRENT_PROJECT_VERSION: $$n/CURRENT_PROJECT_VERSION: $$((n+1))/" project.yml; \
	  xcodegen generate >/dev/null; echo "build $$((n+1))"

archive: web project  ## Release archive for TestFlight (then Organizer > Distribute)
	xcodebuild -project Enjin.xcodeproj -scheme Enjin -configuration Release -destination 'generic/platform=iOS' \
	  -archivePath build/Enjin.xcarchive -allowProvisioningUpdates archive
