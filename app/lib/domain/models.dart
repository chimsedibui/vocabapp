import 'package:unorm_dart/unorm_dart.dart' as unicode;

String normalizeTerm(String value) =>
    unicode.nfc(value).trim().replaceAll(RegExp(r'\s+'), ' ');
String normalizeMeaning(String value) => unicode.nfc(value).trim();

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
  });
  final String entryId, senseId, term, meaning, senseKey, status, groups;
  final bool suspended;
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
  });
  final String id, term, meaning, senseKey, state;
  final int intervalDays, lapses, revision;
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
