#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include <algorithm>
#include <cstring>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;
constexpr int kHotkeyId = 1;
constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuQuit = 2;
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"VocabApp";

std::wstring Utf16(const std::string& text) {
  if (text.empty()) return {};
  const int size = ::MultiByteToWideChar(
      CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                        static_cast<int>(text.size()), wide.data(), size);
  return wide;
}

std::string Utf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int size =
      ::WideCharToMultiByte(CP_UTF8, 0, text.data(),
                            static_cast<int>(text.size()), nullptr, 0,
                            nullptr, nullptr);
  std::string narrow(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text.data(),
                        static_cast<int>(text.size()), narrow.data(), size,
                        nullptr, nullptr);
  return narrow;
}

// Another process may hold the clipboard for a moment after copying.
bool OpenClipboardRetry(HWND owner) {
  for (int i = 0; i < 20; i++) {
    if (::OpenClipboard(owner)) return true;
    ::Sleep(15);
  }
  return false;
}

std::optional<std::wstring> ReadClipboardText(HWND owner) {
  if (!::IsClipboardFormatAvailable(CF_UNICODETEXT) ||
      !OpenClipboardRetry(owner)) {
    return std::nullopt;
  }
  std::optional<std::wstring> text;
  if (HANDLE data = ::GetClipboardData(CF_UNICODETEXT)) {
    if (auto chars = static_cast<const wchar_t*>(::GlobalLock(data))) {
      text = std::wstring(chars);
      ::GlobalUnlock(data);
    }
  }
  ::CloseClipboard();
  return text;
}

void WriteClipboardText(HWND owner, const std::wstring& text) {
  if (!OpenClipboardRetry(owner)) return;
  ::EmptyClipboard();
  const size_t bytes = (text.size() + 1) * sizeof(wchar_t);
  if (HGLOBAL data = ::GlobalAlloc(GMEM_MOVEABLE, bytes)) {
    if (void* target = ::GlobalLock(data)) {
      memcpy(target, text.c_str(), bytes);
      ::GlobalUnlock(data);
      if (!::SetClipboardData(CF_UNICODETEXT, data)) ::GlobalFree(data);
    } else {
      ::GlobalFree(data);
    }
  }
  ::CloseClipboard();
}

// Copies the selection of the focused app by sending Ctrl+C, the same way
// desktop translators do, then puts the previous clipboard text back.
std::optional<std::wstring> CopySelection(HWND owner, UINT hotkey) {
  // The hotkey modifiers are still down; Ctrl+Alt+C would not copy.
  const int keys[] = {VK_CONTROL, VK_MENU, VK_SHIFT, VK_LWIN, VK_RWIN,
                      static_cast<int>(hotkey)};
  for (int i = 0; i < 150; i++) {
    bool held = false;
    for (int key : keys) {
      if (::GetAsyncKeyState(key) & 0x8000) held = true;
    }
    if (!held) break;
    ::Sleep(10);
  }
  const auto saved = ReadClipboardText(owner);
  const DWORD before = ::GetClipboardSequenceNumber();
  INPUT inputs[4] = {};
  const WORD codes[4] = {VK_CONTROL, 'C', 'C', VK_CONTROL};
  for (int i = 0; i < 4; i++) {
    inputs[i].type = INPUT_KEYBOARD;
    inputs[i].ki.wVk = codes[i];
    inputs[i].ki.dwFlags = i >= 2 ? KEYEVENTF_KEYUP : 0;
  }
  ::SendInput(4, inputs, sizeof(INPUT));
  bool copied = false;
  for (int i = 0; i < 50 && !copied; i++) {
    ::Sleep(10);
    copied = ::GetClipboardSequenceNumber() != before;
  }
  if (!copied) return std::nullopt;
  ::Sleep(30);
  auto text = ReadClipboardText(owner);
  if (saved) WriteClipboardText(owner, *saved);
  return text;
}

std::wstring RunCommand() {
  wchar_t path[MAX_PATH];
  const DWORD size = ::GetModuleFileName(nullptr, path, MAX_PATH);
  return L"\"" + std::wstring(path, size) + L"\" --autostart";
}

bool AutostartEnabled() {
  wchar_t value[MAX_PATH * 2];
  DWORD bytes = sizeof(value);
  if (::RegGetValue(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                    nullptr, value, &bytes) != ERROR_SUCCESS) {
    return false;
  }
  return _wcsicmp(value, RunCommand().c_str()) == 0;
}

bool SetAutostart(bool enabled) {
  HKEY key;
  if (::RegOpenKeyEx(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  LSTATUS status;
  if (enabled) {
    const std::wstring command = RunCommand();
    status = ::RegSetValueEx(
        key, kRunValue, 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = ::RegDeleteValue(key, kRunValue);
    if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
  }
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

const flutter::EncodableValue* Argument(const flutter::EncodableValue* args,
                                        const char* name) {
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) return nullptr;
  const auto found = map->find(flutter::EncodableValue(name));
  return found == map->end() ? nullptr : &found->second;
}

int IntArgument(const flutter::EncodableValue* args, const char* name,
                int fallback) {
  const auto* value = Argument(args, name);
  if (const auto* number = value ? std::get_if<int32_t>(value) : nullptr) {
    return *number;
  }
  return fallback;
}

bool BoolArgument(const flutter::EncodableValue* args, const char* name) {
  const auto* value = Argument(args, name);
  const auto* flag = value ? std::get_if<bool>(value) : nullptr;
  return flag && *flag;
}

std::wstring StringArgument(const flutter::EncodableValue* args,
                            const char* name) {
  const auto* value = Argument(args, name);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? Utf16(*text) : std::wstring();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

UINT FlutterWindow::ShowMessage() {
  static const UINT message = ::RegisterWindowMessage(L"VocabApp.Show");
  return message;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "vocabapp/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleCall(call, std::move(result));
      });
  // GetHandle() is already null when OnDestroy runs.
  hwnd_ = GetHandle();
  taskbar_created_ = ::RegisterWindowMessage(L"TaskbarCreated");
  AddTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (hotkey_) ::UnregisterHotKey(hwnd_, kHotkeyId);
  hotkey_ = 0;
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();
  const auto* args = call.arguments();
  if (method == "setStrings") {
    open_label_ = StringArgument(args, "open");
    quit_label_ = StringArgument(args, "quit");
    hint_title_ = StringArgument(args, "hintTitle");
    hint_text_ = StringArgument(args, "hint");
    result->Success();
  } else if (method == "setHotkey") {
    const std::wstring key = StringArgument(args, "key");
    result->Success(flutter::EncodableValue(
        key.size() == 1 && RegisterSelectionHotkey(key[0])));
  } else if (method == "showPopup") {
    ShowPopup(IntArgument(args, "width", 460), IntArgument(args, "height", 440));
    result->Success();
  } else if (method == "endPopup") {
    EndPopup(BoolArgument(args, "show"));
    result->Success();
  } else if (method == "showMain") {
    ShowMain();
    result->Success();
  } else if (method == "getAutostart") {
    result->Success(flutter::EncodableValue(AutostartEnabled()));
  } else if (method == "setAutostart") {
    result->Success(
        flutter::EncodableValue(SetAutostart(BoolArgument(args, "enabled"))));
  } else if (method == "quit") {
    result->Success();
    Quit();
  } else {
    result->NotImplemented();
  }
}

void FlutterWindow::Notify(const std::string& method,
                           flutter::EncodableValue value) {
  if (channel_) {
    channel_->InvokeMethod(
        method, std::make_unique<flutter::EncodableValue>(std::move(value)));
  }
}

void FlutterWindow::AddTrayIcon() {
  if (!tray_icon_) {
    tray_icon_ = static_cast<HICON>(::LoadImage(
        ::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
        ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
        LR_DEFAULTCOLOR));
  }
  NOTIFYICONDATA data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayId;
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = tray_icon_;
  wcscpy_s(data.szTip, L"VocabApp");
  ::Shell_NotifyIcon(NIM_ADD, &data);
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_) return;
  NOTIFYICONDATA data{};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd_;
  data.uID = kTrayId;
  ::Shell_NotifyIcon(NIM_DELETE, &data);
  ::DestroyIcon(tray_icon_);
  tray_icon_ = nullptr;
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = ::CreatePopupMenu();
  ::AppendMenu(menu, MF_STRING, kMenuOpen, open_label_.c_str());
  ::AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenu(menu, MF_STRING, kMenuQuit, quit_label_.c_str());
  POINT point;
  ::GetCursorPos(&point);
  // Without this the menu does not close when clicking elsewhere.
  ::SetForegroundWindow(GetHandle());
  const UINT choice = ::TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, point.x, point.y,
      0, GetHandle(), nullptr);
  ::DestroyMenu(menu);
  if (choice == kMenuOpen) ShowMain();
  if (choice == kMenuQuit) Quit();
}

void FlutterWindow::ShowHint() {
  if (hint_shown_ || hint_text_.empty()) return;
  hint_shown_ = true;
  NOTIFYICONDATA data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayId;
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO;
  wcsncpy_s(data.szInfoTitle, hint_title_.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, hint_text_.c_str(), _TRUNCATE);
  ::Shell_NotifyIcon(NIM_MODIFY, &data);
}

void FlutterWindow::ShowMain() {
  HWND hwnd = GetHandle();
  if (popup_) {
    EndPopup(true);
    Notify("popupClosed");
    return;
  }
  ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowPopup(int width, int height) {
  HWND hwnd = GetHandle();
  if (!popup_) {
    placement_.length = sizeof(placement_);
    ::GetWindowPlacement(hwnd, &placement_);
    was_visible_ = ::IsWindowVisible(hwnd) && !::IsIconic(hwnd);
    popup_ = true;
  }
  POINT cursor;
  ::GetCursorPos(&cursor);
  HMONITOR monitor = ::MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  ::GetMonitorInfo(monitor, &info);
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const RECT work = info.rcWork;
  const int w = std::min(static_cast<int>(width * scale),
                         static_cast<int>(work.right - work.left));
  const int h = std::min(static_cast<int>(height * scale),
                         static_cast<int>(work.bottom - work.top));
  const int gap = static_cast<int>(16 * scale);
  int x = cursor.x + gap;
  int y = cursor.y + gap;
  if (x + w > work.right) x = cursor.x - gap - w;
  if (y + h > work.bottom) y = cursor.y - gap - h;
  x = std::clamp(x, static_cast<int>(work.left), static_cast<int>(work.right) - w);
  y = std::clamp(y, static_cast<int>(work.top), static_cast<int>(work.bottom) - h);
  if (::IsZoomed(hwnd) || ::IsIconic(hwnd)) ::ShowWindow(hwnd, SW_RESTORE);
  ::SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h, SWP_SHOWWINDOW);
  ::SetForegroundWindow(hwnd);
}

void FlutterWindow::EndPopup(bool show) {
  HWND hwnd = GetHandle();
  if (!popup_) {
    if (show) ShowMain();
    return;
  }
  popup_ = false;
  const bool visible = show || was_visible_;
  ::ShowWindow(hwnd, SW_HIDE);
  ::SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  WINDOWPLACEMENT placement = placement_;
  if (!visible) {
    placement.showCmd = SW_HIDE;
  } else if (placement.showCmd != SW_SHOWMAXIMIZED) {
    placement.showCmd = SW_SHOWNORMAL;
  }
  ::SetWindowPlacement(hwnd, &placement);
  if (visible) ::SetForegroundWindow(hwnd);
}

bool FlutterWindow::RegisterSelectionHotkey(UINT key) {
  HWND hwnd = GetHandle();
  if (hotkey_) ::UnregisterHotKey(hwnd, kHotkeyId);
  hotkey_ = 0;
  if (!::RegisterHotKey(hwnd, kHotkeyId, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT,
                        key)) {
    return false;
  }
  hotkey_ = key;
  return true;
}

void FlutterWindow::Quit() {
  quitting_ = true;
  ::DestroyWindow(GetHandle());
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == ShowMessage()) {
    ShowMain();
    return 0;
  }
  if (message == taskbar_created_ && taskbar_created_ != 0) {
    AddTrayIcon();
    return 0;
  }
  switch (message) {
    case WM_CLOSE:
      if (quitting_) break;
      if (popup_) {
        EndPopup(false);
        Notify("popupClosed");
      } else {
        ::ShowWindow(hwnd, SW_HIDE);
        ShowHint();
      }
      return 0;
    case WM_QUERYENDSESSION:
      // Sign-out, shutdown or an installer closing the app must really quit.
      quitting_ = true;
      return TRUE;
    case WM_HOTKEY:
      if (wparam == kHotkeyId) {
        const auto text = CopySelection(hwnd, hotkey_);
        Notify("lookup", text ? flutter::EncodableValue(Utf8(*text))
                              : flutter::EncodableValue());
        return 0;
      }
      break;
    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
          ShowMain();
          break;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
      }
      return 0;
    case WM_ACTIVATE:
      if (popup_ && LOWORD(wparam) == WA_INACTIVE) Notify("popupBlur");
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
