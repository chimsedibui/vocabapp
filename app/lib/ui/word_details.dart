import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../services/speech.dart';

/// "danh từ · /pəˈsɪstənt/ 🔊" line shown under a term.
class WordDetails extends StatelessWidget {
  const WordDetails({
    super.key,
    required this.term,
    this.partOfSpeech,
    this.pronunciation,
    this.alignment = WrapAlignment.start,
  });
  final String term;
  final String? partOfSpeech, pronunciation;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.outline);
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (partsOfSpeech[partOfSpeech] != null)
          Text(
            partsOfSpeech[partOfSpeech]!,
            style: muted.copyWith(fontStyle: FontStyle.italic),
          ),
        if (pronunciation != null) Text('/$pronunciation/', style: muted),
        IconButton(
          tooltip: 'Nghe phát âm',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: () async {
            if (!await Speech.speak(term) && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thiết bị chưa có giọng đọc tiếng Anh.'),
                ),
              );
            }
          },
          icon: const Icon(Icons.volume_up_outlined),
        ),
      ],
    );
  }
}
