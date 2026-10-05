# Validation record — 2026-10-05

## Makefile and environment startup (2026-10-05)

- `make check` passed through the new entry point: 26 Python tooling tests,
  locked dependency resolution, Dart format check (56 files unchanged), static
  analysis (no issues), and **168 Flutter tests**. Dart line coverage:
  **4387/5131 (85.5%)**.
- `make test TEST_ARGS='test/environment_test.dart
  --dart-define=TYPEFLUX_ALLOW_INSECURE_HTTP=true --reporter expanded'` passed
  all 8 tests with the actual compile-time HTTP flag enabled. The normal check
  run covers that flag being absent, including loopback rejection.
- Environment tests cover saved production settings being superseded by an
  explicit development launch, session isolation, invalid-origin handling,
  and debug-only private-network HTTP. Tooling tests cover device selection,
  platform/mode routing, custom paths, and shell-free argument dispatch.
- `make config` was exercised for the default development and local Android
  environments. `Makefile.local` contains this host's toolchain overrides and
  is excluded from Git; the committed example contains no credentials.
- iOS plist, localized permission strings and Xcode project structure passed
  `plutil` validation. This does not establish an iOS build or device connection.
- `make ios-build ENV=local` reached Xcode but failed resolving Swift packages:
  the sandbox denied writing SwiftPM manifest diagnostics under
  `~/Library/Caches/org.swift.swiftpm`. Xcode also reported unavailable
  CoreSimulator runtime services. The command and project configuration exist;
  successful iOS compilation/launch remains unverified on this host. Windows
  run/build requires a Windows host and was not executed here.
- `make apk-debug ENV=local` and `make apk ENV=prod` both succeeded. Each
  corresponding `make apk-verify` passed APK Signature Scheme v2, ZIP integrity,
  ARM64-only contents and package metadata checks. Compiled manifests confirm
  Debug permits development cleartext and Profile explicitly disables it.
  No package was installed on a device.

| New Make build | APK bytes | SHA-256 |
| --- | ---: | --- |
| Debug / local | 92,688,361 | `7923796f0b46a1ba209e902d6c6c249b34529d719762d8f62807834b22fc3132` |
| Profile / prod | 43,375,862 | `aec4699db43a513511115020a18ef8cd6a54650519832b4367008380dc7a26c3` |

## Final v4 UI increment (2026-10-04)

- The final user-supplied v4 HTML supersedes v3 and the two earlier account concepts.
- `flutter analyze --no-pub`: no issues; `dart format --output=none --set-exit-if-changed lib test`: 54 files unchanged.
- `flutter test --coverage`: **160 tests passed**. Dart coverage: **4357/5102 (85.4%)**.
- Coverage includes Apple identity/session handoff and rollback (with an injected identity provider),
  real subscription/usage payload parsing, large-text/small-screen model controls, history swipe/deletion,
  Markdown links/table links/citations/code copying, streaming output and mobile dictation recovery.
- Regression tests prove local voice-error retry preserves drafts, background interruption preserves
  recognizable text for copying, and disposed Windows pages cannot perform delayed text insertion.
  These use injected controllers/bridges and do not prove native device behavior.
- All **43** screenshot exports passed after the final edits, using real Flutter widgets and
  synthetic offline data at 392×852 (compact cases retain their narrower test viewport). Main screens
  were visually inspected after correction. These 43 checks are included in the 160, not additional tests.
- Original HTML rendering remains blocked: automatic approval rejected Chrome access. No browser
  pixel-by-pixel comparison or real device UI acceptance is claimed. See `docs/design-qa.md`.
- Apple native authorization remains unconfigured; account deletion and conversation rename lack
  backend endpoints. Their UI explains the limitation instead of claiming success.
- Native system sharing, microphone permissions, hardware recording, iOS keyboard and platform font
  rendering still require device testing. No real account/email/backend mutation was performed.

### Current v4 Android test package

- `flutter build apk --profile --target-platform android-arm64 --split-per-abi
  --android-project-arg=force-version-code-ignoring-abi=true`: succeeded, exit 0;
  the final split build completed its Gradle task in 18.3 seconds.
- Package `com.typeflux.typeflux_app`, version `0.1.0` (1), min SDK 24,
  target/compile SDK 36. APK inspection confirms **only `arm64-v8a`** native libraries.
  The explicit split removes other plugin ABIs; the project argument preserves
  version code 1 instead of adding Flutter's per-ABI version-code offset.
- Development-signed profile APK; APK Signature Scheme v2 and ZIP integrity passed.
  Size: **31,695,621 bytes**. SHA-256:
  `d4699abfcd5b6faae147d29fec3234f37f74fd5f62df1ec446073f87de0312a1`.
- Delivered inside a ZIP to fit the file transfer limit; extract the APK before
  installation. This is a test package, not a store release. Device installation,
  microphone, native sharing and real account/backend operation remain unverified.
- Existing plugin Kotlin Gradle integration warnings remain; the build succeeded
  with the isolated toolchain documented in `android-local-build.md`.

## Previous increment (historical results)

## Executed locally

- Flutter 3.47.2, Dart 3.13.2, macOS host.
- `flutter analyze`: no issues.
- `flutter test --coverage`: all 129 tests passed.
- `dart format --output=none --set-exit-if-changed lib test`: passed.
- Automated coverage includes auth refresh serialization, logout during refresh,
  HTTP 401 replay with the same message ID, invalid server URLs/responses,
  split UTF-8/SSE framing, partial frames, revision merging, final transcript
  accumulation, ambiguous send recovery, stale selection responses, logout/cache
  isolation, backgrounding during send, attachment conversion/limits and
  persistence failure before network submission.
- Widget interaction tests cover 320, 390, 1000 and 1200 logical pixel widths, Chinese
  copy, large login text and entering a chat draft. A sidebar overflow found in
  testing was fixed.
- Phone and desktop fixture renders were generated using the actual chat widget
  and shared application theme, then visually inspected. They are not native
  device screenshots and do not prove microphone, keyboard or backend operation.

## Mobile v3 design round

- All nine supplied design states plus compact 320-point / 1.6x text layout
  rendered with actual Flutter widgets; separate tablet and Windows routing tests.
- All 14 design/layout interaction checks passed. Manual render review confirmed
  the glass composer, picker anchoring, light/dark palettes, history and reading
  layout. Source reference and detailed scope are in `docs/design-qa.md`.
- Added regression coverage for reasoning model changes and request restoration,
  `/steer` idempotency, ended-run receipt checking, queued-message persistence,
  local-only model protection, interruption/restart, browser link restrictions,
  explicit remote image loading and truthful tool/usage status.
- Final static analysis passed. The full validation commands temporarily waited
  for Flutter startup / Swift Package Manager locks, then completed successfully.
- Added `url_launcher` for explicit link taps. The Android debug build passed in the account-flow round; iOS and Windows
  builds have not been rerun. Generated Windows plugin registration was updated
  by Flutter. Real browser switching remains unverified.

## Approved account-flow implementation

- Login/registration follow selected concept 2; grouped settings follow concept 1.
  The approved reference, state specification and implementation plan are saved
  under `docs/design/` and `docs/account-implementation-plan.md`.
- Register/activate/resend, login, forgot/reset password and password changes
  use the existing API contract. External account/email requests were not made.
- Persistent theme and language settings are wired into MaterialApp; server
  switching is available before login and read-only while signed in.
- Added regression tests for form validation, cooldown, duplicate submission,
  disposed login, failed app handoff, session write/rollback races, password
  errors vs expired-token 401s, expired-session navigation, preference persistence
  and local storage failures. Password-change expiry notifies app navigation.
- 29 rendered states exported after visual corrections, including 20 account and
  settings states. Fixed missing Chinese button glyphs in preview font inheritance,
  misaligned settings chevrons and overly bright dark-mode borders.
- Full test suite: 129 passed; static analysis and formatting passed. Screenshot
  export separately passed 29 checks; these are part of the 129, not additional.
- Screenshots are widget renders with synthetic data and host preview fonts.
  Real system keyboard, font fallback and device accessibility remain unverified.

## Android builds and package verification

- `flutter build apk --debug --target-platform android-arm64`: succeeded,
  exit 0, 268 Gradle tasks; first successful build completed in 4m 5s.
- Build used Temurin JDK 21.0.12.1+1, Gradle 9.3.1, Android SDK 36, platform 35
  for the JNI plugin, NDK 28.2.13676358 and CMake 3.22.1. Tools and caches are
  isolated under the workspace; no global Java/SDK configuration was changed.
- Earlier JDK 26 attempts did not finish. On JDK 21, disabling Gradle filesystem
  watching and running the Kotlin compiler in process allowed the build to
  progress. A missing platform 35 was then installed under the writable SDK.
  This records the successful configuration, not a single proven stall cause.
- Package: `com.typeflux.typeflux_app`, version `0.1.0` (1), min SDK 24,
  target/compile SDK 36. Flutter engine is ARM64; this is a development-signed
  debug package, not a store/release build.
- APK Signature Scheme v2 verification passed; ZIP content integrity passed.
  APK size: 91,743,948 bytes. SHA-256:
  `8771308e749d0689916c307c8961c2c850a253e182ad63a4e39bf3df3c0febf8`.
- A smaller delivery package was built with `flutter build apk --profile
  --target-platform android-arm64`: exit 0, Gradle completed in 60.2 seconds.
  This profile build uses the same app version and development signing. Its v2
  signature and ZIP integrity passed. It is the delivered test APK.
- Profile APK size: 30,980,357 bytes. SHA-256:
  `b0c5f19a5b723c97015505d60b5bac55777c75c4fde6f5db0ba3bb432f1764d0`.
- Build warnings remain for plugins using the older Kotlin Gradle integration
  and SDK XML version parsing. Both builds passed with the locked toolchain;
  upgrading the Flutter/Gradle toolchain will need plugin compatibility checks.
- Reproduction commands and tool paths: [android-local-build.md](android-local-build.md).

## Not verified

- No production credentials were read. No real user account was created or used.
  Authenticated chat/model/ASR/usage behavior against a deployed backend remains
  unverified; tests use synthetic HTTP fixtures.
- iOS simulator build attempted. Xcode 27 reports a CoreDevice framework symbol
  mismatch (`DetailedOperation...metrics`), an invalid CoreSimulator service
  connection and denied writes to system-managed cache/DerivedData directories.
  No simulator build or device installation succeeded.
- Android APK installation and device interaction have not been performed.
  The build and package verification below do not prove device behavior.
- No Windows host is available in this session. The C++ bridge is not compiled
  or exercised here. CI configuration is provided but has not run remotely.
- Measured Dart line coverage: 3212/4036 (79.6%). This is measured
  Dart coverage, not full platform verification. Native integration is not covered.

## Next acceptance run

1. Build on Windows with the configured CI/local toolchain; test the bridge on
   a standard user account and confirm safe fallback for elevated applications.
2. Exercise Chrome/Edge, Word, WeChat and VS Code: Chinese, emoji, multiline text,
   foreground-window changes, held modifiers and application close/reopen.
3. Use an authorized staging account on Android/iOS: register/activate/login,
   stream/cancel/regenerate, switch accounts, network loss and app suspension.
4. Verify voice token → WSS → PCM → final result → server usage recording with
   synthetic audio, denied microphone permission and disconnected devices.
5. Verify images against vision-enabled and text-only models, account-scoped
   caches and cloud chats that are waiting for a macOS-only tool.
6. Complete store/account/billing flows and desktop parity backlog before release.
