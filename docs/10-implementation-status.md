# 10 — Tiến độ triển khai

Ngày 19/10/2026. Bản code đầu tiên: **offline alpha 0.1.0** trong `app/`.

## Đã triển khai

| Phần | Kết quả |
|---|---|
| Flutter shell | Có project Android và Windows, navigation responsive |
| DB | SQLite schema v1: settings, entries, senses, groups/memberships, cards, review events |
| Nhập tay | Thêm từ/cụm từ, nghĩa ngắn, mã nghĩa cho từ đa nghĩa; chọn nhóm |
| Dán danh sách | Tối đa 500 dòng, lưu nháp; gộp trùng, rollback nếu có dòng sai |
| Nhóm | Tạo, đổi tên, ẩn; thêm/bỏ membership, không reset lịch ôn |
| Thư viện | Tìm từ/nghĩa, lọc nhóm và bản nháp; sửa/duyệt nghĩa; tạm dừng/tiếp tục thẻ |
| Học | Từ → lật nghĩa → Quên/Khó/Nhớ/Dễ; desktop hỗ trợ Space và phím 1–4 |
| Lịch ôn | Scheduler v1 theo đặc tả; ưu tiên due, tối đa 20 thẻ/phiên, giới hạn từ mới 0–100/ngày |
| Tiến độ | Ghi event và schedule cùng transaction; chống ghi trùng khi retry; bảo vệ snapshot cũ |
| Thống kê | Số entry/sense/draft, thẻ đến hạn, hạn mức mới còn lại và lượt ôn hôm nay |

Ngày học dùng Asia/Ho_Chi_Minh, độc lập timezone của OS. Bản đầu cố định Anh → Việt. Tiếp tục phiên nghĩa là dựng lại queue từ card state đã lưu; chưa lưu nguyên thứ tự queue cũ. Nhóm ở cấp entry nên một từ có nhiều nghĩa sẽ đưa tất cả nghĩa active vào nhóm, đúng mô hình v1.

## Xác minh

- Static analysis và 16 test tự động đã qua trong WSL; cả 16 test cũng đã chạy thành công trực tiếp trên Windows.
- Test dùng SQLite thật (bao gồm đóng/mở lại file), fault injection để kiểm rollback, kiểm duplicate review, múi giờ và UI học.
- Widget tests kiểm layout điện thoại với chữ 150%; đây không thay thế UAT trên điện thoại thật.
- Android APK build status được ghi ở mục artifact dưới.
- Windows release x64 đã build bằng Build Tools 2022; mở EXE từ ZIP giải nén thấy cửa sổ VocabApp hoạt động và tạo DB local 86.016 bytes tại `C:\Users\Admin\AppData\Roaming\dev.vocabapp\VocabApp\vocabulary.db`. Đây là smoke test khởi động, chưa thay thế UAT đầy đủ.

## Chưa có trong alpha

Import file CSV/XLSX/JSON, converter Parquet, cấu hình API/kho key, enrichment, passage extraction, backup/restore, sync, update và installer. Đặc tả các phần này vẫn có hiệu lực, sẽ triển khai tiếp sau nền offline.

Ẩn nhóm chưa có giao diện khôi phục nhóm trong alpha; từ vẫn ở toàn thư viện và có thể gắn nhóm khác. Sửa từ hiện hỗ trợ nghĩa và giữ/reset lịch, chưa có luồng rename entry hoặc xóa/thùng rác. Chưa benchmark 10.000 nghĩa hoặc kiểm accessibility đầy đủ trên thiết bị thật.

## Dùng thử

1. Cài APK arm64 của bản alpha trên điện thoại Android tương thích.
2. Thêm từ và nghĩa; chọn “Lưu và đưa vào học”. Hoặc dán danh sách rồi mở từng bản nháp để bổ sung nghĩa.
3. Home → Học ngay → Hiện nghĩa → chọn mức nhớ.
4. Đóng/mở lại app để tiếp tục từ tiến độ đã lưu.

Đây là bản thử local chưa có backup: gỡ app hoặc xóa dữ liệu hệ thống sẽ mất thư viện. Không cần nhập API key để dùng alpha.

## Artifact đã tạo

- [ZIP Windows x64 release 0.1.0](../artifacts/VocabApp-0.1.0-windows-x64.zip), khoảng 13 MiB; [SHA-256](../artifacts/VocabApp-0.1.0-windows-x64.zip.sha256). Giải nén toàn bộ rồi chạy `vocabapp.exe`. Bản chưa ký số, chưa có installer; mới kiểm trên host phát triển có VC++ runtime.

- [APK Android arm64 debug 0.1.0](../artifacts/VocabApp-0.1.0-android-arm64-debug.apk), khoảng 79 MiB; Android 7.0/API 24 trở lên, target API 36. Đây là support kỹ thuật của APK hiện tại, chưa phải cam kết đã UAT mọi phiên bản Android.
- [SHA-256](../artifacts/VocabApp-0.1.0-android-arm64-debug.apk.sha256).
- APK được build thành công từ source VocabApp với các plugin DB thật. Chưa cài/chạy trên điện thoại vật lý.
- [Preview Home](../artifacts/preview-home.png) và [preview học](../artifacts/preview-review.png) render từ Flutter widget bằng thư viện tạm có 3 từ mẫu; không phải ảnh chụp thiết bị Windows/Android. Dữ liệu mẫu không được seed vào thư viện thật.

Artifact và dữ liệu runtime được ignore trong Git. Script `scripts/build-android-alpha.sh` tái tạo APK/checksum; `scripts/build-windows-alpha.ps1` tạo ZIP/checksum Windows; source và lockfile là đầu vào build.

## Bổ sung tài liệu flashcard — BA v0.3

[Đặc tả flashcard](11-flashcards.md) làm rõ nền đã có trong alpha và các mở rộng đề xuất. Alpha hiện vẫn chỉ có Anh → Việt, ôn theo lịch. Luyện tự do, chiều Việt → Anh, gợi ý phân biệt nghĩa và lưu thứ tự phiên chính xác chưa được triển khai. Bổ sung tài liệu này không thay phiên bản APK hoặc kết quả kiểm thử code đã nêu ở trên.

## Bản 0.2 — đã phát hành qua GitHub Actions

Đã bổ sung backup/restore có preview, checksum, rollback và recovery snapshot; kiểm tra stable release/mở trang tải từ Cài đặt; version hiển thị lấy từ package metadata. Local đã qua 23 test Flutter và test Python cho tính version. CI mới build/test cả Android và Windows, ký APK bằng key beta ổn định, tạo ZIP và installer Windows, tăng version/tag và upload release. Trạng thái run thực tế ở [GitHub Actions](https://github.com/chimsedibui/vocabapp/actions); xem [hướng dẫn release/backup](12-releases-and-backups.md).

Các phần “chưa có trong alpha” phía trên là mốc lịch sử 0.1.0; backup và kiểm tra release đã có ở 0.2. Tự tải/cài update trong app, sync, API/passage và import vẫn chưa triển khai.

### Kết quả CI v0.2.0

[Run 39204825292](https://github.com/chimsedibui/vocabapp/actions/runs/39204825292) thành công: 23 test Flutter trên mỗi nền tảng, test tính version, build/ký APK, build Windows, đóng installer/ZIP và publish [v0.2.0](https://github.com/chimsedibui/vocabapp/releases/tag/v0.2.0). Đã tải lại cả ba gói và kiểm SHA-256/size với manifest. APK có versionName 0.2.0, versionCode 2 và certificate trùng APK alpha 0.1.0.

Chưa UAT thao tác file picker trên điện thoại thật, chưa tự tải/cài update trong app; người dùng tải/cài gói từ trang Releases. Các artifact CI cũng đã được chép vào Downloads của Windows để cài thử.

### Kết quả tự động tăng phiên bản v0.2.1

[Run 39205602755](https://github.com/chimsedibui/vocabapp/actions/runs/39205602755) thành công và tự tăng version từ 0.2.0+2 lên 0.2.1+3, commit pubspec/tag rồi publish đủ 7 assets. Đã kiểm checksum/size ba gói tải xuống, metadata Windows/APK và kiểm tra release thực tế qua service của app. Bản mới nhất: [v0.2.1](https://github.com/chimsedibui/vocabapp/releases/tag/v0.2.1). Installer, ZIP và APK đã có trong Downloads của Windows.
