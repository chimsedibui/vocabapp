# 09 — Môi trường phát triển trên máy hiện tại

Kiểm tra/cài đặt ngày 19/10/2026. Cấu hình này thuộc máy phát triển, không phải dependency được đóng vào app.

## Cấu hình đã xác nhận

- Host: Windows 11 Pro, build 26200; CPU Intel Core i5-14400F, RAM vật lý 32 GB.
- Workspace hiện tại: Ubuntu 26.04 trong WSL2 x86_64, 16 logical CPUs, khoảng 15 GiB RAM khả dụng cho WSL, swap 4 GiB.
- Ổ workspace còn khoảng 872 GiB tại thời điểm bắt đầu. Có các workload khác đang chạy nên không dùng toàn bộ RAM cho Gradle/emulator.

## Thành phần

| Thành phần | Vị trí / trạng thái |
|---|---|
| Git, curl, Python, tar/xz | Đã có, giữ nguyên |
| unzip, zip, libglu1-mesa (+ libopengl0) | Đã bổ sung bằng apt; không upgrade toàn hệ thống |
| Flutter 3.47.7 / Dart 3.13.5 — Linux | `/home/khanhxoe/.local/opt/flutter` |
| Java Temurin 17.0.20.1 | `/home/khanhxoe/.local/opt/jdk-17` |
| Android SDK | `/home/khanhxoe/Android/Sdk` |
| Android CLI / command-line tools | `cmdline-tools/latest`; bản công cụ mới cảnh báo sdkmanager là wrapper deprecated, vẫn tương thích lệnh đã dùng |
| Android platform / build-tools | API 36 / 36.0.0 |
| Android platform-tools / adb | 37.0.1 / adb 1.0.41 |
| Android NDK / CMake | 28.2.13676358 / 3.22.1 |
| Flutter 3.47.7 / Dart 3.13.5 — Windows | `C:\Users\Admin\develop\flutter` |
| VS Code, Inno Setup 6 | Đã có, giữ nguyên |
| VS Code Flutter + Dart extensions | Đã cài Dart-Code.flutter và Dart-Code.dart-code 3.144.0 vào VS Code Windows |
| Visual Studio C++ Build Tools | Đã cài Build Tools 2022 17.14.42 (17.14.37806.7), MSVC và Windows SDK 10.0.26100.0 sau khi xác nhận UAC |

Flutter/Java archives đã đối chiếu SHA-256 với metadata từ nhà phát hành; Android command-line tools kiểm checksum từ repository XML. Bộ cài Visual Studio đã kiểm Authenticode hợp lệ, signer Microsoft. Flutter analytics đã tắt ở cả WSL và Windows.

## Dùng trong WSL để build Android

```bash
cd /home/khanhxoe/work/13.VocabApp
source scripts/dev-env.sh
flutter --version
java -version
flutter doctor -v
```

PATH được lưu trong `~/.config/vocabapp/dev-env.sh`, được source bởi `~/.bashrc` và `~/.profile`. Terminal đang mở có thể cần source lại như trên. `scripts/check-dev-env.sh` dùng để kiểm tra lại. SDK/API keys là hai thứ khác nhau: đợt setup này không cấu hình key AI.

Flutter doctor đã báo Android toolchain hợp lệ và licenses được chấp nhận. Không cài Android Studio hoặc emulator/system image; có thể build APK bằng command line. Để chạy tương tác cần điện thoại được cấp quyền ADB hoặc cấu hình emulator sau. Extensions đã cài trong VS Code Windows; khi mở cửa sổ Remote–WSL, VS Code có thể yêu cầu cài extension thêm vào WSL host.

Doctor trong WSL còn báo thiếu Chrome và Linux desktop compiler — hai target này không thuộc phạm vi Windows/Android. Lần doctor đầu bị chờ ở bước phát hiện thiết bị sau khi đã in kiểm tra Android; đã dừng riêng tiến trình doctor để chuyển sang build smoke. Không xem việc Android toolchain xanh là bằng chứng đã thử app trên điện thoại.

## Dùng Windows native để build Windows

```powershell
# Trong Windows PowerShell, từ thư mục dự án:
. .\scripts\dev-env.ps1
flutter --version
# Chạy khi có thể xác nhận hộp thoại Administrator:
.\scripts\install-windows-build-tools.ps1
flutter doctor -v
```

Flutter bin đã thêm vào User PATH, nhưng tiến trình/terminal cũ có thể chưa nhận; helper PowerShell cập nhật PATH của phiên hiện tại. Không trỏ Flutter Windows vào Android SDK Linux. Build Windows nên dùng source trên ổ Windows (ví dụ `C:\Users\Admin\develop\VocabApp`) thay vì chạy build từ UNC `\\wsl.localhost\...`; giữ source và đồng bộ bằng Git khi repository ứng dụng được khởi tạo. Script build hiện tạo bản sao phục vụ build tại `C:\Users\Admin\develop\VocabApp-build\app`; source chính vẫn ở workspace WSL.

Đã có C++ workload, MSVC, Windows SDK và CMake của Visual Studio. Windows Developer Mode đã được bật (`AllowDevelopmentWithoutDevLicense=1`) để Flutter tạo symlink plugin; không bật Device Portal. Script `scripts/enable-windows-dev-mode.ps1` lưu lại thao tác cấu hình này. Script cài skip nếu tìm thấy C++ tools và không tự reboot. Nếu cài dở hoặc thiếu component, dùng installer để bổ sung theo `flutter doctor`. Script và bootstrapper không vượt qua UAC; người dùng phải xác nhận theo yêu cầu Windows.

## Kiểm tra build

Smoke project riêng tại `/home/khanhxoe/.cache/vocabapp-setup/android-smoke`, tạo từ Flutter template, không phải source VocabApp. Trạng thái build được cập nhật ở phần kết quả dưới. Smoke project giới hạn Gradle heap 2 GB, metaspace 768 MB và 2 workers để không chiếm RAM của các workload đang chạy. Sau khi bổ sung Visual Studio C++, đã build và smoke-test EXE của VocabApp như kết quả ở dưới.

## Nguồn cài đặt

- [Flutter manual installation](https://docs.flutter.dev/install/manual)
- [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup)
- [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup)
- [Android SDK manager](https://developer.android.com/tools/sdkmanager)
- Flutter stable metadata: `storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` và `releases_windows.json`.
- Android tools metadata: `dl.google.com/android/repository/repository2-1.xml`.
- Java: Adoptium API + Temurin release archive.

## Kết quả kiểm tra cuối

- `flutter --version`: thành công trên WSL và Windows native, cùng Flutter 3.47.7 / Dart 3.13.5.
- `java -version`, `adb version`: thành công trong WSL.
- Flutter doctor WSL: mục Flutter và Android toolchain đạt; không kiểm chứng target Linux desktop/web.
- `flutter build apk --debug --target-platform android-arm64`: **thành công**, lần build với giới hạn RAM mất khoảng 87 giây (không tính tải/cài và lần build chuẩn bị trước đó).
- APK mẫu: `/home/khanhxoe/.cache/vocabapp-setup/android-smoke/build/app/outputs/flutter-apk/app-debug.apk`. Đây là Flutter template dùng kiểm toolchain, chưa cài/chạy trên điện thoại và không phải VocabApp.
- Windows doctor hiện nhận Visual Studio Build Tools và Windows SDK hợp lệ. Android native Windows không cài theo phân chia build Android trong WSL. Helper PowerShell dựng PATH/PATHEXT từ cấu hình native để tránh môi trường kế thừa từ WSL.
- Đã chạy 16 test thành công trực tiếp trên Windows và build release x64 VocabApp 0.1.0; đã mở EXE từ ZIP giải nén và thấy cửa sổ VocabApp cùng DB local được tạo. Installer/update vẫn chưa triển khai; M0 chưa hoàn tất toàn bộ secure storage/file import.
- Bash script đã kiểm syntax, PowerShell installer script đã parse syntax; liên kết tài liệu hợp lệ. Metadata/checksums nguồn tải được lưu tại [toolchain-downloads.json](toolchain-downloads.json). Archive tải xuống của đợt này đã dọn, SDK đã giải nén được giữ.

## Build Windows từ workspace WSL

Chạy `scripts/build-windows-alpha.ps1` bằng Windows PowerShell. Script tạo workspace riêng có marker tại `C:\Users\Admin\develop\VocabApp-build`, mirror source vào thư mục con `app` (bỏ build/cache Linux), chạy Flutter Windows rồi xuất ZIP và SHA-256 về `artifacts/`. Script từ chối ghi đè thư mục chưa có marker sở hữu.

ZIP gồm EXE, Flutter engine, SQLite và data; giải nén nguyên thư mục để chạy. Bản này chưa ký số và chưa có installer. Đã kiểm khởi động trên host hiện tại có VC++ runtime; chưa nghiệm thu ZIP trên một Windows sạch.
