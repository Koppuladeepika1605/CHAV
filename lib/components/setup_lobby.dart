import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'token_generator.dart';
import '../shared_state.dart';

class SetupLobby extends StatefulWidget {
  final String? initialRoom;
  final String? initialUrl;
  final String? initialKey;
  final String? initialSecret;
  final String? initialPublicUrl;

  const SetupLobby({
    super.key,
    this.initialRoom,
    this.initialUrl,
    this.initialKey,
    this.initialSecret,
    this.initialPublicUrl,
  });

  @override
  State<SetupLobby> createState() => _SetupLobbyState();
}

class _SetupLobbyState extends State<SetupLobby> {
  final _roomController = TextEditingController(text: 'my-consultation-room');
  final _nameController = TextEditingController(text: 'Dr. Amanulla Belg');
  final _serverUrlController = TextEditingController(text: 'ws://127.0.0.1:7880');
  final _meetingDescriptionController = TextEditingController();
  
  final _apiKeyController = TextEditingController(text: 'devkey');
  final _apiSecretController = TextEditingController(text: 'secret');
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

  // Accordion state for developer settings
  bool _showDevSettings = false;

  @override
  void initState() {
    super.initState();
    
    if (kIsWeb) {
      final baseUri = Uri.base;
      if (baseUri.host.isNotEmpty) {
        _serverUrlController.text = 'ws://${baseUri.host}:7880';
      }
    }
    
    // Set up initial values
    if (widget.initialRoom != null) {
      _roomController.text = widget.initialRoom!;
      // Default to guest name if invited
      _nameController.text = 'Guest - ${Random().nextInt(900) + 100}';
      isDoctor = false;
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
    _meetingDescriptionController.dispose();
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
    final url = _serverUrlController.text.trim();
    
    if (room.isEmpty || name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out all connection fields')),
      );
      return;
    }

    String token = '';
    if (useLocalDevToken) {
      final apiKey = _apiKeyController.text.trim();
      final apiSecret = _apiSecretController.text.trim();

      if (apiKey.isEmpty || apiSecret.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API Key and Secret are required to generate a token')),
        );
        return;
      }

      token = generateLiveKitToken(
        roomName: room,
        participantName: name,
        apiKey: apiKey,
        apiSecret: apiSecret,
      );
    } else {
      token = customToken.trim();
      if (token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please paste a valid JWT Token')),
        );
        return;
      }
    }

    // Stop preview camera so consultation room creates a fresh camera track
    MeetingController().localVideoTrack = null;
    MeetingController().localAudioTrack = null;
    _localVideoTrack?.dispose();
    _localVideoTrack = null;
    _localAudioTrack?.dispose();
    _localAudioTrack = null;

    final queryParams = {
      'url': url,
      'token': token,
      'room': room,
      'apiKey': useLocalDevToken ? _apiKeyController.text.trim() : '',
      'apiSecret': useLocalDevToken ? _apiSecretController.text.trim() : '',
      'initialVideoOn': _isCameraOn ? 'true' : 'false',
      'initialAudioOn': _isMicOn ? 'true' : 'false',
      'publicUrl': _publicWebUrlController.text.trim(),
      'isDoctor': isDoctor ? 'true' : 'false',
      'desc': _meetingDescriptionController.text.trim(),
    };

    MeetingController().setRoleAndSummary(isDoctor: isDoctor);
    context.go(Uri(path: '/consultation', queryParameters: queryParams).toString());
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
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isDesktop ? 1000 : 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.healing, color: Color(0xFF1E3F96), size: 28),
                        const SizedBox(width: 8),
                        const Text(
                          'CallHealth AuraCare',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3F96).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF1E3F96).withOpacity(0.4)),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3F96),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2),
                    const SizedBox(height: 32),

                    // Main Layout Card / Split Panel
                    isDesktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: _buildCameraPreviewSection(),
                              ),
                              const SizedBox(width: 32),
                              Expanded(
                                flex: 5,
                                child: _buildJoinFormSection(isGuestInvited),
                              ),
                            ],
                          ).animate().fadeIn(duration: 600.ms)
                        : Column(
                            children: [
                              _buildCameraPreviewSection(),
                              const SizedBox(height: 24),
                              _buildJoinFormSection(isGuestInvited),
                            ],
                          ).animate().fadeIn(duration: 600.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreviewSection() {
    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: const Color(0xFF161F30),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera feed or status
          if (_isInitializingMedia)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E3F96)),
            )
          else if (_mediaError != null)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off, size: 48, color: Colors.white38),
                  const SizedBox(height: 16),
                  Text(
                    _mediaError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _initPreviewCamera,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3F96),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            )
          else if (_isCameraOn && _localVideoTrack != null)
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(pi), // Mirror preview for natural look
              child: VideoTrackRenderer(_localVideoTrack!),
            )
          else
            Container(
              color: const Color(0xFF0F172A),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam_off, size: 64, color: Colors.white24),
                    SizedBox(height: 12),
                    Text(
                      'Camera is off',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // Top Info Pill
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

          // Bottom Control Buttons (Mute/Unmute Mic & Camera)
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
        color: isActive ? const Color(0xFF1E3F96) : const Color(0xFFEF4444),
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
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Join Box Header
            if (isGuestInvited) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3F96).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E3F96).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline, color: Color(0xFF1E3F96)),
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
                              color: Color(0xFF1E3F96),
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
              const SizedBox(height: 24),
            ] else ...[
              const Row(
                children: [
                  Icon(Icons.meeting_room_outlined, color: Color(0xFF1E3F96), size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Setup Lobby',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E3F96), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Meeting Description Field
            const Text(
              'Meeting Description',
              style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _meetingDescriptionController,
              minLines: 3,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.description_outlined, color: Colors.white30),
                hintText: 'Enter consultation details...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E3F96), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Room Field (Only show if NOT invited via link)
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1E3F96), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Role selection (Only show for host/non-guest)
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
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 8),

              // Developer settings Accordion
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: const Text(
                    'LiveKit Connection Config',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E3F96), fontWeight: FontWeight.bold),
                  ),
                  iconColor: const Color(0xFF1E3F96),
                  collapsedIconColor: const Color(0xFF1E3F96),
                  childrenPadding: EdgeInsets.zero,
                  tilePadding: EdgeInsets.zero,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _showDevSettings = expanded;
                    });
                  },
                  children: [
                    const SizedBox(height: 8),
                    // Server URL
                    TextField(
                      controller: _serverUrlController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Server URL',
                        labelStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Token sign checkbox
                    Row(
                      children: [
                        Checkbox(
                          value: useLocalDevToken,
                          activeColor: const Color(0xFF1E3F96),
                          onChanged: (val) => setState(() => useLocalDevToken = val ?? true),
                        ),
                        const Expanded(
                          child: Text(
                            'Auto-sign locally with Key/Secret',
                            style: TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                        ),
                      ],
                    ),

                    if (useLocalDevToken) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiKeyController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          labelStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiSecretController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'API Secret',
                          labelStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _publicWebUrlController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Public Web App URL (optional)',
                        labelStyle: const TextStyle(color: Colors.white30),
                        hintText: 'e.g. https://my-app.vercel.app',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Join Meeting Button
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3F96), Color(0xFF70C14D)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E3F96).withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _joinRoom,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
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
                      style: const TextStyle(
                        fontSize: 16,
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 250.ms,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3F96) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
