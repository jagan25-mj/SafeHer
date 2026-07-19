import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';
import '../theme.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final List<_NewsItem> _newsList = [];
  bool _isLoading = true;
  String? _error;
  
  final List<String> _categories = ['General', 'Safety Laws', 'Self Defense', 'Women\'s Rights'];
  String _selectedCategory = 'General';

  @override
  void initState() {
    super.initState();
    _fetchLiveNews(loadFromCacheFirst: true);
  }

  String _getSearchQuery() {
    switch (_selectedCategory) {
      case 'Safety Laws':
        return 'women+safety+laws+india';
      case 'Self Defense':
        return 'women+self+defense+india';
      case 'Women\'s Rights':
        return 'women+rights+india';
      case 'General':
      default:
        return 'women+safety+india';
    }
  }

  Future<void> _fetchLiveNews({bool loadFromCacheFirst = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final cacheKey = 'cached_news_$_selectedCategory';
    final prefs = await SharedPreferences.getInstance();

    if (loadFromCacheFirst) {
      final cachedXml = prefs.getString(cacheKey);
      if (cachedXml != null) {
        _parseAndSetNews(cachedXml);
        // Don't stop loading, we want to fetch the latest in the background
      }
    }

    try {
      final query = _getSearchQuery();
      final url = 'https://news.google.com/rss/search?q=$query&hl=en-IN&gl=IN&ceid=IN:en';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        await prefs.setString(cacheKey, response.body); // Cache it
        _parseAndSetNews(response.body);
      } else {
        throw Exception('Failed to load news (Status ${response.statusCode})');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_newsList.isEmpty) {
            _error = 'Could not fetch live news right now. Please check your internet connection.';
          } else {
            // If we have cached news, just show a small snackbar instead of blocking UI
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Offline mode: Showing cached news.')),
            );
          }
          _isLoading = false;
        });
      }
    }
  }

  void _parseAndSetNews(String xmlString) {
    try {
      final document = XmlDocument.parse(xmlString);
      final items = document.findAllElements('item');

      final parsedNews = <_NewsItem>[];
      final seenUrls = <String>{}; // For deduplication

      for (final item in items) {
        final title = item.findElements('title').firstOrNull?.innerText ?? 'No Title';
        final link = item.findElements('link').firstOrNull?.innerText ?? '';
        final pubDate = item.findElements('pubDate').firstOrNull?.innerText ?? '';
        final source = item.findElements('source').firstOrNull?.innerText ?? 'News Source';

        if (link.isNotEmpty && !seenUrls.contains(link)) {
          seenUrls.add(link);
          parsedNews.add(_NewsItem(
            title: title,
            link: link,
            pubDate: pubDate,
            source: source,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _newsList.clear();
          _newsList.addAll(parsedNews);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error parsing news data.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openArticle(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the article link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafeHerColors.background,
      appBar: AppBar(
        title: const Text('Live Daily News'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildCategoryChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = category == _selectedCategory;
          return ChoiceChip(
            label: Text(category),
            selected: isSelected,
            selectedColor: SafeHerColors.brand.withValues(alpha: 0.2),
            onSelected: (selected) {
              if (selected && _selectedCategory != category) {
                setState(() {
                  _selectedCategory = category;
                });
                _fetchLiveNews(loadFromCacheFirst: true);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _newsList.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: SafeHerColors.brand),
      );
    }

    if (_error != null && _newsList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: SafeHerColors.warning),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: SafeHerColors.brandStrong),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _fetchLiveNews(),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              )
            ],
          ),
        ),
      );
    }

    if (_newsList.isEmpty) {
      return const Center(
        child: Text(
          'No recent news found for this category.',
          style: TextStyle(color: SafeHerColors.brandStrong),
        ),
      );
    }

    return RefreshIndicator(
      color: SafeHerColors.brand,
      onRefresh: () => _fetchLiveNews(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _newsList.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final news = _newsList[index];
          return _buildNewsCard(news);
        },
      ),
    );
  }

  Widget _buildNewsCard(_NewsItem news) {
    return Container(
      decoration: BoxDecoration(
        color: SafeHerColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openArticle(news.link),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.public, size: 16, color: SafeHerColors.brand),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        news.source,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: SafeHerColors.brand,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  news.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: SafeHerColors.foreground,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _formatDate(news.pubDate),
                        style: const TextStyle(
                          fontSize: 12,
                          color: SafeHerColors.brandStrong,
                        ),
                      ),
                    ),
                    const Text(
                      'Read more',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: SafeHerColors.accent,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 10,
                      color: SafeHerColors.accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String rawDate) {
    if (rawDate.length > 22) {
      return rawDate.substring(0, 22);
    }
    return rawDate;
  }
}

class _NewsItem {
  final String title;
  final String link;
  final String pubDate;
  final String source;

  _NewsItem({
    required this.title,
    required this.link,
    required this.pubDate,
    required this.source,
  });
}
