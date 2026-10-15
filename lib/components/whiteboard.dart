import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:file_picker/file_picker.dart';
import '../shared_state.dart';

class WhiteboardWidget extends StatefulWidget {
  final VoidCallback onClose;
  final bool isFullscreen;
  final VoidCallback? onFullscreenToggle;
  final bool isSplitView;
  final VoidCallback? onSplitViewToggle;

  const WhiteboardWidget({
    super.key, 
    required this.onClose,
    this.isFullscreen = false,
    this.onFullscreenToggle,
    this.isSplitView = false,
    this.onSplitViewToggle,
  });

  @override
  State<WhiteboardWidget> createState() => _WhiteboardWidgetState();
}

class _WhiteboardWidgetState extends State<WhiteboardWidget> {
  final MeetingController _controller = MeetingController();
  Color currentColor = Colors.black;
  double currentWidth = 4.0;
  bool isEraser = false; // eraser mode toggle
  static const Color _canvasBg = Colors.white; // matches canvas background
  Uint8List? _backgroundImageBytes;

  // Zoom/Pan controls
  final TransformationController _transformController = TransformationController();
  bool _isPanMode = false;

  // Pen popup visibility
  bool _showPenPopup = false;

  // Canvas capture key — wraps the drawing area in a RepaintBoundary
  final GlobalKey _canvasKey = GlobalKey();

  /// Renders the whiteboard canvas to a PNG and returns raw bytes.
  Future<Uint8List?> _captureWhiteboard() async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0); // 2x for crispness
      
      // Draw a white background rectangle before painting the captured image
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      
      final paint = ui.Paint()..color = Colors.white;
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), 
        paint
      );
      canvas.drawImage(image, ui.Offset.zero, ui.Paint());
      
      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(image.width, image.height);
      
      final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Capture error: $e');
      return null;
    }
  }

  /// Saves the whiteboard as a PNG download in the browser.
  Future<void> _saveWhiteboard() async {
    final bytes = await _captureWhiteboard();
    if (bytes == null) return;
    final blob = html.Blob([bytes], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'whiteboard_${DateTime.now().millisecondsSinceEpoch}.png')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// Captures the whiteboard and shares it to all participants via MeetingController.
  Future<void> _shareWhiteboard() async {
    final bytes = await _captureWhiteboard();
    if (bytes == null) return;
    await _controller.sendWhiteboardImage(bytes);
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.bytes != null) {
      final bytes = result.files.single.bytes!;
      setState(() {
        _backgroundImageBytes = bytes;
      });
      _controller.setWhiteboardBgImage(bytes);
    }
  }

  final List<Color> colors = [
    Colors.black,
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.purple,
    Colors.orange,
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateState);
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_updateState);
    _transformController.dispose();
    super.dispose();
  }

  /// Converts a viewport-space touch point to canvas-space coordinates.
  Offset _toCanvasCoords(Offset viewportPoint) {
    final matrix = _transformController.value;
    final inverted = Matrix4.inverted(matrix);
    return MatrixUtils.transformPoint(inverted, viewportPoint);
  }

  /// Floating pen settings popup — colors + stroke width slider.
  Widget _buildPenPopup() {
    return Positioned(
      bottom: 90, // sits just above the toolbar
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2540),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Pen Settings',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 60),
                    GestureDetector(
                      onTap: () => setState(() => _showPenPopup = false),
                      child: const Icon(Icons.close, color: Colors.white38, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Color swatches row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: colors.map((color) {
                    final isSelected = currentColor == color && !isEraser;
                    return GestureDetector(
                      onTap: () => setState(() {
                        currentColor = color;
                        isEraser = false;
                        _showPenPopup = false; // close on pick
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 10),
                        width: isSelected ? 34 : 28,
                        height: isSelected ? 34 : 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white24,
                            width: isSelected ? 2.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 10)]
                              : [],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 18),

                // Stroke width label + preview
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Stroke width',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    // Live stroke preview circle
                    Container(
                      width: currentWidth.clamp(4, 20).toDouble(),
                      height: currentWidth.clamp(4, 20).toDouble(),
                      decoration: BoxDecoration(
                        color: isEraser ? Colors.white : currentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      currentWidth.toStringAsFixed(0),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Stroke width slider
                SizedBox(
                  width: 240,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: currentColor,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: currentColor,
                      overlayColor: currentColor.withOpacity(0.15),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: currentWidth,
                      min: 2,
                      max: 20,
                      divisions: 18,
                      onChanged: (val) => setState(() => currentWidth = val),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _canvasBg, // Canvas background color
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: RepaintBoundary + InteractiveViewer — visual canvas content.
          // RepaintBoundary allows PNG capture via _canvasKey.
          RepaintBoundary(
            key: _canvasKey,
            child: InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.5,
            maxScale: 5.0,
            panEnabled: _isPanMode,  // pan on drag only in pan mode
            scaleEnabled: true,      // pinch + mouse wheel always active
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background image zooms and pans with the canvas
                if (_controller.whiteboardBgImageBytes != null || _backgroundImageBytes != null)
                  Image.memory(_controller.whiteboardBgImageBytes ?? _backgroundImageBytes!, fit: BoxFit.contain),
                // Strokes rendered here
                CustomPaint(
                  painter: WhiteboardPainter(strokes: _controller.strokes),
                  size: Size.infinite,
                ),
              ],
            ),
          ),
          ),

          // Layer 2: Drawing gesture overlay — sits ABOVE InteractiveViewer.
          // Active only in draw mode. Uses inverse matrix to convert screen
          // coordinates → canvas coordinates so drawing is accurate at any zoom.
          if (!_isPanMode)
            LayoutBuilder(builder: (context, constraints) {
              final canvasW = constraints.maxWidth;
              final canvasH = constraints.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (details) {
                  final cp = _toCanvasCoords(details.localPosition);
                  final nx = (cp.dx / canvasW).clamp(0.0, 1.0);
                  final ny = (cp.dy / canvasH).clamp(0.0, 1.0);
                  final strokeColor = isEraser ? _canvasBg : currentColor;
                  final strokeWidth = isEraser ? 24.0 : currentWidth;
                  _controller.startLocalStroke(nx, ny, strokeColor, strokeWidth);
                },
                onPanUpdate: (details) {
                  final cp = _toCanvasCoords(details.localPosition);
                  final nx = (cp.dx / canvasW).clamp(0.0, 1.0);
                  final ny = (cp.dy / canvasH).clamp(0.0, 1.0);
                  _controller.updateLocalStroke(nx, ny);
                },
                onPanEnd: (_) => _controller.endLocalStroke(),
              );
            }),

          // Pen popup (shown above toolbar when _showPenPopup = true)
          if (_showPenPopup) _buildPenPopup(),

          // Toolbar
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pen button — opens color + stroke popup
                    GestureDetector(
                      onTap: () => setState(() {
                        _showPenPopup = !_showPenPopup;
                        if (_showPenPopup) isEraser = false;
                      }),
                      child: Tooltip(
                        message: 'Pen Settings',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _showPenPopup
                                ? currentColor.withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _showPenPopup ? currentColor : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(Icons.edit, color: _showPenPopup ? currentColor : Colors.white70, size: 22),
                              // Active color dot indicator
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isEraser ? Colors.white : currentColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black54, width: 1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),
                    Container(width: 1, height: 24, color: Colors.white24),
                    const SizedBox(width: 8),

                    // NEW: Pan/Draw mode toggle
                    GestureDetector(
                      onTap: () => setState(() => _isPanMode = !_isPanMode),
                      child: Tooltip(
                        message: _isPanMode ? 'Switch to Whiteboard' : 'Pan / Navigate',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _isPanMode ? Colors.blueAccent.withOpacity(0.3) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isPanMode ? Colors.blueAccent : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            _isPanMode ? Icons.pan_tool : Icons.pan_tool_outlined,
                            color: _isPanMode ? Colors.blueAccent : Colors.white54,
                            size: 22,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),
                    Container(width: 1, height: 24, color: Colors.white24),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => setState(() => isEraser = !isEraser),
                      child: Tooltip(
                        message: isEraser ? 'Switch to Pen' : 'Eraser',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isEraser ? Colors.white24 : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isEraser ? Colors.white54 : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.auto_fix_normal,
                            color: isEraser ? Colors.white : Colors.white54,
                            size: 22,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),
                    Container(width: 1, height: 24, color: Colors.white24),
                    const SizedBox(width: 16),
                    
                    // Undo Button
                    IconButton(
                      icon: Icon(
                        Icons.undo,
                        color: _controller.strokes.isNotEmpty ? Colors.white70 : Colors.white24,
                      ),
                      onPressed: _controller.strokes.isNotEmpty
                          ? () => _controller.undoLastStroke()
                          : null,
                      tooltip: 'Undo',
                    ),

                    // Redo Button
                    IconButton(
                      icon: Icon(
                        Icons.redo,
                        color: _controller.canRedo ? Colors.white70 : Colors.white24,
                      ),
                      onPressed: _controller.canRedo
                          ? () => _controller.redoLastStroke()
                          : null,
                      tooltip: 'Redo',
                    ),

                    Container(width: 1, height: 24, color: Colors.white24),
                    const SizedBox(width: 8),

                    // Image Upload Button
                    IconButton(
                      icon: const Icon(Icons.image_outlined, color: Colors.white70),
                      onPressed: _pickImage,
                      tooltip: 'Upload Image',
                    ),
                    
                    // Save Button
                    IconButton(
                      icon: const Icon(Icons.save_alt, color: Colors.white70),
                      onPressed: _saveWhiteboard,
                      tooltip: 'Save as PNG',
                    ),

                    // Share Button
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white70),
                      onPressed: _shareWhiteboard,
                      tooltip: 'Share to Chat',
                    ),

                    // Clear Button
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white70),
                      onPressed: () {
                        _controller.clearWhiteboard();
                        setState(() {
                          _backgroundImageBytes = null;
                        });
                      },
                      tooltip: 'Clear Board',
                    ),
                    // Split View Toggle
                    if (widget.onSplitViewToggle != null)
                      IconButton(
                        icon: Icon(
                          widget.isSplitView ? Icons.call_merge : Icons.vertical_split,
                          color: Colors.white70,
                        ),
                        onPressed: widget.onSplitViewToggle,
                        tooltip: widget.isSplitView ? 'Normal View' : 'Split View',
                      ),

                    // Fullscreen Toggle
                    if (widget.onFullscreenToggle != null)
                      IconButton(
                        icon: Icon(
                          widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                          color: Colors.white70,
                        ),
                        onPressed: widget.onFullscreenToggle,
                        tooltip: widget.isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                      ),
                      
                    // Close Button
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: widget.onClose,
                      tooltip: 'Close Whiteboard',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WhiteboardPainter extends CustomPainter {
  final List<SharedStroke> strokes;

  WhiteboardPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      if (stroke.points.isNotEmpty) {
        path.moveTo(stroke.points.first.x * size.width, stroke.points.first.y * size.height);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].x * size.width, stroke.points[i].y * size.height);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) => true;
}
