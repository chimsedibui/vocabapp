import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/analytics_repository.dart';
import '../data/library_repository.dart';
import '../domain/analytics.dart';
import '../domain/scheduler.dart';
import 'editors.dart';
import 'progress_charts.dart';
import 'theme.dart';
import 'ui_scale.dart';

/// Learning analytics as swipeable slides, one topic each: a headline number
/// and one large chart. Formulas in docs/15.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key, required this.repository});
  final LibraryRepository repository;
  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late final Future<LearningReport> _report = widget.repository
      .learningReport();
  final _pages = PageController();
  int _page = 0;

  static const _titles = [
    'Tổng quan',
    'Tiến độ',
    'Trí nhớ',
    'Thói quen',
    'Từ của bạn',
    'Sắp tới',
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) {
    if (page < 0 || page >= _titles.length) return;
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

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
        final slides = [
          _OverviewSlide(r),
          _ProgressSlide(r),
          _MemorySlide(r),
          _HabitsSlide(r),
          _WordsSlide(r),
          _UpcomingSlide(r, today: widget.repository.clock()),
        ];
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _go(_page - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _go(_page + 1),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                _tabs(),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: [
                      for (final s in slides)
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: s,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _pager(),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _tabs() => SizedBox(
    height: 52,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final (i, t) in _titles.indexed)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(t),
              selected: i == _page,
              showCheckmark: false,
              onSelected: (_) => _go(i),
            ),
          ),
      ],
    ),
  );

  Widget _pager() {
    final colors = AppColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Trước',
              onPressed: _page == 0 ? null : () => _go(_page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            for (var i = 0; i < _titles.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _page ? 20 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _page ? colors.accent : colors.hairlineStrong,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            IconButton(
              tooltip: 'Sau',
              onPressed: _page == _titles.length - 1
                  ? null
                  : () => _go(_page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

String _date(DateTime d) => '${d.day}/${d.month}';

/// Big number with a label and an optional one-line takeaway.
class _Headline extends StatelessWidget {
  const _Headline(this.value, this.label, {this.note, this.noteColor});
  final String value, label;
  final String? note;
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.titleSmall?.copyWith(color: colors.muted)),
        Text(
          value,
          style: theme.displayMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
        if (note != null)
          Text(
            note!,
            style: theme.bodyMedium?.copyWith(color: noteColor ?? colors.muted),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) => Card(
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
}

/// One chart chosen from a few views with a segmented control.
class _Switcher extends StatefulWidget {
  const _Switcher(this.views);
  final List<(String, Widget)> views;
  @override
  State<_Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<_Switcher> {
  int _view = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          for (final (i, (label, _)) in widget.views.indexed)
            ButtonSegment(value: i, label: Text(label)),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
      ),
      const SizedBox(height: 20),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_view),
          child: widget.views[_view].$2,
        ),
      ),
    ],
  );
}

Widget _rates(List<PassRate> rates, String what) => ValueBars(
  values: [for (final p in rates) p.rate],
  labels: [for (final p in rates) p.label],
  max: 1,
  height: 200,
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

class _OverviewSlide extends StatelessWidget {
  const _OverviewSlide(this.r);
  final LearningReport r;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final projection = r.graduatedTotal + (r.pace * 4).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headline(
          '${r.graduatedTotal}',
          'Từ đã qua',
          note: r.pace > 0 ? '≈ $projection từ sau 4 tuần nữa' : null,
        ),
        ResponsiveGrid(
          minTileWidth: 140,
          maxColumns: 4,
          children: [
            _Stat('${r.matureTotal}', 'Từ vững (≥21 ngày)'),
            _Stat(r.pace.toStringAsFixed(1), 'Từ qua / tuần'),
            _Stat(_pct(r.recall30.rate), 'Nhớ 30 ngày'),
            _Stat('${r.studyDays30}/30', 'Ngày có học'),
          ],
        ),
        if (r.suggestions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Gợi ý', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final tip in r.suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: colors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tip)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _ProgressSlide extends StatelessWidget {
  const _ProgressSlide(this.r);
  final LearningReport r;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final labels = [for (final w in r.weeks) _date(w.start)];
    final now = r.weeks.last.graduated;
    final before = r.weeks[r.weeks.length - 2].graduated;
    final delta = now - before;
    Widget chart(List<double> values, String unit) => ValueBars(
      values: values,
      labels: labels,
      highlightLast: true,
      height: 220,
      summary: [
        for (final (i, v) in values.indexed) '${labels[i]} ${v.round()} $unit',
      ].join(', '),
      tooltips: [
        for (final (i, w) in r.weeks.indexed)
          'Tuần ${labels[i]}: ${values[i].round()} $unit'
              '${w.averageScore == null ? '' : ' · điểm TB ${w.averageScore!.toStringAsFixed(1)}/5'}',
      ],
      valueText: (v) => '${v.round()}',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headline(
          '$now',
          'Từ qua tuần này',
          note: delta == 0
              ? 'Bằng tuần trước'
              : '${delta > 0 ? '▲' : '▼'} ${delta.abs()} so với tuần trước',
          noteColor: delta > 0
              ? colors.accent
              : delta < 0
              ? colors.danger
              : null,
        ),
        _Switcher([
          (
            'Từ qua',
            chart([for (final w in r.weeks) w.graduated.toDouble()], 'từ'),
          ),
          ('Phút học', chart([for (final w in r.weeks) w.minutes], 'phút')),
          (
            'Lượt ôn',
            chart([for (final w in r.weeks) w.reviews.toDouble()], 'lượt'),
          ),
        ]),
      ],
    );
  }
}

class _MemorySlide extends StatelessWidget {
  const _MemorySlide(this.r);
  final LearningReport r;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final rate = r.recall30.rate;
    final (note, color) = switch (rate) {
      null => ('Chưa đủ dữ liệu', null),
      < 0.85 => ('Dưới mục tiêu 85–90%: đang quên nhiều', colors.danger),
      > 0.90 => ('Trên mục tiêu 85–90%: có thể đang ôn thừa', colors.muted),
      _ => ('Đúng mục tiêu 85–90%', colors.accent),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headline(
          _pct(rate),
          'Tỉ lệ nhớ 30 ngày',
          note: note,
          noteColor: color,
        ),
        _Switcher([
          ('Khoảng cách ôn', _rates(r.recallByInterval, 'Cách')),
          ('Độ trễ', _rates(r.byLateness, '')),
        ]),
      ],
    );
  }
}

class _HabitsSlide extends StatelessWidget {
  const _HabitsSlide(this.r);
  final LearningReport r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final trusted = [
      for (final p in r.byDayPart)
        if (p.checks >= LearningReport.minChecks) p,
    ]..sort((a, b) => b.rate!.compareTo(a.rate!));
    final best = trusted.firstOrNull;
    final think = r.medianThink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headline(
          best?.label ?? '—',
          'Buổi nhớ tốt nhất',
          note: best == null
              ? 'Cần thêm lượt ôn để so sánh'
              : '${_pct(best.rate)} không “Quên”'
                    '${think == null ? '' : ' · nghĩ ${(think.inMilliseconds / 1000).toStringAsFixed(1)} giây/thẻ'}',
        ),
        _Switcher([
          ('Buổi trong ngày', _rates(r.byDayPart, 'Buổi')),
          (
            'Độ dài phiên',
            r.fatigue.every((p) => p.checks == 0)
                ? const Text('Cần vài phiên học để có dữ liệu.')
                : _rates(r.fatigue, 'Thẻ thứ'),
          ),
        ]),
        if (r.sessions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Phiên gần đây', style: theme.titleMedium),
          const SizedBox(height: 4),
          for (final s in r.sessions.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
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
                      _pct(s.cards == 0 ? null : s.passed / s.cards),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _WordsSlide extends StatelessWidget {
  const _WordsSlide(this.r);
  final LearningReport r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final t = r.trend30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headline(
          '${t.up}',
          'Từ tiến bộ trong 30 ngày',
          note: t.total == 0 ? null : '${t.down} từ đi xuống',
          noteColor: t.down > t.up ? colors.danger : null,
        ),
        _TrendBar('7 ngày', r.trend7),
        const SizedBox(height: 16),
        _TrendBar('30 ngày', r.trend30),
        const SizedBox(height: 28),
        Text('Từ khó', style: theme.titleMedium),
        const SizedBox(height: 4),
        if (r.leeches.isEmpty)
          const Text('Chưa có từ nào bị quên lặp lại.')
        else
          for (final l in r.leeches)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
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
                  Tooltip(
                    message:
                        'Gần đây: ${l.recent.map((e) => e.label).join(' → ')}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in l.recent) _RatingDot(e),
                        const SizedBox(width: 8),
                        Text('quên ${l.again}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Share of words that went up, stayed or went down, as one stacked bar.
class _TrendBar extends StatelessWidget {
  const _TrendBar(this.title, this.t);
  final String title;
  final Trend t;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final parts = [
      ('Tăng', t.up, colors.accent),
      ('Giữ', t.same, colors.hairlineStrong),
      ('Giảm', t.down, colors.danger),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title · ${t.total} từ', style: theme.labelLarge),
        const SizedBox(height: 6),
        if (t.total == 0)
          const Text('Chưa có từ nào được ôn từ 2 lần trở lên.')
        else ...[
          Semantics(
            label:
                '$title: tăng ${t.up}, giữ ${t.same}, giảm ${t.down} trên ${t.total} từ',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    for (final (_, n, color) in parts)
                      if (n > 0)
                        Expanded(
                          flex: n,
                          child: Container(color: color),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            children: [
              for (final (label, n, color) in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('$label $n', style: theme.bodySmall),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Higher rating, darker dot: one hue, light → dark.
class _RatingDot extends StatelessWidget {
  const _RatingDot(this.r);
  final Rating r;

  @override
  Widget build(BuildContext context) => Container(
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

class _UpcomingSlide extends StatelessWidget {
  const _UpcomingSlide(this.r, {required this.today});
  final LearningReport r;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (var i = 0; i < r.dueForecast.length; i++)
        i == 0 ? 'Nay' : _date(today.add(Duration(days: i))),
    ];
    final week = r.dueForecast.skip(1).take(7).fold(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headline(
          '${r.dueForecast.first}',
          'Thẻ cần ôn hôm nay',
          note: '$week thẻ trong 7 ngày tới · chưa gồm từ mới',
        ),
        ValueBars(
          values: [for (final n in r.dueForecast) n.toDouble()],
          labels: [for (final (i, l) in labels.indexed) i.isEven ? l : ''],
          height: 220,
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
}
