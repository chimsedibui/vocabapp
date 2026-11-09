import 'package:flutter/material.dart';

import '../data/analytics_repository.dart';
import '../data/library_repository.dart';
import '../domain/analytics.dart';
import 'editors.dart';
import '../domain/scheduler.dart';
import 'progress_charts.dart';
import 'theme.dart';
import 'ui_scale.dart';

/// Learning analytics: pace, recall, fatigue, word trends, hard words and
/// the coming workload. Formulas in docs/15.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key, required this.repository});
  final LibraryRepository repository;
  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late final Future<LearningReport> _report = widget.repository
      .learningReport();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phân tích học')),
    body: FutureBuilder<LearningReport>(
      future: _report,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(friendlyError(snap.error!)));
        }
        final r = snap.data;
        if (r == null) return const Center(child: CircularProgressIndicator());
        if (r.totalReviews == 0) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Chưa có lượt ôn nào. Học vài phiên rồi quay lại xem nhé.',
              ),
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _tiles(r),
                const SizedBox(height: 16),
                _suggestions(r),
                const SizedBox(height: 12),
                ResponsiveGrid(
                  minTileWidth: 380,
                  maxColumns: 2,
                  children: [
                    _dailyTime(r),
                    _sessionLengths(r),
                    _weekly(r),
                    _recall(r),
                    _fatigue(r),
                    _dayParts(r),
                    _lateness(r),
                    _trend(r),
                    _forecast(r),
                    _sessions(r),
                  ],
                ),
                const SizedBox(height: 12),
                _leeches(r),
              ],
            ),
          ),
        );
      },
    ),
  );

  String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

  Widget _tiles(LearningReport r) {
    final projection = r.graduatedTotal + (r.pace * 4).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveGrid(
          minTileWidth: 150,
          maxColumns: 5,
          children: [
            _tile('${r.graduatedTotal}', 'Từ đã qua'),
            _tile('${r.matureTotal}', 'Từ vững (≥21 ngày)'),
            _tile(r.pace.toStringAsFixed(1), 'Từ qua / tuần (4 tuần)'),
            _tile(_pct(r.recall30.rate), 'Tỉ lệ nhớ 30 ngày'),
            _tile('${r.studyDays30}/30', 'Ngày có học'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          r.pace > 0
              ? 'Giữ tốc độ này, 4 tuần nữa bạn có khoảng $projection từ đã qua.'
              : 'Chưa có từ nào qua trong 4 tuần gần đây.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _tile(String value, String label) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  Widget _section(String title, String hint, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.of(context).muted),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  String _date(DateTime d) => '${d.day}/${d.month}';

  Widget _weekly(LearningReport r) {
    final labels = [for (final w in r.weeks) _date(w.start)];
    Widget chart(String title, List<double> values, String unit) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        ValueBars(
          values: values,
          labels: labels,
          highlightLast: true,
          height: 96,
          summary:
              '$title: ${[for (final (i, v) in values.indexed) '${labels[i]} ${v.round()} $unit'].join(', ')}',
          tooltips: [
            for (final (i, w) in r.weeks.indexed)
              'Tuần ${labels[i]}: ${values[i].round()} $unit'
                  '${w.averageScore == null ? '' : ' · điểm TB ${w.averageScore!.toStringAsFixed(1)}/5'}',
          ],
          valueText: (v) => '${v.round()}',
        ),
      ],
    );
    return _section('Theo tuần', '8 tuần gần nhất, tuần này ở cuối.', [
      chart('Từ đã qua', [
        for (final w in r.weeks) w.graduated.toDouble(),
      ], 'từ'),
      const SizedBox(height: 12),
      chart('Phút học', [for (final w in r.weeks) w.minutes], 'phút'),
      const SizedBox(height: 12),
      chart('Lượt ôn', [for (final w in r.weeks) w.reviews.toDouble()], 'lượt'),
    ]);
  }

  Widget _rates(List<PassRate> rates, String what) => ValueBars(
    values: [for (final p in rates) p.rate],
    labels: [for (final p in rates) p.label],
    max: 1,
    valueText: (v) => '${(v * 100).round()}%',
    summary: [
      for (final p in rates) '${p.label}: ${_pct(p.rate)} (${p.checks} lượt)',
    ].join(', '),
    tooltips: [
      for (final p in rates)
        '${what.isEmpty ? '' : '$what '}${p.label}: ${_pct(p.rate)} · '
            '${p.passed}/${p.checks} lượt',
    ],
  );

  String _minutes(double m) =>
      m < 10 && m != m.roundToDouble() ? m.toStringAsFixed(1) : '${m.round()}';

  Widget _dailyTime(LearningReport r) {
    final today = widget.repository.clock();
    final n = r.dailyMinutes.length;
    final labels = [
      for (var i = 0; i < n; i++)
        i == n - 1 ? 'Nay' : _date(today.subtract(Duration(days: n - 1 - i))),
    ];
    final studied = r.dailyMinutes.where((m) => m > 0).toList();
    final average = studied.isEmpty
        ? null
        : studied.reduce((a, b) => a + b) / studied.length;
    return _section(
      'Thời gian học mỗi ngày',
      '14 ngày gần nhất, tính từ lúc hiện thẻ tới lúc chấm (tối đa 2 phút/thẻ).'
          '${average == null ? '' : ' Trung bình ${_minutes(average)} phút vào ngày có học.'}',
      [
        if (studied.isEmpty)
          const Text('Cần vài phiên học trên bản mới để có dữ liệu.')
        else
          ValueBars(
            values: r.dailyMinutes,
            labels: [for (final (i, l) in labels.indexed) i.isOdd ? l : ''],
            highlightLast: true,
            valueText: _minutes,
            tooltips: [
              for (final (i, m) in r.dailyMinutes.indexed)
                '${labels[i]}: ${_minutes(m)} phút',
            ],
            summary: [
              for (final (i, m) in r.dailyMinutes.indexed)
                '${labels[i]} ${_minutes(m)} phút',
            ].join(', '),
          ),
      ],
    );
  }

  Widget _sessionLengths(LearningReport r) {
    final buckets = r.sessionLengths;
    final labels = [for (final b in buckets) b.label.replaceAll(' phút', '')];
    final average = r.averageSessionMinutes;
    return _section(
      'Độ dài phiên học',
      'Phiên trong 90 ngày theo thời gian học thực (phút). '
          '${average == null ? '' : 'Trung bình ${_minutes(average)} phút/phiên.'}',
      [
        if (buckets.every((b) => b.sessions == 0))
          const Text('Cần vài phiên học trên bản mới để có dữ liệu.')
        else ...[
          Text('Số phiên', style: Theme.of(context).textTheme.labelMedium),
          ValueBars(
            values: [for (final b in buckets) b.sessions.toDouble()],
            labels: labels,
            height: 96,
            tooltips: [
              for (final b in buckets)
                '${b.label}: ${b.sessions} phiên · ${b.cards} thẻ',
            ],
            summary: [for (final b in buckets) '${b.label} ${b.sessions} phiên']
                .join(', '),
          ),
          const SizedBox(height: 12),
          Text(
            'Tỉ lệ không “Quên”',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          ValueBars(
            values: [for (final b in buckets) b.rate],
            labels: labels,
            height: 96,
            max: 1,
            valueText: (v) => '${(v * 100).round()}%',
            tooltips: [
              for (final b in buckets)
                '${b.label}: ${_pct(b.rate)} · ${b.passed}/${b.cards} thẻ',
            ],
            summary: [for (final b in buckets) '${b.label} ${_pct(b.rate)}']
                .join(', '),
          ),
        ],
      ],
    );
  }

  Widget _recall(LearningReport r) => _section(
    'Tỉ lệ nhớ theo khoảng cách ôn',
    'Thẻ đã qua bước ngắn, không chấm “Quên”. 90 ngày gần nhất. '
        'Mục tiêu 85–90%: thấp hơn là quên nhiều, cao hơn là ôn thừa.',
    [_rates(r.recallByInterval, 'Cách')],
  );

  Widget _suggestions(LearningReport r) => _section(
    'Gợi ý cho bạn',
    'Rút ra từ dữ liệu của bạn; chỉ dùng chỉ số có từ '
        '${LearningReport.minChecks} lượt trở lên.',
    [
      if (r.suggestions.isEmpty)
        const Text(
          'Chưa đủ dữ liệu để gợi ý, hoặc mọi chỉ số đang ổn. Cứ học đều nhé.',
        )
      else
        for (final tip in r.suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 18,
                  color: AppColors.of(context).accent,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(tip)),
              ],
            ),
          ),
    ],
  );

  Widget _dayParts(LearningReport r) => _section(
    'Theo buổi trong ngày',
    'Tỉ lệ không “Quên” của mọi lượt ôn, 90 ngày gần nhất.',
    [_rates(r.byDayPart, 'Buổi')],
  );

  Widget _lateness(LearningReport r) => _section(
    'Ôn đúng hạn hay trễ hạn',
    'Tỉ lệ nhớ của thẻ đã qua bước ngắn theo số ngày ôn trễ, 90 ngày gần nhất.',
    [_rates(r.byLateness, '')],
  );

  Widget _fatigue(LearningReport r) => _section(
    'Đường cong mệt',
    'Tỉ lệ không “Quên” theo thứ tự thẻ trong phiên. '
        'Tụt rõ ở cuối nghĩa là phiên đang quá dài.',
    [
      if (r.fatigue.every((p) => p.checks == 0))
        const Text('Cần vài phiên học trên bản mới để có dữ liệu.')
      else
        _rates(r.fatigue, 'Thẻ thứ'),
      if (r.medianThink case final t?) ...[
        const SizedBox(height: 8),
        Text(
          'Thời gian nghĩ trước khi lật (trung vị 30 ngày): '
          '${(t.inMilliseconds / 1000).toStringAsFixed(1)} giây',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );

  Widget _trend(LearningReport r) {
    final colors = AppColors.of(context);
    Widget row(String title, Trend t) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title · ${t.total} từ',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          if (t.total == 0)
            const Text('Chưa có từ nào được ôn từ 2 lần trở lên.')
          else
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final (icon, label, n) in [
                  (Icons.trending_up, 'Tăng', t.up),
                  (Icons.trending_flat, 'Giữ', t.same),
                  (Icons.trending_down, 'Giảm', t.down),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: colors.muted),
                      const SizedBox(width: 4),
                      Text('$label $n'),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
    return _section(
      'Thay đổi đánh giá từng từ',
      'So lần chấm cuối với lần chấm đầu trong khoảng thời gian.',
      [row('7 ngày', r.trend7), row('30 ngày', r.trend30)],
    );
  }

  Widget _forecast(LearningReport r) {
    final today = widget.repository.clock();
    final labels = [
      for (var i = 0; i < r.dueForecast.length; i++)
        i == 0 ? 'Nay' : _date(today.add(Duration(days: i))),
    ];
    return _section(
      'Lịch ôn 14 ngày tới',
      'Số thẻ đến hạn mỗi ngày; thẻ quá hạn tính vào hôm nay. Chưa gồm từ mới.',
      [
        ValueBars(
          values: [for (final n in r.dueForecast) n.toDouble()],
          labels: [for (final (i, l) in labels.indexed) i.isEven ? l : ''],
          tooltips: [
            for (final (i, n) in r.dueForecast.indexed) '${labels[i]}: $n thẻ',
          ],
          summary: [
            for (final (i, n) in r.dueForecast.indexed) '${labels[i]} $n',
          ].join(', '),
        ),
      ],
    );
  }

  Widget _sessions(LearningReport r) => _section(
    'Phiên học gần đây',
    'Nghỉ quá 5 phút là sang phiên mới. Thời gian mỗi thẻ tính tối đa 2 phút.',
    [
      if (r.sessions.isEmpty)
        const Text('Cần vài phiên học trên bản mới để có dữ liệu.')
      else
        for (final s in r.sessions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(() {
                    final t = s.start.toLocal();
                    return '${_date(t)} ${t.hour.toString().padLeft(2, '0')}:'
                        '${t.minute.toString().padLeft(2, '0')}';
                  }()),
                ),
                Expanded(child: Text('${s.cards} thẻ')),
                Expanded(
                  child: Text(
                    '${(s.active.inSeconds / 60).toStringAsFixed(1)} phút',
                  ),
                ),
                Expanded(
                  child: Text(
                    'nhớ ${_pct(s.cards == 0 ? null : s.passed / s.cards)}',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
    ],
  );

  Widget _leeches(LearningReport r) {
    final colors = AppColors.of(context);
    return _section(
      'Từ khó',
      'Quên ≥4 lần hoặc tụt lịch ≥3 lần. Nên thêm ví dụ, ghi chú hoặc tách nghĩa.',
      [
        if (r.leeches.isEmpty)
          const Text('Chưa có từ nào bị quên lặp lại. Tốt lắm!')
        else
          for (final l in r.leeches)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text.rich(
                      TextSpan(
                        text: l.term,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(
                            text: ' · ${l.meaning}',
                            style: TextStyle(
                              fontWeight: FontWeight.normal,
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Tooltip(
                      message:
                          'Gần đây: ${l.recent.map((e) => e.label).join(' → ')}',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (final e in l.recent) _ratingDot(e),
                          const SizedBox(width: 8),
                          Text('quên ${l.again}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// Higher rating, darker dot: one hue, light → dark.
  Widget _ratingDot(Rating r) => Container(
    width: 10,
    height: 10,
    margin: const EdgeInsets.only(left: 3),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: r == Rating.again
          ? AppColors.of(context).hairlineStrong
          : AppColors.of(context).accent
                .withValues(alpha: 0.2 + 0.2 * (ratingScore(r) - 1)),
    ),
  );
}
