import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'dart:async';
import 'token_generator.dart';
import '../config.dart'; // Import LiveKitConfig
import '../shared_state.dart'; // Import MeetingController

class VirtualWaitingRoom extends StatefulWidget {
  final String? initialRoom;
  final String? initialUrl;
  final String? initialKey;
  final String? initialSecret;
  final String? initialPublicUrl;
  final String? initialDesc;
  final bool isDoctor;

  const VirtualWaitingRoom({
    super.key,
    this.initialRoom,
    this.initialUrl,
    this.initialKey,
    this.initialSecret,
    this.initialPublicUrl,
    this.initialDesc,
    this.isDoctor = true,
  });

  @override
  State<VirtualWaitingRoom> createState() => _VirtualWaitingRoomState();
}

class _VirtualWaitingRoomState extends State<VirtualWaitingRoom> with TickerProviderStateMixin {
  final _roomController = TextEditingController(text: 'my-consultation-room');
  final _nameController = TextEditingController(text: 'Dr. Amanulla Belg');
  final _serverUrlController = TextEditingController(text: '');
  
  // Custom API key/secret inputs (remain in code to prevent compilation errors but hidden from UI)
  final _apiKeyController = TextEditingController(text: '');
  final _apiSecretController = TextEditingController(text: '');
  final _publicWebUrlController = TextEditingController();
  late final TextEditingController _descController;

  late bool isDoctor;
  String customToken = '';
  bool useLocalDevToken = true;

  // Camera preview variables
  LocalVideoTrack? _localVideoTrack;
  LocalAudioTrack? _localAudioTrack;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  String? _mediaError;
  bool _isInitializingMedia = true;
  bool _joinPressed = false;

  // Animation controllers
  late AnimationController _breathController;
  late AnimationController _gradientController;
  late Animation<double> _gradientAnim;

  @override
  void initState() {
    super.initState();
    
    _descController = TextEditingController(text: widget.initialDesc ?? '');
    isDoctor = widget.isDoctor;

    // Animation controllers
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _gradientAnim = CurvedAnimation(parent: _gradientController, curve: Curves.easeInOut);
    
    // Set up initial values
    if (widget.initialRoom != null && widget.initialRoom!.isNotEmpty) {
      _roomController.text = widget.initialRoom!;
      _nameController.text = isDoctor ? 'Dr. Amanulla Belg' : 'James Carter - ${Random().nextInt(900) + 100}';
    } else {
      _roomController.text = 'chav-consultation-room';
      _nameController.text = isDoctor ? 'Dr. Amanulla Belg' : 'James Carter';
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

      // Ensure MeetingController has localVideoTrack
      await MeetingController().ensureLocalVideoTrack();
      _localVideoTrack = MeetingController().localVideoTrack;
      if (MeetingController().localAudioTrack == null) {
        try {
          MeetingController().localAudioTrack = await LocalAudioTrack.create();
        } catch (_) {}
      }
      _localAudioTrack = MeetingController().localAudioTrack;

      if (mounted) {
        setState(() {
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
    _descController.dispose();
    _breathController.dispose();
    _gradientController.dispose();
    
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

    debugPrint("[CHAV-LIVEKIT] Joining room from Waiting Room: Room='$room', Name='$name', isDoctor=$isDoctor, isCameraOn=$_isCameraOn");
    MeetingController().localVideoTrack = _localVideoTrack;
    MeetingController().localAudioTrack = _localAudioTrack;
    MeetingController().isVideoOn = _isCameraOn;
    MeetingController().isAudioOn = _isMicOn;
    MeetingController().setRoleAndSummary(
      isDoctor: isDoctor,
      meetingDescriptionText: _descController.text.isNotEmpty ? _descController.text : null,
    );

    // Set to null so they aren't disposed when VirtualWaitingRoom unmounts
    _localVideoTrack = null;
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
          'token': token,
          'isDoctor': isDoctor ? 'true' : 'false',
          if (_descController.text.isNotEmpty) 'desc': _descController.text,
        },
      ).toString(),
    );
  }


  @override
  Widget build(BuildContext context) {
    final isGuestInvited = widget.initialRoom != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 850;

    return Scaffold(
      backgroundColor: const Color(0xFF070C18),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          color: const Color(0xFF0A0F1D),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Color(0xFF0F1B33), shape: BoxShape.circle),
                child: const Icon(Icons.shield, color: Color(0xFF22C55E), size: 20),
              ),
              const SizedBox(width: 8),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(text: 'Call', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 18)),
                    TextSpan(text: 'Health ', style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle),
                child: const Icon(Icons.add, color: Colors.white, size: 10),
              ),
              const SizedBox(width: 12),
              const Text('Everything about health', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(screenWidth < 400 ? 12.0 : 24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop ? 1000 : 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Center Brand Title Header matching Screenshot 1
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFF0F1B33), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.shield, color: Color(0xFF22C55E), size: 26),
                      ),
                      const SizedBox(width: 10),
                      RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(text: 'Call', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 22)),
                            TextSpan(text: 'Health ', style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 22)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle),
                        child: const Icon(Icons.add, color: Colors.white, size: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Everything about health | Pre-Flight Setup',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 28),

                  // Layout based on Desktop/Mobile
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: _buildVideoPreviewSection()),
                        const SizedBox(width: 28),
                        Expanded(flex: 5, child: _buildJoinFormSection(isGuestInvited)),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _buildVideoPreviewSection(),
                        const SizedBox(height: 24),
                        _buildJoinFormSection(isGuestInvited),
                      ],
                    ),
                ],
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera state
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(anim), child: child),
            ),
            child: _isInitializingMedia
                ? const Column(
                    key: ValueKey('loading'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.indigoAccent, strokeWidth: 2),
                      SizedBox(height: 16),
                      Text('Configuring media hardware...', style: TextStyle(color: Colors.white30, fontSize: 13)),
                    ],
                  )
                : _mediaError != null
                    ? Padding(
                        key: const ValueKey('error'),
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam_off_rounded, color: Color(0xFFEF4444), size: 48)
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .scaleXY(begin: 0.9, end: 1.0, duration: 1200.ms),
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
                    : _isCameraOn && _localVideoTrack != null
                        ? ClipRRect(
                            key: const ValueKey('video'),
                            borderRadius: BorderRadius.circular(24),
                            child: VideoTrackRenderer(_localVideoTrack!),
                          )
                        : const Column(
                            key: ValueKey('off'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 48),
                              SizedBox(height: 12),
                              Text('Your camera is turned off', style: TextStyle(color: Colors.white30, fontSize: 13)),
                            ],
                          ),
          ),

          // Top Info Tag with breathing dot
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _breathController,
                    builder: (_, __) => Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(
                          alpha: 0.6 + _breathController.value * 0.4,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent.withValues(
                              alpha: _breathController.value * 0.7,
                            ),
                            blurRadius: 8,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Device Check',
                    style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 600.ms).slideX(begin: -0.1),
          ),

          // Bottom 5 Control Buttons matching Screenshot 1
          Positioned(
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLobbyCircleBtn(
                  icon: _isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                  btnColor: _isMicOn ? const Color(0xFF2563EB) : const Color(0xFFEF4444),
                  onTap: _toggleMic,
                ),
                const SizedBox(width: 12),
                _buildLobbyCircleBtn(
                  icon: _isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  btnColor: _isCameraOn ? const Color(0xFF2563EB) : const Color(0xFFEF4444),
                  onTap: _toggleCamera,
                ),
                const SizedBox(width: 12),
                _buildLobbyCircleBtn(
                  icon: Icons.auto_awesome_rounded,
                  btnColor: const Color(0xFFEF4444),
                  onTap: () {
                    MeetingController().setBgTheme(MeetingController().currentBgTheme == 'none' ? 'blur' : 'none');
                  },
                ),
                const SizedBox(width: 12),
                _buildLobbyCircleBtn(
                  icon: Icons.graphic_eq_rounded,
                  btnColor: const Color(0xFF2563EB),
                  onTap: () {},
                ),
                const SizedBox(width: 12),
                _buildLobbyCircleBtn(
                  icon: Icons.cameraswitch_rounded,
                  btnColor: const Color(0xFFEF4444),
                  onTap: () {},
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
    required Color btnColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: btnColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: btnColor.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(11.0),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinFormSection(bool isGuestInvited) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 400;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: EdgeInsets.all(isSmall ? 16.0 : 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Offline Alert Box matching Screenshot 1
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1F3D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1D4ED8), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E3A8A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_moderator_rounded, color: Color(0xFF3B82F6), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'DOCTOR IS CURRENTLY OFFLINE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'The doctor is currently away. Toggle the ONLINE switch at top right or wait for alert.',
                        style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Title matching Screenshot 1
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Color(0xFF0F291E), shape: BoxShape.circle),
                child: const Icon(Icons.shield, color: Color(0xFF22C55E), size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Setup Lobby',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

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

            // Meeting Description (Always Visible)
            const Text(
              'Meeting Description (Optional)',
              style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.description_outlined, color: Colors.white30),
                hintText: 'Enter meeting topic or details',
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

          // Consent Checkbox matching Screenshot 1
          StatefulBuilder(
            builder: (context, setConsentState) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1F3D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2563EB), width: 1.2),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: true,
                        onChanged: (_) {},
                        activeColor: const Color(0xFF3B82F6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'I accept Tele-health Privacy Terms & Biometric Data Collection Consent.',
                        style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.3),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 18),

          // Green Start Consultation Button matching Screenshot 1
          Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF22C55E)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _joinRoom,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Start Consultation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
