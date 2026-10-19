# 02 — Đối chiếu dự án 1

Kiểm tra source tại `../1.crow-translate-customize`, HEAD `2ab0fa6`, ngày 19/10/2026. Đây là kiểm tra khả năng trong source, chưa xác minh key đang có, quota, billing, deployment đang chạy hay release online mới nhất. Không đọc file bí mật.

## API thực tế

| Thành phần | Chức năng trong source | Chứng cứ |
|---|---|---|
| Google Cloud Translation Basic v2 | Dịch và nhận diện ngôn ngữ bằng API key | `src/py_crow_tool/providers/google_v2.py` |
| Azure OpenAI | Provider dịch; OCR; Refine nội dung | `providers/azure_openai.py`, `providers/azure_openai_ocr.py`, `providers/refiner.py` dưới `src/py_crow_tool/` |
| OpenAI trực tiếp | OCR và Refine dự phòng | `src/py_crow_tool/providers/openai_ocr.py`, `providers/refiner.py` |
| Google Cloud Text-to-Speech | Đọc văn bản thành tiếng | `src/py_crow_tool/providers/google_tts.py`, `services/tts.py` |

Không thấy Gemini/Vertex AI trong các provider đã kiểm tra. “Gcloud” trong dự án này là Cloud Translation và Cloud TTS; không đồng nghĩa đã có một model AI của Google tích hợp.

Azure cần endpoint + deployment + key, và API version theo adapter. OpenAI cần key + model. Google dịch và TTS là hai dịch vụ riêng; việc dùng được dịch không chứng minh TTS đã bật hoặc có quyền. Không sao chép mặc định model/API version cũ sang app mới mà chưa smoke test.

## Luồng fallback đang có

- Refine: Azure OpenAI → OpenAI cho những provider đã cấu hình; báo provider trả kết quả và lỗi trước đó. Có trong `services/refine.py`.
- OCR: chọn một trong Azure/OpenAI, không tự tráo provider; mô tả trong README và các provider OCR.
- Translation: Google v2 là luồng thông thường. Azure có provider dịch và CLI; README có phần diễn đạt GUI/`preferred_provider` chưa hoàn toàn nhất quán, không coi đây là chứng cứ đã có UI chọn tất cả dịch vụ.
- Không có bằng chứng luồng **AI tạo dữ liệu từ vựng → Google dịch dự phòng** đã được xây dựng. Đây là logic mới cho VocabApp.

## Desktop và cập nhật

Stack thực tế: Python 3.11+, PySide6/QML; Windows đóng gói bằng PyInstaller + Inno Setup. Đây là phiên bản Python viết lại; không phải app Android sẵn có.

`services/updater.py` kiểm tra redirect của GitHub Releases/latest, so sánh version, tải installer và file checksum, kiểm SHA-256, rồi chạy PowerShell chờ app thoát trước khi cài và mở lại. `.github/workflows/release.yml` nhận tag `vX.Y.Z`, chạy test, build installer và xuất release kèm checksum.

Hướng dẫn packaging có bước ký Windows, nhưng workflow đã đọc không có bước ký certificate. Vì vậy chỉ xác nhận cơ chế build/publish/checksum; không khẳng định các binary hiện tại đã được ký số. Checksum giúp phát hiện file lỗi/thay đổi, không thay thế xác thực nhà phát hành.

## Kế thừa thế nào

| Kế thừa thiết kế | Cần xây mới/port |
|---|---|
| Interface provider, phân loại lỗi, cấu hình tách theo provider | Adapter Dart và contract kết quả từ vựng |
| Refine fallback và khả năng hiển thị nguồn | Fallback theo capability: dịch đơn giản không có đủ dữ liệu ngữ nghĩa |
| Check release, tải, kiểm checksum, yêu cầu cài | Windows updater cho Flutter; Android mở trình cài APK |
| Settings có version, test provider bằng mock | SQLite và migration cho từ/nghĩa/lịch ôn; kho bí mật hệ điều hành |
| Tách UI và service | Shared domain cho học và import trên Windows/Android |

Không bê nguyên QML/Python UI sang Flutter. Học lại các quyết định tốt từ dự án 1 và port phần logic phù hợp. Repository 1 khai báo GPL-3.0-or-later; ghi nhận nguồn và quyết định phạm vi tái sử dụng code trước giai đoạn phân phối, không mặc nhiên đổi giấy phép code sao chép.

## Tài liệu chính thức đã đối chiếu

- [Flutter supported platforms](https://docs.flutter.dev/reference/supported-platforms): có Windows và Android, phù hợp hướng một codebase. Plugin vẫn cần kiểm tra riêng.
- [Flutter Android deployment](https://docs.flutter.dev/deployment/android): có luồng build APK và ký Android.
- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs): có thể ràng buộc cấu trúc đầu ra với model hỗ trợ; cấu trúc hợp lệ không bảo đảm nghĩa từ đúng, vẫn cần validate và duyệt.
- [Google Cloud Translation](https://docs.cloud.google.com/translate/docs/translate-text): API dịch văn bản, dùng cho nhánh dự phòng nghĩa dịch ngắn.

Các tài liệu web được kiểm tra cho định hướng kiến trúc, không phải bằng chứng API key cá nhân đang hoạt động.
