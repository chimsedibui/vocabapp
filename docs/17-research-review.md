# 17 — Tổng quan nghiên cứu: log ôn tập và phân tích 1 người học

Ngày 10/11/2026. Tài liệu tổng hợp các nghiên cứu về phân tích log flashcard/spaced repetition và về phân tích dữ liệu của một người (n-of-1). Mục đích: kiểm chứng các chỉ số trong [15 — Phân tích học tập](15-learning-analytics.md) và các insight trong [16 — Phân tích hành vi](16-behavior-analysis.md) trước khi triển khai tiếp.

**Trạng thái: chờ duyệt.** Chưa có thay đổi code nào dựa trên tài liệu này.

**Cần kiểm tra trước khi dùng:**
- Link được tìm và kiểm qua web search, riêng link HLR (mục 1) được ghi theo trí nhớ, nên bấm thử.
- Các mục có dấu ⚠️ là bằng chứng yếu, còn lẫn lộn, hoặc chưa qua peer-review.

## 1. Mô hình hóa log ôn tập

| # | Nguồn | Dữ liệu | Phát hiện chính | Áp dụng cho app |
|---|---|---|---|---|
| 1 | Settles & Meeder 2016, *A Trainable Spaced Repetition Model for Language Learning* (HLR), ACL. https://doi.org/10.18653/v1/P16-1174 | ~13 triệu lượt ôn, Duolingo, dữ liệu công khai | Xác suất nhớ p = 2^(−Δ/h). Half-life h phụ thuộc số lần đúng/sai và đặc trưng của từ. Sai số thấp hơn rõ so với Leitner/Pimsleur | Dùng `previous_interval` (Δ) và số lần đúng/sai làm biến nền; có thể fit HLR cho riêng một người |
| 2 | Tabibian et al. 2019, *Enhancing human learning via spaced repetition optimization*, PNAS 116(10). https://doi.org/10.1073/pnas.1815156116 | Log Duolingo, quy mô lớn, thiết kế quasi-experiment | Lịch ôn tối ưu (MEMORIZE) cho kết quả nhớ tốt hơn mà không tốn thêm công so với heuristic | Đây là bằng chứng quan sát. Không kết luận "lịch X tốt hơn" chỉ từ log của chính mình |
| 3 | Ye, Su, Cao 2022, *A Stochastic Shortest Path Algorithm for Optimizing Spaced Repetition Scheduling*, KDD. https://doi.org/10.1145/3534678.3539081 (data: https://doi.org/10.7910/DVN/VAGUL0) | 220 triệu log, MaiMemo (app học từ vựng) | Mô hình DSR (Difficulty, Stability, Retrievability) là nền của FSRS. Lịch tối ưu hơn SOTA 12,6% | Có cơ sở để tính S và D cho từng từ. Dữ liệu cùng miền từ vựng |
| 4 | Open Spaced Repetition, *anki-revlogs-10k* và *srs-benchmark* (2024–2025). https://huggingface.co/datasets/open-spaced-repetition/anki-revlogs-10k · https://github.com/open-spaced-repetition/srs-benchmark ⚠️ báo cáo kỹ thuật, chưa peer-review | ~727 triệu lượt ôn, 10.000 người | Chuẩn đánh giá: log-loss, AUC, RMSE(bins). FSRS-6/7 thuộc nhóm tốt nhất; tham số mặc định là median của 10.000 bộ dữ liệu | Khi chưa đủ dữ liệu, dùng tham số FSRS mặc định làm prior. Đánh giá bằng log-loss và RMSE(bins) |
| 5 | Zaidi et al. 2020, *Adaptive Forgetting Curves for Spaced Repetition Language Learning*, AIED. https://arxiv.org/abs/2004.11327 | Duolingo, chỉ lấy từ tiếng Anh | Độ phức tạp của từ là biến dự đoán mạnh cho khả năng nhớ | Thêm đặc trưng của từ: CEFR, độ dài, tần suất |
| 6 | Shu et al. 2024, *KARL: Knowledge-Aware Retrieval and Representations…*, EMNLP. https://doi.org/10.18653/v1/2024.emnlp-main.784 ⚠️ mẫu online nhỏ | 123k log; online study 27 người | Thêm embedding nội dung thẻ giúp AUC và calibration tốt hơn mô hình chỉ dùng lịch sử | Có thể dùng embedding nghĩa/ví dụ để dự đoán cho từ mới chưa có lịch sử |
| 7 | Lindsey, Shroyer, Pashler, Mozer 2014, *Improving Students' Long-Term Knowledge Retention Through Personalized Review*, Psychological Science 25(3). https://doi.org/10.1177/0956797613504302 | Học sinh lớp 8, từ vựng tiếng Tây Ban Nha, một học kỳ | Ôn cá nhân hóa cho kết quả nhớ hơn 16,5% so với học dồn, hơn 10% so với giãn cách chung | Kết hợp dữ liệu chung (prior) với dữ liệu cá nhân là hướng đúng cho một người |

## 2. Yếu tố hành vi

| # | Nguồn | Mẫu | Phát hiện | Áp dụng cho app |
|---|---|---|---|---|
| 8 | Cepeda et al. 2008, *Spacing Effects in Learning: A Temporal Ridgeline of Optimal Retention*, Psychological Science 19(11). https://doi.org/10.1111/j.1467-9280.2008.02209.x | >1.350 người | Khoảng cách ôn tối ưu có dạng chữ U ngược: khoảng 20–40% thời gian cần nhớ (với test sau 1 tuần), khoảng 5–10% (với test sau 1 năm) | Chỉ số học dồn: tỉ lệ lượt ôn sớm hoặc cùng ngày so với lịch |
| 9 | Kornell 2009, *Optimising learning using flashcards: Spacing is more effective than cramming*, Applied Cognitive Psychology 23(9). https://doi.org/10.1002/acp.1537 | 3 thí nghiệm, từ GRE | Học giãn cách tốt hơn ở 90% người học, nhưng 72% người học **tin** học dồn tốt hơn | Cảm giác "Dễ" trong phiên không phải thước đo đã học. Phải đo ở lần ôn sau |
| 10 | Bahrick et al. 1993, *Maintenance of Foreign Language Vocabulary and the Spacing Effect*, Psychological Science 4(5). https://doi.org/10.1111/j.1467-9280.1993.tb00571.x | **4 người**, 300 cặp từ, theo dõi 9 năm | Ôn cách 56 ngày nhớ lâu hơn ôn cách 14 ngày, dù phải học lại nhiều lượt hơn | Tiền lệ cho thiết kế n nhỏ, nhiều từ, theo dõi dài hạn: vẫn rút ra được kết luận |
| 11 | Pavlik & Anderson 2008, *Using a Model to Compute the Optimal Schedule of Practice*, JEP: Applied 14(2). https://doi.org/10.1037/1076-898X.14.2.101 | Thí nghiệm lab | Mô hình ACT-R dùng cả độ đúng và **thời gian phản hồi** để lên lịch; nhớ tốt hơn sau 1 tuần | Thời gian nghĩ (`shown_at` → `flipped_at`) là tín hiệu độ mạnh trí nhớ |
| 12 | Wilschut et al. 2021, *Benefits of Adaptive Learning Transfer From Typing-Based Learning to Speech-Based Learning*, Frontiers in AI. https://doi.org/10.3389/frai.2021.780131 ⚠️ trả lời bằng gõ/nói, không phải thẻ lật | Từ vựng ngoại ngữ | Ước lượng tốc độ quên từ thời gian trả lời: chậm nghĩa là trí nhớ yếu | Chuẩn hóa thời gian nghĩ theo từng người (log, z-score), chỉ dùng cho lượt trả lời đúng. Với thẻ lật, tín hiệu này nhiễu hơn |
| 13 | Mazza et al. 2016, *Relearn Faster and Retain Longer: Along With Practice, Sleep Makes Perfect*, Psychological Science. https://doi.org/10.1177/0956797616659930 | ~40 người | Học buổi tối, ngủ, rồi học lại buổi sáng: số lượt cần học lại giảm một nửa, nhớ tốt hơn sau 1 tuần và 6 tháng | Biến cần đo: có giấc ngủ xen giữa hai lần ôn hay không. Trái với kết luận cũ "học khuya kém" |
| 14 | Gais, Lucas, Born 2006, *Sleep after learning aids memory recall*, Learning & Memory 13(3). https://doi.org/10.1101/lm.132106 ⚠️ mẫu nhỏ | Từ vựng | Ngủ sớm sau khi học giúp nhớ tốt hơn so với thức lâu | Ủng hộ học buổi tối. Ảnh hưởng của giờ trong ngày, khi tách khỏi giấc ngủ, có bằng chứng yếu |
| 15 | Kornell & Bjork 2009, *A Stability Bias in Human Memory*, JEP: General. https://doi.org/10.1037/a0017350; Koriat & Bjork 2005 (foresight bias) | Thí nghiệm lab | Người học tự tin quá mức và không lường trước việc quên | Đo calibration: P(nhớ ở lần sau \| bấm "Dễ") so với các nút khác |
| 16 | de Groot & Keijzer 2000, *What is hard to learn is easy to forget*, Language Learning 50(1). https://doi.org/10.1111/0023-8333.00110 | Học cặp từ, người học có kinh nghiệm | Từ cụ thể và từ cognate dễ học, lâu quên; từ trừu tượng quên nhanh hơn; tần suất ảnh hưởng ít hơn | Thêm điểm concreteness (Brysbaert norms) và tần suất (SUBTLEX). CEFR do LLM ước lượng chỉ là proxy |
| 17 | Prince 1996, *Second Language Vocabulary Learning: The Role of Context versus Translations…*, Modern Language Journal 80(4). https://doi.org/10.1111/j.1540-4781.1996.tb05468.x ⚠️ bằng chứng lẫn lộn | Sinh viên học ngoại ngữ | Học bằng bản dịch cho kết quả nhớ tốt hơn học qua câu, nhất là với người yếu. Câu ví dụ có lợi khi người học tự tạo hoặc phải truy xuất | So tỉ lệ nhớ theo nguồn từ (passage hay nhập tay). Cẩn thận nhiễu: từ trong passage có thể vốn dễ hơn |

**Chưa có nghiên cứu mạnh:**
- Độ dài phiên và mệt mỏi trong phiên flashcard → app tự đo theo vị trí thẻ trong phiên, có tách trạng thái thẻ.
- Số từ mới mỗi ngày tối ưu. Kornell 2009 cho thấy học một chồng lớn (giãn cách trong phiên) tốt hơn; FSRS chủ yếu mô phỏng khối lượng ôn.

## 3. Phương pháp cho dữ liệu của 1 người (n-of-1)

| # | Nguồn | Ý chính |
|---|---|---|
| 18 | Daza 2018, *Causal Analysis of Self-tracked Time Series Data Using a Counterfactual Framework for N-of-1 Trials*, Methods of Information in Medicine 57. https://doi.org/10.3414/ME16-02-0044 | Dữ liệu tự theo dõi chỉ dùng để **gợi ý giả thuyết**. Muốn kết luận nhân quả thì phải tự làm thử nghiệm ngẫu nhiên (ví dụ chọn ngẫu nhiên học sáng hay tối theo ngày), và xử lý tự tương quan cùng xu hướng theo thời gian |

**Mẫu hiện tại (~240 lượt ôn, 111 từ, 8 ngày):**
- ✅ **Làm được:** mô tả số phiên, độ dài phiên, giờ học, phân bố rating, thời gian nghĩ trung vị, tỉ lệ quên trong phiên.
- ❌ **Chưa làm được:**
  - Đánh giá trí nhớ dài hạn, vì phần lớn từ chưa có lần ôn cách ≥ 7 ngày.
  - So sánh theo giờ hoặc theo CEFR, vì mỗi nhóm chỉ vài chục lượt.
  - Fit FSRS riêng, vì cần khoảng 400–1.000 lượt ôn trở lên.

**Ngưỡng thực dụng** (quy tắc kinh nghiệm, không phải chuẩn công bố):
- Ước lượng một tỉ lệ (ví dụ nhớ 85%): khoảng 50 lượt ôn lại cho sai số ±10%, khoảng 200 lượt cho ±5%.
- So sánh hai nhóm để thấy chênh 10 điểm %: khoảng 300–400 lượt mỗi nhóm.
- Hồi quy logistic: khoảng 10–20 lần "Quên" cho mỗi biến. Với tỉ lệ nhớ 85%, 1.000 lượt ôn chỉ có khoảng 150 lần quên, tức tối đa 8–15 biến.

**Phương pháp phù hợp:**
1. Hồi quy logistic mixed-effects với hệ số ngẫu nhiên theo từ `(1|word)`, vì các lượt ôn của cùng một từ không độc lập với nhau.
2. Bayesian với prior lấy từ tham số FSRS mặc định. Luôn báo khoảng tin cậy, không chỉ báo một con số.
3. Kiểm định theo thời gian: học trên dữ liệu quá khứ, kiểm tra trên dữ liệu tương lai. Không chia ngẫu nhiên.
4. Kiểm soát nhiễu: giờ học liên quan tới loại thẻ đến hạn và mức mệt. Đây chính là lỗi đã khiến docs 16 kết luận sai rằng học khuya kém hơn.

## 4. Chỉ số khuyến nghị

- **Tỉ lệ nhớ thật:** % lượt ôn của thẻ ôn lại không chấm "Quên". Tách thẻ non (interval < 21 ngày) và thẻ vững. Tham khảo https://expertium.github.io/Retention.html
- **Dự đoán khả năng nhớ:** log-loss là chính; RMSE(bins) để đo calibration; AUC là phụ, vì AUC thấp với dữ liệu một người là bình thường.
- **Theo từng từ:** Stability, Difficulty, Retrievability (FSRS) và số lần quên.
- **"Từ học thật":** từ trả lời đúng ở lần ôn đầu tiên cách ít nhất 1 ngày sau khi qua. Không đếm số thẻ đã xem trong phiên.
- **Calibration của rating:** tỉ lệ nhớ ở lần sau, tách theo nút đã bấm. Nếu "Dễ" và "Nhớ" cho kết quả gần nhau thì rating không mang thêm thông tin.
- **Mức trễ:** (ngày ôn thực − ngày đến hạn) / interval, rồi tính tỉ lệ nhớ theo từng khoảng trễ.

## 5. Đối chiếu với app hiện tại (v0.3.16)

| Hiện trạng | Vấn đề theo tài liệu | Đề xuất |
|---|---|---|
| Gợi ý khi mỗi nhóm có ≥ 15 lượt và chênh ≥ 10 điểm % | Quá thấp: cần khoảng 300–400 lượt mỗi nhóm. Có thể sinh lời khuyên sai | Thêm khoảng tin cậy (Wilson); chỉ gợi ý khi hai khoảng không chồng nhau; gắn nhãn "ít dữ liệu, chưa kết luận" |
| "Theo buổi trong ngày" và "Độ dài phiên" tính trên mọi lượt ôn | Trộn thẻ mới với thẻ ôn lại, nên bị nhiễu (lỗi của docs 16) | Chỉ tính thẻ ôn lại, hoặc tách theo trạng thái thẻ |
| Tỉ lệ nhớ coi "Khó" là nhớ, trong khi scheduler v2 đưa thẻ ôn lại bấm "Khó" về học lại sau 1 giờ | Chỉ số và lịch ôn đang hiểu "Khó" khác nhau | Quyết định "Khó" là nhớ (giống FSRS) rồi sửa scheduler, hoặc là quên rồi sửa chỉ số |
| "Từ đã qua" = lần đầu lên trạng thái ôn lại | Chưa chứng minh từ đã thật sự nhớ | Thêm chỉ số "từ học thật" |
| Chưa có calibration rating, chưa tách thẻ non và thẻ vững | Thiếu các chỉ số chuẩn | Thêm vào trang Phân tích |
| Forecast mới chỉ có lịch đến hạn và xu hướng tuyến tính | Khớp với mức dữ liệu hiện tại | Khi có ≥ 400–1.000 lượt ôn lại: fit FSRS hoặc HLR, đánh giá bằng log-loss theo thời gian |

## 6. Đề xuất thứ tự triển khai (chờ duyệt)

1. Sửa độ tin cậy của Gợi ý: khoảng tin cậy, ngưỡng mới, nhãn ít dữ liệu, chỉ so thẻ ôn lại.
2. Thống nhất cách hiểu "Khó" giữa scheduler và chỉ số.
3. Thêm chỉ số: tỉ lệ nhớ thẻ non/vững, từ học thật, calibration rating, mức trễ theo interval.
4. Thử nghiệm cá nhân (tùy chọn): 4–6 tuần, chọn ngẫu nhiên học sáng hay tối theo ngày.
5. Mô hình FSRS/HLR khi đủ dữ liệu.
