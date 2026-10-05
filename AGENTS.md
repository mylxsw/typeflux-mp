# Typeflux Flutter client

Read the parent Typeflux workspace guide before cross-repository work.
This repository targets Android, iOS and Windows; the Swift macOS client is not
being replaced. Keep API compatibility with released macOS clients.

Use Flutter 3.47.2 and the committed lockfile. Validate with `flutter analyze`,
`flutter test --coverage` and `dart format --output=none --set-exit-if-changed lib test`.
Changes to native behavior require real platform builds and device interaction;
fixture/widget tests cannot be reported as end-to-end validation.

Keep visible copy in `lib/ui/strings.dart`, with Chinese and English entries.
Never log credentials, audio or conversation text. Never replay local tools from
stream previews. Do not upload macOS-local conversations. Keep cache ownership
scoped by origin and authenticated account. Maintain message IDs on uncertain
send retries. Add regression tests for auth/lifecycle/stream state changes.

See README.md and docs/validation.md for current implementation boundaries.
