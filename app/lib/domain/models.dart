import 'package:unorm_dart/unorm_dart.dart' as unicode;

String normalizeTerm(String value) =>
    unicode.nfc(value).trim().replaceAll(RegExp(r'\s+'), ' ');
String normalizeMeaning(String value) => unicode.nfc(value).trim();

/// Allowed `senses.part_of_speech` values, shared by import, editor and AI.
const partsOfSpeech = {
  'noun': 'danh từ',
  'verb': 'động từ',
  'adjective': 'tính từ',
  'adverb': 'trạng từ',
  'pronoun': 'đại từ',
  'preposition': 'giới từ',
  'conjunction': 'liên từ',
  'interjection': 'thán từ',
  'determiner': 'hạn định từ',
  'phrase': 'cụm từ',
  'other': 'khác',
};

/// IPA without the surrounding slashes or brackets; empty becomes null.
String? normalizePronunciation(String? value) {
  if (value == null) return null;
  final ipa = unicode
      .nfc(value)
      .trim()
      .replaceAll(RegExp(r'^[/\[]+|[/\]]+$'), '')
      .trim();
  return ipa.isEmpty ? null : ipa;
}

class UserFacingException implements Exception {
  const UserFacingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Deck {
  const Deck(this.id, this.name, this.count);
  final String id;
  final String name;
  final int count;
}

class Vocabulary {
  const Vocabulary({
    required this.entryId,
    required this.senseId,
    required this.term,
    required this.meaning,
    required this.senseKey,
    required this.status,
    required this.groups,
    required this.suspended,
    this.partOfSpeech,
    this.pronunciation,
  });
  final String entryId, senseId, term, meaning, senseKey, status, groups;
  final bool suspended;
  final String? partOfSpeech, pronunciation;
}

class StudyCard {
  const StudyCard({
    required this.id,
    required this.term,
    required this.meaning,
    required this.senseKey,
    required this.state,
    required this.intervalDays,
    required this.lapses,
    required this.revision,
    this.partOfSpeech,
    this.pronunciation,
  });
  final String id, term, meaning, senseKey, state;
  final int intervalDays, lapses, revision;
  final String? partOfSpeech, pronunciation;
}

class StudyStats {
  const StudyStats({
    required this.entries,
    required this.senses,
    required this.drafts,
    required this.due,
    required this.fresh,
    required this.newRemaining,
    required this.reviewedToday,
    required this.nextDue,
  });
  final int entries, senses, drafts, due, fresh, newRemaining, reviewedToday;
  final DateTime? nextDue;
}
