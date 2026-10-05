# Typeflux Flutter

Flutter implementation of Typeflux for Android, iOS and Windows.
The existing Swift macOS app remains the macOS client. This is development
source, not a released app or full macOS feature parity.

## Implemented

- Mobile UI follows the final iOS **v4** reference: source SVG icons, 96/132pt
  animated color orb, glass composer, horizontal suggestions, 300/352pt
  model/reasoning cards, floating history drawer and a grouped settings sheet.
  Light/dark color tokens and the main 392×852 geometry are transcribed from
  the supplied HTML. Mobile dictation fills the editable draft; sharing opens
  the operating system share sheet after an explicit tap.
- Desktop adopts the macOS sidebar, reading column, title capsule and composer
  layout, while preserving Windows voice entry. This is visual groundwork,
  not complete macOS feature parity.
- Real catalog capabilities, context/output limits and credit multipliers;
  reasoning selection uses the nearest supported level on a model change.
- Running conversations accept follow-up instructions through `/steer`.
  Accepted but unread queued messages survive interruption and can be resumed.
  Locally retained drafts for device-only models must be copied back to that
  device; they are not silently synchronized or executed on mobile.
- Chinese/English copy, selectable Markdown and horizontal tables; http/https
  links open on a user tap. Remote answer images load only after a tap.
- Final v4 account design: welcome → email sign-in, registration, verification and
  resend countdown, forgotten/reset password, and grouped account settings.
  Validation, loading and error states preserve recoverable input.
- Password changes, persistent system/light/dark appearance and Chinese/English
  preferences. Alternate servers live under advanced settings; signed-in users
  must sign out before switching servers.
- Secure token storage, serialized refresh/session writes, stale-login rollback
  and logout. No credentials are stored in the chat cache.
- Cloud conversation listing/pagination, model selection, send, cancel,
  regenerate and explicitly confirmed deletion. History rows expose swipe actions;
  unsupported rename/account-deletion operations show an honest explanation.
- Revision-aware snapshot/progress SSE, UTF-8 framing, bounded reconnection,
  foreground recovery and stale-response isolation.
- Account/server-scoped local cache of the conversation list, last conversation
  and unresolved outgoing or accepted unread queued messages. A persisted message UUID is reused for
  explicit retries. This is not a complete offline history database.
- JPEG/PNG/WebP conversion to bounded metadata-free JPEG, UTF-8 text/Markdown/
  CSV/JSON/log attachments, and model-vision checks. PDF is not implemented.
- Foreground 16 kHz mono PCM cloud transcription, partial/final results,
  sentence/authoritative final handling, cancellation and incomplete-result
  preservation. Speech is not automatically submitted as a chat message.
- Windows opt-in Ctrl+Alt+Space toggle, a non-activating recording indicator,
  original-window/process checks and Unicode text insertion. Rejected insertion
  leaves the transcript in the composer; no clipboard replacement is performed.

## Run

Use Flutter **3.47.2 / Dart 3.13.2** (the SDK used for this increment).

The Makefile is the entry point for development, following the existing macOS
client's environment names:

```sh
make help
make dev                       # shared HTTPS development API; select a device
make ios ENV=dev                # connected iPhone / running simulator
make android ENV=dev            # connected Android device / running emulator
make windows ENV=dev            # Windows host
make local PLATFORM=android    # local API through Android emulator's 10.0.2.2
make dev-nas PLATFORM=ios       # NAS API through nas-server.local
make dev-macbook PLATFORM=ios   # MacBook API through mac-pro.local:8080
make dev-macmini PLATFORM=android # Mac mini API through mac-mini.local:8080
make config ENV=dev-macmini     # inspect API and launch arguments without starting
make prod DEVICE=<device-id>    # production API
```

`make run` defaults to the development API. An explicit launch API takes
precedence over the previously saved server; sessions and chat caches stay
separated by origin. Running Flutter directly without a define retains the
saved server, falling back to `https://api.typeflux.app` on a fresh install.
Local HTTP requires an explicit development flag and a **debug** build, and is
restricted to loopback/private-network addresses. Profile/release builds require
HTTPS. See [development.md](docs/development.md) for all environments, physical
device routing, local overrides, screenshot exports and build commands.

Build Android with an Android SDK and JDK 21. The verified local toolchain is
documented in `docs/android-local-build.md`. Build iOS on macOS with a working
Xcode installation and select your signing team for device installation. Build
Windows on Windows with Visual Studio's Desktop development with C++ workload.
Application identifiers are provisional; configure production identity and
signing before publishing. Generated Android release signing remains development
only. Never distribute a debug-signed app as a production release.

```sh
make check                     # tooling tests, locked dependencies, formatting, analysis, coverage
make screenshots               # fixture renders in build/screenshots
make apk ENV=prod              # ARM64 profile test APK
make apk-verify
make ios-build ENV=dev          # simulator build, no signing
make windows-build ENV=dev      # Windows host
```

`.github/workflows/verify.yml` defines those checks for hosted runners. The
workflow runs on push and pull requests; local checks do not establish a
successful hosted CI run.

## Architecture

- `lib/auth`: email-account flows, validation and resend cooldown.
- `lib/core`: server validation, secure sessions, preferences, HTTP and SSE.
- `lib/chat`: cloud conversation state, retry IDs, cache and attachments.
- `lib/voice`: recorder/WebSocket lifecycle and Windows channel interface.
- `lib/ui`: adaptive screens, localized copy and shared theme.
- `windows/runner/dictation_bridge.*`: Win32 hotkey, status popup and insertion.

No macOS code is linked into this app. No new backend endpoints were introduced.
Cloud chats are shared through the existing backend. Local-only macOS chats are
not uploaded or migrated. Device-bound tool/inference steps are display-only;
the Flutter client advertises no local tools and never executes preview calls.

## Data and privacy

Tokens use the operating-system credential store via `flutter_secure_storage`.
The last-chat cache and pending outgoing content use a JSON file in the app's
private application-support directory, partitioned by server/account. This
cache is **not application-encrypted**; logout removes it. Android application
backup is disabled. Review device backups and add encrypted history storage
before making stronger privacy claims. Raw audio is streamed, not saved by this
client. Production credentials and captured user content must never enter tests
or logs.

## Remaining product work

- Verify real authenticated chat and ASR with an authorized test account.
- Windows build/runtime certification: focus/IME/UIPI, multiline/emoji, Word,
  WeChat, browsers, VS Code, multi-monitor DPI, hardware microphones and Bluetooth.
- Windows rewrite/persona/vocabulary parity, selectable hotkeys, tray, startup,
  recording history, device selection UI, signed installer and updates.
- Local speech/model inference, custom providers, local-only conversations,
  desktop file/terminal/browser/computer tools and approval flows.
- Mobile OAuth configuration, account deletion, store purchases/restoration,
  accessible device testing and release
  privacy/store requirements. This build is not ready for store submission.

`docs/design/mobile-v4-reference.html` is the final UI source of truth; it
supersedes the earlier v3 and account concepts. See `docs/design-qa.md` for
implementation coverage and visual-verification limits, and `docs/validation.md`
for actual checks and platform blockers.

The Apple button and token-to-session API are present, but this build has no
configured native Apple authorization provider. Enable the correct iOS signing
capability and audience (plus Android Services ID/callback) before claiming Apple
sign-in works. Account deletion and conversation rename need backend support;
neither is simulated as a successful operation. Settings balance and plan use
the same real subscription/usage endpoints as the macOS client.
