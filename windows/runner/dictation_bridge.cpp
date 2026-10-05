#include "dictation_bridge.h"
#include <flutter/standard_method_codec.h>
#include <vector>
#include <string>

namespace { constexpr int kHotkey = 0x5446; }
DictationBridge::DictationBridge(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "typeflux/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "registerHotkey") {
      if (!registered_) registered_ = RegisterHotKey(window_, kHotkey,
          MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_SPACE) != 0;
      if (registered_) result->Success();
      else result->Error("HOTKEY_UNAVAILABLE", "The shortcut is already in use.");
    } else if (call.method_name() == "unregisterHotkey") {
      if (registered_) UnregisterHotKey(window_, kHotkey);
      registered_ = false; recording_ = false; target_ = nullptr;
      result->Success();
    } else if (call.method_name() == "resetCapture") {
      recording_ = false; target_ = nullptr;
      if (overlay_) ShowWindow(overlay_, SW_HIDE);
      result->Success();
    } else if (call.method_name() == "showStatus") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      std::string text;
      if (args) {
        auto found = args->find(flutter::EncodableValue("text"));
        if (found != args->end() && std::holds_alternative<std::string>(found->second))
          text = std::get<std::string>(found->second);
      }
      if (text.empty()) {
        if (overlay_) ShowWindow(overlay_, SW_HIDE);
      } else {
        if (!overlay_) overlay_ = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT,
            L"STATIC", L"", WS_POPUP | WS_BORDER | SS_CENTER | SS_CENTERIMAGE,
            0, 0, 340, 56, window_, nullptr, GetModuleHandle(nullptr), nullptr);
        const int length = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
        std::wstring wide(static_cast<size_t>(length), L'\0');
        MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, wide.data(), length);
        SetWindowTextW(overlay_, wide.c_str());
        MONITORINFO monitor = {}; monitor.cbSize = sizeof(monitor);
        GetMonitorInfoW(MonitorFromWindow(target_ ? target_ : window_, MONITOR_DEFAULTTONEAREST), &monitor);
        SetWindowPos(overlay_, HWND_TOPMOST,
            monitor.rcWork.left + (monitor.rcWork.right - monitor.rcWork.left - 340) / 2,
            monitor.rcWork.bottom - 100, 340, 56, SWP_NOACTIVATE | SWP_SHOWWINDOW);
      }
      result->Success();
    } else if (call.method_name() == "insertText") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) { result->Error("INVALID_ARGUMENT", "Missing text."); return; }
      auto found = args->find(flutter::EncodableValue("text"));
      if (found == args->end() || !std::holds_alternative<std::string>(found->second)) {
        result->Error("INVALID_ARGUMENT", "Missing text."); return;
      }
      const bool inserted = Insert(std::get<std::string>(found->second));
      recording_ = false; target_ = nullptr;
      result->Success(flutter::EncodableValue(inserted));
    } else result->NotImplemented();
  });
}
DictationBridge::~DictationBridge() {
  if (registered_) UnregisterHotKey(window_, kHotkey);
  if (overlay_) DestroyWindow(overlay_);
  channel_->SetMethodCallHandler(nullptr);
}
bool DictationBridge::HandleMessage(UINT message, WPARAM parameter) {
  if (message != WM_HOTKEY || parameter != kHotkey || !registered_) return false;
  if (!recording_) {
    target_ = GetForegroundWindow();
    if (!target_ || GetAncestor(target_, GA_ROOT) == window_) return true;
    GetWindowThreadProcessId(target_, &target_process_);
    recording_ = true;
  }
  channel_->InvokeMethod("toggleDictation", nullptr);
  return true;
}
bool DictationBridge::Insert(const std::string& text) {
  if (!target_ || !IsWindow(target_) || GetForegroundWindow() != target_ ||
      text.empty() || text.size() > 100000) return false;
  DWORD process = 0;
  GetWindowThreadProcessId(target_, &process);
  if (process != target_process_) return false;
  // Never combine synthesized Unicode with held shortcut modifiers.
  for (int key : {VK_CONTROL, VK_MENU, VK_SHIFT, VK_LWIN, VK_RWIN}) {
    if (GetAsyncKeyState(key) & 0x8000) return false;
  }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) return false;
  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), wide.data(), length);
  std::vector<INPUT> inputs(static_cast<size_t>(length) * 2);
  for (int i = 0; i < length; ++i) {
    auto& down = inputs[static_cast<size_t>(i) * 2];
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = wide[static_cast<size_t>(i)];
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    auto& up = inputs[static_cast<size_t>(i) * 2 + 1];
    up = down; up.ki.dwFlags |= KEYEVENTF_KEYUP;
  }
  // UIPI and incompatible controls can reject input. Dart retains the transcript.
  return SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT)) == static_cast<UINT>(inputs.size());
}
