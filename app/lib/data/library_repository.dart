import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/scheduler.dart';
import 'ids.dart';

class LibraryRepository {
  LibraryRepository(this.db, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final Database db;
  final DateTime Function() clock;
  final _uuid = const Uuid();
  final _scheduler = Scheduler();

  Future<Map<String, Object?>> settings() async =>
      (await db.query('settings')).single;

  Future<void> setDailyLimit(int value) async {
    if (value < 0 || value > 100) {
      throw const UserFacingException('Số từ mới mỗi ngày phải từ 0 đến 100.');
    }
    await db.update('settings', {'daily_new_limit': value}, where: 'id = 1');
  }

  String _studyDay(DateTime now, String timezone) {
    final local = tz.TZDateTime.from(now, tz.getLocation(timezone));
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Future<List<Deck>> decks({bool includeArchived = false}) async {
    final rows = await db.rawQuery(
      '''SELECT d.*, count(de.entry_id) AS count
      FROM decks d LEFT JOIN deck_entries de ON de.deck_id=d.id
      ${includeArchived ? '' : 'WHERE d.archived=0'} GROUP BY d.id ORDER BY d.name''',
    );
    return rows
        .map(
          (r) =>
              Deck(r['id'] as String, r['name'] as String, r['count'] as int),
        )
        .toList();
  }

  Future<String> createDeck(String name) async {
    final normalized = normalizeTerm(name);
    if (normalized.isEmpty || normalized.length > 120) {
      throw const UserFacingException('Tên nhóm cần từ 1 đến 120 ký tự.');
    }
    final key = 'group-${_uuid.v4()}';
    final id = Ids.deck(key);
    await db.insert('decks', {'id': id, 'deck_key': key, 'name': normalized});
    return id;
  }

  Future<void> renameDeck(String id, String name) async {
    final value = normalizeTerm(name);
    if (value.isEmpty || value.length > 120) {
      throw const UserFacingException('Tên nhóm cần từ 1 đến 120 ký tự.');
    }
    await db.update('decks', {'name': value}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> archiveDeck(String id) async {
    await db.update('decks', {'archived': 1}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> removeFromDeck(String entryId, String deckId) async {
    await db.delete(
      'deck_entries',
      where: 'entry_id=? AND deck_id=?',
      whereArgs: [entryId, deckId],
    );
  }

  Future<void> attachToDeck(String entryId, String deckId) async {
    await db.transaction((tx) async {
      await _checkDeck(tx, deckId);
      await tx.insert('deck_entries', {
        'entry_id': entryId,
        'deck_id': deckId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<void> _checkDeck(DatabaseExecutor tx, String deckId) async {
    if ((await tx.query(
      'decks',
      where: 'id=? AND archived=0',
      whereArgs: [deckId],
    )).isEmpty) {
      throw const UserFacingException(
        'Nhóm không còn khả dụng. Hãy chọn nhóm khác.',
      );
    }
  }

  /// Returns true for a new sense; an existing sense is never overwritten here.
  Future<bool> addWord({
    required String term,
    required String meaning,
    required String deckId,
    String senseKey = 'primary',
    bool approve = true,
  }) => db.transaction(
    (tx) => _addWord(
      tx,
      term: term,
      meaning: meaning,
      deckId: deckId,
      senseKey: senseKey,
      approve: approve,
    ),
  );

  Future<bool> _addWord(
    DatabaseExecutor tx, {
    required String term,
    required String meaning,
    required String deckId,
    required String senseKey,
    required bool approve,
  }) async {
    final word = normalizeTerm(term);
    final definition = normalizeMeaning(meaning);
    final key = senseKey.trim();
    if (word.isEmpty ||
        word.length > 200 ||
        definition.length > 1000 ||
        !RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(key)) {
      throw const UserFacingException(
        'Kiểm tra từ (1–200 ký tự), nghĩa (tối đa 1000) và mã nghĩa (chữ thường, số, dấu - hoặc _).',
      );
    }
    if (approve && definition.isEmpty) {
      throw const UserFacingException('Cần có nghĩa trước khi đưa vào học.');
    }
    await _checkDeck(tx, deckId);
    final matches = await tx.query(
      'entries',
      where: 'normalized_term=? AND source_language=? AND target_language=?',
      whereArgs: [word, 'en', 'vi'],
    );
    final entryId = matches.isEmpty
        ? Ids.entry(word, 'en', 'vi')
        : matches.single['id'] as String;
    if (matches.isEmpty) {
      await tx.insert('entries', {
        'id': entryId,
        'term': word,
        'normalized_term': word,
        'created_at': clock().toUtc().millisecondsSinceEpoch,
      });
    }
    final existing = await tx.query(
      'senses',
      where: 'entry_id=? AND sense_key=?',
      whereArgs: [entryId, key],
    );
    if (existing.isNotEmpty &&
        definition.isNotEmpty &&
        existing.single['meaning'] != definition) {
      throw const UserFacingException(
        'Từ và mã nghĩa này đã có nội dung khác. Hãy sửa nghĩa hiện có hoặc chọn mã nghĩa mới.',
      );
    }
    await tx.insert('deck_entries', {
      'deck_id': deckId,
      'entry_id': entryId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (existing.isNotEmpty) return false;
    final senseId = Ids.sense(entryId, key);
    await tx.insert('senses', {
      'id': senseId,
      'entry_id': entryId,
      'sense_key': key,
      'meaning': definition,
      'search_text': '$word $definition'.toLowerCase(),
      'status': approve ? 'approved' : 'draft',
    });
    if (approve) {
      await tx.insert('cards', {'id': Ids.card(senseId), 'sense_id': senseId});
    }
    return true;
  }

  Future<int> addDraftLines(String text, String deckId) async {
    final words = text
        .split('\n')
        .map(normalizeTerm)
        .where((s) => s.isNotEmpty)
        .toSet();
    if (words.isEmpty || words.length > 500) {
      throw const UserFacingException(
        'Dán từ 1 đến 500 từ, mỗi dòng một từ hoặc cụm từ.',
      );
    }
    return db.transaction((tx) async {
      var added = 0;
      for (final word in words) {
        if (await _addWord(
          tx,
          term: word,
          meaning: '',
          deckId: deckId,
          senseKey: 'primary',
          approve: false,
        )) {
          added++;
        }
      }
      return added;
    });
  }

  Future<void> saveMeaning(
    String senseId,
    String meaning, {
    required bool approve,
    bool resetSchedule = false,
  }) async {
    final definition = normalizeMeaning(meaning);
    if (definition.length > 1000 || (approve && definition.isEmpty)) {
      throw const UserFacingException(
        'Nghĩa cần từ 1 đến 1000 ký tự trước khi duyệt.',
      );
    }
    await db.transaction((tx) async {
      final rows = await tx.rawQuery(
        'SELECT s.*, e.term FROM senses s JOIN entries e ON e.id=s.entry_id WHERE s.id=?',
        [senseId],
      );
      if (rows.isEmpty) {
        throw const UserFacingException('Không tìm thấy từ này.');
      }
      final row = rows.single;
      if (row['status'] == 'approved' && !approve) {
        throw const UserFacingException(
          'Từ đã duyệt cần có nghĩa. Dùng tạm dừng để ngừng học.',
        );
      }
      await tx.update(
        'senses',
        {
          'meaning': definition,
          'search_text': '${row['term']} $definition'.toLowerCase(),
          'status': approve ? 'approved' : 'draft',
          'content_revision': (row['content_revision'] as int) + 1,
        },
        where: 'id=?',
        whereArgs: [senseId],
      );
      if (approve) {
        final cards = await tx.query(
          'cards',
          where: 'sense_id=?',
          whereArgs: [senseId],
        );
        if (cards.isEmpty) {
          await tx.insert('cards', {
            'id': Ids.card(senseId),
            'sense_id': senseId,
          });
        } else {
          final card = cards.single;
          await tx.update(
            'cards',
            {
              'revision': (card['revision'] as int) + 1,
              if (resetSchedule) ...{
                'state': 'new',
                'due_at': null,
                'interval_days': 1,
                'lapses': 0,
                'last_review_id': null,
              },
            },
            where: 'id=?',
            whereArgs: [card['id']],
          );
        }
      }
    });
  }

  Future<void> setSuspended(String senseId, bool suspended) async {
    await db.rawUpdate(
      'UPDATE cards SET suspended=?, revision=revision+1 WHERE sense_id=?',
      [suspended ? 1 : 0, senseId],
    );
  }

  Future<List<Vocabulary>> vocabulary({
    String search = '',
    String? deckId,
    bool draftsOnly = false,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (search.trim().isNotEmpty) {
      final escaped = normalizeTerm(search)
          .toLowerCase()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      conditions.add("s.search_text LIKE ? ESCAPE '\\'");
      args.add('%$escaped%');
    }
    if (deckId != null) {
      conditions.add(
        'EXISTS(SELECT 1 FROM deck_entries de WHERE de.entry_id=e.id AND de.deck_id=?)',
      );
      args.add(deckId);
    }
    if (draftsOnly) conditions.add("s.status='draft'");
    final rows = await db.rawQuery(
      '''SELECT e.id entry_id, e.term, s.id sense_id, s.meaning, s.sense_key, s.status,
      coalesce(c.suspended,0) suspended,
      (SELECT group_concat(d.name, ', ') FROM decks d JOIN deck_entries de ON de.deck_id=d.id WHERE de.entry_id=e.id AND d.archived=0) groups
      FROM senses s JOIN entries e ON s.entry_id=e.id LEFT JOIN cards c ON c.sense_id=s.id
      ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'} ORDER BY e.term COLLATE NOCASE,s.sense_key''',
      args,
    );
    return rows
        .map(
          (r) => Vocabulary(
            entryId: r['entry_id'] as String,
            senseId: r['sense_id'] as String,
            term: r['term'] as String,
            meaning: r['meaning'] as String,
            senseKey: r['sense_key'] as String,
            status: r['status'] as String,
            groups: r['groups'] as String? ?? 'Chưa có nhóm',
            suspended: r['suspended'] == 1,
          ),
        )
        .toList();
  }

  Future<int> _newUsed(DatabaseExecutor tx, String day) async =>
      (await tx.rawQuery(
            'SELECT count(*) n FROM review_events WHERE study_day=? AND was_new=1',
            [day],
          )).single['n']
          as int;

  Future<StudyStats> stats() => db.transaction((tx) async {
    final config = (await tx.query('settings')).single;
    final now = clock().toUtc();
    final day = _studyDay(now, config['timezone'] as String);
    final counts = (await tx.rawQuery(
      '''SELECT
      (SELECT count(*) FROM entries) entries,
      (SELECT count(*) FROM senses) senses,
      (SELECT count(*) FROM senses WHERE status='draft') drafts,
      (SELECT count(*) FROM cards WHERE suspended=0 AND state='new') fresh,
      (SELECT count(*) FROM cards WHERE suspended=0 AND state!='new' AND due_at<=?) due,
      (SELECT count(*) FROM review_events WHERE study_day=?) reviews,
      (SELECT min(due_at) FROM cards WHERE suspended=0 AND state!='new' AND due_at>?) next_due''',
      [now.millisecondsSinceEpoch, day, now.millisecondsSinceEpoch],
    )).single;
    return StudyStats(
      entries: counts['entries'] as int,
      senses: counts['senses'] as int,
      drafts: counts['drafts'] as int,
      due: counts['due'] as int,
      fresh: counts['fresh'] as int,
      newRemaining: max(
        0,
        (config['daily_new_limit'] as int) - await _newUsed(tx, day),
      ),
      reviewedToday: counts['reviews'] as int,
      nextDue: counts['next_due'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              counts['next_due'] as int,
              isUtc: true,
            ),
    );
  });

  Future<List<StudyCard>> studyQueue({
    String? deckId,
    int limit = 20,
  }) => db.transaction((tx) async {
    final now = clock().toUtc();
    final config = (await tx.query('settings')).single;
    final remaining = max(
      0,
      (config['daily_new_limit'] as int) -
          await _newUsed(tx, _studyDay(now, config['timezone'] as String)),
    );
    final group = deckId == null
        ? ''
        : 'AND EXISTS(SELECT 1 FROM deck_entries de WHERE de.entry_id=e.id AND de.deck_id=?)';
    const base = '''SELECT c.*, e.term, s.meaning, s.sense_key FROM cards c
      JOIN senses s ON s.id=c.sense_id JOIN entries e ON e.id=s.entry_id
      WHERE c.suspended=0 AND s.status='approved' ''';
    final due = await tx.rawQuery(
      '$base AND c.state!=? AND c.due_at<=? $group ORDER BY c.due_at,c.id LIMIT ?',
      ['new', now.millisecondsSinceEpoch, ?deckId, limit],
    );
    final fresh = await tx.rawQuery(
      '$base AND c.state=? $group ORDER BY e.created_at,c.id LIMIT ?',
      ['new', ?deckId, min(remaining, max(0, limit - due.length))],
    );
    return [...due, ...fresh]
        .map(
          (r) => StudyCard(
            id: r['id'] as String,
            term: r['term'] as String,
            meaning: r['meaning'] as String,
            senseKey: r['sense_key'] as String,
            state: r['state'] as String,
            intervalDays: r['interval_days'] as int,
            lapses: r['lapses'] as int,
            revision: r['revision'] as int,
          ),
        )
        .toList();
  });

  /// Event ID is generated on reveal and reused on retry. Review + schedule are atomic.
  Future<void> review(StudyCard snapshot, Rating rating, String eventId) =>
      db.transaction((tx) async {
        final previousEvent = await tx.query(
          'review_events',
          where: 'id=?',
          whereArgs: [eventId],
        );
        if (previousEvent.isNotEmpty) {
          if (previousEvent.single['card_id'] != snapshot.id ||
              previousEvent.single['rating'] != rating.name) {
            throw const UserFacingException(
              'Lượt ôn không khớp. Hãy mở lại phiên học.',
            );
          }
          return;
        }
        final records = await tx.rawQuery(
          'SELECT c.*, s.content_revision, s.status FROM cards c JOIN senses s ON s.id=c.sense_id WHERE c.id=?',
          [snapshot.id],
        );
        if (records.isEmpty) {
          throw const UserFacingException('Thẻ không còn khả dụng.');
        }
        final card = records.single;
        if (card['revision'] != snapshot.revision ||
            card['suspended'] == 1 ||
            card['status'] != 'approved') {
          throw const UserFacingException(
            'Thẻ đã thay đổi. Hãy mở lại phiên học để tải nội dung mới.',
          );
        }
        final now = clock().toUtc();
        final config = (await tx.query('settings')).single;
        final day = _studyDay(now, config['timezone'] as String);
        if (card['state'] == 'new' &&
            await _newUsed(tx, day) >= (config['daily_new_limit'] as int)) {
          throw const UserFacingException(
            'Đã đủ từ mới hôm nay. Bạn vẫn có thể ôn các thẻ đến hạn.',
          );
        }
        if (card['state'] != 'new' &&
            (card['due_at'] as int) > now.millisecondsSinceEpoch) {
          throw const UserFacingException('Thẻ này chưa đến hạn ôn.');
        }
        final next = _scheduler.review(
          state: card['state'] as String,
          intervalDays: card['interval_days'] as int,
          lapses: card['lapses'] as int,
          rating: rating,
          now: now,
        );
        await tx.insert('review_events', {
          'id': eventId,
          'card_id': snapshot.id,
          'rating': rating.name,
          'reviewed_at': now.millisecondsSinceEpoch,
          'study_day': day,
          'was_new': card['state'] == 'new' ? 1 : 0,
          'device_id': config['device_id'],
          'content_revision': card['content_revision'],
          'scheduler_version': Scheduler.version,
          'previous_state': card['state'],
          'new_state': next.state,
          'previous_interval': card['interval_days'],
          'new_interval': next.intervalDays,
          'previous_due': card['due_at'],
          'new_due': next.due.millisecondsSinceEpoch,
        });
        await tx.update(
          'cards',
          {
            'state': next.state,
            'due_at': next.due.millisecondsSinceEpoch,
            'interval_days': next.intervalDays,
            'lapses': next.lapses,
            'revision': snapshot.revision + 1,
            'scheduler_version': Scheduler.version,
            'last_review_id': eventId,
          },
          where: 'id=?',
          whereArgs: [snapshot.id],
        );
      });
}
