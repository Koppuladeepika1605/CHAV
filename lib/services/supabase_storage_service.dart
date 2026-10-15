import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

/// Uploads received consultation-chat files to Supabase Storage.
///
/// This is a drop-in replacement for the previous MinIOService.
/// The public API ([uploadFile]) is intentionally identical so that
/// call-sites only need to change the import and class name.
///
/// Usage: call [uploadFile] once per received file when the call ends.
///
/// Setup (one-time):
///   1. Open the Supabase dashboard → Storage → New bucket → name it "chav"
///      (or whatever [SupabaseConfig.bucket] is set to).
///   2. Make sure [Supabase.initialize] is called in main() before any
///      uploads are attempted (see lib/main.dart).
class SupabaseStorageService {
  // ── MIME helper ───────────────────────────────────────────────────────────

  static String _mimeType(String fileName) {
    final ext =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    const map = {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'svg': 'image/svg+xml',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'html': 'text/html',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'doc': 'application/msword',
      'xls': 'application/vnd.ms-excel',
      'zip': 'application/zip',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Uploads [bytes] to Supabase Storage.
  ///
  /// Object path pattern:
  ///   {prefix}/{callEndedEpochMs}_{fileName}
  ///
  /// Files are stored flat under the prefix — no room-name subfolder.
  ///
  /// Returns true on success.
  static Future<bool> uploadFile({
    required String fileName,
    required Uint8List bytes,
    required DateTime receivedAt,
    required DateTime callEndedAt,
  }) async {
    try {
      final epoch = callEndedAt.millisecondsSinceEpoch;
      final filePath = '${SupabaseConfig.prefix}/${epoch}_$fileName';
      final mime = _mimeType(fileName);

      final storage = Supabase.instance.client.storage;

      debugPrint(
          'Supabase → uploadBinaryData $filePath (${bytes.length} bytes)');

      await storage.from(SupabaseConfig.bucket).uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: mime,
              // Overwrite if a file with the same path already exists.
              upsert: true,
            ),
          );

      debugPrint('Supabase ✓ uploaded: $filePath');
      return true;
    } on StorageException catch (e) {
      debugPrint(
        'Supabase storage error for $fileName: '
        '[status=${e.statusCode}] ${e.message} | error=${e.error}',
      );
      return false;
    } catch (e, st) {
      debugPrint('Supabase upload error for $fileName: $e\n$st');
      return false;
    }
  }
}
