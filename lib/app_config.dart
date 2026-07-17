class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ljrutrzzgrlcjsadqaeo.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxqcnV0cnp6Z3JsY2pzYWRxYWVvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQyMjkxNjMsImV4cCI6MjA5OTgwNTE2M30.biBIHxwggBEzhBbG7TR45alOJDA3tycuKAqeqg6jAEU',
  );

  static const String webAppUrl = String.fromEnvironment(
    'SAFEHER_WEB_URL',
    defaultValue: 'https://safeher-ruby.vercel.app',
  );

  static Uri? get webAppUri {
    final raw = webAppUrl.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return null;
    return uri;
  }
}
