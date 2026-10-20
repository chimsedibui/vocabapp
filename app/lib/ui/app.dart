import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../domain/models.dart';
import '../services/sync_service.dart';
import 'editors.dart';
import 'data_settings.dart';
import 'review_page.dart';
import 'ai_settings.dart';
import 'passage_page.dart';
import 'import_page.dart';
import 'sync_settings.dart';
import 'ui_scale.dart';

class VocabApp extends StatefulWidget {
  const VocabApp({
    super.key,
    required this.repository,
    this.uiScale,
    this.sync,
  });
  final LibraryRepository repository;

  /// Optional replication; without it the app stays local-only.
  final SyncService? sync;

  /// Zoom preference; tests and previews get a non-persistent 100% default.
  final UiScaleController? uiScale;
  @override
  State<VocabApp> createState() => _VocabAppState();
}

class _VocabAppState extends State<VocabApp> {
  late final UiScaleController _scale = widget.uiScale ?? UiScaleController();

  @override
  void dispose() {
    if (widget.uiScale == null) _scale.dispose();
    super.dispose();
  }

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
    builder: (context, child) => ValueListenableBuilder<double>(
      valueListenable: _scale,
      builder: (context, scale, _) => UiZoom(scale: scale, child: child!),
    ),
    home: LibraryHome(
      repository: widget.repository,
      uiScale: _scale,
      sync: widget.sync,
    ),
  );
}

class _Overview {
  const _Overview(this.stats, this.decks, this.dailyLimit);
  final StudyStats stats;
  final List<Deck> decks;
  final int dailyLimit;
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({
    super.key,
    required this.repository,
    this.uiScale,
    this.sync,
  });
  final LibraryRepository repository;
  final UiScaleController? uiScale;
  final SyncService? sync;
  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> with WidgetsBindingObserver {
  int _tab = 0;
  String? _deck;
  bool _draftsOnly = false;
  final _search = TextEditingController();
  // Last loaded data stays on screen while a refresh runs, so periodic and
  // post-action reloads never flash a spinner or reset scroll positions.
  _Overview? _data;
  bool _loadFailed = false;
  List<Vocabulary>? _words;
  bool _wordsFailed = false;
  int _overviewGen = 0, _wordsGen = 0;
  Timer? _timer, _searchDebounce;
  int _remoteSeen = 0;
  LibraryRepository get repo => widget.repository;

  void _onSync() {
    final version = widget.sync!.remoteVersion;
    if (version != _remoteSeen) {
      _remoteSeen = version;
      _refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remoteSeen = widget.sync?.remoteVersion ?? 0;
    widget.sync?.addListener(_onSync);
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _tab == 0) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.sync?.removeListener(_onSync);
    _timer?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      widget.sync?.sync();
    }
  }

  Future<_Overview> _load() async => _Overview(
    await repo.stats(),
    await repo.decks(),
    (await repo.settings())['daily_new_limit'] as int,
  );

  Future<void> _refresh() async {
    final gen = ++_overviewGen;
    _reloadWords();
    try {
      final data = await _load();
      if (mounted && gen == _overviewGen) {
        setState(() {
          _data = data;
          _loadFailed = false;
        });
      }
    } catch (_) {
      if (mounted && gen == _overviewGen) setState(() => _loadFailed = true);
    }
  }

  Future<void> _reloadWords() async {
    final gen = ++_wordsGen;
    try {
      final words = await repo.vocabulary(
        search: _search.text,
        deckId: _deck,
        draftsOnly: _draftsOnly,
      );
      if (mounted && gen == _wordsGen) {
        setState(() {
          _words = words;
          _wordsFailed = false;
        });
      }
    } catch (_) {
      if (mounted && gen == _wordsGen) setState(() => _wordsFailed = true);
    }
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    _reloadWords();
  }

  void _onSearch(String _) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), _reloadWords);
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _action(Future<void> Function() callback) async {
    try {
      await callback();
      widget.sync?.requestSync();
      await _refresh();
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
      widget.sync?.requestSync();
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
      widget.sync?.requestSync();
      _refresh();
      _message('Đã thêm $count từ nháp. Các từ trùng được giữ nguyên.');
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    widget.sync?.requestSync();
    _refresh();
  }

  Future<void> _import() => _open(ImportPage(library: repo));
  Future<void> _passage() =>
      _open(PassagePage(library: repo, initialDeck: _deck));
  Future<void> _study() => _open(ReviewPage(repository: repo, deckId: _deck));

  static const _destinations = [
    (Icons.wb_sunny_outlined, Icons.wb_sunny, 'Hôm nay'),
    (Icons.auto_stories_outlined, Icons.auto_stories, 'Thư viện'),
    (Icons.tune_outlined, Icons.tune, 'Cài đặt'),
  ];

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
          if (widget.sync != null) SyncStatusButton(sync: widget.sync!),
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
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: label,
                  ),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _tab,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
          if (wide) const VerticalDivider(width: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final data = _data;
    if (data == null) {
      return Center(
        child: _loadFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Chưa tải được thư viện.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Thử lại'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: switch (_tab) {
              0 => _today(data),
              1 => _library(data),
              _ => _settings(data),
            },
          ),
        ),
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
    onChanged: (v) => _setFilter(() => _deck = v == '' ? null : v),
  );

  Widget _heading(String eyebrow, String title, [String? subtitle]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          letterSpacing: 2,
          fontSize: 12,
          color: Color(0xff536957),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle)],
    ],
  );

  Widget _today(_Overview data) {
    final s = data.stats;
    final stats = [
      _stat('${s.due}', 'Thẻ đến hạn', Icons.schedule),
      _stat('${s.entries}', 'Từ / cụm từ', Icons.auto_stories_outlined),
      _stat('${s.senses}', 'Nghĩa trong thư viện', Icons.layers_outlined),
      _stat(
        '${s.reviewedToday}',
        'Lượt ôn hôm nay',
        Icons.check_circle_outline,
      ),
    ];
    final drafts = s.drafts == 0
        ? null
        : Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text('${s.drafts} nghĩa đang ở bản nháp'),
              subtitle: const Text('Bổ sung nghĩa và duyệt để đưa vào học.'),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => _setFilter(() {
                _tab = 1;
                _draftsOnly = true;
                _deck = null;
              }),
            ),
          );
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 860;
        final hero = _heroCard(data);
        return ListView(
          key: const PageStorageKey('today'),
          padding: const EdgeInsets.all(24),
          children: [
            _heading(
              'MỖI NGÀY MỘT CHÚT',
              'Gom từ. Nhớ lâu hơn.',
              'Một nơi cho những từ bạn muốn nhớ. Học gọn, theo nhịp của bạn.',
            ),
            const SizedBox(height: 24),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: hero),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        ResponsiveGrid(
                          minTileWidth: 160,
                          maxColumns: 2,
                          children: stats,
                        ),
                        if (drafts != null) ...[
                          const SizedBox(height: 12),
                          drafts,
                        ],
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              hero,
              const SizedBox(height: 16),
              ResponsiveGrid(minTileWidth: 120, children: stats),
              if (drafts != null) ...[const SizedBox(height: 16), drafts],
            ],
            const SizedBox(height: 24),
            const Row(
              children: [
                Icon(Icons.offline_bolt_outlined, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Học offline · Không cần tài khoản · Không cần API',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _heroCard(_Overview data) {
    final s = data.stats;
    final empty = s.senses == 0;
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xffe9f0e5),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              empty ? 'Bắt đầu từ một từ.' : 'Dành vài phút cho trí nhớ.',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              empty
                  ? 'Thêm từ và nghĩa bạn muốn học. Thư viện được lưu ngay trên thiết bị.'
                  : '${s.due} thẻ đến hạn · ${min(s.fresh, s.newRemaining)} từ mới có thể học trong toàn thư viện.',
            ),
            const SizedBox(height: 20),
            if (empty)
              FilledButton.icon(
                onPressed: () => _edit(data),
                icon: const Icon(Icons.add),
                label: const Text('Thêm từ đầu tiên'),
              )
            else ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _groupPicker(data),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
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
              const SizedBox(height: 16),
              Text(
                'Mỗi phiên tối đa 20 thẻ. Ưu tiên thẻ đến hạn, rồi đến từ mới.'
                '${s.nextDue == null ? '' : '\nLượt ôn tiếp theo: ${_nextDueLabel(s.nextDue!)}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _nextDueLabel(DateTime date) {
    final duration = date.difference(repo.clock().toUtc());
    if (duration.inMinutes < 1) return 'sắp đến hạn';
    if (duration.inHours < 1) return 'sau khoảng ${duration.inMinutes} phút';
    if (duration.inDays < 1) return 'sau khoảng ${duration.inHours} giờ';
    return 'sau khoảng ${duration.inDays} ngày';
  }

  Widget _stat(String value, String label, IconData icon) => Card(
    margin: EdgeInsets.zero,
    child: LayoutBuilder(
      builder: (context, box) {
        final badge = CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xffe9f0e5),
          foregroundColor: const Color(0xff21634b),
          child: Icon(icon, size: 20),
        );
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
        // Narrow phone tiles stack the badge so two columns still fit.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: box.maxWidth < 180
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [badge, const SizedBox(height: 10), text],
                )
              : Row(
                  children: [
                    badge,
                    const SizedBox(width: 14),
                    Expanded(child: text),
                  ],
                ),
        );
      },
    ),
  );

  Widget _library(_Overview data) => CustomScrollView(
    key: const PageStorageKey('library'),
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                'THƯ VIỆN',
                'Thư viện của bạn',
                '${data.stats.entries} từ / cụm từ · ${data.stats.senses} nghĩa · ${data.decks.length} nhóm',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _edit(data),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm từ'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _bulk(data),
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Dán danh sách'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Nhập JSON / CSV'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _passage,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Từ passage (AI)'),
                  ),
                  TextButton.icon(
                    onPressed: _addDeck,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Tạo nhóm'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _filters(data),
            ],
          ),
        ),
      ),
      ..._wordList(data),
    ],
  );

  Widget _filters(_Overview data) {
    final search = TextField(
      controller: _search,
      onChanged: _onSearch,
      decoration: InputDecoration(
        labelText: 'Tìm từ hoặc nghĩa',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Xóa tìm kiếm',
                onPressed: () => _setFilter(_search.clear),
                icon: const Icon(Icons.close),
              ),
      ),
    );
    final group = Row(
      children: [
        Expanded(child: _groupPicker(data)),
        if (_deck != null) _deckMenu(data),
      ],
    );
    final drafts = FilterChip(
      label: const Text('Chỉ bản nháp'),
      selected: _draftsOnly,
      onSelected: (v) => _setFilter(() => _draftsOnly = v),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 720
          ? Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: group),
                const SizedBox(width: 12),
                drafts,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                search,
                const SizedBox(height: 12),
                group,
                const SizedBox(height: 8),
                drafts,
              ],
            ),
    );
  }

  Widget _deckMenu(_Overview data) => PopupMenuButton<String>(
    tooltip: 'Quản lý nhóm',
    onSelected: (value) async {
      final deck = data.decks.firstWhere((d) => d.id == _deck);
      if (value == 'rename') {
        final name = await askDeckName(context, initial: deck.name);
        if (name != null) {
          await _action(() => repo.renameDeck(deck.id, name));
        }
      } else {
        await _action(() async {
          await repo.archiveDeck(deck.id);
          _deck = null;
        });
        _message('Đã ẩn nhóm. Từ và tiến độ vẫn còn trong toàn thư viện.');
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'rename', child: Text('Đổi tên nhóm')),
      PopupMenuItem(value: 'archive', child: Text('Ẩn nhóm')),
    ],
  );

  List<Widget> _wordList(_Overview data) {
    Widget note(String text) => SliverPadding(
      padding: const EdgeInsets.all(24),
      sliver: SliverToBoxAdapter(
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
    final words = _words;
    if (words == null) {
      return [
        _wordsFailed
            ? note('Chưa tải được danh sách. Hãy làm mới.')
            : const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
      ];
    }
    if (words.isEmpty) {
      return [note('Chưa có từ phù hợp. Thêm từ mới hoặc đổi bộ lọc.')];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        sliver: SliverList.separated(
          itemCount: words.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _wordTile(data, words[index]),
        ),
      ),
    ];
  }

  Widget _wordTile(_Overview data, Vocabulary word) {
    final (status, color) = word.status == 'draft'
        ? ('Bản nháp', const Color(0xfffbe9c8))
        : word.suspended
        ? ('Tạm dừng học', const Color(0xffe6e6e6))
        : ('Đã duyệt', const Color(0xffdcebdd));
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        title: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              word.term,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(status, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                word.meaning.isEmpty ? 'Chưa có nghĩa' : word.meaning,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (word.groups.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(word.groups, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        onTap: () => _edit(data, word: word),
        trailing: _wordMenu(data, word),
      ),
    );
  }

  Widget _wordMenu(_Overview data, Vocabulary word) => PopupMenuButton<String>(
    tooltip: 'Tùy chọn ${word.term}',
    onSelected: (value) async {
      switch (value) {
        case 'edit':
          await _edit(data, word: word);
        case 'suspend':
          await _action(() => repo.setSuspended(word.senseId, !word.suspended));
        case 'remove':
          await _action(() => repo.removeFromDeck(word.entryId, _deck!));
        case 'attach':
          final id = await showDialog<String>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Gắn vào nhóm'),
              children: data.decks
                  .map(
                    (d) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, d.id),
                      child: Text(d.name),
                    ),
                  )
                  .toList(),
            ),
          );
          if (id != null) {
            await _action(() => repo.attachToDeck(word.entryId, id));
          }
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'edit', child: Text('Sửa / duyệt nghĩa')),
      const PopupMenuItem(value: 'attach', child: Text('Gắn thêm nhóm')),
      if (word.status == 'approved')
        PopupMenuItem(
          value: 'suspend',
          child: Text(word.suspended ? 'Tiếp tục học' : 'Tạm dừng học'),
        ),
      if (_deck != null)
        const PopupMenuItem(
          value: 'remove',
          child: Text('Bỏ từ khỏi nhóm này'),
        ),
    ],
  );

  Widget _section(String title, String body, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(body),
          if (children.isNotEmpty) const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _displayCard(UiScaleController scale) => ValueListenableBuilder(
    valueListenable: scale,
    builder: (context, value, _) => _section(
      'Cỡ giao diện',
      'Phóng to hoặc thu nhỏ toàn bộ chữ, nút và khoảng cách. Trên máy tính dùng Ctrl + / Ctrl − / Ctrl 0.',
      [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.outlined(
              tooltip: 'Thu nhỏ',
              onPressed: scale.canZoomOut ? scale.zoomOut : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '${(value * 100).round()}%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton.outlined(
              tooltip: 'Phóng to',
              onPressed: scale.canZoomIn ? scale.zoomIn : null,
              icon: const Icon(Icons.add),
            ),
            TextButton(
              onPressed: value == 1 ? null : scale.reset,
              child: const Text('Mặc định'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _settings(_Overview data) {
    final left = [
      _section(
        'Từ mới mỗi ngày',
        'Đặt 0 nếu chỉ muốn ôn từ cũ. Thẻ đến hạn không bị giới hạn bởi số này.',
        [
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
      if (widget.uiScale != null) _displayCard(widget.uiScale!),
      _section(
        'Thư viện riêng trên thiết bị',
        'Ngôn ngữ: Anh → Việt\nNgày học: múi giờ Việt Nam (UTC+7)\nMỗi phiên: tối đa 20 thẻ\n\nThư viện được lưu trên thiết bị. Sao lưu để giữ tiến độ trước khi chuyển máy; đồng bộ tự động chưa được bật.',
        const [],
      ),
    ];
    final right = [
      if (widget.sync != null) SyncSettings(sync: widget.sync!),
      const AiSettings(),
      DataSettings(
        repository: repo,
        onRestored: () {
          _deck = null;
          widget.sync?.requestSync();
          _refresh();
          _message('Đã khôi phục thư viện và tiến độ học.');
        },
      ),
    ];
    Widget column(List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          items[i],
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        key: const PageStorageKey('settings'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading('CÀI ĐẶT', 'Nhịp học của bạn'),
            const SizedBox(height: 24),
            if (box.maxWidth >= 860)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: column(left)),
                  const SizedBox(width: 16),
                  Expanded(child: column(right)),
                ],
              )
            else
              column([...left, ...right]),
          ],
        ),
      ),
    );
  }
}
