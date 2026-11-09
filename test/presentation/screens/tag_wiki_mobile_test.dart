import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_providers.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/cooccurrence_completion_source.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:nai_launcher/core/autocomplete/unified_tag_repository.dart';
import 'package:nai_launcher/core/rag/rag_client.dart';
import 'package:nai_launcher/core/rag/rag_settings.dart';
import 'package:nai_launcher/core/rag/rag_text_search.dart';
import 'package:nai_launcher/core/tag_expansion/tag_expansion_providers.dart';
import 'package:nai_launcher/core/wiki/auto_tag_translation_controller.dart';
import 'package:nai_launcher/core/wiki/tag_wiki_repository.dart';
import 'package:nai_launcher/core/wiki/wiki_directory.dart';
import 'package:nai_launcher/core/wiki/wiki_example_repository.dart';
import 'package:nai_launcher/core/wiki/wiki_tag_links.dart';
import 'package:nai_launcher/data/models/prompt_block/prompt_block.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/providers/prompt_block_library_provider.dart';
import 'package:nai_launcher/presentation/providers/rag_provider.dart';
import 'package:nai_launcher/presentation/screens/tag_wiki/tag_wiki_screen.dart';
import 'package:nai_launcher/presentation/themes/presets/geist_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/studio_capture_fonts.dart';

class _Tags extends UnifiedTagRepository {
  _Tags()
    : super(
        catalog: TagCatalogRepository(),
        runtime: () async => throw StateError('not used'),
      );

  static const entries = [
    CompletionCandidate(
      canonicalTag: 'blue_eyes',
      category: TagCategory.general,
      postCount: 100,
      matchKind: CompletionMatchKind.englishExact,
      sources: {CompletionSourceKind.base},
    ),
    CompletionCandidate(
      canonicalTag: 'short_hair',
      category: TagCategory.general,
      postCount: 50,
      matchKind: CompletionMatchKind.englishPrefix,
      sources: {CompletionSourceKind.base},
    ),
  ];

  @override
  Future<List<CompletionCandidate>> browse({
    TagCategory? category,
    bool? hasWiki,
    bool alphabetical = false,
    int offset = 0,
    int limit = 80,
  }) async => entries.skip(offset).take(limit).toList();

  @override
  Future<int> count({TagCategory? category, bool? hasWiki}) async =>
      entries.length;

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async =>
      entries.where((e) => e.canonicalTag.startsWith(query.token)).toList();

  @override
  Future<List<CompletionCandidate>> searchContains(
    String input, {
    int limit = 20,
  }) async => entries.where((e) => e.canonicalTag.contains(input)).toList();

  @override
  Future<List<CompletionCandidate>> byNames(Iterable<String> names) async =>
      entries.where((item) => names.contains(item.canonicalTag)).toList();
}

class _Wiki implements TagWikiRepository {
  @override
  Future<TagWikiEntry?> find(String tag) async => TagWikiEntry(
    tag: tag,
    body: 'Blue eyes are visible.',
    sourceUrl: 'https://safebooru.donmai.us/wiki_pages/$tag',
  );
}

class _Cooccurrence extends CooccurrenceCompletionSource {
  _Cooccurrence()
    : super.withLoader(
        () async => throw StateError('unused'),
        catalog: TagCatalogRepository(),
      );

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async =>
      const [];
}

class _Blocks extends PromptBlockLibraryNotifier {
  @override
  Future<PromptBlockLibraryState> build() async =>
      PromptBlockLibraryState(blocks: <PromptBlock>[], folders: []);
}

class _Auto extends ChangeNotifier implements AutoTagTranslationController {
  @override
  String? wikiFor(String tag) => null;
  @override
  bool get enabled => false;
  @override
  int get activeRequests => 0;
  @override
  bool isWikiTranslating(String tag) => false;
  @override
  Object? noSuchMethod(Invocation invocation) => null;
}

class _RagSettings extends RagSettingsController {
  @override
  RagSettings build() => const RagSettings(enabled: false);
}

class _Rag extends RagController {
  @override
  RagStatus build() => const RagStatus();
  @override
  Future<List<RagSearchHit>> searchText(
    RagTextQuery query, {
    required RagCancellation cancellation,
  }) async => const [];
}

const _directory = WikiDirectory(
  roots: [WikiDirectoryNode(label: 'Traits', group: 'traits', children: [])],
  groups: {
    'traits': WikiDirectoryGroup(
      title: 'Traits',
      members: ['blue_eyes'],
      children: [],
      sourceUrl: 'https://example.test',
    ),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioCaptureFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugForceMobileLayout = true;
  });
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpWiki(
    WidgetTester tester, {
    double width = 360,
    double height = 780,
    String locale = 'zh',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ragSettingsProvider.overrideWith(_RagSettings.new),
          ragControllerProvider.overrideWith(_Rag.new),
          unifiedTagRepositoryProvider.overrideWith((ref) => _Tags()),
          tagWikiRepositoryProvider.overrideWith((ref) => _Wiki()),
          cooccurrenceCompletionSourceProvider.overrideWithValue(
            _Cooccurrence(),
          ),
          autoTagTranslationProvider.overrideWith((ref) => _Auto()),
          wikiTagLinksProvider.overrideWithValue(
            WikiTagLinks(exactLookup: (_) async => {}),
          ),
          wikiExampleRepositoryProvider.overrideWithValue(
            WikiExampleRepository(
              fetchWiki: (tag, {cancelToken}) async => null,
              fetchPosts: (ids, {cancelToken}) async => [],
            ),
          ),
          promptBlockLibraryNotifierProvider.overrideWith(_Blocks.new),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: GeistTheme.light,
          home: const Scaffold(body: TagWikiScreen(directory: _directory)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('360dp 列表：书签常显、排序可点、无溢出', (tester) async {
    await pumpWiki(tester);
    expect(find.byKey(const Key('wiki-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('wiki-type-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('wiki-sort-filter')), findsOneWidget);
    // 手机端没有 hover，未选中的行也要露出书签按钮。
    final bookmark = find.byKey(const ValueKey('wiki-row-bookmark-blue_eyes'));
    expect(bookmark, findsOneWidget);
    expect(tester.getSize(bookmark).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp 点行进入全屏文章，返回列表', (tester) async {
    await pumpWiki(tester);
    await tester.tap(find.byKey(const ValueKey('wiki-row-blue_eyes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wiki-article-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('wiki-row-blue_eyes')), findsNothing);
    // 单栏文章头部：返回按钮与操作按钮都在，且按钮触控区 ≥ 44。
    final back = find.byKey(const ValueKey('wiki-article-back'));
    expect(back, findsOneWidget);
    expect(tester.getSize(back).width, greaterThanOrEqualTo(44));
    final bookmark = find.byKey(const ValueKey('wiki-article-bookmark'));
    expect(bookmark, findsOneWidget);
    expect(tester.getSize(bookmark).width, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wiki-row-blue_eyes')), findsOneWidget);
  });

  testWidgets('360dp 目录进底部弹层', (tester) async {
    await pumpWiki(tester);
    await tester.tap(find.byKey(const ValueKey('wiki-directory-button')));
    await tester.pumpAndSettle();
    expect(find.text('Traits'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp 各语言不溢出', (tester) async {
    for (final locale in ['zh', 'en', 'ja', 'ko']) {
      await pumpWiki(tester, locale: locale);
      expect(tester.takeException(), isNull, reason: '$locale 在 360dp 下溢出');
    }
  });
}
