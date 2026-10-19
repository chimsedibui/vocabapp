import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../domain/models.dart';
import 'editors.dart';
import 'data_settings.dart';
import 'review_page.dart';
import 'ai_settings.dart';
import 'passage_page.dart';

class VocabApp extends StatelessWidget {
  const VocabApp({super.key, required this.repository});
  final LibraryRepository repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'VocabApp',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xff21634b),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xff21634b),
            surface: const Color(0xfffaf9f5),
          ),
      scaffoldBackgroundColor: const Color(0xfffaf9f5),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfffaf9f5),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xffe3e6de)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        ),
      ),
    ),
    home: LibraryHome(repository: repository),
  );
}

class _Overview {
  const _Overview(this.stats, this.decks, this.dailyLimit);
  final StudyStats stats;
  final List<Deck> decks;
  final int dailyLimit;
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({super.key, required this.repository});
  final LibraryRepository repository;
  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> with WidgetsBindingObserver {
  int _tab = 0;
  String? _deck;
  bool _draftsOnly = false;
  final _search = TextEditingController();
  late Future<_Overview> _overview;
  Timer? _timer;
  LibraryRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _overview = _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _tab == 0) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<_Overview> _load() async => _Overview(
    await repo.stats(),
    await repo.decks(),
    (await repo.settings())['daily_new_limit'] as int,
  );
  void _refresh() {
    if (mounted) {
      setState(() {
        _overview = _load();
      });
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _action(Future<void> Function() callback) async {
    try {
      await callback();
      _refresh();
    } catch (e) {
      _message(friendlyError(e));
    }
  }

  Future<void> _addDeck() async {
    final name = await askDeckName(context);
    if (name != null) {
      await _action(() async {
        _deck = await repo.createDeck(name);
      });
    }
  }

  Future<void> _edit(_Overview data, {Vocabulary? word}) async {
    if (word == null && data.decks.isEmpty) {
      await _addDeck();
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WordEditor(
        repository: repo,
        decks: data.decks,
        word: word,
        initialDeck: _deck,
      ),
    );
    if (result == true) {
      _refresh();
      _message('Đã lưu vào thư viện.');
    }
  }

  Future<void> _bulk(_Overview data) async {
    if (data.decks.isEmpty) {
      await _addDeck();
      return;
    }
    final count = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          BulkEditor(repository: repo, decks: data.decks, initialDeck: _deck),
    );
    if (count != null) {
      _refresh();
      _message('Đã thêm $count từ nháp. Các từ trùng được giữ nguyên.');
    }
  }

  Future<void> _passage() async {
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => PassagePage(library: repo, initialDeck: _deck),
      ),
    );
    _refresh();
  }

  Future<void> _study() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReviewPage(repository: repo, deckId: _deck),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.spa_outlined, color: Color(0xff21634b)),
            SizedBox(width: 10),
            Text('VocabApp', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.wb_sunny_outlined),
                  label: 'Hôm nay',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_stories_outlined),
                  label: 'Thư viện',
                ),
                NavigationDestination(icon: Icon(Icons.tune), label: 'Cài đặt'),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _tab,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.wb_sunny_outlined),
                  label: Text('Hôm nay'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.auto_stories_outlined),
                  label: Text('Thư viện'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.tune),
                  label: Text('Cài đặt'),
                ),
              ],
            ),
          if (wide) const VerticalDivider(width: 1),
          Expanded(
            child: FutureBuilder<_Overview>(
              future: _overview,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Chưa tải được thư viện.'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _refresh,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  );
                }
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: switch (_tab) {
                      0 => _today(data),
                      1 => _library(data),
                      _ => _settings(data),
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupPicker(_Overview data) => DropdownButtonFormField<String>(
    key: ValueKey('group-$_tab-$_deck-${data.decks.length}'),
    initialValue: _deck ?? '',
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Nhóm từ'),
    items: [
      const DropdownMenuItem(value: '', child: Text('Tất cả nhóm')),
      ...data.decks.map(
        (d) => DropdownMenuItem(
          value: d.id,
          child: Text(
            '${d.name} (${d.count})',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ],
    onChanged: (v) => setState(() => _deck = v == '' ? null : v),
  );

  Widget _today(_Overview data) {
    final s = data.stats;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'MỖI NGÀY MỘT CHÚT',
          style: TextStyle(
            letterSpacing: 2,
            fontSize: 12,
            color: Color(0xff536957),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Gom từ. Nhớ lâu hơn.',
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'Một nơi cho những từ bạn muốn nhớ. Học gọn, theo nhịp của bạn.',
        ),
        const SizedBox(height: 28),
        Card(
          color: const Color(0xffe9f0e5),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.senses == 0
                      ? 'Bắt đầu từ một từ.'
                      : 'Dành vài phút cho trí nhớ.',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  s.senses == 0
                      ? 'Thêm từ và nghĩa bạn muốn học. Thư viện được lưu ngay trên thiết bị.'
                      : '${s.due} thẻ đến hạn · ${min(s.fresh, s.newRemaining)} từ mới có thể học trong toàn thư viện.',
                ),
                const SizedBox(height: 24),
                if (s.senses == 0)
                  FilledButton.icon(
                    onPressed: () => _edit(data),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm từ đầu tiên'),
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _study,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Học ngay'),
                      ),
                      TextButton(
                        onPressed: () => _edit(data),
                        child: const Text('Thêm từ mới'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat('${s.entries}', 'Từ / cụm từ', Icons.auto_stories_outlined),
            _stat('${s.senses}', 'Nghĩa trong thư viện', Icons.layers_outlined),
            _stat(
              '${s.reviewedToday}',
              'Lượt ôn hôm nay',
              Icons.check_circle_outline,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _groupPicker(data),
        const SizedBox(height: 12),
        const Text(
          'Mỗi phiên tối đa 20 thẻ. Ưu tiên thẻ đến hạn, rồi đến từ mới.',
        ),
        if (s.drafts > 0)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text('${s.drafts} nghĩa đang ở bản nháp'),
                subtitle: const Text('Bổ sung nghĩa và duyệt để đưa vào học.'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => setState(() {
                  _tab = 1;
                  _draftsOnly = true;
                  _deck = null;
                }),
              ),
            ),
          ),
        if (s.nextDue != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('Lượt ôn tiếp theo: ${_nextDueLabel(s.nextDue!)}'),
          ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Icon(Icons.offline_bolt_outlined, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text('Học offline · Không cần tài khoản · Không cần API'),
            ),
          ],
        ),
      ],
    );
  }

  String _nextDueLabel(DateTime date) {
    final duration = date.difference(repo.clock().toUtc());
    if (duration.inMinutes < 1) return 'sắp đến hạn';
    if (duration.inHours < 1) return 'sau khoảng ${duration.inMinutes} phút';
    if (duration.inDays < 1) return 'sau khoảng ${duration.inHours} giờ';
    return 'sau khoảng ${duration.inDays} ngày';
  }

  Widget _stat(String value, String label, IconData icon) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xff58705b)),
            const SizedBox(height: 16),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    ),
  );

  Widget _library(_Overview data) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: OutlinedButton.icon(
            onPressed: _passage,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Thêm từ từ passage (AI)'),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thư viện của bạn',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _edit(data),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm từ'),
                  ),
                  OutlinedButton(
                    onPressed: () => _bulk(data),
                    child: const Text('Dán danh sách'),
                  ),
                  TextButton.icon(
                    onPressed: _addDeck,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Tạo nhóm'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Tìm từ hoặc nghĩa',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _groupPicker(data)),
                  if (_deck != null)
                    PopupMenuButton<String>(
                      tooltip: 'Quản lý nhóm',
                      onSelected: (value) async {
                        final deck = data.decks.firstWhere(
                          (d) => d.id == _deck,
                        );
                        if (value == 'rename') {
                          final name = await askDeckName(
                            context,
                            initial: deck.name,
                          );
                          if (name != null) {
                            await _action(() => repo.renameDeck(deck.id, name));
                          }
                        } else {
                          await _action(() async {
                            await repo.archiveDeck(deck.id);
                            _deck = null;
                          });
                          _message(
                            'Đã ẩn nhóm. Từ và tiến độ vẫn còn trong toàn thư viện.',
                          );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Đổi tên nhóm'),
                        ),
                        PopupMenuItem(value: 'archive', child: Text('Ẩn nhóm')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FilterChip(
                label: const Text('Chỉ bản nháp'),
                selected: _draftsOnly,
                onSelected: (v) => setState(() => _draftsOnly = v),
              ),
            ],
          ),
        ),
      ),
      FutureBuilder<List<Vocabulary>>(
        future: repo.vocabulary(
          search: _search.text,
          deckId: _deck,
          draftsOnly: _draftsOnly,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Chưa tải được danh sách. Hãy làm mới.'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final words = snapshot.data!;
          if (words.isEmpty) {
            return const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Chưa có từ phù hợp. Thêm từ mới hoặc đổi bộ lọc.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: SliverList.builder(
              itemCount: words.length,
              itemBuilder: (context, index) {
                final word = words[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    title: Text(
                      word.term,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            word.meaning.isEmpty
                                ? 'Chưa có nghĩa'
                                : word.meaning,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${word.status == 'draft'
                                ? 'Bản nháp'
                                : word.suspended
                                ? 'Tạm dừng học'
                                : 'Đã duyệt'} · ${word.groups}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    onTap: () => _edit(data, word: word),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Tùy chọn ${word.term}',
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            await _edit(data, word: word);
                          case 'suspend':
                            await _action(
                              () => repo.setSuspended(
                                word.senseId,
                                !word.suspended,
                              ),
                            );
                          case 'remove':
                            await _action(
                              () => repo.removeFromDeck(word.entryId, _deck!),
                            );
                          case 'attach':
                            final id = await showDialog<String>(
                              context: context,
                              builder: (context) => SimpleDialog(
                                title: const Text('Gắn vào nhóm'),
                                children: data.decks
                                    .map(
                                      (d) => SimpleDialogOption(
                                        onPressed: () =>
                                            Navigator.pop(context, d.id),
                                        child: Text(d.name),
                                      ),
                                    )
                                    .toList(),
                              ),
                            );
                            if (id != null) {
                              await _action(
                                () => repo.attachToDeck(word.entryId, id),
                              );
                            }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Sửa / duyệt nghĩa'),
                        ),
                        const PopupMenuItem(
                          value: 'attach',
                          child: Text('Gắn thêm nhóm'),
                        ),
                        if (word.status == 'approved')
                          PopupMenuItem(
                            value: 'suspend',
                            child: Text(
                              word.suspended ? 'Tiếp tục học' : 'Tạm dừng học',
                            ),
                          ),
                        if (_deck != null)
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Bỏ từ khỏi nhóm này'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    ],
  );

  Widget _settings(_Overview data) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Nhịp học của bạn',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Từ mới mỗi ngày',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Đặt 0 nếu chỉ muốn ôn từ cũ. Thẻ đến hạn không bị giới hạn bởi số này.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                isExpanded: true,
                key: ValueKey(data.dailyLimit),
                initialValue: data.dailyLimit,
                decoration: const InputDecoration(labelText: 'Giới hạn'),
                items:
                    ({0, 5, 10, 15, 20, 30, 50, 100, data.dailyLimit}.toList()
                          ..sort())
                        .map(
                          (n) => DropdownMenuItem(
                            value: n,
                            child: Text('$n từ mới / ngày'),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) _action(() => repo.setDailyLimit(v));
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thư viện riêng trên thiết bị',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text(
                'Ngôn ngữ: Anh → Việt\nNgày học: múi giờ Việt Nam (UTC+7)\nMỗi phiên: tối đa 20 thẻ',
              ),
              SizedBox(height: 12),
              Text(
                'Thư viện được lưu trên thiết bị. Sao lưu để giữ tiến độ trước khi chuyển máy; đồng bộ tự động chưa được bật.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const AiSettings(),
      const SizedBox(height: 16),
      DataSettings(
        repository: repo,
        onRestored: () {
          _deck = null;
          _refresh();
          _message('Đã khôi phục thư viện và tiến độ học.');
        },
      ),
    ],
  );
}
