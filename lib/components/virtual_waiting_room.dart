import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'token_generator.dart';
import '../config.dart'; // Import LiveKitConfig

class VirtualWaitingRoom extends StatefulWidget {
  final String? initialRoom;
  final String? initialUrl;
  final String? initialKey;
  final String? initialSecret;
  final String? initialPublicUrl;

  const VirtualWaitingRoom({
    super.key,
    this.initialRoom,
    this.initialUrl,
    this.initialKey,
    this.initialSecret,
    this.initialPublicUrl,
  });

  @override
  State<VirtualWaitingRoom> createState() => _VirtualWaitingRoomState();
}

class _VirtualWaitingRoomState extends State<VirtualWaitingRoom> {
  final _roomController = TextEditingController(text: 'my-consultation-room');
  final _nameController = TextEditingController(text: 'Dr. Amanulla Belg');
  final _serverUrlController = TextEditingController(text: '');
  
  // Custom API key/secret inputs (remain in code to prevent compilation errors but hidden from UI)
  final _apiKeyController = TextEditingController(text: '');
  final _apiSecretController = TextEditingController(text: '');
  final _publicWebUrlController = TextEditingController();

  bool isDoctor = true;
  String customToken = '';
  bool useLocalDevToken = true;

  // Camera preview variables
  LocalVideoTrack? _localVideoTrack;
  LocalAudioTrack? _localAudioTrack;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  String? _mediaError;
  bool _isInitializingMedia = true;

  @override
  void initState() {
    super.initState();
    
    // Set up initial values
    if (widget.initialRoom != null) {
      _roomController.text = widget.initialRoom!;
      _nameController.text = 'Guest - ${Random().nextInt(900) + 100}';
      isDoctor = false;
    } else {
      // Generate a unique random room ID (e.g. chav-xxxxxxxx) to terminate/avoid reuse of old links
      final rand = Random();
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final suffix = List.generate(8, (index) => chars[rand.nextInt(chars.length)]).join('');
      _roomController.text = 'chav-$suffix';
    }
    if (widget.initialUrl != null) {
      _serverUrlController.text = widget.initialUrl!;
    }
    if (widget.initialKey != null) {
      _apiKeyController.text = widget.initialKey!;
    }
    if (widget.initialSecret != null) {
      _apiSecretController.text = widget.initialSecret!;
    }
    if (widget.initialPublicUrl != null) {
      _publicWebUrlController.text = widget.initialPublicUrl!;
    }

    _initPreviewCamera();
  }

  Future<void> _initPreviewCamera() async {
    setState(() {
      _isInitializingMedia = true;
      _mediaError = null;
    });

    try {
      if (!kIsWeb) {
        final cameraStatus = await Permission.camera.request();
        final micStatus = await Permission.microphone.request();
        if (cameraStatus.isDenied || micStatus.isDenied) {
          setState(() {
            _mediaError = "Camera or microphone permission was denied.";
            _isInitializingMedia = false;
          });
          return;
        }
      }

      // Create tracks
      final videoTrack = await LocalVideoTrack.createCameraTrack();
      final audioTrack = await LocalAudioTrack.create();

      if (mounted) {
        setState(() {
          _localVideoTrack = videoTrack;
          _localAudioTrack = audioTrack;
          _isInitializingMedia = false;
          _mediaError = null;
        });
      }
    } catch (e) {
      debugPrint("Lobby camera error: $e");
      if (mounted) {
        setState(() {
          _mediaError = "Hardware camera not available or permission blocked.";
          _isInitializingMedia = false;
        });
      }
    }
  }

  Future<void> _toggleCamera() async {
    if (_localVideoTrack != null) {
      if (_isCameraOn) {
        await _localVideoTrack!.mute();
      } else {
        await _localVideoTrack!.unmute();
      }
      setState(() {
        _isCameraOn = !_isCameraOn;
      });
    }
  }

  Future<void> _toggleMic() async {
    if (_localAudioTrack != null) {
      if (_isMicOn) {
        await _localAudioTrack!.mute();
      } else {
        await _localAudioTrack!.unmute();
      }
      setState(() {
        _isMicOn = !_isMicOn;
      });
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    _nameController.dispose();
    _serverUrlController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _publicWebUrlController.dispose();
    
    // Dispose preview tracks so they don't block the consultation room camera
    _localVideoTrack?.dispose();
    _localAudioTrack?.dispose();
    
    super.dispose();
  }

  void _joinRoom() {
    final room = _roomController.text.trim();
    final name = _nameController.text.trim();
    
    if (room.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out all fields')),
      );
      return;
    }

    // Stop preview camera so the call screen can access the camera hardware
    _localVideoTrack?.dispose();
    _localVideoTrack = null;
    _localAudioTrack?.dispose();
    _localAudioTrack = null;

    // Generates token invisibly in the background using config
    final token = generateLiveKitToken(
      roomName: room,
      participantName: name,
      apiKey: LiveKitConfig.apiKey,
      apiSecret: LiveKitConfig.apiSecret,
    );

    context.go(
      Uri(
        path: '/consultation',
        queryParameters: {
          'room': room,
          'url': LiveKitConfig.serverUrl,
        },
      ).toString(),
      extra: {
        'token': token,
        'isDoctor': isDoctor ? 'true' : 'false',
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final isGuestInvited = widget.initialRoom != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 850;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E1E38)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(screenWidth < 400 ? 12.0 : 24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isDesktop ? 1000 : 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.spa, color: Colors.indigoAccent, size: 28),
                        const SizedBox(width: 8),
                        const Text(
                          'AuraCare',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ).animate().fadeIn().slideY(begin: -0.2),
                    const SizedBox(height: 32),

                    // Layout based on Desktop/Mobile
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: _buildVideoPreviewSection()),
                          const SizedBox(width: 32),
                          Expanded(flex: 5, child: _buildJoinFormSection(isGuestInvited)),
                        ],
                      ).animate().fadeIn(delay: 200.ms)
                    else
                      Column(
                        children: [
                          _buildVideoPreviewSection(),
                          const SizedBox(height: 24),
                          _buildJoinFormSection(isGuestInvited),
                        ],
                      ).animate().fadeIn(delay: 200.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreviewSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      height: screenWidth < 500 ? 240 : 380,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera state
          if (_isInitializingMedia)
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.indigoAccent),
                SizedBox(height: 16),
                Text('Configuring media hardware...', style: TextStyle(color: Colors.white30, fontSize: 13)),
              ],
            )
          else if (_mediaError != null)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off, color: Color(0xFFEF4444), size: 48),
                  const SizedBox(height: 16),
                  Text(_mediaError!, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _initPreviewCamera,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent),
                    child: const Text('Retry Connection', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            )
          else if (_isCameraOn && _localVideoTrack != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: VideoTrackRenderer(_localVideoTrack!),
            )
          else
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 48),
                SizedBox(height: 12),
                Text('Your camera is turned off', style: TextStyle(color: Colors.white30, fontSize: 13)),
              ],
            ),

          // Top Info Tag
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Device Check',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Control Buttons
          Positioned(
            bottom: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLobbyCircleBtn(
                  icon: _isMicOn ? Icons.mic : Icons.mic_off,
                  isActive: _isMicOn,
                  onTap: _toggleMic,
                ),
                const SizedBox(width: 16),
                _buildLobbyCircleBtn(
                  icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                  isActive: _isCameraOn,
                  onTap: _toggleCamera,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyCircleBtn({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive ? Colors.indigoAccent : const Color(0xFFEF4444),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinFormSection(bool isGuestInvited) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 400;

    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      child: Padding(
        padding: EdgeInsets.all(isSmall ? 16.0 : 28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Join Box Header
            if (isGuestInvited) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigoAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.indigoAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline, color: Colors.indigoAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'INVITATION LINK ACTIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigoAccent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Room: ${_roomController.text}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isSmall ? 16 : 24),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.meeting_room_outlined, color: Colors.indigoAccent, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Setup Lobby',
                    style: TextStyle(
                      fontSize: isSmall ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isSmall ? 14 : 20),
            ],

            // Name Field
            const Text(
              'Your Name',
              style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_outline, color: Colors.white30),
                hintText: 'Enter your name',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: isSmall ? 10 : 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.indigoAccent, width: 2),
                ),
              ),
            ),
            SizedBox(height: isSmall ? 14 : 20),

            // Room Field
            if (!isGuestInvited) ...[
              const Text(
                'Room ID',
                style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _roomController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.meeting_room, color: Colors.white30),
                  hintText: 'Enter room name',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: isSmall ? 10 : 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.indigoAccent, width: 2),
                  ),
                ),
              ),
              SizedBox(height: isSmall ? 14 : 20),

              // Role selection
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Join Role',
                    style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _buildRoleChip('Doctor', isDoctor, () {
                          setState(() {
                            isDoctor = true;
                            if (_nameController.text.startsWith('James Carter')) {
                              _nameController.text = 'Dr. Amanulla Belg';
                            }
                          });
                        }),
                        _buildRoleChip('Patient', !isDoctor, () {
                          setState(() {
                            isDoctor = false;
                            if (_nameController.text.startsWith('Dr. Amanulla Belg')) {
                              _nameController.text = 'James Carter';
                            }
                          });
                        }),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: isSmall ? 10 : 16),
            ],

            SizedBox(height: isSmall ? 10 : 16),

            // Join Meeting Button
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Colors.indigoAccent, Color(0xFF4F46E5)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigoAccent.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _joinRoom,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size.fromHeight(isSmall ? 46 : 56),
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.video_call, color: Colors.white),
                    const SizedBox(width: 12),
                    Text(
                      isGuestInvited ? 'Join Meeting' : 'Start Consultation',
                      style: TextStyle(
                        fontSize: isSmall ? 14 : 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(String text, bool isSelected, VoidCallback onTap) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 400;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 250.ms,
        padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 16, vertical: isSmall ? 6 : 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigoAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: isSmall ? 11 : 13,
          ),
        ),
      ),
    );
  }
}
