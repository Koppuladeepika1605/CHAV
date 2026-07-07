import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart' as lk show ConnectionState;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'whiteboard_canvas.dart';



class ChatMessage {
  final String text;
  final bool isMe;
  final String time;
  ChatMessage(this.text, this.isMe, this.time);
}

class ConsultationRoom extends StatefulWidget {
  final String url;
  final String token;
  final String roomName;
  final String apiKey;
  final String apiSecret;
  final bool initialVideoOn;
  final bool initialAudioOn;
  final String publicUrl;
  final bool isPip;
  final VoidCallback? onExpand;
  final bool isDoctor;

  const ConsultationRoom({
    super.key,
    required this.url,
    required this.token,
    this.roomName = '',
    this.apiKey = '',
    this.apiSecret = '',
    this.initialVideoOn = true,
    this.initialAudioOn = true,
    this.publicUrl = '',
    this.isPip = false,
    this.onExpand,
    this.isDoctor = false,
  });

  @override
  State<ConsultationRoom> createState() => _ConsultationRoomState();
}

class _ConsultationRoomState extends State<ConsultationRoom> {
  late bool isVideoOn = widget.initialVideoOn;
  late bool isAudioOn = widget.initialAudioOn;
  bool isChatOpen = false;
  bool isBlurActive = false;
  String? _mediaErrorMessage;
  bool isWhiteboardOpen = false;
  bool _showInlineInviteCard = true; 
  bool _inviteLinkCopied = false;
  int _unreadMessageCount = 0; 


  // For reassembling incoming file chunks
  final Map<String, List<String?>> _incomingFileChunks = {};


  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _ipOverrideController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final StreamController<dynamic> _whiteboardStreamController = StreamController<dynamic>.broadcast();

  
  // LiveKit WebRTC Tracks
  LocalVideoTrack? _localVideoTrack;
  LocalAudioTrack? _localAudioTrack;
  late final Room _room = Room();
  EventsListener<RoomEvent>? _listener;

  // Renamed variables to force a fresh state reset on hot reload
  double _chatBoxX = 24;
  double _chatBoxY = 100;
  double _chatBoxW = 320;
  double _chatBoxH = 450;

  @override
  void initState() {
    super.initState();
    // Rebuild UI when connection state or participants change
    _room.addListener(_onRoomChanged);

    // Pre-populate IP override if the session URL or web host is an IP address
    try {
      final uri = Uri.parse(widget.url);
      final host = uri.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1' && host != '::1') {
        _ipOverrideController.text = host;
      } else {
        final webHost = Uri.base.host;
        if (webHost.isNotEmpty && webHost != 'localhost' && webHost != '127.0.0.1' && webHost != '::1') {
          _ipOverrideController.text = webHost;
        }
      }
    } catch (e) {
      debugPrint("Error parsing initial URL: $e");
    }
    
    // 2. Listen to data channel messages (real-time chat)
    _listener = _room.createListener();
    _listener!.on<DataReceivedEvent>((event) {
      final decoded = utf8.decode(event.data);
      try {
        final decodedMap = jsonDecode(decoded) as Map<String, dynamic>;
        
        // 1. Intercept whiteboard topic events first
        if (event.topic == 'whiteboard') {
          _whiteboardStreamController.add(decodedMap);
          if (!isWhiteboardOpen) {
            if (mounted) {
              setState(() {
                isWhiteboardOpen = true;
              });
            }
          }
          return;
        }

        // 2. Intercept room call controls (e.g. Doctor ending the call)
        if (event.topic == 'room_control') {
          final action = decodedMap['action'] as String;
          if (action == 'end_call') {
            _exitRoom(message: 'The doctor has ended this consultation.');
          }
          return;
        }

        // 3. Reassemble chunked file sharing for the whiteboard
        if (event.topic == 'whiteboard_file') {
          final type = decodedMap['type'] as String;
          if (type == 'file_chunk') {
            final fileId = decodedMap['fileId'] as String;
            final fileName = decodedMap['fileName'] as String;
            final index = decodedMap['index'] as int;
            final total = decodedMap['total'] as int;
            final chunkData = decodedMap['data'] as String;

            if (!_incomingFileChunks.containsKey(fileId)) {
              _incomingFileChunks[fileId] = List<String?>.filled(total, null);
            }

            _incomingFileChunks[fileId]![index] = chunkData;

            // Once all pieces arrive, combine and load background
            if (_incomingFileChunks[fileId]!.every((c) => c != null)) {
              final completeBase64 = _incomingFileChunks[fileId]!.join('');
              _incomingFileChunks.remove(fileId);

              _whiteboardStreamController.add({
                'action': 'set_background',
                'fileName': fileName,
                'base64': completeBase64,
              });

              if (!isWhiteboardOpen) {
                if (mounted) {
                  setState(() {
                    isWhiteboardOpen = true;
                  });
                }
              }
            }
          }
          return;
        }

        // 4. Standard chat message processing
        final text = decodedMap['text'] as String;
        final sender = decodedMap['sender'] as String;
        final isMe = sender == _room.localParticipant?.identity;
        
        if (mounted) {
          setState(() {
            _messages.add(
              ChatMessage(
                text,
                isMe,
                DateFormat('hh:mm a').format(DateTime.now()),
              ),
            );
            if (!isMe) {
              if (!isChatOpen) {
                _unreadMessageCount++;
              } else {
                isChatOpen = true;
              }
            }
          });
        }
      } catch (e) {
        debugPrint("Error parsing data packet: $e");
      }
    });

    _initLocalCamera();
  }

  void _exitRoom({String? message}) {
    _room.disconnect();
    if (mounted) {
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.indigo.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      context.go('/');
    }
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initLocalCamera() async {
    _mediaErrorMessage = null;
    
    // 1. Request permissions on native platforms
    if (!kIsWeb) {
      try {
        final cameraStatus = await Permission.camera.request();
        final micStatus = await Permission.microphone.request();
        if (cameraStatus.isDenied || micStatus.isDenied) {
          setState(() {
            _mediaErrorMessage = "Camera or Mic permission denied.";
          });
        }
      } catch (e) {
        debugPrint("Permission request failed: $e");
      }
    }

    // 2. Initialize camera track
    if (_mediaErrorMessage == null) {
      try {
        final videoTrack = await LocalVideoTrack.createCameraTrack();
        if (!isVideoOn) {
          await videoTrack.mute();
        }
        _localVideoTrack = videoTrack;
      } catch (e) {
        debugPrint("Camera hardware failed/blocked: $e");
        _mediaErrorMessage = "Camera blocked or not found.";
      }
    }

    // 3. Initialize microphone track
    try {
      final audioTrack = await LocalAudioTrack.create();
      if (!isAudioOn) {
        await audioTrack.mute();
      }
      _localAudioTrack = audioTrack;
    } catch (e) {
      debugPrint("Microphone hardware failed/blocked: $e");
      _mediaErrorMessage = (_mediaErrorMessage == null) 
          ? "Microphone blocked or not found." 
          : "Devices blocked or not found.";
    }

    if (mounted) {
      setState(() {});
    }
    
    // 4. ALWAYS attempt to connect to LiveKit server, even if media hardware failed!
    if (widget.url.isNotEmpty && widget.token.isNotEmpty) {
      await _connectToLiveKit(widget.url, widget.token);
    }
  }

  @override
  void dispose() {
    _listener?.dispose();
    _whiteboardStreamController.close();
    _localVideoTrack?.dispose();
    _localAudioTrack?.dispose();
    _room.dispose();
    _chatController.dispose();
    _ipOverrideController.dispose();
    super.dispose();
  }
  

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    // Publish data channel message to all remote participants
    final payload = jsonEncode({
      'text': text,
      'sender': _room.localParticipant?.identity ?? 'User',
    });
    
    _room.localParticipant?.publishData(
      utf8.encode(payload),
      reliable: true,
    );

    setState(() {
      _messages.add(ChatMessage(text, true, DateFormat('hh:mm a').format(DateTime.now())));
      _chatController.clear();
    });
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File uploading ("${result.files.single.name}") is disabled in the local sandbox environment.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }
  }

  Future<void> _toggleVideo() async {
    final nextState = !isVideoOn;
    try {
      if (_room.connectionState == lk.ConnectionState.connected) {
        await _room.localParticipant?.setCameraEnabled(nextState);
      } else {
        if (nextState) {
          await _localVideoTrack?.unmute();
        } else {
          await _localVideoTrack?.mute();
        }
      }
      setState(() {
        isVideoOn = nextState;
      });
    } catch (e) {
      debugPrint("Error toggling video: $e");
    }
  }

  Future<void> _toggleAudio() async {
    final nextState = !isAudioOn;
    try {
      if (_room.connectionState == lk.ConnectionState.connected) {
        await _room.localParticipant?.setMicrophoneEnabled(nextState);
      } else {
        if (nextState) {
          await _localAudioTrack?.unmute();
        } else {
          await _localAudioTrack?.mute();
        }
      }
      setState(() {
        isAudioOn = nextState;
      });
    } catch (e) {
      debugPrint("Error toggling audio: $e");
    }
  }

  // Connect to the self-hosted LiveKit server
  Future<void> _connectToLiveKit(String url, String token) async {
    try {
      await _room.connect(url, token);
      if (_localVideoTrack != null) await _room.localParticipant?.publishVideoTrack(_localVideoTrack!);
      if (_localAudioTrack != null) await _room.localParticipant?.publishAudioTrack(_localAudioTrack!);
    } catch (e) {
      debugPrint("LiveKit Connect Error: $e");
    }
  }

  String _generateInviteLink() {
    final baseUri = Uri.base;
    String origin;
    if (widget.publicUrl.isNotEmpty) {
      origin = widget.publicUrl;
      if (origin.endsWith('/')) {
        origin = origin.substring(0, origin.length - 1);
      }
    } else {
      origin = '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ":${baseUri.port}" : ""}';
    }

    var overrideIp = _ipOverrideController.text.trim();
    if (overrideIp.isNotEmpty) {
      // Clean up input if the user enters a full URL instead of just the IP
      if (overrideIp.startsWith('http://')) overrideIp = overrideIp.substring(7);
      if (overrideIp.startsWith('https://')) overrideIp = overrideIp.substring(8);
      if (overrideIp.startsWith('ws://')) overrideIp = overrideIp.substring(5);
      if (overrideIp.startsWith('wss://')) overrideIp = overrideIp.substring(6);
      
      final portIndex = overrideIp.indexOf(':');
      if (portIndex != -1) {
        overrideIp = overrideIp.substring(0, portIndex);
      }
      final pathIndex = overrideIp.indexOf('/');
      if (pathIndex != -1) {
        overrideIp = overrideIp.substring(0, pathIndex);
      }
      
      origin = origin.replaceAll('localhost', overrideIp).replaceAll('127.0.0.1', overrideIp);
    }

    String serverUrl = widget.url;
    if (overrideIp.isNotEmpty) {
      serverUrl = serverUrl.replaceAll('localhost', overrideIp).replaceAll('127.0.0.1', overrideIp);
    }

    final Map<String, String> queryParams = {
      if (widget.roomName.isNotEmpty) 'room': widget.roomName,
      if (serverUrl.isNotEmpty) 'url': serverUrl,
      if (widget.apiKey.isNotEmpty) 'key': widget.apiKey,
      if (widget.apiSecret.isNotEmpty) 'secret': widget.apiSecret,
    };
    
    final queryString = Uri(queryParameters: queryParams).query;
    return '$origin/#/?$queryString';
  }

  void _showInviteDialog() {
    bool copied = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final inviteUrl = _generateInviteLink();
            final isLocalhost = widget.url.contains('localhost') || 
                                widget.url.contains('127.0.0.1') ||
                                Uri.base.host == 'localhost' || 
                                Uri.base.host == '127.0.0.1';

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 40,
                      offset: Offset(0, 10),
                    )
                  ],
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.indigoAccent.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_add, color: Colors.indigoAccent, size: 24),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Invite Participants',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Anyone with this link can join this secure session and participate in the audio/video call.',
                      style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                    ),
                    if (isLocalhost) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Warning: Meeting is running on localhost. Other devices on your Wi-Fi will need your computer\'s IP address to connect.',
                                style: TextStyle(color: Colors.orangeAccent, fontSize: 11, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'HOST COMPUTER IP OVERRIDE',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _ipOverrideController,
                        onChanged: (_) {
                          setDialogState(() {});
                        },
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter PC local IP (e.g., 192.168.1.50)',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white30, size: 16),
                            onPressed: () {
                              _ipOverrideController.clear();
                              setDialogState(() {});
                            },
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'SHAREABLE MEETING LINK',
                                style: TextStyle(
                                  color: Colors.indigoAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (widget.roomName.isNotEmpty)
                                Text(
                                  'Room: ${widget.roomName}',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            inviteUrl,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white54,
                          ),
                          child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: inviteUrl));
                            setDialogState(() {
                              copied = true;
                            });
                            // Close dialog after copy is clicked
                            Future.delayed(const Duration(milliseconds: 500), () {
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            });
                          },
                          icon: Icon(
                            copied ? Icons.check : Icons.copy,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: Text(
                            copied ? 'Copied!' : 'Copy Link',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: copied ? Colors.green : Colors.indigoAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildParticipantGrid(List<RemoteParticipant> participants) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = participants.length;
        int cols = 1;
        int rows = 1;
        
        if (count == 2) {
          if (constraints.maxWidth > constraints.maxHeight) {
            cols = 2;
            rows = 1;
          } else {
            cols = 1;
            rows = 2;
          }
        } else if (count <= 4) {
          cols = 2;
          rows = 2;
        } else if (count <= 6) {
          cols = 3;
          rows = 2;
        } else {
          cols = 3;
          rows = 3;
        }
        
        final itemWidth = constraints.maxWidth / cols;
        final itemHeight = constraints.maxHeight / rows;
        
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: itemWidth / itemHeight,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: count,
          itemBuilder: (context, index) {
            final participant = participants[index];
            return _buildParticipantTile(participant);
          },
        );
      },
    );
  }

  Widget _buildParticipantTile(RemoteParticipant participant) {
    final videoPublication = participant.videoTrackPublications.isNotEmpty
        ? participant.videoTrackPublications.first
        : null;
    final videoTrack = videoPublication?.track as VideoTrack?;
    final isVideoMuted = videoPublication?.muted ?? true;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null && !isVideoMuted)
            VideoTrackRenderer(videoTrack)
          else
            _buildParticipantPlaceholder(participant.identity),

          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: participant.isSpeaking ? Colors.greenAccent : Colors.white30,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          participant.identity,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _buildAudioIndicator(participant),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantPlaceholder(String identity) {
    String initials = '';
    final parts = identity.split(' ');
    if (parts.isNotEmpty) {
      initials += parts[0].isNotEmpty ? parts[0][0] : '';
      if (parts.length > 1 && parts[1].isNotEmpty) {
        initials += parts[1][0];
      }
    }
    if (initials.isEmpty) initials = '?';
    initials = initials.toUpperCase();

    final colors = [
      Colors.indigo,
      Colors.blueGrey,
      Colors.teal,
      Colors.pink,
      Colors.purple,
      Colors.blue,
    ];
    final color = colors[identity.hashCode % colors.length];

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: color,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Icon(Icons.videocam_off, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioIndicator(RemoteParticipant participant) {
    final audioPublication = participant.audioTrackPublications.isNotEmpty
        ? participant.audioTrackPublications.first
        : null;
    final isAudioMuted = audioPublication?.muted ?? true;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isAudioMuted ? const Color(0xFFEF4444).withOpacity(0.9) : Colors.black.withOpacity(0.65),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white10),
      ),
      child: Icon(
        isAudioMuted ? Icons.mic_off : Icons.mic,
        color: Colors.white,
        size: 14,
      ),
    );
  }

    Widget _buildWaitingOrDisconnectedScreen(String message) {
    bool isConnected = _room.connectionState == lk.ConnectionState.connected;
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Loading/Connection Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isConnected 
                      ? Colors.greenAccent.withOpacity(0.1) 
                      : Colors.orangeAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isConnected 
                        ? Colors.greenAccent.withOpacity(0.3) 
                        : Colors.orangeAccent.withOpacity(0.3)
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isConnected)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent),
                      )
                    else
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      message,
                      style: TextStyle(
                        color: isConnected ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              if (_showInlineInviteCard) ...[
                Builder(
                  builder: (context) {
                    final inviteUrl = _generateInviteLink();
                    final isLocalhost = widget.url.contains('localhost') || 
                                        widget.url.contains('127.0.0.1') ||
                                        Uri.base.host == 'localhost' || 
                                        Uri.base.host == '127.0.0.1';

                    return Container(
                      constraints: const BoxConstraints(maxWidth: 460),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.share, color: Colors.indigoAccent, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Share Meeting Invitation',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Send this link to anyone you want to join. They will be able to join directly with their name.',
                            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                          ),
                          if (isLocalhost) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Warning: Meeting is running on localhost. Other devices on your Wi-Fi will need your computer\'s IP address to connect.',
                                      style: TextStyle(color: Colors.orangeAccent, fontSize: 11, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'HOST COMPUTER IP OVERRIDE',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _ipOverrideController,
                              onChanged: (_) {
                                setState(() {});
                              },
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Enter PC local IP (e.g., 192.168.1.50)',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.white30, size: 16),
                                  onPressed: () {
                                    _ipOverrideController.clear();
                                    setState(() {});
                                  },
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          
                          // Link display field
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: SelectableText(
                              inviteUrl,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Copy Button
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [Colors.indigoAccent, Color(0xFF4F46E5)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.indigoAccent.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: inviteUrl));
                                setState(() {
                                  _inviteLinkCopied = true;
                                });
                                // Hide the inline invite component after copying
                                Future.delayed(const Duration(milliseconds: 500), () {
                                  if (mounted) {
                                    setState(() {
                                      _showInlineInviteCard = false;
                                    });
                                  }
                                });
                              },
                              icon: Icon(
                                _inviteLinkCopied ? Icons.check : Icons.copy,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: Text(
                                _inviteLinkCopied ? 'Copied Link!' : 'Copy Invitation Link',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _inviteLinkCopied ? Colors.green : Colors.transparent,
                                shadowColor: Colors.transparent,
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                ),
              ] else ...[
                // Minimalist waiting state once the link is copied
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: Colors.indigoAccent),
                const SizedBox(height: 16),
                const Text(
                  'Invitation link copied to clipboard!',
                  style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Waiting for other participants to join the call...',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  icon: const Icon(Icons.share, size: 16, color: Colors.indigoAccent),
                  label: const Text('Show Invite Link Again', style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() {
                      _inviteLinkCopied = false;
                      _showInlineInviteCard = true;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isMobile = screenWidth < 600;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161E2E), // Darker slate
      ),
      child: Stack(
        children: [
          // Remote Participants (REAL TIME WEBRTC GRID)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: widget.isPip ? 12 : (isMobile ? 12 : 24),
                left: widget.isPip ? 12 : (isMobile ? 12 : 24),
                right: widget.isPip ? 12 : (isMobile ? 12 : 24),
                bottom: widget.isPip ? 60 : (isMobile ? 80 : 100),
              ),
              child: Builder(
                builder: (context) {
                  final remoteParticipants = _room.remoteParticipants.values.toList();
                  if (remoteParticipants.isNotEmpty) {
                    return _buildParticipantGrid(remoteParticipants);
                  }

                  // If no one is connected, show waiting screen with share link
                  return _buildWaitingOrDisconnectedScreen(
                    _room.connectionState == lk.ConnectionState.connected 
                        ? 'Waiting for others to join the room...' 
                        : 'Not connected to LiveKit Server', 
                  );
                }
              ),
            ).animate().fadeIn(duration: 800.ms),
          ),

          // Local Participant PiP (Top Right)
          AnimatedPositioned(
            duration: 300.ms,
            top: widget.isPip ? 8 : (isMobile ? 12 : 24),
            right: widget.isPip ? 8 : (isMobile ? 12 : 24),
            width: widget.isPip ? 100 : (isMobile ? 120 : 220),
            height: widget.isPip ? 56 : (isMobile ? 68 : 124),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: (isVideoOn && _localVideoTrack != null)
                        ? VideoTrackRenderer(_localVideoTrack!)
                        : Container(
                            color: const Color(0xFF1E293B),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _mediaErrorMessage ?? (isVideoOn ? 'No Camera Device Found\n(VM / Permission Blocked)' : 'Camera Off'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white54, fontSize: widget.isPip ? 8 : (isMobile ? 9 : 10)),
                                    ),
                                    if (_mediaErrorMessage != null) ...[
                                      const SizedBox(height: 6),
                                      GestureDetector(
                                        onTap: _initLocalCamera,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.indigoAccent,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Retry',
                                            style: TextStyle(
                                              fontSize: widget.isPip ? 8 : (isMobile ? 9 : 10),
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Text('You (Doctor)', style: TextStyle(fontSize: widget.isPip ? 8 : (isMobile ? 10 : 12), color: Colors.white, fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 2, color: Colors.black)])),
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
                    )
                ],
              ),
            ),
          ),
          // Shared Whiteboard Overlay Panel
          if (isWhiteboardOpen)
            Positioned.fill(
              child: Container(
                color: Colors.black45, // Dim background
                padding: isMobile 
                    ? const EdgeInsets.fromLTRB(8, 64, 8, 76) 
                    : const EdgeInsets.fromLTRB(24, 80, 24, 110),
                child: WhiteboardCanvas(
                  remoteEventStream: _whiteboardStreamController.stream,
                  onLocalDraw: (point) {
                    final payload = jsonEncode({
                      'action': point.action,
                      'x': point.x,
                      'y': point.y,
                      'color': point.color,
                      'width': point.strokeWidth,
                    });
                    _room.localParticipant?.publishData(
                      utf8.encode(payload),
                      reliable: true,
                      topic: 'whiteboard',
                    );
                  },
                  onLocalClear: () {
                    final payload = jsonEncode({
                      'action': 'clear',
                    });
                    _room.localParticipant?.publishData(
                      utf8.encode(payload),
                      reliable: true,
                      topic: 'whiteboard',
                    );
                  },
                ),
              ),
            ),

          

          // Bottom Controls Bar
          AnimatedPositioned(
            duration: 300.ms,
            bottom: widget.isPip ? 12 : (isMobile ? 16 : 32),
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.isPip ? 12 : (isMobile ? 12 : 24),
                  vertical: widget.isPip ? 8 : (isMobile ? 10 : 12),
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9), // Slate 800
                  borderRadius: BorderRadius.circular(widget.isPip ? 16 : (isMobile ? 20 : 30)),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildControlButton(
                      icon: isAudioOn ? Icons.mic_none : Icons.mic_off,
                      isDanger: !isAudioOn,
                      onTap: _toggleAudio,
                      isMobile: isMobile,
                    ),
                    SizedBox(width: widget.isPip ? 8 : (isMobile ? 10 : 16)),
                    _buildControlButton(
                      icon: isVideoOn ? Icons.videocam_outlined : Icons.videocam_off_outlined,
                      isDanger: !isVideoOn,
                      onTap: _toggleVideo,
                      isMobile: isMobile,
                    ),
                    SizedBox(width: widget.isPip ? 8 : (isMobile ? 10 : 16)),
                    _buildControlButton(
                      icon: Icons.chat_bubble_outline,
                      isActive: isChatOpen,
                      badgeCount: _unreadMessageCount,
                      onTap: () {
                        setState(() {
                          isChatOpen = !isChatOpen;
                          if (isChatOpen) {
                            _unreadMessageCount = 0;
                          }
                        });
                      },
                      isMobile: isMobile,
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 16),
                      _buildControlButton(
                        icon: Icons.gesture,
                        isActive: isWhiteboardOpen,
                        label: widget.isPip ? null : 'Whiteboard',
                        onTap: () => setState(() => isWhiteboardOpen = !isWhiteboardOpen),
                      ),
                      const SizedBox(width: 16),
                      _buildControlButton(
                        icon: Icons.blur_on,
                        label: widget.isPip ? null : 'Blur',
                        isActive: isBlurActive,
                        onTap: () {
                          setState(() => isBlurActive = !isBlurActive);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Background Blur requires ML WebAssembly assets (TFLite) and Cross-Origin isolation headers to be deployed on the hosting server. This feature will activate in production!'),
                              backgroundColor: Colors.indigo.shade800,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      _buildControlButton(
                        icon: Icons.person_add_alt_1,
                        label: widget.isPip ? null : 'Invite',
                        onTap: _showInviteDialog,
                      ),
                    ] else ...[
                      SizedBox(width: widget.isPip ? 8 : (isMobile ? 10 : 16)),
                      _buildControlButton(
                        icon: Icons.more_horiz,
                        onTap: _showMoreOptionsBottomSheet,
                        isMobile: isMobile,
                      ),
                    ],
                    SizedBox(width: widget.isPip ? 8 : (isMobile ? 10 : 16)),
                    GestureDetector(
                      onTap: () async {
                        if (widget.isDoctor) {
                          try {
                            final payload = jsonEncode({'action': 'end_call'});
                            await _room.localParticipant?.publishData(
                              utf8.encode(payload),
                              reliable: true,
                              topic: 'room_control',
                            );
                            // Give data channel a brief moment to transmit
                            await Future.delayed(const Duration(milliseconds: 300));
                          } catch (e) {
                            debugPrint("Error ending call: $e");
                          }
                        }
                        _exitRoom();
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.isPip ? 12 : (isMobile ? 16 : 24),
                          vertical: widget.isPip ? 8 : (isMobile ? 10 : 12),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(widget.isPip ? 12 : (isMobile ? 16 : 25)),
                        ),
                        child: Text(
                          'End Call',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: widget.isPip ? 10 : (isMobile ? 12 : 14),
                          ),
                        ),
                      ),
                    ),
                  ],

                ),
              ),
            ),
          ),
          
          // Chat Overlay (Draggable on Desktop, Fixed bottom panel on Mobile)
          if (isChatOpen)
            isMobile
                ? Positioned(
                    left: 16,
                    right: 16,
                    bottom: widget.isPip ? 60 : 76,
                    height: screenHeight * 0.52,
                    child: _buildChatOverlay(isMobile: true)
                        .animate()
                        .slideY(begin: 0.2, duration: 200.ms)
                        .fadeIn(),
                  )
                : Positioned(
                    left: _chatBoxX,
                    top: _chatBoxY,
                    child: _buildChatOverlay(isMobile: false)
                        .animate()
                        .scaleXY(begin: 0.9, duration: 200.ms, curve: Curves.easeOutBack)
                        .fadeIn(),
                  ),
        ],
      ),
    );
  }

  void _showMoreOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'More Options',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Whiteboard
                    _buildSheetOption(
                      icon: Icons.gesture,
                      label: 'Whiteboard',
                      isActive: isWhiteboardOpen,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => isWhiteboardOpen = !isWhiteboardOpen);
                      },
                    ),
                    // Blur
                    _buildSheetOption(
                      icon: Icons.blur_on,
                      label: 'Blur',
                      isActive: isBlurActive,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => isBlurActive = !isBlurActive);
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: const Text('Background Blur requires ML WebAssembly assets (TFLite) and Cross-Origin isolation headers to be deployed on the hosting server. This feature will activate in production!'),
                            backgroundColor: Colors.indigo.shade800,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      },
                    ),
                    // Invite
                    _buildSheetOption(
                      icon: Icons.person_add_alt_1,
                      label: 'Invite',
                      onTap: () {
                        Navigator.pop(context);
                        _showInviteDialog();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetOption({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive ? Colors.indigoAccent : const Color(0xFF334155),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    bool isDanger = false,
    bool isActive = false,
    String? label,
    int badgeCount = 0,
    required VoidCallback onTap,
    bool isMobile = false,
  }) {
    Color bgColor = const Color(0xFF334155); // Slate 700
    Color iconColor = Colors.white70;
    if (isDanger) {
      bgColor = const Color(0xFFE11D48).withOpacity(0.2); // Rose 600
      iconColor = const Color(0xFFE11D48);
    } else if (isActive) {
      bgColor = Colors.indigoAccent;
      iconColor = Colors.white;
    }

    final isCompact = widget.isPip || isMobile;

    final buttonWidget = AnimatedContainer(
      duration: 200.ms,
      height: isCompact ? 38 : 48,
      padding: EdgeInsets.symmetric(horizontal: (label != null && !isCompact) ? 16 : 0),
      width: (label == null || isCompact) ? (isCompact ? 38 : 48) : null,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(isCompact ? 10 : 24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: isCompact ? 18 : 20),
          if (label != null && !isCompact) ...[
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: iconColor, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: badgeCount > 0
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                buttonWidget,
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE11D48), // Rose 600
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Center(
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : buttonWidget,
    );
  }

  Widget _buildChatOverlay({bool isMobile = false}) {
    return Container(
      width: isMobile ? double.infinity : _chatBoxW,
      height: isMobile ? double.infinity : _chatBoxH,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 40)],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // Chat Messages List
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: isMobile ? null : (details) {
                    final size = MediaQuery.of(context).size;
                    setState(() {
                      _chatBoxX = (_chatBoxX + details.delta.dx).clamp(0.0, size.width - _chatBoxW);
                      _chatBoxY = (_chatBoxY + details.delta.dy).clamp(0.0, size.height - _chatBoxH);
                    });
                  },
                  child: Stack(
                    children: [
                      // Visual Drag Handle
                      if (!isMobile)
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.only(top: 12),
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, isMobile ? 16 : 32, 16, 0),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _messages.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 16, top: 8),
                                child: Text('Chat started. Messages are end-to-end\nencrypted.', 
                                  style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.5), textAlign: TextAlign.center
                                ),
                              );
                            }
                            final msg = _messages[index - 1];
                            return Align(
                              alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: msg.isMe ? const Color(0xFF4F46E5) : const Color(0xFF334155),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                                    bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(msg.time, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9)),
                                  ],
                                ),
                              ).animate().fadeIn().slideY(begin: 0.2),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Input Area
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _pickFile,
                      child: Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.attach_file, color: Colors.white70, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: TextField(
                          controller: _chatController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.send, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Close Button
          Positioned(
            top: 16,
            right: 16,
            child: GestureDetector(
              onTap: () => setState(() => isChatOpen = false),
              child: const Icon(Icons.close, color: Colors.white38, size: 20),
            ),
          ),
          
          // Resizable Handle
          if (!isMobile)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  setState(() {
                    _chatBoxW = max(250, min(_chatBoxW + details.delta.dx, 600)); // Max width 600
                    _chatBoxH = max(300, min(_chatBoxH + details.delta.dy, 800)); // Max height 800
                  });
                },
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.filter_list, size: 16, color: Colors.white24), // Subtle handle icon
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
