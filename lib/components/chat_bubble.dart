import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:math';
import '../shared_state.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Formats a file size in bytes to a human-readable string.
String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Returns icon and accent color for a given file type.
(IconData, Color) _fileIconAndColor(ChatFileType type) {
  switch (type) {
    case ChatFileType.pdf:
      return (Icons.picture_as_pdf_rounded, const Color(0xFFEF4444));
    case ChatFileType.word:
      return (Icons.description_rounded, const Color(0xFF3B82F6));
    case ChatFileType.excel:
      return (Icons.table_chart_rounded, const Color(0xFF22C55E));
    case ChatFileType.powerpoint:
      return (Icons.slideshow_rounded, const Color(0xFFF97316));
    case ChatFileType.audio:
      return (Icons.audio_file_rounded, const Color(0xFFA855F7));
    case ChatFileType.video:
      return (Icons.video_file_rounded, const Color(0xFF06B6D4));
    case ChatFileType.medical:
      return (Icons.medical_information_rounded, const Color(0xFF10B981));
    case ChatFileType.zip:
      return (Icons.folder_zip_rounded, const Color(0xFFF59E0B));
    default:
      return (Icons.attach_file_rounded, const Color(0xFF94A3B8));
  }
}

/// Downloads a file using the browser anchor trick (web only).
void _downloadFile(String fileName, Uint8List bytes) {
  if (!kIsWeb) return;
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Opens a full-screen image viewer dialog.
void _showFullScreenImage(BuildContext context, Uint8List bytes, String? fileName) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: Row(
              children: [
                if (fileName != null)
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    tooltip: 'Download',
                    onPressed: () => _downloadFile(fileName, bytes),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// A rich chat bubble that renders text, images, and file attachments appropriately.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final bubbleColor = isMe ? const Color(0xFF4F46E5) : const Color(0xFF1E293B);
    final align = isMe ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender name (only for received messages in a group)
            if (!isMe && message.senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  message.senderName,
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // Bubble
            Container(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildContent(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.fileType) {
      case ChatFileType.image:
        return _buildImageContent(context);
      case ChatFileType.text:
        return _buildTextContent();
      default:
        return _buildFileContent(context);
    }
  }

  /// Plain text message bubble.
  Widget _buildTextContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: message.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            message.text,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(
            message.time,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 9),
          ),
        ],
      ),
    );
  }

  /// Image bubble with tap-to-fullscreen.
  Widget _buildImageContent(BuildContext context) {
    final bytes = message.fileBytes;
    if (bytes == null) return _buildTextContent();
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showFullScreenImage(context, bytes, message.fileName),
            child: Hero(
              tag: message.id,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      width: 240,
                      height: 180,
                      gaplessPlayback: true,
                    ),
                    Positioned(
                      bottom: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (message.fileName != null && message.fileName != 'whiteboard.png')
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                message.fileName!,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.fileSize != null)
                  Text(
                    _formatFileSize(message.fileSize!),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 9),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _downloadFile(message.fileName ?? 'image.png', bytes),
                  child: const Tooltip(
                    message: 'Download',
                    child: Icon(Icons.download_rounded, color: Colors.white54, size: 16),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  message.time,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Generic file attachment bubble (PDF, Word, Audio, etc.).
  Widget _buildFileContent(BuildContext context) {
    final (icon, color) = _fileIconAndColor(message.fileType);
    final bytes = message.fileBytes;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (message.fileSize != null)
                      Text(
                        _formatFileSize(message.fileSize!),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                      ),
                    const Spacer(),
                    Text(
                      message.time,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (bytes != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _downloadFile(message.fileName ?? 'file', bytes),
              child: Tooltip(
                message: 'Download',
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.download_rounded, color: Colors.white70, size: 16),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
