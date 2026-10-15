import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'consultation_room.dart';
import 'clinical_panel.dart';
import 'whiteboard.dart';
import '../shared_state.dart';

class ConsultationView extends StatefulWidget {
  final String? url;
  final String? token;
  final String? room;

  const ConsultationView({super.key, this.url, this.token, this.room});

  @override
  State<ConsultationView> createState() => _ConsultationViewState();
}

class _ConsultationViewState extends State<ConsultationView> {
  String viewMode = 'split'; // 'split', 'form', 'video'
  final GlobalKey _videoKey = GlobalKey();
  
  double? _pipX;
  double? _pipY;
  bool _isPipMinimized = false;
  bool _isVideoOverlayVisible = true;

  @override
  void initState() {
    super.initState();
    MeetingController().addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MeetingController().removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // Initialize PiP coordinates
        if (_pipX == null || _pipY == null) {
          _pipX = screenWidth - 340;
          _pipY = 32;
        }

        double videoLeft = 16;
        double videoTop = 16;
        double videoWidth = 0;
        double videoHeight = 0;

        double formLeft = 0;
        double formTop = 16;
        double formWidth = 0;
        double formHeight = 0;
        
        bool isVideoPip = false;
        bool isFormPip = false;
        bool isWhiteboardOpen = MeetingController().isWhiteboardOpen;

        if (isWhiteboardOpen) {
          isVideoPip = true;
          isFormPip = true;
        } else {
          if (viewMode == 'split') {
            videoWidth = (screenWidth * 0.72) - 24;
            videoHeight = screenHeight - 32;
            formLeft = (screenWidth * 0.72) + 8;
            formWidth = (screenWidth * 0.28) - 24;
            formHeight = screenHeight - 32;
          } else if (viewMode == 'form') {
            formLeft = 16;
            formWidth = screenWidth - 32;
            formHeight = screenHeight - 32;
            
            videoWidth = 400;
            videoHeight = 280;
            videoLeft = screenWidth - videoWidth - 32;
            videoTop = screenHeight - videoHeight - 32;
            isVideoPip = true;
          } else if (viewMode == 'video') {
            videoWidth = screenWidth - 32;
            videoHeight = screenHeight - 32;
            
            formWidth = 240;
            formHeight = 160;
            formLeft = screenWidth - formWidth - 32;
            formTop = screenHeight - formHeight - 32;
            isFormPip = true;
          }
        }

        // 1. Build the Video Pane
        Widget videoPane = AnimatedContainer(
          duration: 500.ms,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: isVideoPip && !isWhiteboardOpen ? [const BoxShadow(color: Colors.black54, blurRadius: 20)] : [],
          ),
          clipBehavior: Clip.antiAlias,
          child: ConsultationRoom(
            key: _videoKey,
            url: widget.url,
            token: widget.token,
            roomName: widget.room,
            isPip: isVideoPip, 
            onExpand: () {
              if (isWhiteboardOpen) {
                MeetingController().toggleWhiteboardState(false);
              } else {
                setState(() => viewMode = 'video');
              }
            },
            onWhiteboardToggle: () {
              final nextState = !MeetingController().isWhiteboardOpen;
              if (nextState) {
                setState(() {
                  _isVideoOverlayVisible = true;
                  _isPipMinimized = false;
                });
              }
              MeetingController().toggleWhiteboardState(nextState);
            },
          ),
        );

        // 2. Build the Form Pane
        Widget formPane = AnimatedContainer(
          duration: 500.ms,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: isFormPip ? [const BoxShadow(color: Colors.black54, blurRadius: 20)] : [],
            color: isFormPip ? const Color(0xFF1E293B) : Colors.transparent,
          ),
          clipBehavior: Clip.antiAlias,
          child: isFormPip 
            ? _buildMinimizedForm() 
            : const ClinicalPanel(),
        );

        final List<Widget> stackChildren = [];

        if (isWhiteboardOpen) {
          // Whiteboard mode layout
          stackChildren.add(
            Positioned(
              left: 16,
              top: 16,
              width: screenWidth - 32,
              height: screenHeight - 32,
              child: WhiteboardWidget(
                onClose: () {
                  MeetingController().toggleWhiteboardState(false);
                },
              ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95)),
            ),
          );

          // Hide form pane mostly, keep it accessible if needed
          stackChildren.add(
            AnimatedPositioned(
              duration: 500.ms,
              curve: Curves.easeInOutCubic,
              left: 32,
              bottom: 32,
              width: 140,
              height: 100,
              child: formPane,
            ),
          );

          // Floating Draggable Video Overlay
          if (_isVideoOverlayVisible) {
            double overlayWidth = _isPipMinimized ? 240 : 340;
            double overlayHeight = _isPipMinimized ? 36 : 280;

            stackChildren.add(
              Positioned(
                left: _pipX,
                top: _pipY,
                width: overlayWidth,
                height: overlayHeight,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _pipX = (_pipX! + details.delta.dx).clamp(0.0, screenWidth - overlayWidth);
                      _pipY = (_pipY! + details.delta.dy).clamp(0.0, screenHeight - overlayHeight);
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 2)],
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // Drag Handle Header
                        Container(
                          height: 36,
                          color: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.drag_indicator, color: Colors.white38, size: 16),
                              const SizedBox(width: 8),
                              const Text('Meeting', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => setState(() => _isPipMinimized = !_isPipMinimized),
                                child: Icon(_isPipMinimized ? Icons.unfold_more : Icons.minimize, color: Colors.white54, size: 16),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () => MeetingController().toggleWhiteboardState(false),
                                child: const Icon(Icons.open_in_full, color: Colors.white54, size: 14),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () => setState(() => _isVideoOverlayVisible = false),
                                child: const Icon(Icons.close, color: Colors.white54, size: 18),
                              ),
                            ],
                          ),
                        ),
                        // Video Area
                        if (!_isPipMinimized)
                          Expanded(
                            child: videoPane,
                          ),
                      ],
                    ),
                  ).animate().scaleXY(begin: 0.9, duration: 200.ms, curve: Curves.easeOutCubic).fadeIn(),
                ),
              ),
            );
          }
        } else {
          // Normal view mode layout
          stackChildren.add(
            AnimatedPositioned(
              duration: 500.ms,
              curve: Curves.easeInOutCubic,
              left: videoLeft,
              top: videoTop,
              width: videoWidth,
              height: videoHeight,
              child: videoPane,
            ),
          );

          stackChildren.add(
            AnimatedPositioned(
              duration: 500.ms,
              curve: Curves.easeInOutCubic,
              left: formLeft,
              top: formTop,
              width: formWidth,
              height: formHeight,
              child: formPane,
            ),
          );

          // Toggle Bar
          stackChildren.add(
            Positioned(
              top: 24,
              left: 24,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141D2E).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
                ),
                child: Row(
                  children: [
                    _buildToggleBtn(Icons.grid_view_rounded, 'split'),
                    const SizedBox(width: 4),
                    _buildToggleBtn(Icons.article_outlined, 'form'),
                    const SizedBox(width: 4),
                    _buildToggleBtn(Icons.videocam_outlined, 'video'),
                  ],
                ),
              ).animate().slideY(begin: -1, duration: 600.ms, curve: Curves.easeOutCubic),
            ),
          );
        }

        return Stack(children: stackChildren);
      },
    );
  }

  Widget _buildToggleBtn(IconData icon, String mode) {
    final isActive = viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => viewMode = mode),
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF3B82F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isActive ? Colors.white : Colors.white60, size: 18),
      ),
    );
  }

  Widget _buildMinimizedForm() {
    return GestureDetector(
      onTap: () {
        if (MeetingController().isWhiteboardOpen) {
           MeetingController().toggleWhiteboardState(false);
           setState(() => viewMode = 'form');
        } else {
           setState(() => viewMode = 'form');
        }
      },
      child: Stack(
        children: [
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description, size: 40, color: Colors.indigoAccent),
                SizedBox(height: 8),
                Text('Form', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.open_in_full, size: 14, color: Colors.white),
            ),
          )
        ],
      ),
    );
  }
}

