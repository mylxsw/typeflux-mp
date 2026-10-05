# Development commands

Run commands at the `typeflux-flutter` repository root. Requirements: Flutter
3.47.2 / Dart 3.13.2, Python 3.9+, GNU Make, and the native platform toolchain.
On Windows, use GNU Make in Git Bash/MSYS2 and set `PYTHON=python` if necessary.
Windows compilation also requires Visual Studio's C++ desktop workload; iOS
requires macOS/Xcode. Dependencies are restored by `flutter run`/build; `make
deps` explicitly restores the committed lockfile.

## Start and switch environments

| Environment | Default API origin | Command |
| --- | --- | --- |
| `dev` (default) | `https://typeflux-api.dev.fallout.in` | `make dev` |
| `prod` | `https://api.typeflux.app` | `make prod` |
| `dev-nas` | `http://nas-server.local:8080` | `make dev-nas PLATFORM=ios` |
| `dev-macbook` | `http://mac-pro.local:8080` | `make dev-macbook PLATFORM=ios` |
| `dev-macmini` | `http://mac-mini.local:8080` | `make dev-macmini PLATFORM=android` |
| `local`, Android emulator | `http://10.0.2.2:8080` | `make local PLATFORM=android` |
| `local`, iOS simulator / Windows | `http://127.0.0.1:8080` | `make local PLATFORM=ios` / `windows` |

These origins come from the existing macOS client's Makefiles and server
configuration. Targets start the Flutter client; they do not start or deploy
the backend. Start the API separately using its own repository instructions.

Environment and platform are independent. For example:

```sh
make android ENV=dev
make ios ENV=prod
make windows ENV=dev
make dev DEVICE=<exact-device-id>
make config ENV=local PLATFORM=android
make config ENV=dev-macmini
make ios ENV=dev-macbook
```

`make run`/`dev` lets Flutter select a device. The `android` and `ios` targets
automatically use a single connected matching device. When several match, the
terminal lists their names, device/simulator types and IDs; enter a number to
continue launching on that device, or `q` to cancel. Invalid input prompts again.
`DEVICE=<id>` skips selection. Without an interactive terminal, multiple devices
are listed and an explicit `DEVICE` is required. If none match, connect a device
or start a simulator first. These targets do not install a simulator or SDK.

```sh
make devices
make emulators
make emulator EMULATOR=<installed-emulator-id>
make ios DEVICE=<simulator-or-phone-id>
```

`make local` needs `PLATFORM` to choose the correct host alias, or an explicit
`API_URL`. Android's `10.0.2.2` is for its standard emulator, not a physical phone.
On a physical Android/iPhone, use the development server's LAN IP or HTTPS URL;
the phone and server must share a reachable network. The server must listen on
that LAN interface. NAS `.local` resolution likewise depends on the network.

```sh
make local PLATFORM=android DEVICE=<phone-id> API_URL=http://192.168.1.20:8080
make dev-nas PLATFORM=ios API_URL=http://192.168.1.30:8080
make dev API_URL=https://another-test-api.example
```

Make passes `TYPEFLUX_API_URL` to Dart. This explicitly selected origin wins
over a previously saved server. Tokens and chat caches remain scoped by origin;
switching environments does not send another server's token to the new server.
Without a build-time origin, direct `flutter run` uses the saved setting, then
production as the fresh-install default. Stop and restart the app when switching
environments; hot reload is not a build-time configuration switch.

HTTP requires `ENV=local`/`dev-nas`/`dev-macbook`/`dev-macmini`, `MODE=debug`, and a local address. Make then
passes `TYPEFLUX_ALLOW_INSECURE_HTTP=true`; the Dart layer additionally requires
debug mode and rejects public HTTP origins. Android's cleartext exception and
iOS's local-network ATS allowance apply only to Debug. `MODE=profile`/`release`
must use HTTPS even if pointed at a test server. No TLS certificate verification
is disabled. API URLs cannot contain credentials, query parameters or paths.

### Realtime ASR on the two Macs

Realtime addresses come from the selected API's `/api/v1/asr/token` response.
Configure each API server's environment separately, then restart that API service:

```dotenv
# MacBook API environment
REALTIME_ASR_SERVER_ORIGINS=http://mac-pro.local:8081
```

```dotenv
# Mac mini API environment
REALTIME_ASR_SERVER_ORIGINS=http://mac-mini.local:8081
```

The API and its realtime service must use matching token-signing settings and
reachable callback settings, as described in their own configuration examples.
The client maps these origins to `ws://<host>:8081/api/v1/asr/ws/default` only in
an explicitly opted-in Debug build; HTTPS servers continue to use `wss://`.
Public HTTP and malformed realtime origins are rejected, using the same policy
as API requests. No separate client realtime override is needed.

Do not return `127.0.0.1` to a phone: that refers to the phone itself. Both
8080 and 8081 must be reachable from the device. If `.local` names do not resolve
on an Android device/emulator or another network, use `API_URL` with the Mac's
LAN IP and advertise a reachable LAN IP in `REALTIME_ASR_SERVER_ORIGINS` as well.

Platform references: [Flutter network policy](https://docs.flutter.dev/release/breaking-changes/network-policy-ios-android),
[Android emulator networking](https://developer.android.com/studio/run/emulator-networking-address),
[Apple local-network ATS allowance](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking),
and [Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
The Dart-origin check is necessary because native transport policy does not
cover every Dart-owned socket.

## Toolchain and local overrides

`scripts/flutter_tool.py` supplies a portable process environment and invokes
Flutter with an argument list, not an interpolated shell command. Make contains
the actual run/test/build commands. If the sibling workspace `.tools` exists,
the helper finds the previously installed Flutter SDK, JDK 21 and Android SDK,
and keeps caches there. Otherwise it uses `flutter` from PATH and normal system
tool configuration. Explicit environment values take precedence.

Copy `Makefile.local.example` to `Makefile.local` for private machine settings.
`Makefile.local` is ignored by Git. For example:

```make
FLUTTER = /path/to/flutter/bin/flutter
PLATFORM = ios
DEVICE = <device-id>
ENV = dev
export JAVA_HOME = /path/to/jdk-21
export ANDROID_HOME = /path/to/android-sdk
```

Use `make config` to inspect resolved non-secret tools and launch arguments and
`make doctor` for toolchain diagnostics. `API_URL` overrides a preset; command-line
Make variables override the local file. Keep credentials out of Make variables,
dart-defines and source control. The exact verified workspace toolchain is in
[android-local-build.md](android-local-build.md).

## Checks, screenshots and builds

| Command | Result |
| --- | --- |
| `make check` | Tooling tests, locked dependencies, format check, analysis and coverage, sequentially |
| `make test TEST_ARGS=test/api_test.dart` | Focused Flutter tests |
| `make coverage` | Full tests and `coverage/lcov.info` |
| `make format` / `make format-check` | Format / verify Dart sources |
| `make screenshots` | Actual Flutter widget fixtures in `build/screenshots` |
| `make apk ENV=prod` | ARM64 profile test APK |
| `make apk-debug ENV=local` | ARM64 debug APK using emulator local API |
| `make apk-release ENV=prod` | ARM64 release-mode APK; current signing remains development-only |
| `make apk-verify` | APK ZIP, architecture, Android signature, metadata and SHA-256 checks |
| `make ios-build ENV=dev` | Unsigned iOS simulator debug build |
| `make windows-build ENV=dev` | Windows debug build on a Windows host |
| `make clean` | Remove generated Flutter build artifacts |

Screenshot options: `SCREENSHOT_DIR=/absolute/output/path` and
`PREVIEW_FONT=/path/to/chinese-font.ttf`. These are offline fixture renders,
not screenshots from physical devices. `RUN_ARGS`, `BUILD_ARGS` and `TEST_ARGS`
are optional additional Flutter arguments; use `ENV`/`API_URL` for server
configuration rather than duplicate dart-defines.

ARM64 APK output: `build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk`
(or `debug`/`release`). `make apk-verify APK_MODE=debug` verifies the debug output;
`APK=/path/to/package.apk` overrides it. The split build excludes other plugin
ABIs and preserves the package version code. A successful build or signature
check is not device installation or authenticated backend verification.

Do not run independent Flutter targets concurrently against this checkout;
`make check` deliberately runs its steps in order. Native signing, Apple OAuth,
release packaging and real device validation remain separate work, as recorded
in [validation.md](validation.md).
