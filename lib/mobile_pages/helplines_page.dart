import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class HelplinesPage extends StatefulWidget {
  const HelplinesPage({super.key});

  @override
  State<HelplinesPage> createState() => _HelplinesPageState();
}

class _HelplinesPageState extends State<HelplinesPage> {
  List<_HelplineItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHelplines();
  }

  Future<void> _loadHelplines() async {
    try {
      final rows = await Supabase.instance.client
          .from('helplines')
          .select('id,name,number,category,created_at')
          .order('name', ascending: true);

      final parsed = (rows as List)
          .map((row) => _HelplineItem.fromRow(Map<String, dynamic>.from(row)))
          .toList();

      if (!mounted) return;
      setState(() {
        _items = parsed;
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

  Future<void> _dial(String number) async {
    final uri = Uri.parse('tel:$number');
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Helplines')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: SafeHerGradients.pageBackground,
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadHelplines,
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
                              'Crisis Support',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: const Color(0xFF4F336F),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Verified emergency responders and support services available 24/7 for immediate assistance.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF7F5B96),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_error != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
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
                                'Unable to load helplines.',
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
                                style: const TextStyle(
                                  color: Color(0xFF7F5B96),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _loadHelplines,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SafeHerColors.brandStrong,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ..._items.map(
                        (item) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: safeHerGlassDecoration(),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: SafeHerColors.accentSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.support_agent,
                                  color: SafeHerColors.accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.service,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: SafeHerColors.foreground,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item.category} • ${item.availability}',
                                      style: const TextStyle(
                                        color: Color(0xFF7F5B96),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    item.number,
                                    style: const TextStyle(
                                      color: SafeHerColors.brandStrong,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _dial(item.number),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(88, 38),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      backgroundColor:
                                          SafeHerColors.brandStrong,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.call_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Call',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: SafeHerColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: SafeHerColors.stroke),
                        ),
                        child: const Text(
                          '112 works even when the phone has no active SIM card or mobile data.',
                          style: TextStyle(
                            color: Color(0xFF6E5386),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _HelplineItem {
  final String service;
  final String number;
  final String category;
  final String availability;

  const _HelplineItem(
    this.service,
    this.number,
    this.category,
    this.availability,
  );

  factory _HelplineItem.fromRow(Map<String, dynamic> row) {
    return _HelplineItem(
      row['name']?.toString() ?? '',
      row['number']?.toString() ?? '',
      row['category']?.toString() ?? 'Safety',
      '24/7',
    );
  }
}
