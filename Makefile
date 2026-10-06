SIM ?= iPad Pro 11-inch (M5)

.PHONY: setup web fixtures project app test test-web test-swift e2e ui

setup:            ## Install tools and deps
	brew list xcodegen >/dev/null || brew install xcodegen
	cd canvas-web && npm install && npx playwright install webkit

web:              ## Build canvas-web into App/Resources/canvas-web
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
