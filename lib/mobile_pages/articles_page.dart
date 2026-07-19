import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  final List<_ArticleItem> _articles = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _activeCategory = 'All';

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    try {
      final rows = await Supabase.instance.client
          .from('safety_content')
          .select('id,title,content,image_url,created_at')
          .eq('type', 'ARTICLE')
          .order('created_at', ascending: false);

      final parsed = (rows as List)
          .map((row) => _ArticleItem.fromRow(Map<String, dynamic>.from(row)))
          .toList();

      if (!mounted) return;
      setState(() {
        _articles
          ..clear()
          ..addAll(parsed);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<String> get _categories {
    final categories = <String>{'All'};
    for (final article in _articles) {
      categories.add(article.category);
    }
    return categories.toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _articles.where((article) {
      final matchesQuery = article.title.toLowerCase().contains(
        _query.toLowerCase(),
      );
      final matchesCategory =
          _activeCategory == 'All' || article.category == _activeCategory;
      return matchesQuery && matchesCategory;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Safety Articles')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: SafeHerGradients.pageBackground,
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: safeHerGlassDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resource Library',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF4F336F),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Short reads to help you stay alert, prepared, and informed.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF7F5B96),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search safety guides...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories
                            .map(
                              (category) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(category),
                                  selected: _activeCategory == category,
                                  onSelected: (_) => setState(
                                    () => _activeCategory = category,
                                  ),
                                  selectedColor: SafeHerColors.brandStrong,
                                  labelStyle: TextStyle(
                                    color: _activeCategory == category
                                        ? Colors.white
                                        : SafeHerColors.foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  backgroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: SafeHerColors.stroke,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: safeHerGlassDecoration(),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: safeHerGlassDecoration(),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                        size: 36,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Unable to load articles.',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: SafeHerColors.foreground,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF7F5B96)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadArticles,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SafeHerColors.brandStrong,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: safeHerGlassDecoration(),
                  child: const Center(
                    child: Text(
                      'No matching articles found.',
                      style: TextStyle(
                        color: Color(0xFF6E5386),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                ...filtered.map(
                  (article) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: safeHerGlassDecoration(),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading:
                          article.imageUrl == null || article.imageUrl!.isEmpty
                          ? Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: SafeHerColors.accentSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.menu_book_rounded,
                                color: SafeHerColors.accent,
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(
                                article.imageUrl!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            ),
                      title: Text(
                        article.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: SafeHerColors.foreground,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${article.category} • ${article.readTime}\n${article.summary}',
                          style: const TextStyle(
                            color: Color(0xFF7F5B96),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) {
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(28),
                                ),
                              ),
                              child: SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      article.title,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: SafeHerColors.foreground,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${article.category} • ${article.readTime}',
                                      style: const TextStyle(
                                        color: Color(0xFF7F5B96),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Html(
                                      data: article.content,
                                      style: {
                                        'body': Style(
                                          margin: Margins.zero,
                                          padding: HtmlPaddings.zero,
                                          color: const Color(0xFF6E5386),
                                          fontWeight: FontWeight.w600,
                                          lineHeight: const LineHeight(1.5),
                                        ),
                                        'h1': Style(
                                          color: SafeHerColors.foreground,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        'h2': Style(
                                          color: SafeHerColors.foreground,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        'p': Style(
                                          margin: Margins.only(bottom: 8),
                                        ),
                                        'li': Style(
                                          margin: Margins.only(bottom: 6),
                                        ),
                                      },
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleItem {
  final String id;
  final String title;
  final String category;
  final String readTime;
  final String summary;
  final String? imageUrl;
  final String content;

  const _ArticleItem({
    required this.id,
    required this.title,
    required this.category,
    required this.readTime,
    required this.summary,
    required this.content,
    this.imageUrl,
  });

  factory _ArticleItem.fromRow(Map<String, dynamic> row) {
    final title = (row['title']?.toString() ?? '').trim();
    final rawContent = (row['content']?.toString() ?? '').trim();
    // Sanitize HTML to prevent XSS from compromised admin content
    final content = _sanitizeHtml(rawContent);
    final category = _deriveCategory(title, content);
    return _ArticleItem(
      id: row['id']?.toString() ?? '',
      title: title,
      category: category,
      readTime: _deriveReadTime(content),
      summary: _deriveSummary(content),
      content: content,
      imageUrl: row['image_url']?.toString(),
    );
  }

  /// Strip dangerous HTML tags, keeping only safe formatting tags.
  static String _sanitizeHtml(String html) {
    // Allowlist: only these tags are preserved
    const allowedTags = [
      'p', 'br', 'b', 'strong', 'i', 'em', 'u',
      'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'a', 'span', 'blockquote', 'hr', 'div',
    ];
    final tagPattern = allowedTags.join('|');
    // Remove all tags that are NOT in the allowlist
    return html.replaceAllMapped(
      RegExp(r'<\/?(?!(?:' + tagPattern + r')(?:\s|>|\/))(\w+)[^>]*>', caseSensitive: false),
      (match) => '',
    );
  }

  static String _deriveCategory(String title, String content) {
    final text = '$title $content'.toLowerCase();
    if (text.contains('digital') || text.contains('privacy')) {
      return 'Digital Safety';
    }
    if (text.contains('travel') ||
        text.contains('commute') ||
        text.contains('night')) {
      return 'Travel';
    }
    if (text.contains('sos') ||
        text.contains('plan') ||
        text.contains('prepared')) {
      return 'Preparedness';
    }
    if (text.contains('response') || text.contains('alert')) {
      return 'Response';
    }
    return 'Safety';
  }

  static String _deriveReadTime(String content) {
    final words = content
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
    final minutes = (words / 180).ceil().clamp(1, 15);
    return '$minutes min';
  }

  static String _deriveSummary(String content) {
    final collapsed = content
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (collapsed.length <= 160) return collapsed;
    return '${collapsed.substring(0, 157)}...';
  }
}
