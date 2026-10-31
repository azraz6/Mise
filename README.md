# Mise

**Save anything. Cook without the clutter.**

Mise is a native, local-first recipe box for iPhone. Import from public links, pasted text, or screenshots; review every draft; scale ingredients; build honest shopping lists; plan a week of meals; and cook step by step. No account, no analytics, no feed.

## Stack

- SwiftUI and SwiftData, iOS 17+
- StoreKit 2 subscriptions (monthly and annual)
- Vision on-device text recognition
- Share Extension with an App Group import queue
- XcodeGen project definition
- XCTest and XCUITest suites, including StoreKit configuration tests and an accessibility audit

## Build

```sh
xcodegen generate
xcodebuild -project Mise.xcodeproj -scheme Mise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Tests

```sh
xcodebuild test -project Mise.xcodeproj -scheme Mise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:MiseTests -collect-test-diagnostics never

xcodebuild test -project Mise.xcodeproj -scheme Mise \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:MiseUITests/MiseUITests -collect-test-diagnostics never
```

StoreKit configuration tests require an iOS 27 simulator; StoreKitTest is known to fail on the iOS 26.5 runtime.

## Legal and support

- [Support](https://azraz6.github.io/Mise/support.html)
- [Privacy](https://azraz6.github.io/Mise/privacy.html)
- [Terms](https://azraz6.github.io/Mise/terms.html)

## Import limits

Mise reads ordinary public HTTP(S) recipe pages only. It does not sign in, bypass paywalls, CAPTCHAs, or access controls, or promise universal extraction from social platforms. Social links are saved honestly, with text, screenshot, and manual fallbacks.

## License

Source code © 2026 Mise. All rights reserved. Bundled starter photography is used under the Unsplash License.
