import 'dart:async';
import 'package:flutter/material.dart';

enum WhiteboardTool { pen, eraser }

class WhiteboardPoint {
  final double x; // Normalized coordinate (0.0 - 1.0)
  final double y; // Normalized coordinate (0.0 - 1.0)
  final String action; // 'start', 'draw', 'end'
  final int color;
  final double strokeWidth;

  WhiteboardPoint({
    required this.x,
    required this.y,
    required this.action,
    required this.color,
    required this.strokeWidth,
  });

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'action': action,
    'color': color,
    'width': strokeWidth,
  };
}

class WhiteboardCanvas extends StatefulWidget {
  final Function(WhiteboardPoint) onLocalDraw;
  final VoidCallback onLocalClear;
  final Stream<dynamic>? remoteEventStream;

  const WhiteboardCanvas({
    super.key,
    required this.onLocalDraw,
    required this.onLocalClear,
    this.remoteEventStream,
  });

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  final List<DrawingLine> _lines = [];
  DrawingLine? _currentDrawingLine;

  Color _activeColor = Colors.indigoAccent;
  double _strokeWidth = 4.0;
  WhiteboardTool _activeTool = WhiteboardTool.pen;
  StreamSubscription? _remoteStreamSub;

  @override
  void initState() {
    super.initState();
    // Listen to remote drawings arriving from the LiveKit Data Channel
    _remoteStreamSub = widget.remoteEventStream?.listen((event) {
      if (event is Map<String, dynamic>) {
        final action = event['action'] as String;
        if (action == 'clear') {
          setState(() {
            _lines.clear();
          });
        } else {
          final x = (event['x'] as num).toDouble();
          final y = (event['y'] as num).toDouble();
          final colorVal = event['color'] as int;
          final width = (event['width'] as num).toDouble();
          _handleRemoteDraw(x, y, action, colorVal, width);
        }
      }
    });
  }

  @override
  void dispose() {
    _remoteStreamSub?.cancel();
    super.dispose();
  }

  void _handleRemoteDraw(double x, double y, String action, int colorVal, double width) {
    if (!mounted) return;
    
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // Convert normalized percentages back to local screen pixels
    final size = renderBox.size;
    final localOffset = Offset(x * size.width, y * size.height);

    setState(() {
      if (action == 'start') {
        _lines.add(DrawingLine(
          points: [localOffset],
          color: Color(colorVal),
          strokeWidth: width,
        ));
      } else if (action == 'draw' && _lines.isNotEmpty) {
        _lines.last.points.add(localOffset);
      }
    });
  }

  void _onDrawingAction(Offset localPosition, String action, Size canvasSize) {
    // 1. Normalize local points into a percentage (0.0 to 1.0)
    final double normX = localPosition.dx / canvasSize.width;
    final double normY = localPosition.dy / canvasSize.height;

    // 2. Dispatch to the parent room to publish over LiveKit
    widget.onLocalDraw(WhiteboardPoint(
      x: normX,
      y: normY,
      action: action,
      color: _activeTool == WhiteboardTool.eraser ? 0xFF0F172A : _activeColor.value,
      strokeWidth: _activeTool == WhiteboardTool.eraser ? 24.0 : _strokeWidth,
    ));

    // 3. Render immediately locally
    setState(() {
      if (action == 'start') {
        _currentDrawingLine = DrawingLine(
          points: [localPosition],
          color: _activeTool == WhiteboardTool.eraser ? const Color(0xFF0F172A) : _activeColor,
          strokeWidth: _activeTool == WhiteboardTool.eraser ? 24.0 : _strokeWidth,
        );
        _lines.add(_currentDrawingLine!);
      } else if (action == 'draw' && _currentDrawingLine != null) {
        _currentDrawingLine!.points.add(localPosition);
      } else if (action == 'end') {
        _currentDrawingLine = null;
      }
    });
  }

  void _clearCanvas() {
    widget.onLocalClear();
    setState(() {
      _lines.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 700;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
      ),
      child: Column(
        children: [
          // Toolbar
          Container(
            padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                _buildToolBtn(Icons.edit, WhiteboardTool.pen, isNarrow: isNarrow),
                SizedBox(width: isNarrow ? 4 : 8),
                _buildToolBtn(Icons.cleaning_services, WhiteboardTool.eraser, isNarrow: isNarrow),
                SizedBox(width: isNarrow ? 8 : 16),
                
                if (_activeTool == WhiteboardTool.pen) ...[
                  _buildColorIndicator(Colors.indigoAccent),
                  _buildColorIndicator(Colors.pinkAccent),
                  _buildColorIndicator(Colors.greenAccent),
                  _buildColorIndicator(Colors.amber),
                  _buildColorIndicator(Colors.white),
                  SizedBox(width: isNarrow ? 8 : 16),
                ],

                if (isNarrow) ...[
                  IconButton(
                    icon: Icon(
                      _strokeWidth <= 4.0 
                          ? Icons.lens_outlined 
                          : (_strokeWidth <= 9.0 ? Icons.lens : Icons.adjust),
                      size: _strokeWidth <= 4.0 ? 12 : (_strokeWidth <= 9.0 ? 16 : 20),
                      color: Colors.white70,
                    ),
                    tooltip: 'Cycle Brush Size',
                    onPressed: () {
                      setState(() {
                        if (_strokeWidth <= 4.0) {
                          _strokeWidth = 8.0;
                        } else if (_strokeWidth <= 9.0) {
                          _strokeWidth = 14.0;
                        } else {
                          _strokeWidth = 3.0;
                        }
                      });
                    },
                  ),
                  const Spacer(),
                ] else ...[
                  const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _strokeWidth,
                      min: 2.0,
                      max: 15.0,
                      activeColor: Colors.indigoAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (val) => setState(() => _strokeWidth = val),
                    ),
                  ),
                ],

                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: _clearCanvas,
                  tooltip: 'Clear Board',
                ),
              ],
            ),
          ),
          
          // Sketch Area
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      onPanStart: (details) => _onDrawingAction(details.localPosition, 'start', canvasSize),
                      onPanUpdate: (details) => _onDrawingAction(details.localPosition, 'draw', canvasSize),
                      onPanEnd: (details) => _onDrawingAction(Offset.zero, 'end', canvasSize),
                      child: CustomPaint(
                        painter: WhiteboardPainter(lines: _lines),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBtn(IconData icon, WhiteboardTool tool, {bool isNarrow = false}) {
    final isActive = _activeTool == tool;
    return Container(
      decoration: BoxDecoration(
        color: isActive ? Colors.indigoAccent.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        iconSize: isNarrow ? 18 : 24,
        padding: isNarrow ? const EdgeInsets.all(4) : const EdgeInsets.all(8),
        constraints: isNarrow ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
        icon: Icon(icon, color: isActive ? Colors.indigoAccent : Colors.white54),
        onPressed: () => setState(() => _activeTool = tool),
      ),
    );
  }

  Widget _buildColorIndicator(Color color) {
    final isActive = _activeColor == color;
    return GestureDetector(
      onTap: () => setState(() => _activeColor = color),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: isActive ? Colors.white : Colors.transparent, width: 2),
        ),
      ),
    );
  }
}

class DrawingLine {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  DrawingLine({required this.points, required this.color, required this.strokeWidth});
}

class WhiteboardPainter extends CustomPainter {
  final List<DrawingLine> lines;

  WhiteboardPainter({required this.lines});

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle background grid
    final paintGrid = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..strokeWidth = 1.0;
    
    const double step = 40.0;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paintGrid);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paintGrid);
    }

    // Draw paths
    for (final line in lines) {
      if (line.points.isEmpty) continue;
      
      final paint = Paint()
        ..color = line.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = line.strokeWidth
        ..style = PaintingStyle.stroke;

      if (line.points.length == 1) {
        canvas.drawCircle(line.points.first, line.strokeWidth / 2, paint..style = PaintingStyle.fill);
      } else {
        final path = Path()..moveTo(line.points.first.dx, line.points.first.dy);
        for (int i = 1; i < line.points.length; i++) {
          path.lineTo(line.points[i].dx, line.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) => true;
}
