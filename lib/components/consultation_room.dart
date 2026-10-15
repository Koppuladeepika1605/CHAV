import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart' as lk show ConnectionState;
import 'dart:math';
import '../shared_state.dart';
import '../config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'token_generator.dart';
import 'captions_overlay.dart';
import 'bg_images.dart';
import 'package:geolocator/geolocator.dart';
import 'chat_bubble.dart';
import 'dart:typed_data';

class ConsultationRoom extends StatefulWidget {
  final String? url;
  final String? token;
  final String? roomName;
  final bool isPip;
  final VoidCallback? onExpand;
  final VoidCallback? onWhiteboardToggle;

  const ConsultationRoom({
    super.key, 
    this.url, 
    this.token, 
    this.roomName,
    this.isPip = false, 
    this.onExpand, 
    this.onWhiteboardToggle
  });

  @override
  State<ConsultationRoom> createState() => _ConsultationRoomState();
}

class _ConsultationRoomState extends State<ConsultationRoom> with TickerProviderStateMixin {
  bool isVideoOn = true;
  bool isAudioOn = true;
  bool isChatOpen = false;
  bool isBlurActive = false;
  String _currentBgTheme = 'none';
  String? _customBgBase64;

  String _previewBgTheme = 'none';
  String? _previewBgUrl;
  
  // Camera Drag variables
  double? _selfVideoX;
  double? _selfVideoY;
  bool _isDraggingSelfVideo = false;
  bool? _lastIsPip;
  late AnimationController _selfVideoGradientController;

  double _blurStrength = 15.0; // Low=8, Med=15, High=25
  bool _bgIsLoading = false;

  final List<Map<String, String>> _bgThemes = [
    {'id': 'none', 'title': 'No Blur'},
    {'id': 'light_blur', 'title': 'Light Blur'},
    {'id': 'blur', 'title': 'Medium Blur'},
    {'id': 'strong_blur', 'title': 'Heavy Blur'},
    {'id': 'modern_office', 'title': 'Modern Office', 'url': BgImages.modernOffice},
    {'id': 'home', 'title': 'Home', 'url': BgImages.home},
    {'id': 'hospital', 'title': 'Hospital', 'url': BgImages.hospital},
    {'id': 'library', 'title': 'Library', 'url': BgImages.library},
    {'id': 'nature_garden', 'title': 'Nature / Garden', 'url': BgImages.natureGarden},
    {'id': 'luxury_room', 'title': 'Luxury / Premium Room', 'url': BgImages.luxuryRoom},
  ];

  bool _blurAvailable = false; // true after MediaPipe loads on web
  String? _mediaErrorMessage;

  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _ipOverrideController = TextEditingController();
  bool _hasConsentForLink = false;
  bool _isNoiseShieldActive = true;

  bool _isDescriptionExpanded = false;
  bool _isEditingDescription = false;
  final TextEditingController _descEditController = TextEditingController();
  
  // LiveKit WebRTC Tracks are now managed by MeetingController

  // Renamed variables to force a fresh state reset on hot reload
  double _chatBoxX = 24;
  double _chatBoxY = 100;
  double _chatBoxW = 320;
  double _chatBoxH = 450;

  // Chat scroll controller for auto-scroll
  final ScrollController _chatScrollController = ScrollController();
  bool _chatUserScrolledUp = false;
  
  bool _hasSharedLocation = false;

  @override
  void initState() {
    super.initState();
    _selfVideoGradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    MeetingController().addListener(_onMeetingControllerUpdate);
    
    final roomToConnect = widget.roomName ?? 'my-consultation-room';
    if (widget.url != null && widget.token != null && widget.token!.isNotEmpty) {
      MeetingController().connectWithToken(widget.url!, widget.token!, roomName: roomToConnect);
    } else {
      // Fallback: Automatically connect to local LiveKit server
      final token = generateLiveKitToken(roomName: roomToConnect, participantName: MeetingController().isDoctor ? 'Doctor' : 'Patient');
      MeetingController().connectWithToken(widget.url ?? 'ws://127.0.0.1:7880', token, roomName: roomToConnect);
    }
  }


  void _onMeetingControllerUpdate() {
    if (mounted) {
      setState(() {});
      
      if (MeetingController().isConnected && !_hasSharedLocation) {
        _hasSharedLocation = true;
        _shareMyLocation();
      }

      if (MeetingController().roomControlAction == 'end_call') {
        MeetingController().roomControlAction = null; // Clear to prevent loops
        context.go('/');
        return; // Exit early
      }

      // Auto-scroll to bottom only if user hasn't scrolled up manually
      if (!_chatUserScrolledUp && _chatScrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollController.hasClients) {
            _chatScrollController.animateTo(
              _chatScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  // Camera initialization is handled by MeetingController

  @override
  void dispose() {
    _selfVideoGradientController.dispose();
    MeetingController().removeListener(_onMeetingControllerUpdate);
    _chatController.dispose();
    _ipOverrideController.dispose();
    _chatScrollController.dispose();
    _descEditController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    MeetingController().sendChatMessage(text);
    _chatController.clear();
  }

  Future<void> _pickFile() async {
    // Supported extensions
    const supportedExtensions = [
      'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp',
      'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'csv',
      'dcm', 'dicom', 'zip',
      'mp4', 'mp3', 'wav',
    ];
    const maxBytes = 25 * 1024 * 1024; // 25 MB

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      withData: true, // Required to get bytes on web
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    final fileName = file.name;

    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file. Please try again.'),
              backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    if (bytes.length > maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File too large: ${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB. Maximum is 25 MB.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    try {
      await MeetingController().sendFileMessage(fileName, Uint8List.fromList(bytes));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _shareMyLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition();
      String locationStr = "${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}";

      await MeetingController().shareLocation(locationStr);
      
      // Update local state directly to show it immediately on our end
      final identity = MeetingController().room?.localParticipant?.identity ?? 'Me';
      final name = MeetingController().room?.localParticipant?.name ?? 'Me';
      
      setState(() {
        MeetingController().participantLocations[identity] = {
          'name': name,
          'city': locationStr,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
      });
    } catch (e) {
      debugPrint("Error sharing location: $e");
    }
  }

  Future<void> _toggleVideo() async {
    MeetingController().toggleVideo();
  }

  Future<void> _toggleAudio() async {
    MeetingController().toggleAudio();
  }



  void _showBackgroundEffectsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final activeTheme = MeetingController().currentBgTheme;
            final virtualOptions = [
              {'id': 'modern_office', 'title': 'Modern Office', 'url': BgImages.modernOffice},
              {'id': 'home', 'title': 'Home', 'url': BgImages.home},
              {'id': 'hospital', 'title': 'Hospital', 'url': BgImages.hospital},
              {'id': 'library', 'title': 'Library', 'url': BgImages.library},
              {'id': 'nature_garden', 'title': 'Nature / Garden', 'url': BgImages.natureGarden},
              {'id': 'luxury_room', 'title': 'Luxury / Premium Room', 'url': BgImages.luxuryRoom},
            ];

            return Container(
              padding: const EdgeInsets.all(24),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.indigoAccent, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Background Effects',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Main Mode Selector Tabs: [ None ] [ Blur ] [ Virtual Background ]
                  Row(
                    children: [
                      // Mode 1: None
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            MeetingController().setBgTheme('none');
                            setState(() {});
                            setSheetState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: activeTheme == 'none' ? Colors.indigoAccent : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: activeTheme == 'none' ? Colors.indigoAccent : Colors.white12,
                                width: activeTheme == 'none' ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.block, size: 16, color: activeTheme == 'none' ? Colors.white : Colors.white70),
                                  const SizedBox(width: 6),
                                  Text(
                                    'None',
                                    style: TextStyle(
                                      color: activeTheme == 'none' ? Colors.white : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Mode 2: Blur Background
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            MeetingController().setBgTheme('blur');
                            setState(() {});
                            setSheetState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: activeTheme == 'blur' ? Colors.indigoAccent : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: activeTheme == 'blur' ? Colors.indigoAccent : Colors.white12,
                                width: activeTheme == 'blur' ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.blur_on, size: 16, color: activeTheme == 'blur' ? Colors.white : Colors.white70),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Blur',
                                    style: TextStyle(
                                      color: activeTheme == 'blur' ? Colors.white : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Virtual Background Grid Section
                  const Text(
                    'Virtual Background Images:',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: virtualOptions.length,
                      itemBuilder: (context, idx) {
                        final opt = virtualOptions[idx];
                        final isSelected = activeTheme == opt['id'];
                        return InkWell(
                          onTap: () {
                            MeetingController().setBgTheme(opt['id']!);
                            setState(() {});
                            setSheetState(() {});
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Colors.indigoAccent : Colors.white12,
                                width: isSelected ? 3 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  opt['url']!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(color: const Color(0xFF1E293B)),
                                ),
                                Container(
                                  color: Colors.black38,
                                ),
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Text(
                                      opt['title']!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                                      ),
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Positioned(
                                    top: 4,
                                    right: 4,
                                    child: CircleAvatar(
                                      radius: 9,
                                      backgroundColor: Colors.indigoAccent,
                                      child: Icon(Icons.check, size: 11, color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getInvitationLink() {
    String link = '';
    if (kIsWeb) {
      String href = html.window.location.href;
      Uri uri;
      String baseUrl = '';
      bool hasHash = href.contains('#');
      
      if (hasHash) {
        final parts = href.split('#');
        baseUrl = '${parts[0]}#';
        uri = Uri.parse(parts[1]);
      } else {
        uri = Uri.parse(href);
        baseUrl = '${uri.origin}/#';
      }

      final currentParams = uri.queryParameters;
      final room = widget.roomName ?? currentParams['room'] ?? MeetingController().currentRoomName ?? 'my-consultation-room';
      final apiKey = currentParams['apiKey'] ?? LiveKitConfig.apiKey;
      final apiSecret = currentParams['apiSecret'] ?? LiveKitConfig.apiSecret;
      
      String livekitUrl = currentParams['url'] ?? LiveKitConfig.serverUrl;
      final currentHost = html.window.location.hostname;
      if (currentHost != null && currentHost.isNotEmpty && currentHost != 'localhost' && currentHost != '127.0.0.1') {
        livekitUrl = 'ws://$currentHost:7880';
      }
      
      final ipOverride = _ipOverrideController.text.trim();
      if (ipOverride.isNotEmpty) {
        baseUrl = 'http://$ipOverride:8080/#';
        livekitUrl = 'ws://$ipOverride:7880';
      }
      
      final patientToken = generateLiveKitToken(
        roomName: room,
        participantName: 'Patient-${DateTime.now().millisecondsSinceEpoch % 10000}',
        apiKey: apiKey,
        apiSecret: apiSecret,
      );

      final newParams = {
        'url': livekitUrl,
        'room': room,
        'token': patientToken,
        'isDoctor': 'false',
        if (MeetingController().meetingDescription != null && MeetingController().meetingDescription!.isNotEmpty)
          'desc': MeetingController().meetingDescription!,
      };
      final invitePath = Uri(path: '/consultation', queryParameters: newParams).toString();
      link = '$baseUrl$invitePath';
    } else {
      link = 'Meeting Room: ${widget.url}';
    }
    return link;
  }

  void _showInviteDialog() {
    final link = _getInvitationLink();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Invite Patient', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this link with your patient to join the consultation:', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: SelectableText(link, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 13, fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite link copied!'), backgroundColor: Color(0xFF22C55E)),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF15803D), foregroundColor: Colors.white),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Link'),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitationCard() {
    final inviteLink = _getInvitationLink();

    return Center(
      child: Container(
        width: 460,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF111A2C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E2D4A)),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title with Green Share Icon
            Row(
              children: const [
                Icon(Icons.share_outlined, color: Color(0xFF22C55E), size: 20),
                SizedBox(width: 10),
                Text(
                  'Share Meeting Invitation',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Send this link to anyone you want to join. They will be able to join directly with their name.',
              style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),

            // Blue Notice Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF172554).withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.info_outline, color: Color(0xFF60A5FA), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Meeting is running on localhost. Other devices on your Wi-Fi will need your computer\'s IP address to connect.',
                      style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // HOST COMPUTER IP OVERRIDE
            const Text(
              'HOST COMPUTER IP OVERRIDE',
              style: TextStyle(color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0C1322),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                controller: _ipOverrideController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter PC local IP (e.g., 192.168.1.50)',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 12.5),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  suffixIcon: _ipOverrideController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                          onPressed: () {
                            setState(() {
                              _ipOverrideController.clear();
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),

            // Consent Checkbox
            GestureDetector(
              onTap: () {
                setState(() {
                  _hasConsentForLink = !_hasConsentForLink;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1322),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _hasConsentForLink ? const Color(0xFF22C55E).withOpacity(0.4) : Colors.white12),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _hasConsentForLink,
                        activeColor: const Color(0xFF22C55E),
                        side: const BorderSide(color: Colors.white38),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          setState(() {
                            _hasConsentForLink = val ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'I confirm explicit patient consent for link sharing & guest participation.',
                        style: TextStyle(color: Colors.white, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Link Status / Revealed Link
            if (!_hasConsentForLink)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1322),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Text(
                  '🔒 Link Locked: Tick "I confirm explicit patient consent" above to reveal invitation URL & Access Code.',
                  style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1322),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4)),
                ),
                child: SelectableText(
                  inviteLink,
                  style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11.5, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: inviteLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation link copied!'), backgroundColor: Color(0xFF22C55E)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white),
                  label: const Text('Copy Invitation Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopCenterStatusPill() {
    final isConnected = MeetingController().isConnected;
    final isConnecting = MeetingController().isConnecting;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isConnected ? const Color(0xFF22C55E) : const Color(0xFFD97706),
            width: 1.2,
          ),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isConnected)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              )
            else
              const Icon(Icons.sync, color: Color(0xFFF59E0B), size: 15),
            const SizedBox(width: 8),
            Text(
              isConnected
                  ? 'Connected to LiveKit Server'
                  : (isConnecting ? 'Connecting to LiveKit Server...' : 'Not connected to LiveKit Server'),
              style: TextStyle(
                color: isConnected ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    final originalText = MeetingController().originalCaption;
    final translatedText = MeetingController().translatedCaption;
    final hasCaption = (originalText != null && originalText.isNotEmpty) || (translatedText != null && translatedText.isNotEmpty);
    final statusText = hasCaption 
        ? (translatedText != null && translatedText.isNotEmpty ? translatedText : originalText!)
        : 'Consultation connected. Speech captions active...';

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220).withOpacity(0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: Row(
          children: [
            // Left Status
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                statusText,
                style: TextStyle(
                  color: hasCaption ? const Color(0xFF86EFAC) : Colors.white70,
                  fontSize: 12.5,
                  fontWeight: hasCaption ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),

            // Center Copy Invitation Link Button
            GestureDetector(
              onTap: () {
                final link = _getInvitationLink();
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invitation link copied to clipboard!'), backgroundColor: Color(0xFF22C55E)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF14532D).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.copy, size: 14, color: Color(0xFF86EFAC)),
                    SizedBox(width: 6),
                    Text(
                      'Copy Invitation Link',
                      style: TextStyle(color: Color(0xFF86EFAC), fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Right Language Selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: MeetingController().selectedCaptionLanguage,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('EN')),
                    DropdownMenuItem(value: 'te', child: Text('TE')),
                    DropdownMenuItem(value: 'hi', child: Text('HI')),
                    DropdownMenuItem(value: 'ta', child: Text('TA')),
                    DropdownMenuItem(value: 'kn', child: Text('KN')),
                    DropdownMenuItem(value: 'ml', child: Text('ML')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      MeetingController().setCaptionLanguage(val);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlDock() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF111A2C).withOpacity(0.95),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white12),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16)],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Mic
              _buildCircleDockButton(
                icon: MeetingController().isAudioOn ? Icons.mic_none : Icons.mic_off,
                isDanger: !MeetingController().isAudioOn,
                onTap: _toggleAudio,
              ),
              const SizedBox(width: 8),
              // 2. Camera
              _buildCircleDockButton(
                icon: MeetingController().isVideoOn ? Icons.videocam_outlined : Icons.videocam_off_outlined,
                isDanger: !MeetingController().isVideoOn,
                onTap: _toggleVideo,
              ),
              const SizedBox(width: 8),
              // 3. Chat
              _buildCircleDockButton(
                icon: Icons.chat_bubble_outline_rounded,
                isActive: isChatOpen,
                onTap: () => setState(() => isChatOpen = !isChatOpen),
              ),
              const SizedBox(width: 8),
              // 4. Whiteboard
              _buildPillDockButton(
                icon: Icons.draw_outlined,
                label: 'Whiteboard',
                isActive: MeetingController().isWhiteboardOpen,
                onTap: () {
                  if (widget.onWhiteboardToggle != null) widget.onWhiteboardToggle!();
                },
              ),
              const SizedBox(width: 8),
              // 5. Blur
              _buildPillDockButton(
                icon: Icons.auto_awesome_outlined,
                label: 'Blur',
                isActive: MeetingController().currentBgTheme != 'none',
                onTap: _showBackgroundEffectsSheet,
              ),
              const SizedBox(width: 8),
              // 6. Noise Shield (Royal Blue Highlight)
              _buildPillDockButton(
                icon: Icons.graphic_eq_rounded,
                label: 'Noise Shield',
                isHighlighted: _isNoiseShieldActive,
                highlightColor: const Color(0xFF3B82F6),
                onTap: () {
                  setState(() => _isNoiseShieldActive = !_isNoiseShieldActive);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isNoiseShieldActive ? 'AI Noise Shield Activated' : 'Noise Shield Deactivated'),
                      duration: const Duration(seconds: 1),
                      backgroundColor: _isNoiseShieldActive ? const Color(0xFF3B82F6) : Colors.grey,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // 7. Live Photo
              _buildPillDockButton(
                icon: Icons.camera_alt_outlined,
                label: 'Live Photo',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Live Photo snapshot captured!'), backgroundColor: Color(0xFF22C55E)),
                  );
                },
              ),
              const SizedBox(width: 8),
              // 8. Flip
              _buildPillDockButton(
                icon: Icons.flip_camera_ios_outlined,
                label: 'Flip',
                onTap: () {
                  MeetingController().toggleVideo();
                  MeetingController().toggleVideo();
                },
              ),
              const SizedBox(width: 8),
              // 9. Invite
              _buildPillDockButton(
                icon: Icons.person_add_alt_1_outlined,
                label: 'Invite',
                onTap: _showInviteDialog,
              ),
              const SizedBox(width: 8),
              // 10. End Call (Solid Red)
              GestureDetector(
                onTap: () async {
                  if (MeetingController().isDoctor) {
                    await MeetingController().endCallForEveryone();
                  }
                  if (context.mounted) {
                    context.go('/');
                  }
                },
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'End Call',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleDockButton({required IconData icon, bool isDanger = false, bool isActive = false, required VoidCallback onTap}) {
    Color bgColor = const Color(0xFF1E293B);
    Color iconColor = Colors.white70;
    if (isDanger) {
      bgColor = const Color(0xFFEF4444).withOpacity(0.2);
      iconColor = const Color(0xFFEF4444);
    } else if (isActive) {
      bgColor = const Color(0xFF3B82F6);
      iconColor = Colors.white;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
    );
  }

  Widget _buildPillDockButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    bool isHighlighted = false,
    Color? highlightColor,
    required VoidCallback onTap,
  }) {
    Color bgColor = const Color(0xFF1E293B);
    Color contentColor = Colors.white70;
    
    if (isHighlighted) {
      bgColor = highlightColor ?? const Color(0xFF3B82F6);
      contentColor = Colors.white;
    } else if (isActive) {
      bgColor = const Color(0xFF3B82F6);
      contentColor = Colors.white;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: contentColor, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: contentColor,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final isMobile = screenWidth < 600;

        final double rightMargin = widget.isPip ? 8 : (isMobile ? 12 : 24);
        final double topMargin = widget.isPip ? 8 : (isMobile ? 12 : 24);
        final double selfWidth = widget.isPip ? 100 : (isMobile ? 120 : 190);
        final double selfHeight = widget.isPip ? 56 : (isMobile ? 68 : 120);

        if (_lastIsPip != widget.isPip) {
          _lastIsPip = widget.isPip;
          _selfVideoX = null;
          _selfVideoY = null;
        }

        if (_selfVideoX == null || _selfVideoY == null) {
          _selfVideoX = screenWidth - selfWidth - rightMargin;
          _selfVideoY = topMargin;
        } else {
          _selfVideoX =
              _selfVideoX!.clamp(0.0, max(0.0, screenWidth - selfWidth));
          _selfVideoY =
              _selfVideoY!.clamp(0.0, max(0.0, screenHeight - selfHeight));
        }

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0C1322), // Deep dark navy slate
          ),
          child: Stack(
            children: [
              // Main Video Area or Invitation / Waiting Screen
              Positioned.fill(
                child: Builder(
                  builder: (context) {
                    final room = MeetingController().room;
                    final remoteParticipants = room?.remoteParticipants.values.toList() ?? [];
                    final firstRemote = remoteParticipants.isNotEmpty ? remoteParticipants.first : null;
                    
                    VideoTrack? remoteVideoTrack;
                    if (firstRemote != null) {
                      for (final pub in firstRemote.videoTrackPublications) {
                        if (pub.track != null && pub.track is VideoTrack) {
                          remoteVideoTrack = pub.track as VideoTrack;
                          break;
                        }
                      }
                    }

                    if (firstRemote != null) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (remoteVideoTrack != null)
                            VideoTrackRenderer(remoteVideoTrack)
                          else
                            Container(
                              color: const Color(0xFF0C1322),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 54,
                                      backgroundColor: const Color(0xFF2563EB),
                                      child: Text(
                                        (firstRemote.identity?.isNotEmpty ?? false) ? firstRemote.identity!.substring(0, 1).toUpperCase() : '?',
                                        style: const TextStyle(fontSize: 42, color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      MeetingController().isDoctor ? 'Patient Camera Off / Connecting...' : 'Doctor Camera Off / Connecting...',
                                      style: const TextStyle(color: Colors.white54, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: widget.isPip ? 12 : 120,
                            left: widget.isPip ? 12 : 28,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(firstRemote.identity.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                  if (MeetingController().participantLocations.containsKey(firstRemote.identity)) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      MeetingController().participantLocations[firstRemote.identity]!['city'],
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    if (!MeetingController().isDoctor) {
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111A2C),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF1E2D4A)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, 8)),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              CircularProgressIndicator(color: Color(0xFF2563EB)),
                              SizedBox(height: 20),
                              Text(
                                'Connected as Patient',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'You are in the room. Waiting for Doctor to connect...',
                                style: TextStyle(color: Colors.white60, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // When no remote participant is connected and current user is Doctor, show the centered Invitation Card
                    return _buildInvitationCard();
                  }
                ),
              ),

              // Top Center Server Connection Status Pill
              if (!widget.isPip)
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: _buildTopCenterStatusPill(),
                ),

              // Local Participant PiP (Top Right)
              AnimatedPositioned(
                duration: _isDraggingSelfVideo
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                left: _selfVideoX,
                top: _selfVideoY,
                width: selfWidth,
                height: selfHeight,
                child: GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _isDraggingSelfVideo = true;
                      _selfVideoGradientController.repeat();
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _selfVideoX = (_selfVideoX! + details.delta.dx)
                          .clamp(0.0, screenWidth - selfWidth);
                      _selfVideoY = (_selfVideoY! + details.delta.dy)
                          .clamp(0.0, screenHeight - selfHeight);
                    });
                  },
                  onPanEnd: (details) {
                    setState(() {
                      _isDraggingSelfVideo = false;
                      _selfVideoGradientController.stop();
                    });
                  },
                  onPanCancel: () {
                    setState(() {
                      _isDraggingSelfVideo = false;
                      _selfVideoGradientController.stop();
                    });
                  },
                  child: AnimatedBuilder(
                    animation: _selfVideoGradientController,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.all(1.0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 4)),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            (() {
                              final room = MeetingController().room;
                              VideoTrack? activeLocalTrack = MeetingController().localVideoTrack;
                              if (room?.localParticipant?.videoTrackPublications.isNotEmpty ?? false) {
                                final pub = room!.localParticipant!.videoTrackPublications.first;
                                if (pub.track != null && pub.track is VideoTrack) {
                                  activeLocalTrack = pub.track as VideoTrack;
                                }
                              }

                              return (MeetingController().isVideoOn && activeLocalTrack != null)
                                  ? VideoTrackRenderer(activeLocalTrack)
                                  : Container(
                                      color: const Color(0xFF111A2C),
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                MeetingController().cameraError != null
                                                    ? 'Camera Busy or In Use\n(Close other apps using camera)'
                                                    : (MeetingController().isVideoOn
                                                        ? 'Camera Initializing...'
                                                        : 'Camera Off'),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(color: Colors.white70, fontSize: widget.isPip ? 9 : 11),
                                              ),
                                              const SizedBox(height: 6),
                                              InkWell(
                                                onTap: () {
                                                  MeetingController().ensureLocalVideoTrack();
                                                },
                                                borderRadius: BorderRadius.circular(4),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF2563EB),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.videocam, size: 11, color: Colors.white),
                                                      SizedBox(width: 4),
                                                      Text('Turn On Camera', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                            })(),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              child: Text(
                                MeetingController().isDoctor ? 'You (Doctor)' : 'You (Patient)',
                                style: TextStyle(
                                  fontSize: widget.isPip ? 8 : 11.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
                                ),
                              ),
                            ),
                            if (widget.isPip && widget.onExpand != null)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: widget.onExpand,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                                    child: const Icon(Icons.open_in_full, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Speech Captions & Status Bar
              if (!widget.isPip)
                Positioned(
                  bottom: 74,
                  left: 0,
                  right: 0,
                  child: _buildBottomStatusBar(),
                ),

              // Bottom Controls Dock (10 Buttons)
              AnimatedPositioned(
                duration: 300.ms,
                bottom: widget.isPip ? 12 : 20,
                left: 0,
                right: 0,
                child: _buildControlDock(),
              ),

              // Draggable/Resizable Chat Overlay
              if (isChatOpen)
                Positioned(
                  left: _chatBoxX,
                  top: _chatBoxY,
                  child: _buildChatOverlay().animate().scaleXY(begin: 0.9, duration: 200.ms, curve: Curves.easeOutBack).fadeIn(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChatOverlay() {
    final messages = MeetingController().messages;
    return Container(
      width: _chatBoxW,
      height: _chatBoxH,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 50, offset: Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // ── Header ──
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  setState(() {
                    _chatBoxX += details.delta.dx;
                    _chatBoxY += details.delta.dy;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_rounded, color: Color(0xFF6366F1), size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Meeting Chat',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${messages.length}',
                          style: const TextStyle(color: Color(0xFF818CF8), fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      // Drag handle hint
                      Container(
                        width: 30, height: 4,
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Message List ──
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollUpdateNotification && _chatScrollController.hasClients) {
                      final atBottom = _chatScrollController.position.pixels >=
                          _chatScrollController.position.maxScrollExtent - 40;
                      if (_chatUserScrolledUp != !atBottom) {
                        setState(() => _chatUserScrolledUp = !atBottom);
                      }
                    }
                    return false;
                  },
                  child: messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  color: Colors.white.withValues(alpha: 0.15), size: 40),
                              const SizedBox(height: 12),
                              Text(
                                'No messages yet.\nSay hello!',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _chatScrollController,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            return ChatBubble(message: messages[index]);
                          },
                        ),
                ),
              ),

              // ── Scroll-to-bottom FAB ──
              if (_chatUserScrolledUp)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () {
                      _chatScrollController.animateTo(
                        _chatScrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                      setState(() => _chatUserScrolledUp = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('New messages', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Input Area ──
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                ),
                child: Row(
                  children: [
                    // Attach file button
                    GestureDetector(
                      onTap: _pickFile,
                      child: Tooltip(
                        message: 'Attach file (max 25 MB)',
                        child: Container(
                          height: 40,
                          width: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.attach_file_rounded, color: Colors.white60, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Text input
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 40, maxHeight: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: TextField(
                          controller: _chatController,
                          maxLines: null,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Send button
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.4), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Close Button ──
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: () => setState(() => isChatOpen = false),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
              ),
            ),
          ),

          // ── Resize Handle ──
          Positioned(
            bottom: 0, right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) {
                setState(() {
                  _chatBoxW = max(280, min(_chatBoxW + details.delta.dx, 600));
                  _chatBoxH = max(320, min(_chatBoxH + details.delta.dy, 800));
                });
              },
              child: const MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.drag_handle_rounded, size: 16, color: Colors.white24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
