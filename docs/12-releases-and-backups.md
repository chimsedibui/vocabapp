# 12 — GitHub, phát hành và backup từ 0.2

Ngày 19/10/2026. Repository public: [chimsedibui/vocabapp](https://github.com/chimsedibui/vocabapp). Dữ liệu người học, backup, key AI và khóa ký không nằm trong repository.

## CI và version

- Pull request chạy format, static analysis, test Flutter và test tính version; không dùng signing secrets.
- Push thay đổi app/pipeline vào `main` chạy **Build and release**. Hai job build Android/Windows cùng dùng một version và build number.
- Chưa có tag: phát hành version trong `app/pubspec.yaml`. Những push sau mặc định tăng patch và build number. Nếu developer đặt version nguồn cao hơn tag mới nhất, CI dùng version đó và vẫn đảm bảo Android build number tăng.
- Có thể chạy workflow thủ công với `auto`, `patch`, `minor`, `major`. Ví dụ: `gh workflow run release.yml --repo chimsedibui/vocabapp -f bump=minor`.
- Chỉ khi cả hai nền tảng đã test/build thành công, CI cập nhật `app/pubspec.yaml` nếu cần, push commit + tag atomically, upload draft release và công khai khi đầy đủ asset. Commit version có `[skip ci]` và dùng `GITHUB_TOKEN` để không tạo vòng lặp.
- Nếu source `main` đổi trong lúc build, run cũ không phát hành bản từ commit cũ. Run mới thay thế. Không push commit docs chen giữa một release đang chạy nếu không có run tiếp theo; khi đó có thể chạy lại workflow thủ công.
- Sau khi bot tăng version, luôn `git pull --ff-only` trước khi sửa/push tiếp. Không force-push lịch sử release.
- Các action được pin SHA từ release chính thức; Flutter SDK cố định 3.47.7 và dependencies cố định bằng lockfile.

Kết quả trên [Releases](https://github.com/chimsedibui/vocabapp/releases): APK arm64 release, ZIP Windows x64, installer Windows per-user, SHA-256 cho từng gói và `release.json`. Windows gói thêm VC++ runtime từ Visual Studio runner. Không cần Microsoft Store hoặc Google Play.

APK CI dùng khóa ký ổn định trong GitHub Secrets. Giai đoạn beta đang dùng cùng khóa local đã ký alpha 0.1.0, để giữ khả năng cài đè dữ liệu cũ. Đây vẫn là khóa beta/debug certificate, chưa phải quy trình production signing. Không tự đổi khóa hoặc Application ID (`dev.vocabapp.vocabapp`), nếu không Android sẽ từ chối cài đè. Windows installer/ZIP chưa ký Authenticode.

## Kiểm tra cập nhật trong app

Cài đặt → Kiểm tra bản mới: đọc stable release mới nhất từ đúng repo, so sánh version bằng số; không dùng prerelease hoặc downgrade. Không tự gọi mạng lúc học. “Mở trang phát hành” mở browser để người dùng xem thay đổi, tải gói và xác nhận cài.

Bản này **chưa tự tải/checksum/cài trong app**. CI cung cấp checksum để kiểm tra file tải, Android kiểm chữ ký package khi cài đè; Windows installer giữ nguyên AppId và thư mục DB. Không coi Windows binary chưa ký là đã có xác thực nhà phát hành. Cơ chế tải/kiểm/cài tích hợp sẽ triển khai tiếp theo FR13.

## Backup/restore

Cài đặt → Sao lưu tạo file `.vocabbackup`, là JSON snapshot có `format`, version format/DB, thời gian tạo, SHA-256 payload và 7 bảng nội dung/tiến độ. Giữ UUID, nhóm, các nghĩa, card state, lịch ôn và review events. Không gọi API hoặc ghi dữ liệu người học lên GitHub.

Khôi phục có preview số từ/nghĩa/lượt ôn và xác nhận thay thế toàn thư viện. Không merge hai máy. Trước khi thay, app lưu snapshot hiện tại vào thư mục support của app, dưới `recovery/before-restore-*.vocabbackup`. Nếu ghi recovery thất bại hoặc insert/FK/state không hợp lệ, transaction rollback và giữ thư viện đang dùng. Device ID hiện tại được giữ để hai máy không nhận cùng định danh thiết bị.

Backup tối đa 20 MiB; phiên bản chưa biết hoặc checksum sai bị từ chối. Checksum giúp phát hiện file hỏng/chỉnh sửa, không phải chữ ký xác thực nguồn; chỉ khôi phục file của mình. File chứa dữ liệu học cá nhân và chưa được mã hóa. Recovery trước restore hiện được giữ để người dùng tự quản lý, chưa có màn quản lý/xóa recovery.

Triển khai dùng snapshot logic và transaction trong DB đang mở (có kiểm toàn vẹn), thay cho đổi file DB vật lý của đề xuất ban đầu. Việc ghi recovery nằm trong cùng transaction khóa ghi, tránh mất một thay đổi xen giữa snapshot và restore. Không đổi DB schema version 1 trong đợt này.

## Còn phải triển khai

Cấu hình API và secure storage, enrichment/fallback, passage B1+, nhập CSV/JSON/XLSX, Parquet converter, sync, flashcard mở rộng. Backup và kiểm tra stable release hiện là nền cho các mốc đó; không coi toàn bộ MVP đã hoàn tất.

## Tham chiếu vận hành

- [GitHub: bỏ qua workflow theo commit](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)
- [GitHub: sự kiện phát sinh từ GITHUB_TOKEN](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

## Lần phát hành đầu đã xác nhận

[CI v0.2.0](https://github.com/chimsedibui/vocabapp/actions/runs/39204825292) đã hoàn thành đủ version → Android/Windows → publish. [Release công khai](https://github.com/chimsedibui/vocabapp/releases/tag/v0.2.0) có 7 assets: APK, ZIP, installer, 3 checksum và release.json. Cả ba gói đã được tải lại và kiểm manifest; chữ ký APK giữ nguyên từ alpha 0.1.0. Bộ tính version sau khi fetch tag hiện trả 0.2.1+3 cho push app tiếp theo.

## Xác nhận tự tăng version v0.2.1

[Run 39205602755](https://github.com/chimsedibui/vocabapp/actions/runs/39205602755) đã phát hành [v0.2.1](https://github.com/chimsedibui/vocabapp/releases/tag/v0.2.1) từ push sửa workflow. CI tự chọn 0.2.1+3, tạo commit `d8a7395` cập nhật pubspec và tag, không sinh run lặp. Cả hai nền tảng qua test/build. Đã tải lại và đối chiếu SHA-256/size của đủ ba gói với manifest; Windows binary có ProductVersion/FileVersion 0.2.1+3, APK có versionName 0.2.1/versionCode 3 và giữ certificate beta. File cài đặt đã chép vào Downloads trên Windows. Chưa thay thế UAT trên thiết bị thật.
