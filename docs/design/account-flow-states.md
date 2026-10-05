# Approved account flow: states and visual acceptance

Status: implementation specification, not a record of completed runtime checks.
The user approved the centered sign-in/registration composition from concept 2
and the grouped settings composition from concept 1. Use
[account-flow-approved.png](account-flow-approved.png) as the visual reference
and [the implementation scope](../account-implementation-plan.md) as the scope.
This document fills in the states needed to make that approved flow usable; it
does not introduce another design option or require another approval.

## Shared visual rules

- Preserve the v3 palette: light background `#F7F7F9`, primary text `#24262C`,
  secondary text `#70747E`, blue `#2E6EF0`; dark background `#18181C`, text
  `#F1F1F4`, secondary text `#B0B0BB`, blue `#178CFF`.
- Use system text with the existing Chinese fallback. The preview font must not
  become an application font setting. Keep blue for actions and selection, red
  for sign-out/destructive or error states, and purple for the existing highest
  reasoning setting rather than account branding.
- Auth pages have centered color drop, Typeflux name, heading and description.
  Field labels are outside and above separate light input surfaces. Do not add
  the rejected large card around the entire form or leading email/lock icons.
- Settings have a left-aligned heading, circular back button, neutral person
  outline avatar and a name/email row. Keep the account, preferences, advanced,
  and sign-out groups. Do not replace them with the centered identity layout.
- Use thin outlines, modest soft shadows and the existing glass surfaces. Do
  not invent a plan badge, subscription details or an account name when the API
  has not supplied them. The reference's sample identity is not production data.

### Layout targets

The approved PNG is a presentation board rather than a native device capture.
These are logical-pixel targets derived from its proportions; compare rendered
content at matching viewports, excluding board labels and frames.

| Element | Target and adaptation |
| --- | --- |
| Review viewport | 393 × 852 phone; also check the existing 381 × 840 content fixture |
| Auth column | 24 px horizontal inset, maximum width 400; stretch fields/buttons within it |
| Auth hero | Approximately 96–104 px color drop on a full-height phone, same size on sign-in and registration; retain the existing v3 curve/gradient |
| Type hierarchy | Auth heading 28–32 px, Typeflux name 22–24 px, input/body 15–16 px, labels 13–14 px, helper text 12–13 px; respect system text scaling |
| Form spacing | 8 px label-to-field; 20–24 px between field groups; 24–32 px before the primary action; helpers remain adjacent to their field/action |
| Fields | Minimum 54 px height; 14–16 px corner radius; grow with errors, wrapping and accessibility text |
| Main action | Approximately 56–60 px minimum height, full column width, capsule corner; do not shrink the label to fit |
| Navigation | 44 px minimum back/visibility/icon hit area; respect system top and bottom safe areas |
| Settings column | 18–24 px horizontal inset; 20 px group-card corners; minimum 56–64 px rows, allowed to grow |
| Settings identity | Approximately 64 px avatar, 12–16 px gap to name/email, text truncation only when wrapping cannot preserve the row |
| Settings groups | 24–28 px section spacing; inner separators only between related rows; no separator through leading icons |

Auth pages scroll as a unit when height is limited. Reduce decorative top space
before squeezing controls; do not fix the main button below the visible
viewport or overlay it on fields. Settings rows and secondary pages use the same
surface and spacing language, with the large auth hero omitted.

## Screen and state definitions

| Screen | Content and states | Interaction and destination |
| --- | --- | --- |
| Sign in | Empty, email/password entered, password visible, invalid email, incorrect credentials, inactive account, submitting, network failure | Email → password → Sign in. Success enters cloud chat. Create account and Forgot password open their own flow. Advanced settings is a quiet footer entry. |
| Create account | Distinct heading/description, email, new password, visible password rule, submitting, weak password, existing account, unsupported email domain, network failure | Create account sends one registration request; success opens Verify email with the entered address. The email address is retained when returning to sign in. |
| Verify email | Address recap, one six-digit code field, waiting for input, verifying, invalid/expired code, rate limit/lock, resend cooldown, resend failure, success | Verify email calls activation once. Resend uses the same email and registration/sign-in password. Successful activation may sign in with the retained password; if that later sign-in fails, return to sign in with a verified notice rather than repeatedly redeeming the used code. |
| Forgot password | Email field, neutral explanation, sending, request failure, sent acknowledgement | Submit email to request a code; then open Reset password. The acknowledgement must not reveal whether an account exists. |
| Reset password | Address recap, six-digit code, new password, password rule, invalid/expired code, weak password, submitting, failure, success | Submit code and new password. On confirmed success, clear sensitive form state and return to sign in with a success notice. |
| Settings | Back control, real identity, Account group, Preferences group, Advanced settings card, red Sign out card | Back returns to the originating chat/history screen. Each visible row opens its actual destination. No inert navigation arrows. |
| Change password | Current password, new password, visibility controls, password rule, wrong current password, submitting, error, success | Use the authenticated change-password endpoint. On success remove the current client session and return to sign in; show success there. |
| Appearance | System, Light, Dark options; current choice marked | Selection immediately updates all visible surfaces, including the selector and account pages, and persists on this device. Back returns to Settings. |
| Language | System, Simplified Chinese, English options; current choice marked | Selection updates visible copy and persists on this device. Back returns to Settings; changing language must not clear a draft or credentials. |
| Advanced settings | Current API origin and explanatory helper; editable while signed out, read-only while signed in; invalid origin and save failure | Signed-out users can save a valid origin. Signed-in users must sign out before changing it; never silently move a session to another server. |
| Sign out | Ready, working, completed or local-storage failure | Single tap starts one action. Remove local session and account-scoped active state, then return to sign in. Appearance/language remain device preferences. |

For any request, keep the form layout stable while showing progress in the main
action, disable duplicate submission and preserve entered values on recoverable
failure. Use inline field errors for invalid input and one nearby notice for
network/server failure. Do not replace the page with a generic dialog or rely on
a transient toast as the only explanation. Passwords/codes are not persisted in
draft storage or included in logs and screenshots.

## Copy and validation

Visible strings belong in `lib/ui/strings.dart`. The following wording fixes the
meaning and hierarchy; placeholders must match in both locales.

| Context | Simplified Chinese | English |
| --- | --- | --- |
| Sign-in heading | 欢迎回来 | Welcome back |
| Sign-in description | 登录后，继续你的云端对话 | Sign in to continue your cloud conversations |
| Registration heading/action | 创建账户 | Create account |
| Registration description | 使用邮箱注册 Typeflux | Sign up for Typeflux with your email |
| Email label / placeholder | 邮箱 / 请输入邮箱 | Email / Enter your email |
| Password label / placeholder | 密码 / 请输入密码 | Password / Enter your password |
| Current / new password | 当前密码 / 新密码 | Current password / New password |
| Password rule | 至少 8 位，包含大写字母、小写字母和数字 | At least 8 characters, including uppercase and lowercase letters and a number |
| Forgot-password entry | 忘记密码？ | Forgot password? |
| Registration next step | 下一步：验证邮箱 | Next: verify your email |
| Verification heading/action | 验证邮箱 | Verify email |
| Code label | 6 位验证码 | 6-digit code |
| Activation code helper | 验证码已发送至 {email}，15 分钟内有效 | A code was sent to {email}. It is valid for 15 minutes |
| Resend action/countdown | 重新发送 / {seconds} 秒后可重新发送 | Resend code / Resend in {seconds}s |
| Neutral reset acknowledgement | 如果该邮箱已注册，你会收到验证码；请检查邮箱 | If this email is registered, you will receive a code. Please check your inbox |
| Reset-code helper | 重置验证码在 30 分钟内有效 | The reset code is valid for 30 minutes |
| Invalid or expired code | 验证码不正确或已过期，请检查后重试 | The code is incorrect or expired. Check it and try again |
| Too many attempts | 尝试次数过多，请稍后重试 | Too many attempts. Please try again later |
| Activated but sign-in unfinished | 邮箱已验证，请登录 | Your email is verified. Please sign in |
| Password success | 密码已更新，请重新登录 | Your password has been updated. Please sign in again |
| Settings/group headings | 设置 / 账户 / 偏好设置 | Settings / Account / Preferences |
| Settings rows | 修改密码 / 外观 / 语言 / 高级设置 / 退出登录 | Change password / Appearance / Language / Advanced settings / Sign out |
| Appearance choices | 跟随系统 / 浅色 / 深色 | System / Light / Dark |
| Language choices | 跟随系统 / 简体中文 / English | System / 简体中文 / English |
| Signed-in origin helper | 更换服务地址前，请先退出登录 | Sign out before changing the server address |

Trim email/origin input but never trim or transform a password. Existing-password
sign-in must not apply the new-password complexity rule to an otherwise nonempty
password. New passwords use the actual API rule, even if small text in the
generated reference is ambiguous. Do not silently truncate long passwords;
report an understandable length error when the current password backend limit
would be exceeded.

The code field supports pasting a full code and the system one-time-code autofill
hint. A single accessible field is sufficient; six separate focus stops are not
required. Show six digits, not an arbitrary alphanumeric registration token.
Password visibility changes leave focus and text unchanged; registration/reset
use new-password autofill and sign-in/current-password use existing-password
autofill.

## Verified server contract

Reviewed against `typeflux-api/internal/transport/http/dto/auth.go`,
`internal/transport/http/handler/auth_handler.go` and
`internal/service/auth_service.go` on 2026-10-04. These are existing contracts;
this account flow does not require server changes.

| Action | Existing endpoint and request fields |
| --- | --- |
| Register | `POST /api/v1/auth/register`: `email`, `password`; optional `name` is not a new UI field |
| Activate | `POST /api/v1/auth/activate`: `email`, `code` |
| Resend activation | `POST /api/v1/auth/resend-activation`: `email`, `password` |
| Sign in | `POST /api/v1/auth/login`: `email`, `password` |
| Forgot password | `POST /api/v1/auth/forgot-password`: `email` |
| Reset password | `POST /api/v1/auth/reset-password`: `email`, `code`, `new_password` |
| Change password | Authenticated `POST /api/v1/auth/change-password`: `old_password`, `new_password` |

- Activation codes are six digits, valid for 15 minutes; activation resend has a
  60-second server cooldown. A local countdown is a convenience, not authority
  to bypass a server `AUTH_ACTIVATION_RESEND_LIMITED` response.
- Password-reset codes are six digits and valid for 30 minutes. The service does
  not expose the same activation-resend cooldown contract for reset requests;
  do not label a client resend delay as a server guarantee.
- New-password checks require upper/lowercase letters and a digit. The DTO also
  requires eight characters. Current hashing uses bcrypt, whose long-input byte
  limit needs local handling rather than a silently shortened password.
- Forgot password intentionally returns `sent: true` for unknown addresses.
  Invalid/locked code and credential errors still need readable localized copy.
- Reset and change password revoke all refresh tokens. This does not promise
  immediate revocation of every already-issued access token; the client returns
  to sign in after success.
- If a registration response is lost after the server created the account, a
  later existing-account response must offer sign in/verification recovery
  instead of erasing the entered address or claiming creation never occurred.

## Acceptance matrix

The following are acceptance criteria, not checked-off results. Root owns SDK
commands and will supply real Flutter renders for the visual report.

| Area | Required observation |
| --- | --- |
| Approved three screens | Capture sign in, registration and settings with the same width, scale and theme; compare the auth centered composition and settings grouped composition independently |
| Keyboard | At 393 × 852 and 320 × 568 with an approximately 300 px keyboard inset, focused fields, validation and submit remain reachable by scrolling; no bottom action covers a field |
| Small/large text | At 320 px width and text scale 1.5 and 2.0, labels/helpers wrap, control heights grow, and no row or CTA overflows; drop or reduce decorative spacing before hiding content |
| Dark mode | Background, fields, cards, dividers, placeholder text and errors all follow the dark palette; no white surface leaks or invisible password icons |
| Language | Inspect Chinese and English, including wrapped password rules, long email addresses, countdowns and preference values; avoid fixed-height text clipping |
| Appearance persistence | Explicit light/dark survives restart; System follows host changes; sign out preserves the chosen device preference |
| Language persistence | Explicit Chinese/English survives restart; System follows supported host locale, with English fallback for unsupported locales |
| Request states | Validate each form error and a network failure, confirm entered text remains, busy state prevents duplicate submissions, and success reaches the stated destination |
| Code flow | Paste/autofill six digits; check invalid, expired, locked, resend cooldown and resend-failed states without claiming mail delivery from a mocked response |
| Navigation | System back and visible back return one level; password success reaches sign in; settings/back preserves the current conversation |
| Server isolation | Signed-in origin is read-only; signed-out origin changes reset sensitive verification context and never reuse credentials or account cache from a different origin |
| Native interaction | Verify real keyboard resizing, autofill, secure-storage persistence, screen-reader names and actual back gestures on iOS/Android; fixture screenshots cannot prove these |

Visual QA should record the actual image filenames, viewport/theme/text scale,
reference match, outstanding mismatches and their severity. A generated design
image is the target; a Flutter fixture render proves layout only, while a device
or simulator run is needed for native interaction evidence.
