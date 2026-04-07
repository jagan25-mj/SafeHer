class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ckjjocbjnpqvnpxdihfl.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNrampvY2JqbnBxdm5weGRpaGZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNDIwMDcsImV4cCI6MjA4ODgxODAwN30.SkwgyuUXlOgpRWPL7nYaHb-5p-6SZneH28rJaRqqt-Y',
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
