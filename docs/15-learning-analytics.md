# 15 — Phân tích học tập

Triển khai ngày 10/11/2026. Mục tiêu: dùng chính hành vi ôn từ để trả lời các câu hỏi sau.
- Mỗi tuần học được bao nhiêu từ?
- Nhớ có chắc không?
- Học lúc nào hiệu quả nhất?
- Phiên học dài bao nhiêu là vừa?
- Từ nào đang làm khó mình?

Toàn bộ phân tích chạy trong app (Hôm nay → **Xem phân tích**). Không gửi dữ liệu ra ngoài.

## 1. Dữ liệu thu thập

Mỗi lượt chấm thẻ ghi một dòng vào `review_events`.

| Trường | Có từ | Dùng để |
|---|---|---|
| `rating` (Quên/Khó/Tạm/Nhớ/Dễ) | v1 | Điểm 1–5, tỉ lệ nhớ, xu hướng |
| `reviewed_at`, `study_day` | v1 | Theo ngày/tuần, buổi trong ngày, đều đặn |
| `previous_state` → `new_state` | v1 | Thẻ "đã qua", kiểm tra trí nhớ thật |
| `previous_interval`, `previous_due` | v1 | Tỉ lệ nhớ theo khoảng cách ôn, ôn trễ hạn |
| `was_new`, `scheduler_version` | v1 | Từ mới mỗi tuần; tách dữ liệu khi đổi thuật toán |
| **`session_id`** | **DB v6** | Gom lượt ôn thành phiên. Nghỉ quá 5 phút thì sang phiên mới |
| **`shown_at`** | **DB v6** | Lúc mặt trước được hiện (lần cuối, trước khi lật lần đầu) |
| **`flipped_at`** | **DB v6** | Lúc lật xem đáp án lần đầu |

- Lượt ôn trước DB v6 không có ba trường mới: chúng vẫn được tính vào mọi chỉ số, trừ thời gian học, phiên học và đường cong mệt.
- Không ghi các sự kiện mất focus hay undo (quyết định ngày 10/11/2026).

## 2. Định nghĩa chỉ số

| Chỉ số | Công thức |
|---|---|
| **Từ đã qua** | Thẻ lần đầu chuyển sang `review` (xong các bước 1 phút/10 phút/1 giờ). Mỗi thẻ chỉ đếm một lần |
| **Từ vững** | Thẻ `review` có interval ≥ 21 ngày |
| **Tốc độ học** | Số từ đã qua trong 4 tuần gần nhất ÷ 4 |
| **Tỉ lệ nhớ** | % lượt **không** chấm "Quên", chỉ tính thẻ đang ở `review`, tức kiểm tra trí nhớ thật sau ≥1 ngày |
| **Phút học** | Tổng của (`reviewed_at` − `shown_at`) qua các lượt, mỗi thẻ tối đa 2 phút để thẻ bỏ quên không bị tính |
| **Phút học mỗi ngày** | Phút học theo ngày học, 14 ngày gần nhất; trung bình chỉ tính ngày có học |
| **Độ dài phiên** | Phút học thực của phiên, chia khung <10, 10–20, 20–30, 30–45, >45 phút (90 ngày). Mỗi khung có số phiên và % thẻ không "Quên" |
| **Thời gian nghĩ** | `flipped_at` − `shown_at`, lấy trung vị trong 30 ngày |
| **Điểm rating** | Quên = 1, Khó = 2, Tạm = 3, Nhớ = 4, Dễ = 5. Trung bình theo tuần |
| **Xu hướng từng từ** | Với từ được ôn ≥ 2 lần trong 7 hoặc 30 ngày: so lần chấm cuối với lần chấm đầu → tăng / giữ / giảm |
| **Đường cong mệt** | % không "Quên" theo thứ tự thẻ trong phiên: 1–10, 11–20, 21–30, 31–40, >40 |
| **Từ khó (leech)** | `lapses` ≥ 3 hoặc ≥ 4 lần "Quên". Hiện 8 lượt chấm gần nhất |
| **Lịch ôn 14 ngày** | Đếm `cards.due_at` theo ngày; thẻ quá hạn tính vào hôm nay |

Code: [analytics.dart](../app/lib/domain/analytics.dart) (công thức thuần, có test) và [analytics_repository.dart](../app/lib/data/analytics_repository.dart) (đọc SQLite, xuất CSV).

## 3. Các yếu tố đánh giá hành vi học

Chia làm hai nhóm: **kết quả**, tức đo xem đã học được gì, và **hành vi**, tức cách bạn học, thứ có thể thay đổi để cải thiện kết quả.

### Kết quả (đầu ra)

| Yếu tố | Chỉ số trong app | Đọc thế nào |
|---|---|---|
| Lượng từ học được | Từ đã qua, từ vững, tốc độ/tuần | Chỉ số chính để theo dõi tiến bộ |
| Độ bền trí nhớ | Tỉ lệ nhớ theo khoảng cách ôn | Mục tiêu 85–90%. Tỉ lệ giảm mạnh ở khoảng dài là quên nhanh |
| Chất lượng nhớ | Điểm rating TB, xu hướng tăng/giảm | Nhiều từ "giảm" là đang nhớ mập mờ |
| Chi phí | Phút học / từ đã qua | Phút học tăng mà từ đã qua không tăng là học kém hiệu quả |

### Hành vi (đầu vào, có thể điều chỉnh)

| Yếu tố | Đo bằng | Giả thuyết cần kiểm chứng |
|---|---|---|
| **Đều đặn** | Số ngày có học / 30, streak | Học ít mà đều tốt hơn dồn vào một buổi |
| **Ôn đúng hạn** | Tỉ lệ nhớ: đúng hạn / trễ 2–7 / trễ >7 ngày | Trễ hạn làm tỉ lệ nhớ tụt, kéo theo nhiều lượt "Quên" |
| **Độ dài phiên** | Đường cong mệt, số thẻ/phiên | Có một ngưỡng mà sau đó tỉ lệ nhớ tụt: đó là độ dài phiên tối ưu |
| **Thời điểm học** | Tỉ lệ nhớ theo buổi (sáng/trưa/chiều/tối/khuya) | Có buổi bạn tỉnh táo hơn: nên học từ mới vào buổi đó |
| **Tốc độ thêm từ mới** | Từ mới/tuần so với từ đã qua/tuần, lịch ôn 14 ngày | Thêm từ mới quá nhanh làm thẻ dồn và tỉ lệ nhớ giảm |
| **Cách chấm / tập trung** | Thời gian nghĩ trước khi lật | Nghĩ quá lâu là đoán mò hoặc phân tán; nên lật sau ~5 giây |
| **Chất lượng nội dung từ** | Từ khó (leech) | Từ quên lặp lại thường thiếu ngữ cảnh, dễ nhầm với từ khác, hoặc có nghĩa quá rộng |

### Các đòn bẩy để cải thiện (theo mức tác động dự kiến)

1. **Học mỗi ngày, ôn hết thẻ đến hạn trước khi học từ mới.** Ôn đúng hạn là yếu tố tác động lớn nhất trong lặp lại ngắt quãng.
2. **Giới hạn độ dài phiên** theo đường cong mệt, ví dụ phiên 10–20 thẻ rồi nghỉ 1–2 phút.
3. **Điều chỉnh số từ mới theo tỉ lệ nhớ.** Dưới 80% thì giảm từ mới; trên 95% thì tăng.
4. **Học từ mới vào buổi bạn nhớ tốt nhất**, buổi kém hơn thì chỉ ôn.
5. **Xử lý từ khó**: thêm câu ví dụ trong passage, ghi chú cách nhớ, tách nghĩa dễ nhầm, hoặc tạm dừng.
6. **Chấm thật.** Nghĩ quá 5 giây chưa ra thì lật và chấm "Khó"/"Quên" để thẻ quay lại sớm.

## 4. Gợi ý tự động

Mục "Gợi ý cho bạn" sinh câu khuyên từ các luật dưới đây. Mỗi tỉ lệ chỉ được dùng khi có ≥ 15 lượt.

| Điều kiện | Gợi ý |
|---|---|
| Tỉ lệ nhớ 30 ngày < 80% / > 95% | Giảm / tăng số từ mới mỗi phiên |
| Một nhóm thẻ trong phiên thấp hơn nhóm 1–10 ≥ 10 điểm % | Chia phiên ở ngưỡng trước đó |
| Khung độ dài phiên tốt nhất hơn khung kém nhất ≥ 10 điểm % (mỗi khung ≥ 3 phiên, ≥ 15 thẻ) | Ưu tiên phiên dài bằng khung tốt nhất |
| Buổi tốt nhất hơn buổi kém nhất ≥ 10 điểm % | Học từ mới vào buổi tốt nhất |
| Ôn đúng hạn hơn ôn trễ ≥ 10 điểm % | Học đều mỗi ngày |
| Học < 15/30 ngày | Đặt mốc học cố định mỗi ngày |
| ≥ 50 thẻ đến hạn hôm nay | Ôn trước, tạm ngừng từ mới |
| 30 ngày: từ giảm > từ tăng (≥ 10 từ) | Đang thêm từ nhanh hơn khả năng ôn |
| ≥ 3 từ khó | Thêm ví dụ/ghi chú hoặc tạm dừng |
| Thời gian nghĩ trung vị > 8 giây | Lật sau ~5 giây |

## 5. Forecast

| Mức dữ liệu | Có trong app | Hướng mở rộng |
|---|---|---|
| Ngay từ đầu | Lịch ôn 14 ngày tới (tính thẳng từ `due_at`) | Cộng thêm từ mới dự kiến mỗi ngày |
| ≥ 4 tuần | "Giữ tốc độ này, 4 tuần nữa có ~N từ đã qua" (tuyến tính) | Khoảng tin cậy theo độ dao động giữa các tuần |
| ≥ ~1000 lượt kiểm tra trí nhớ | — | Mô hình xác suất nhớ từng từ: Half-Life Regression hoặc fit tham số FSRS cho riêng bạn, rồi dùng để thay scheduler v2 (`scheduler_version` 3) |
| ≥ 2–3 tháng | — | Thử nghiệm cá nhân A/B: hai tuần phiên 10 thẻ, hai tuần phiên 20 thẻ; so tốc độ học và tỉ lệ nhớ |

## 6. Xuất dữ liệu

Cài đặt → Dữ liệu → **Xuất lượt ôn (CSV)**. File UTF-8 có BOM, mỗi dòng một lượt ôn gồm: từ, nghĩa, rating, điểm, các mốc thời gian ISO UTC, `think_ms`, `answer_ms`, trạng thái/interval trước và sau, số lần quên của thẻ. Dùng khi muốn tự phân tích sâu hơn ngoài app.

## 7. Tương thích và giới hạn

- **DB v6** thêm 3 cột nullable vào `review_events`. Backup lên **format 5**; backup 1–4 vẫn khôi phục được, các cột mới để trống.
- **Sync khi hai máy khác phiên bản:**
  - App gửi kèm `schema` (phiên bản DB), số phiên bản app và hệ điều hành mỗi lần đồng bộ.
  - Worker cắt các cột mà máy cũ chưa biết trước khi gửi xuống, nên máy cũ vẫn đồng bộ bình thường.
  - Khi máy cũ gửi lại một lượt ôn, worker giữ nguyên dữ liệu thời gian đang có trên server.
  - Máy mới hiện thông báo "… chưa cập nhật" ở Hôm nay và Cài đặt → Đồng bộ, áp dụng cho máy đã đồng bộ trong 30 ngày gần nhất.
  - Khi máy cũ lên DB v6, app kéo lại toàn bộ dữ liệu một lần để lấy đủ dữ liệu thời gian.
  - **Cần deploy lại Worker trước khi cài app mới**; nếu không, máy cũ vẫn báo "cập nhật app" như trước.
- Thời gian học chỉ tính từ bản này trở đi, và mỗi thẻ tối đa 2 phút.
- Dữ liệu cá nhân ít, nên chênh lệch nhỏ giữa các nhóm chỉ là nhiễu. Gợi ý chỉ xuất hiện khi chênh ≥ 10 điểm % và có đủ lượt.

## Xác minh

`flutter analyze` sạch; 104 test Flutter qua, gồm:
- Công thức: từ đã qua, phút học có giới hạn 2 phút, tỉ lệ nhớ theo khoảng cách, xu hướng 7/30 ngày, đường cong mệt, buổi trong ngày, ôn trễ hạn, từ khó, gợi ý.
- Lưu thời gian khi chấm thẻ qua UI.
- Xuất CSV có ký tự đặc biệt.
- Khôi phục backup format 4.
- Nâng cấp DB cũ lên v6.
- Trang Phân tích render ở 390 px và 1280 px.
