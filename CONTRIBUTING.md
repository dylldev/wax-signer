# Contributing to Wax

Thanks for helping. Wax is a free, Apache-2.0 iPhone app that signs IPAs on the phone and installs them.

## Ground rules
- **Never put secrets or personal details in a commit**: certificates, profiles, tokens, server addresses, personal emails.
  The tests use fixtures only. If you find a leak, report it privately (see `SECURITY.md`).
- Changes to signing, unpacking or install code need a test that fails first (red), then passes (green).
- Keep the Wax look: use the colours and components in `App/Theme.swift`, not stock controls.
- Say what you could and could not test. Only one iPhone (17, iOS 27.2) has been verified so far.

## Setup
```bash
brew install xcodegen
xcodegen generate
swift test                                  # engine tests
xcodebuild test -project LocalIPASigner.xcodeproj -scheme LocalIPASigner \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO     # app tests
python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'
```

## Pull requests
Keep them small and say why, not just what. CI must be green. By contributing you agree your work is licensed under Apache-2.0.
