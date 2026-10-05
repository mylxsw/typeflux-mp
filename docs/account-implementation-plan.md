> 历史计划：当前 UI 以最终 [v4 HTML](design/mobile-v4-reference.html) 为准。

# Approved account flow implementation

Design decision: use the centered login/registration screens from concept 2 and
the grouped settings screen from concept 1. The combined account-flow reference
is the visual source of truth. Keep the existing v3 chat and native macOS client.

## Design states before implementation

- Authentication: sign in, create account, verify email, resend cooldown,
  forgotten password, reset password, success, validation and network errors.
- Settings: identity, change password, appearance (system/light/dark), language
  (system/Chinese/English), advanced server information, sign out.
- Signed-in server switching requires signing out first; credentials and caches
  remain scoped to their origin/account.
- All forms scroll on compact screens and above the keyboard, preserve entered
  values on recoverable errors, disable duplicate submissions, and support dark
  mode, large text, autofill and password visibility.
- Registration passwords need 8+ characters with uppercase, lowercase and digits.
  Activation uses six digits, 15-minute validity and 60-second resend cooldown.
  Password reset uses a six-digit code with 30-minute validity, neutral email
  acknowledgement and a return to sign-in after success.

## Delivery order

1. Save the approved reference and supporting state designs; establish shared
   account page, field, button and notice components using the existing palette.
2. Implement the real email-account flows using existing API contracts without
   server changes. Add focused request, validation and navigation tests.
3. Implement the full settings page and local appearance/language persistence;
   wire settings into mobile history and desktop account navigation.
4. Check widget interactions at phone, small-screen, keyboard and large-text
   sizes. Render real Flutter pages in light/dark and compare with the reference.
5. Run formatting, static analysis and the complete test suite with coverage;
   attempt an available native build and record the exact verification boundary.

No deployment, account creation on a real service, commit or push is included.

## Completed validation

The implementation passed 129 tests, static analysis and formatting. The review
exports include 29 real widget states; details and the remaining device checks
are recorded in `account-design-qa.md` and `validation.md`.
