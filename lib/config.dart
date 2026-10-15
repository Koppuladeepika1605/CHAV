class LiveKitConfig {
  // Local LiveKit Server URL
  static const String serverUrl = 'ws://127.0.0.1:7880';

  // Credentials used to sign tokens locally for testing
  static const String apiKey = 'devkey';
  static const String apiSecret = 'secret';
}

class SupabaseConfig {
  static const String url = 'https://yfhnpautctntwdcisvmb.supabase.co';
  static const String publishableKey =
      'sb_publishable_VnqEoHFr0lCKOPK-hrxyCw_NkjUyJQC';

  /// Storage bucket that holds consultation files.
  /// Create this bucket in the Supabase dashboard → Storage.
  static const String bucket = 'chav_consultation_files';

  /// All consultation files are stored under this prefix inside the bucket.
  static const String prefix = 'consultation-files';
}
