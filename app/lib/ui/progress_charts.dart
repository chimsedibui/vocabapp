import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Reviews per day for the last 7 days, today last. One series, so no legend;
/// each bar has a tooltip and the whole chart a spoken summary.
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.counts, required this.today});
  final List<int> counts;
  final DateTime today;

  static const _days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.muted);
    final peak = max(1, counts.fold(0, max));
    final labels = [
      for (var i = counts.length - 1; i >= 0; i--)
        _days[today.subtract(Duration(days: i)).weekday - 1],
    ];
    return Semantics(
      label:
          'Lượt ôn 7 ngày qua: ${[for (final (i, n) in counts.indexed) '${labels[i]} $n'].join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: 112,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, n) in counts.indexed)
              Expanded(
                child: Tooltip(
                  message:
                      '${i == counts.length - 1 ? 'Hôm nay' : labels[i]}: $n lượt',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (n > 0) Text('$n', style: style),
                      const SizedBox(height: 2),
                      Container(
                        height: max(2, 56 * n / peak),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: n == 0
                              ? colors.hairline
                              : i == counts.length - 1
                              ? colors.accent
                              : colors.accent.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        labels[i],
                        style: i == counts.length - 1
                            ? style?.copyWith(
                                color: colors.ink,
                                fontWeight: FontWeight.w600,
                              )
                            : style,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cards by stage: new → learning → known, one hue from light to dark.
class CardMix extends StatelessWidget {
  const CardMix({
    super.key,
    required this.fresh,
    required this.learning,
    required this.mature,
  });
  final int fresh, learning, mature;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final parts = [
      ('Mới', fresh, colors.hairlineStrong),
      ('Đang học', learning, colors.accent.withValues(alpha: 0.5)),
      ('Đã thuộc', mature, colors.accent),
    ];
    final total = fresh + learning + mature;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 10,
            child: total == 0
                ? ColoredBox(color: colors.hairline)
                : Row(
                    children: [
                      for (final (i, (label, n, color))
                          in parts.where((p) => p.$2 > 0).indexed) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: n,
                          child: Tooltip(
                            message: '$label: $n thẻ',
                            child: ColoredBox(color: color),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final (label, n, color) in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const SizedBox(width: 10, height: 10),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$label $n',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
