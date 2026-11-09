# 16 — Phân tích hành vi học (BA)

Ngày 10/11/2026. Tài liệu này bổ sung cho [15 — Phân tích học tập](15-learning-analytics.md) và trả lời bốn câu hỏi:
- DB còn những dữ liệu nào chưa khai thác?
- Nên ghi thêm dữ liệu gì?
- Rút ra được những insight nào?
- Bước tiếp theo nên làm gì?

## 1. Insight từ dữ liệu hiện có

Nguồn: bản sao DB trên Windows (`%APPDATA%\dev.vocabapp\VocabApp\vocabulary.db`, DB v5), đọc chỉ-đọc ngày 10/11/2026.

Quy mô: 111 từ, 242 lượt ôn trên 83 thẻ, 8 ngày học trong khoảng 21/10 → 10/11/2026.

**Mẫu còn rất nhỏ.** Các con số dưới đây chỉ là tín hiệu ban đầu để định hướng, chưa phải kết luận. Theo [17 — Tổng quan nghiên cứu](17-research-review.md), muốn so sánh hai nhóm chênh 10 điểm % cần khoảng 300–400 lượt mỗi nhóm.

Ngày 10/11/2026, kiểm lại có tách thẻ mới / bước ngắn / thẻ ôn lại, nên đã sửa các dòng 2, 3, 5.

| # | Quan sát | Số liệu | Gợi ý hành động |
|---|---|---|---|
| 1 | **Nạp từ theo đợt lớn, sau đó dồn** | 110/111 từ được thêm trong cùng một ngày (01/11), qua 3 passage B2 Gemini. Sau 9 ngày còn 28 từ (25%) chưa ôn lần nào | Chia passage thành các đợt nhỏ. Theo dõi chỉ số "tồn kho từ chưa học" |
| 2 | **Học dồn rồi nghỉ** (đã sửa) | Ngày nhiều nhất 70 lượt nhưng chỉ 58 từ khác nhau (67 lượt là 46 từ). Phần còn lại là thẻ quay lại trong phiên. Nghỉ liền 3 ngày (05–07/11). 8 ngày học trên 21 ngày | Vẫn là học dồn nhưng nhẹ hơn con số lượt ôn. Nên đo theo số **từ khác nhau** mỗi ngày, không theo lượt |
| 3 | **Phần lớn học khuya; ~~khuya nhớ kém hơn~~: sai, do nhiễu** | 74% lượt ôn rơi vào 22–23 giờ. Khuya trông kém hơn chỉ vì phần lớn từ mới được học vào buổi tối. Riêng thẻ ôn lại: 22 giờ 100% (n = 37), 23 giờ 91% (n = 34), 10 giờ 100% (n = 10) | Chưa có bằng chứng giờ học ảnh hưởng tới trí nhớ. Nghiên cứu còn cho thấy học tối rồi ngủ có lợi (Mazza 2016). Muốn kết luận thì phải chỉ so thẻ ôn lại, hoặc tự làm thử nghiệm sáng/tối (xem docs 17) |
| 4 | **Lần đầu gặp từ mới khó** | Không-quên ở lần gặp đầu 66% (n = 83), ở bước ngắn 87%, ở thẻ đã qua 96% (n = 82) | Hợp lý. Tỉ lệ 96% chưa đủ để kéo dài interval vì "Khó" đang được tính là nhớ (xem dòng 5), và với n = 82 thì sai số khoảng ±5–10% |
| 5 | **"Khó" ở thẻ ôn lại** (đã sửa) | Tổng Khó 29%, nhưng phần lớn là ở bước ngắn (28/77), nơi "Khó" chỉ có nghĩa là quay lại sau 10 phút, nên bình thường. Đáng chú ý là ở thẻ ôn lại: Khó 21/82 (26%) | Scheduler v2 đưa thẻ ôn lại bấm "Khó" về học lại sau 1 giờ, gần như là quên. Thế nhưng chỉ số "tỉ lệ nhớ" lại tính "Khó" là nhớ, nên con số 96% đang bị thổi phồng. Cần thống nhất "Khó" là nhớ hay quên (Anki/FSRS coi "Khó" là nhớ) |
| 6 | **Cấp CEFR càng cao, càng hay quên** | Tỉ lệ không-quên trung bình theo thẻ: B2 0,91 (59 từ), C1 0,83 (43 từ), C2 0,62 (9 từ). Số lần quên: B2 7, C1 14, C2 4 | Mỗi phiên trộn ít từ C1/C2 hơn. Ưu tiên thêm câu ví dụ cho từ C1/C2 |
| 7 | **Động từ dễ nhớ hơn tính từ và danh từ** | Không-quên theo thẻ: động từ 0,97 (20), danh từ 0,82 (45), tính từ 0,80 (40) | Tính từ trừu tượng (phenomenal, conducive…) cần thêm ngữ cảnh |
| 8 | **Đã có từ khó** | equatorial (quên 4, lapses 3), phenomenal 3, conducive 3, ingenious 2 | Thêm ví dụ, ghi chú hoặc tách nghĩa cho các từ này |
| 9 | **Thẻ qua nhanh** | Trung bình 1,4 lượt từ khi gặp đến khi "đã qua"; 71/111 thẻ đã qua | Có thể nhiều thẻ được chấm "Nhớ/Dễ" ngay lần đầu, dẫn tới vào interval dài sớm. Cần đo tỉ lệ quên ở lần kiểm tra đầu tiên sau khi qua |
| 10 | **Chưa có từ nào có câu ví dụ** | `senses.note` trống ở 111/111 từ. Câu ví dụ từ passage mới có từ 09/11 | Tạo điều kiện so sánh "có ví dụ" với "không có ví dụ" một cách tự nhiên từ các đợt passage tới |
| 11 | **Chưa thấy dấu hiệu quá tự tin** | 0 trường hợp chấm "Dễ" rồi sau đó "Quên" | Đo lại khi interval đã dài hơn 10 ngày |

Thời gian ngồi học hằng ngày tính từ lượt đầu tới lượt cuối trong ngày, ví dụ 01/11 là 272 phút. Con số này gồm cả quãng nghỉ, nên chưa tin được. Từ DB v6 sẽ có `session_id` và `shown_at` để tính chính xác.

## 2. Kiểm kê dữ liệu: những gì chưa khai thác

| Bảng / cột | Hành vi có thể suy ra | docs/15 đã dùng? |
|---|---|---|
| `entries.created_at` | Nhịp nạp từ, tồn kho từ chưa học, thời gian từ lúc thêm tới lần ôn đầu | Chưa |
| `sense_origins.estimated_level`, `level_source`, `provider/model` | Độ khó CEFR so với tỉ lệ nhớ; LLM có xếp mức đúng không (người dùng có sửa level không) | Chưa |
| `sense_origins.job_id` → `passage_jobs` | Nguồn từ: passage, import hay nhập tay; passage nào cho nhiều từ khó | Chưa |
| `passage_jobs.min_level`, `max_items`, `removed` | Bao nhiêu từ LLM đề xuất bị bỏ, tức mức độ lọc của người dùng | Chưa |
| `import_batches` | Nạp từ qua file theo đợt | Chưa |
| `senses.part_of_speech`, `pronunciation`, `note` (câu ví dụ) | Loại từ, có phiên âm hay có ví dụ, so với tỉ lệ nhớ | Chưa |
| `sense_history` (SCD2) | Sửa nghĩa sau khi quên: sửa xong có nhớ tốt hơn không | Chưa |
| `review_events.content_revision` | Lượt ôn trước và sau khi sửa nội dung | Chưa |
| `deck_entries`, `decks` | Hiệu quả theo nhóm hoặc chủ đề | Chưa |
| `cards.suspended`, `lapses` | Né từ khó (tạm dừng), độ lì của từ | Một phần (leech) |
| `review_events.new_interval`, `new_state` | Số bước cần để qua, tỉ lệ nhớ ở lần kiểm tra đầu sau khi qua | Một phần |
| `review_events.study_day` (thứ trong tuần) | Thói quen theo thứ | Chưa |
| `session_id`, `shown_at`, `flipped_at` (v6) | Thời gian bắt đầu phiên, số thẻ mỗi phiên, tốc độ chấm | Có |
| `entries.term` | Độ dài từ, cụm nhiều từ | Chưa |

## 3. Dữ liệu nên ghi thêm

Mọi dữ liệu dưới đây chỉ lưu cục bộ và đồng bộ như dữ liệu hiện có. Không theo dõi mất focus hay undo (đã loại).

| Ưu tiên | Ghi gì | Trả lời câu hỏi | Cách lưu | Chi phí |
|---|---|---|---|---|
| **P1** | **Phiên học**: lúc mở và đóng phiên, số thẻ trong hàng đợi, số thẻ đã chấm | Có bỏ dở phiên không; nên đặt hàng đợi bao nhiêu thẻ | Bảng `study_sessions(id, started_at, ended_at, queued, rated, deck_id)` | Thấp |
| **P1** | **Bỏ qua thẻ**: vuốt qua mà không chấm | Từ nào hay bị né. Né từ thường là dấu hiệu từ khó trước cả khi quên | `study_session_events(session_id, card_id, kind='skip', at)` | Thấp |
| **P1** | **Xem lại đáp án**: số lần lật qua lại trước khi chấm | Lưỡng lự, nhớ mập mờ | Cột `flips INTEGER` trong `review_events` | Rất thấp |
| P2 | **Nghe phát âm (R)** | Phát âm có giúp nhớ không; từ nào hay phải nghe | `study_session_events kind='speak'` | Thấp |
| P2 | **Mở chi tiết từ / ví dụ** trong lúc học | Có tra thêm ngữ cảnh không, và tra xong có nhớ tốt hơn không | `kind='details'` | Thấp |
| P2 | **Tự đánh giá đầu phiên**: năng lượng 1–3, có thể bỏ qua | Giải thích những phiên học tệ | Cột `energy` trong `study_sessions` | Thấp, cần 1 chạm |
| P2 | **Lý do tạm dừng từ** (quá khó / không cần / trùng) | Phân biệt né từ khó với dọn rác | Cột `suspend_reason` trong `cards` | Thấp |
| P3 | **Nguồn ngữ cảnh**: câu gốc trong passage | Từ có ngữ cảnh gốc so với từ nhập tay | Đã có `note`/`job_id`; chỉ cần đánh dấu đã hiện cho người học | Rất thấp |
| P3 | **Hướng thẻ** (EN→VI / VI→EN) khi có chiều học mới | Chiều nào khó hơn | Cột `direction` trong `review_events` | Thấp |

## 4. Danh mục insight

"Có sẵn" nghĩa là đã tính được từ dữ liệu DB v5/v6. "Cần mới" là cần dữ liệu ở mục 3.

### Thu nạp từ

| Câu hỏi | Chỉ số / công thức | Dữ liệu | Tối thiểu | Biểu đồ | Hành động |
|---|---|---|---|---|---|
| Nạp từ có vượt khả năng học không? | Tồn kho = số thẻ `new` theo ngày; từ thêm/tuần so với từ qua/tuần | Có sẵn | 2 tuần | Hai đường trên cùng một trục (đơn vị: từ) | Tồn kho tăng quá 2 tuần thì tạm dừng thêm passage |
| Từ chờ bao lâu mới được học? | Trung vị (lần ôn đầu − `created_at`) | Có sẵn | 30 từ | Histogram | Hiện tại trung bình 51 giờ, 25% chưa học. Giảm `max_items` mỗi passage |
| Nguồn từ nào dễ nhớ hơn? | Tỉ lệ nhớ theo nguồn (passage / import / tay) | Có sẵn | 30 kiểm tra mỗi nguồn | Cột | Ưu tiên nguồn cho tỉ lệ nhớ cao |
| Người dùng lọc đề xuất LLM thế nào? | `removed` / số đề xuất mỗi passage | Có sẵn | 5 passage | Cột | Lọc nhiều thì nâng `min_level` hoặc giảm `max_items` |

### Ghi nhớ

| Câu hỏi | Chỉ số / công thức | Dữ liệu | Tối thiểu | Biểu đồ | Hành động |
|---|---|---|---|---|---|
| Từ khó cỡ nào thì vượt sức? | Tỉ lệ nhớ và số lần quên theo CEFR | Có sẵn | 30 kiểm tra mỗi mức | Cột | Giới hạn số từ C1/C2 mỗi phiên |
| Loại từ nào khó? | Tỉ lệ nhớ theo `part_of_speech` | Có sẵn | 30 mỗi loại | Cột | Thêm ví dụ cho loại khó |
| "Qua" có thật sự chắc không? | Tỉ lệ nhớ ở **lần kiểm tra đầu tiên sau khi qua** | Có sẵn | 30 thẻ | Một con số + xu hướng | Dưới 80% thì bước qua đang quá dễ |
| Có chấm quá tự tin không? | P(Quên ở lần sau \| Dễ ở lần này) so với P(Quên \| Nhớ) | Có sẵn | 50 cặp | Ma trận chuyển rating | "Dễ" quên nhiều thì nên bấm "Nhớ" |
| Sửa nghĩa có giúp không? | Tỉ lệ nhớ trước và sau khi `content_revision` tăng, chỉ tính từ đã từng quên | Có sẵn | 10 từ được sửa | Cặp cột trước/sau | Nếu có ích thì gợi ý sửa từ khó |
| Câu ví dụ có giúp nhớ không? | Tỉ lệ nhớ: có `note` / không có `note` | Có sẵn (từ 09/11) | 30 mỗi nhóm | Cột | Có ích thì luôn yêu cầu ví dụ |
| Cụm từ có khó hơn từ đơn? | Tỉ lệ nhớ theo số từ trong `term` và theo độ dài | Có sẵn | 20 cụm | Cột | — |

### Phiên học

| Câu hỏi | Chỉ số / công thức | Dữ liệu | Tối thiểu | Biểu đồ | Hành động |
|---|---|---|---|---|---|
| Có bỏ dở phiên không? | % phiên có `rated < queued` | Cần mới (P1) | 10 phiên | Cột theo tuần | Hay bỏ dở thì giảm hàng đợi mặc định từ 20 xuống 10 |
| Từ nào hay bị né? | Số lần bỏ qua mỗi thẻ | Cần mới (P1) | 2 tuần | Danh sách | Gộp vào danh sách từ khó |
| Lưỡng lự trước khi chấm? | Số lần lật > 1, thời gian từ lật tới chấm | Cần mới + v6 | 100 lượt | Phân phối | Lưỡng lự nhiều thì đó là nhớ mập mờ |
| Phát âm có giúp nhớ? | Tỉ lệ nhớ khi có nghe so với không nghe | Cần mới (P2) | 50 mỗi nhóm | Cột | — |

### Thói quen

| Câu hỏi | Chỉ số / công thức | Dữ liệu | Tối thiểu | Biểu đồ | Hành động |
|---|---|---|---|---|---|
| Học dồn hay học đều? | Hệ số biến thiên số lượt mỗi ngày; số ngày nghỉ liên tiếp dài nhất | Có sẵn | 3 tuần | Heatmap lịch | Hệ số cao thì đặt trần lượt mỗi ngày |
| Ngày nào trong tuần hay bỏ học? | Số lượt theo thứ | Có sẵn | 4 tuần | Cột 7 thứ | Nhắc học vào ngày hay bỏ |
| Học trễ giờ có kém hơn? | Tỉ lệ nhớ theo giờ, **chỉ tính thẻ ôn lại** | Có sẵn | ~300 mỗi khung để thấy chênh 10 điểm % | Cột + khoảng tin cậy | Hiện chưa thấy khác biệt. Muốn kết luận nhân quả thì làm thử nghiệm sáng/tối ngẫu nhiên 4–6 tuần |
| Hôm học dồn có làm hôm sau kém? | Tỉ lệ nhớ ngày D+1 theo số lượt ngày D | Có sẵn | 20 cặp ngày | Scatter | — |
| Năng lượng ảnh hưởng thế nào? | Tỉ lệ nhớ theo `energy` | Cần mới (P2) | 15 phiên mỗi mức | Cột | Năng lượng thấp thì chỉ ôn, không học từ mới |

### Nội dung từ

| Câu hỏi | Chỉ số / công thức | Dữ liệu | Tối thiểu | Biểu đồ | Hành động |
|---|---|---|---|---|---|
| Nhóm/chủ đề nào khó? | Tỉ lệ nhớ theo deck | Có sẵn | 30 mỗi nhóm | Cột | — |
| LLM xếp mức có đúng không? | % từ có `level_source='user'`; tỉ lệ nhớ theo mức | Có sẵn | 50 từ | Bảng | Mức sai nhiều thì đổi model hoặc prompt |
| Tạm dừng vì sao? | Phân bố `suspend_reason` | Cần mới (P2) | 10 từ | Cột | — |

### Dự báo

| Câu hỏi | Mô hình | Dữ liệu | Tối thiểu | Hành động |
|---|---|---|---|---|
| Mai cần ôn bao nhiêu? | `due_at` + từ mới dự kiến | Có sẵn | Ngay | Đã có lịch 14 ngày |
| Khả năng nhớ từng từ hôm nay? | Half-Life Regression; đặc trưng: số lần nhớ/quên, CEFR, loại từ, có ví dụ, độ dài từ | Có sẵn | ~1000 kiểm tra | Xếp thẻ có xác suất nhớ thấp lên trước |
| Bao giờ đạt N từ vững? | Hồi quy tốc độ qua/tuần, kèm khoảng tin cậy | Có sẵn | 6 tuần | Đặt mục tiêu thực tế |
| Nguy cơ bỏ học? | Số ngày nghỉ, xu hướng lượt mỗi tuần, tồn kho | Có sẵn | 6 tuần | Cảnh báo khi tồn kho tăng và số ngày học giảm |

## 5. Lộ trình đề xuất cho trang Phân tích

1. **Nạp từ so với khả năng học** (có sẵn): tồn kho từ chưa học, thời gian chờ, từ thêm/tuần so với từ qua/tuần. Đây là vấn đề lớn nhất trong dữ liệu hiện tại.
2. **Theo độ khó** (có sẵn): tỉ lệ nhớ theo CEFR và loại từ, kèm gợi ý giới hạn số từ C1/C2 mỗi phiên.
3. **Heatmap thói quen** (có sẵn): lịch theo ngày và tuần, số ngày nghỉ liên tiếp, hệ số biến thiên.
4. **Ghi dữ liệu P1**: phiên học có số thẻ trong hàng đợi, thẻ bị bỏ qua, số lần lật. Sau đó thêm chỉ số bỏ dở phiên và từ hay bị né.
5. **Chất lượng của "qua"**: tỉ lệ nhớ ở lần kiểm tra đầu sau khi qua, và ma trận chuyển rating.
6. **So sánh có ví dụ với không có ví dụ**: chờ có ~30 kiểm tra mỗi nhóm.
7. **Mô hình xác suất nhớ (HLR)**: khi có ~1000 kiểm tra trí nhớ thật. Với nhịp hiện tại khoảng 80 kiểm tra mỗi 3 tuần, cần vài tháng.
