import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:async'; // NEW

import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'components/bg_images.dart';
import 'services/speech_translation_service.dart'; // NEW
import 'config.dart';
import 'components/token_generator.dart';

enum ChatFileType { text, image, pdf, word, excel, powerpoint, audio, video, medical, zip, other }

class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final String time;
  final String senderName;
  final ChatFileType fileType;
  final Uint8List? fileBytes;
  final String? fileName;
  final int? fileSize;

  ChatMessage(
    this.text,
    this.isMe,
    this.time, {
    String? id,
    this.senderName = '',
    this.fileType = ChatFileType.text,
    Uint8List? fileBytes,        // plain param so we can merge with imageBytes below
    Uint8List? imageBytes,       // backward-compat alias
    this.fileName,
    this.fileSize,
  })  : id = id ?? '${DateTime.now().microsecondsSinceEpoch}',
        fileBytes = fileBytes ?? imageBytes;

  // Backward-compat getter
  Uint8List? get imageBytes => fileType == ChatFileType.image ? fileBytes : null;

  /// Detect file type from extension
  static ChatFileType detectType(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) return ChatFileType.image;
    if (ext == 'pdf') return ChatFileType.pdf;
    if (['doc', 'docx'].contains(ext)) return ChatFileType.word;
    if (['xls', 'xlsx', 'csv'].contains(ext)) return ChatFileType.excel;
    if (['ppt', 'pptx'].contains(ext)) return ChatFileType.powerpoint;
    if (['mp3', 'wav'].contains(ext)) return ChatFileType.audio;
    if (ext == 'mp4') return ChatFileType.video;
    if (['dcm', 'dicom'].contains(ext)) return ChatFileType.medical;
    if (ext == 'zip') return ChatFileType.zip;
    return ChatFileType.other;
  }
}

class StrokePoint {
  final double x;
  final double y;
  StrokePoint(this.x, this.y);
  
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class SharedStroke {
  final List<StrokePoint> points;
  final Color color;
  final double strokeWidth;

  SharedStroke({required this.points, required this.color, required this.strokeWidth});
}

class PatientSessionData {
  static String aiSummary = "Waiting for the patient to complete the pre-consultation AI check...";
}

class MeetingController extends ChangeNotifier {
  // Singleton pattern so the entire app can easily share the same active session
  static final MeetingController _instance = MeetingController._internal();
  factory MeetingController() => _instance;
  MeetingController._internal() {
    SpeechTranslationService().onLocalSpeech = _handleLocalSpeech;
  }

  Room? room;
  EventsListener<RoomEvent>? _listener;

  LocalVideoTrack? localVideoTrack;
  LocalAudioTrack? localAudioTrack;

  bool _isCreatingCameraTrack = false;
  Future<void> ensureLocalVideoTrack() async {
    if (_isCreatingCameraTrack) return;
    if (localVideoTrack != null && isVideoOn) return;

    _isCreatingCameraTrack = true;
    try {
      if (room?.localParticipant != null) {
        final pubs = room!.localParticipant!.videoTrackPublications;
        if (pubs.isNotEmpty && pubs.first.track != null) {
          localVideoTrack = pubs.first.track;
          await localVideoTrack?.unmute();
          cameraError = null;
        } else {
          cameraError = null;
          await room!.localParticipant!.setCameraEnabled(true);
          final updatedPubs = room!.localParticipant!.videoTrackPublications;
          if (updatedPubs.isNotEmpty) {
            localVideoTrack = updatedPubs.first.track;
            await localVideoTrack?.unmute();
            cameraError = null;
          }
        }
      } else {
        cameraError = null;
        localVideoTrack = await LocalVideoTrack.createCameraTrack();
        cameraError = null;
      }
      isVideoOn = true;
      cameraError = null;
      notifyListeners();
    } catch (e) {
      cameraError = e.toString();
      debugPrint("Failed to create camera track: $e");
      notifyListeners();
    } finally {
      _isCreatingCameraTrack = false;
    }
  }

  bool isConnected = false;
  bool isConnecting = false;
  String? connectionError;
  String? cameraError;

  bool isVideoOn = true;
  bool isAudioOn = true;

  String currentBgTheme = 'none';

  void setBgTheme(String theme, {String? customUrl}) {
    currentBgTheme = theme;
    debugPrint("[CHAV-LIVEKIT] Applied background theme: $currentBgTheme");
    notifyListeners();

    if (kIsWeb) {
      try {
        final windowJs = web.window as JSObject;
        if (theme == 'none') {
          if (windowJs.has('stopBgBlur')) {
            windowJs.callMethod('stopBgBlur'.toJS);
          }
        } else if (theme == 'blur') {
          if (windowJs.has('startBgBlur')) {
            windowJs.callMethod('startBgBlur'.toJS, 15.toJS);
            windowJs.callMethod('setBgTheme'.toJS, 'blur'.toJS, 15.toJS);
          }
        } else {
          String imageUrl = customUrl ?? '';
          if (imageUrl.isEmpty) {
            if (theme == 'modern_office') imageUrl = BgImages.modernOffice;
            else if (theme == 'home') imageUrl = BgImages.home;
            else if (theme == 'hospital') imageUrl = BgImages.hospital;
            else if (theme == 'library') imageUrl = BgImages.library;
            else if (theme == 'nature_garden') imageUrl = BgImages.natureGarden;
            else if (theme == 'luxury_room') imageUrl = BgImages.luxuryRoom;
            else imageUrl = BgImages.modernOffice;
          }
          if (windowJs.has('startBgBlur')) {
            windowJs.callMethod('startBgBlur'.toJS, 15.toJS);
            windowJs.callMethod('setBgTheme'.toJS, 'image'.toJS, imageUrl.toJS);
          }
        }
      } catch (e) {
        debugPrint("[CHAV-LIVEKIT] JS Background Effect Error: $e");
      }
    }
  }

  bool _isWhiteboardOpen = false;
  bool get isWhiteboardOpen => _isWhiteboardOpen;
  set isWhiteboardOpen(bool value) {
    _isWhiteboardOpen = value;
    notifyListeners();
  }

  Future<void> toggleWhiteboardState(bool open) async {
    _isWhiteboardOpen = open;
    notifyListeners();
    
    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'whiteboard_toggle',
          'open': open,
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint("Failed to send whiteboard_toggle: $e");
      }
    }
  }

  final List<ChatMessage> messages = [];
  final List<SharedStroke> strokes = [];
  final List<SharedStroke> _redoStack = []; // redo history
  bool get canRedo => _redoStack.isNotEmpty;
  SharedStroke? currentRemoteStroke;

  // Chat file chunk reassembly buffers
  final Map<String, List<String?>> _incomingChatFileChunks = {};
  final Map<String, String> _incomingChatFileNames = {};
  final Map<String, int> _incomingChatFileSizes = {};
  final Map<String, String> _incomingChatSenderNames = {};
  final Set<String> _seenMessageIds = {}; // deduplication
  final Set<String> _seenTranscriptIds = {}; // transcript deduplication
  
  String get aiSummary => PatientSessionData.aiSummary;
  set aiSummary(String val) {
    PatientSessionData.aiSummary = val;
    notifyListeners();
  }

  // To be set by patient when they join, so they can send it immediately
  String? pendingAiSummary;

  String? meetingDescription;

  // Location Sharing State
  final Map<String, Map<String, dynamic>> participantLocations = {};

  // Room Control State
  String? roomControlAction;
  
  void clearRoomControlAction() {
    roomControlAction = null;
    notifyListeners();
  }

  // Live Captions State
  bool isCaptionVisible = false;
  bool isCapturing = false;
  String selectedSpokenLanguage = 'en-US';
  String selectedCaptionLanguage = 'en';
  String? originalCaption;
  String? translatedCaption;
  String? rawOriginalText; // NEW: store raw text for manual translation
  String? currentSpeaker; // NEW: store speaker for manual translation
  String? captionError; // NEW: store errors to display
  Timer? _captionDebounceTimer;
  Timer? _captionClearTimer; // NEW: fades out subtitles after 6 seconds

  void toggleCaptions() {
    isCaptionVisible = !isCaptionVisible;
    if (isCaptionVisible) {
      startCapturing();
    } else {
      stopCapturing();
      originalCaption = null;
      translatedCaption = null;
    }
    notifyListeners();
  }

  void startCapturing({Function(String)? onError}) {
    isCapturing = true;
    captionError = null;
    SpeechTranslationService().onSpeechError = (error) {
       isCapturing = false;
       captionError = error;
       notifyListeners();
       if (onError != null) onError(error);
    };
    SpeechTranslationService().startListening();
    notifyListeners();
  }

  void stopCapturing() {
    isCapturing = false;
    SpeechTranslationService().stopListening();
    notifyListeners();
  }

  void setSpokenLanguage(String lang) {
    selectedSpokenLanguage = lang;
    SpeechTranslationService().setSpokenLanguage(lang);
    notifyListeners();
  }

  void setCaptionLanguage(String lang) {
    selectedCaptionLanguage = lang;
    notifyListeners();
  }

  Future<void> forceTranslate() async {
    if (rawOriginalText == null || rawOriginalText!.trim().isEmpty || currentSpeaker == null) return;
    
    translatedCaption = "Translation:\n...";
    notifyListeners();
    
    final translated = await SpeechTranslationService().translateText(rawOriginalText!, selectedCaptionLanguage);
    translatedCaption = "Translation:\n$translated";
    notifyListeners();
  }

  void _handleLocalSpeech(String text, bool isFinal) {
    final senderRole = isDoctor ? "Doctor" : "Patient";
    debugPrint("[CHAV-TRANSCRIPT] Local speech detected ($senderRole): '$text' (isFinal: $isFinal)");
    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'caption',
          'speaker': senderRole,
          'text': text,
          'isFinal': isFinal,
          'lang': selectedSpokenLanguage,
        });
        room!.localParticipant!.publishData(utf8.encode(payload), reliable: false); // Use unreliable for fast interim text
      } catch (e) {
        debugPrint("[CHAV-TRANSCRIPT ERROR] Failed to send caption: $e");
      }
    }
    _processIncomingCaption(text, isFinal, senderRole, selectedSpokenLanguage, isLocal: true);
  }

  void _processIncomingCaption(String text, bool isFinal, String speaker, String sourceLang, {bool isLocal = false}) async {
    captionError = null;
    rawOriginalText = text;
    currentSpeaker = speaker;
    originalCaption = "$speaker:\n$text";
    
    _captionClearTimer?.cancel();

    if (text.trim().isEmpty) {
      translatedCaption = null; // No translation needed
      notifyListeners();
      return;
    }

    if (isFinal) {
      _captionDebounceTimer?.cancel();
      final translated = await SpeechTranslationService().translateText(text, selectedCaptionLanguage);
      translatedCaption = "Translation:\n$translated";
      
      // Record spoken phrase in background transcript log cleanly
      final timeStr = DateFormat('hh:mm a').format(DateTime.now());
      final entryId = '${speaker}_${DateTime.now().millisecondsSinceEpoch}_${text.hashCode}';
      
      if (!_seenTranscriptIds.contains(entryId)) {
        _seenTranscriptIds.add(entryId);
        callTranscriptLog.add({
          'id': entryId,
          'speaker': speaker,
          'text': text,
          'time': timeStr,
        });
        debugPrint("[CHAV-TRANSCRIPT] Recorded transcript entry [$speaker - $timeStr]: '$text'");
        _updateTranscriptInDescription();

        // Broadcast transcript entry to all other room participants over DataChannel if local
        if (isLocal && room?.localParticipant != null) {
          try {
            final payload = json.encode({
              'type': 'transcript_entry',
              'id': entryId,
              'speaker': speaker,
              'text': text,
              'time': timeStr,
            });
            room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
            debugPrint("[CHAV-TRANSCRIPT] Broadcasted transcript_entry over DataChannel to remote participants");
          } catch (e) {
            debugPrint("[CHAV-TRANSCRIPT ERROR] Failed to broadcast transcript entry: $e");
          }
        }
      }

      _captionClearTimer = Timer(const Duration(seconds: 6), () {
        originalCaption = null;
        translatedCaption = null;
        notifyListeners();
      });
      notifyListeners();
    } else {
      // Show intermediate indicator for translation
      translatedCaption = "Translation:\n...";
      notifyListeners();

      _captionDebounceTimer?.cancel();
      _captionDebounceTimer = Timer(const Duration(milliseconds: 600), () async {
        final translated = await SpeechTranslationService().translateText(text, selectedCaptionLanguage);
        translatedCaption = "Translation:\n$translated";
        notifyListeners();
      });
    }
  }

  // Track current room name
  String? currentRoomName;

  // Background Speech Recording Transcript
  final List<Map<String, String>> callTranscriptLog = [];

  // Whiteboard Background Image Bytes Sync
  Uint8List? whiteboardBgImageBytes;
  final Map<int, String> _wbBgChunks = {};
  int _wbBgTotalChunks = 0;

  Future<void> setWhiteboardBgImage(Uint8List bytes) async {
    whiteboardBgImageBytes = bytes;
    notifyListeners();

    if (room?.localParticipant == null) return;
    try {
      final b64 = base64Encode(bytes);
      const chunkSize = 12000;
      final totalChunks = (b64.length / chunkSize).ceil();
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize).clamp(0, b64.length);
        final payload = json.encode({
          'type': 'wb_bg_chunk',
          'chunkIndex': i,
          'totalChunks': totalChunks,
          'data': b64.substring(start, end),
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      }
    } catch (e) {
      debugPrint("Failed to send whiteboard background image chunks: $e");
    }
  }

  void addSpeechTranscript(String speaker, String text) {
    if (text.trim().isEmpty) return;
    final timeStr = DateFormat('hh:mm a').format(DateTime.now());
    callTranscriptLog.add({
      'speaker': speaker,
      'text': text,
      'time': timeStr,
    });
    _updateTranscriptInDescription();

    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'transcript_entry',
          'speaker': speaker,
          'text': text,
          'time': timeStr,
        });
        room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint("Failed to send transcript entry: $e");
      }
    }
  }

  String? initialBaseMeetingDescription;

  void _updateTranscriptInDescription() {
    if (callTranscriptLog.isEmpty) return;

    final buffer = StringBuffer();
    if (initialBaseMeetingDescription != null && initialBaseMeetingDescription!.isNotEmpty) {
      buffer.writeln(initialBaseMeetingDescription);
      buffer.writeln();
    }
    buffer.writeln("--- Live Call Transcript ---");
    for (final entry in callTranscriptLog) {
      buffer.writeln("[${entry['speaker']} - ${entry['time']}]: ${entry['text']}");
    }

    meetingDescription = buffer.toString();
    notifyListeners();
  }

  // Track if we are Doctor or Patient
  bool isDoctor = false;

  void setRoleAndSummary({required bool isDoctor, String? aiSummaryText, String? meetingDescriptionText}) {
    this.isDoctor = isDoctor;
    if (aiSummaryText != null && aiSummaryText.isNotEmpty) {
      pendingAiSummary = aiSummaryText;
    }
    if (meetingDescriptionText != null && meetingDescriptionText.isNotEmpty) {
      initialBaseMeetingDescription = meetingDescriptionText;
      meetingDescription = meetingDescriptionText;
      _updateTranscriptInDescription();
    }
    notifyListeners();
  }

  Future<void> updateMeetingDescription(String desc, {bool broadcast = false}) async {
    meetingDescription = desc;
    notifyListeners();

    if (broadcast && room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'meeting_description',
          'description': desc,
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint("Failed to send meeting description: $e");
      }
    }
  }

  Future<void> shareLocation(String city) async {
    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'location',
          'city': city,
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint("Failed to send location: $e");
      }
    }
  }

  Future<void> endCallForEveryone() async {
    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'room_control',
          'action': 'end_call',
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint("Failed to end call: $e");
      }
    }
  }
  
  Future<void> connect(String baseUrl, String wsUrl, String roomName, String identity) async {
    if (isConnected || isConnecting) return;
    
    isConnecting = true;
    connectionError = null;
    notifyListeners();

    try {
      // Create local tracks first if not already created. Catch errors (e.g. no webcam)
      try {
        localVideoTrack ??= await LocalVideoTrack.createCameraTrack();
      } catch (e) {
        debugPrint("Camera error: $e");
      }
      try {
        localAudioTrack ??= await LocalAudioTrack.create();
      } catch (e) {
        debugPrint("Mic error: $e");
      }

      // Fetch Token
      final response = await http.get(Uri.parse('$baseUrl/api/getToken?room=$roomName&user=$identity'));
      if (response.statusCode != 200) {
        throw Exception("Failed to fetch token: ${response.body}");
      }

      print("GET TOKEN URL: $baseUrl/api/getToken?room=$roomName&user=$identity");
      print("TOKEN RESPONSE BODY: ${response.body}");
      final data = json.decode(response.body);
      print("DECODED DATA TYPE: ${data.runtimeType}");
      final token = data['token'];
      // Read dynamic wsUrl from backend, fallback to local wsUrl
      final serverWsUrl = data['wsUrl'] ?? wsUrl;
      print("TOKEN VALUE: $token");
      print("WS URL: $serverWsUrl");

      // Initialize LiveKit Room
      final newRoom = Room();
      room = newRoom;
      
      // Setup room listener
      _listener = newRoom.createListener();
      _listener!.on<DataReceivedEvent>(handleDataReceived);
      _listener!.on<ParticipantConnectedEvent>((_) => _sendChatHistoryToNewParticipant());

      newRoom.addListener(_onRoomStateChanged);

      // Connect
      await newRoom.connect(serverWsUrl, token);
      
      // Publish Local Tracks
      if (localVideoTrack != null && isVideoOn) {
        await newRoom.localParticipant?.publishVideoTrack(localVideoTrack!);
      }
      if (localAudioTrack != null && isAudioOn) {
        await newRoom.localParticipant?.publishAudioTrack(localAudioTrack!);
      }

      isConnected = true;
      isConnecting = false;
      
      // If we are the patient and we have a pending AI summary, send it to the doctor immediately!
      if (!isDoctor && pendingAiSummary != null) {
        await sendAiSummary(pendingAiSummary!);
      }

      // Initialize STT and start background recording automatically
      SpeechTranslationService().onLocalSpeech = _handleLocalSpeech;
      SpeechTranslationService().init();
      SpeechTranslationService().startListening();

      notifyListeners();
    } catch (e) {
      isConnecting = false;
      isConnected = false;
      connectionError = e.toString();
      debugPrint("MeetingController Connect Error: $e");
      notifyListeners();
    }
  }

  Future<void> connectWithToken(String url, String token, {String? roomName}) async {
    if (isConnected || isConnecting) return;

    if (roomName != null && roomName.isNotEmpty) {
      currentRoomName = roomName;
    }

    if (url.trim().isEmpty) {
      url = 'ws://127.0.0.1:7880';
    }

    if (token.trim().isEmpty) {
      token = generateLiveKitToken(
        roomName: currentRoomName ?? 'my-consultation-room',
        participantName: isDoctor ? 'Doctor' : 'Patient',
        apiKey: LiveKitConfig.apiKey,
        apiSecret: LiveKitConfig.apiSecret,
      );
    }
    
    isConnecting = true;
    connectionError = null;
    notifyListeners();

    try {
      try {
        localVideoTrack ??= await LocalVideoTrack.createCameraTrack();
      } catch (e) {
        debugPrint("Camera error: $e");
      }
      try {
        localAudioTrack ??= await LocalAudioTrack.create();
      } catch (e) {
        debugPrint("Mic error: $e");
      }

      final roleLabel = isDoctor ? 'DOCTOR' : 'PATIENT';
      final fallbackIdentity = isDoctor ? 'Doctor' : 'Patient';
      debugPrint("[CHAV-LIVEKIT] $roleLabel Connecting to LiveKit Server at '$url' for room '$currentRoomName'...");

      final newRoom = Room();
      room = newRoom;
      
      _listener = newRoom.createListener();
      _listener!.on<DataReceivedEvent>(handleDataReceived);
      _listener!.on<RoomConnectedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] RoomConnectedEvent fired for room '${event.room.name}'");
        notifyListeners();
      });
      _listener!.on<ParticipantConnectedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] ParticipantConnected: identity=${event.participant.identity}, name=${event.participant.name}");
        _sendChatHistoryToNewParticipant();
        notifyListeners();
      });
      _listener!.on<ParticipantDisconnectedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] ParticipantDisconnected: identity=${event.participant.identity}");
        notifyListeners();
      });
      _listener!.on<TrackPublishedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] TrackPublished: participant=${event.participant.identity}, sid=${event.publication.sid}, kind=${event.publication.kind}");
        notifyListeners();
      });
      _listener!.on<TrackUnpublishedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] TrackUnpublished: participant=${event.participant.identity}, sid=${event.publication.sid}");
        notifyListeners();
      });
      _listener!.on<TrackSubscribedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] TrackSubscribed: participant=${event.participant.identity}, trackSid=${event.track.sid}, kind=${event.track.kind}");
        notifyListeners();
      });
      _listener!.on<TrackUnsubscribedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] TrackUnsubscribed: participant=${event.participant.identity}, trackSid=${event.track.sid}");
        notifyListeners();
      });
      _listener!.on<TrackMutedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] TrackMuted: participant=${event.participant.identity}");
        notifyListeners();
      });
      _listener!.on<TrackUnmutedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] TrackUnmuted: participant=${event.participant.identity}");
        notifyListeners();
      });
      _listener!.on<LocalTrackPublishedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] LocalTrackPublished: sid=${event.publication.sid}, kind=${event.publication.kind}");
        notifyListeners();
      });
      _listener!.on<LocalTrackUnpublishedEvent>((event) {
        debugPrint("[CHAV-LIVEKIT] LocalTrackUnpublished: sid=${event.publication.sid}");
        notifyListeners();
      });

      newRoom.addListener(_onRoomStateChanged);

      await newRoom.connect(url, token);
      
      final activeIdentity = newRoom.localParticipant?.identity ?? fallbackIdentity;
      debugPrint("[CHAV-LIVEKIT] $roleLabel: Server = $url | Room = ${newRoom.name} | Identity = $activeIdentity");
      debugPrint("[CHAV-LIVEKIT] Connected to room successfully! Room Name: ${newRoom.name}");
      
      if (isVideoOn) {
        debugPrint("[CHAV-LIVEKIT] Enabling camera track on room participant...");
        try {
          if (localVideoTrack != null) {
            final pub = await newRoom.localParticipant?.publishVideoTrack(localVideoTrack!);
            await localVideoTrack?.unmute();
            cameraError = null;
            debugPrint("[CHAV-LIVEKIT] Local camera track published & unmuted SID: ${pub?.sid}");
          } else {
            await newRoom.localParticipant?.setCameraEnabled(true);
            final pubs = newRoom.localParticipant?.videoTrackPublications;
            if (pubs != null && pubs.isNotEmpty) {
              localVideoTrack = pubs.first.track;
              await localVideoTrack?.unmute();
              cameraError = null;
              debugPrint("[CHAV-LIVEKIT] Local camera enabled & unmuted via setCameraEnabled, SID: ${pubs.first.sid}");
            }
          }
        } catch (e) {
          cameraError = e.toString();
          debugPrint("[CHAV-LIVEKIT ERROR] Failed to enable/publish local video track: $e");
        }
      }

      if (isAudioOn) {
        debugPrint("[CHAV-LIVEKIT] Publishing local microphone audio track...");
        try {
          if (localAudioTrack != null) {
            final pub = await newRoom.localParticipant?.publishAudioTrack(localAudioTrack!);
            debugPrint("[CHAV-LIVEKIT] Local audio track published SID: ${pub?.sid}");
          } else {
            await newRoom.localParticipant?.setMicrophoneEnabled(true);
            final pubs = newRoom.localParticipant?.audioTrackPublications;
            if (pubs != null && pubs.isNotEmpty) {
              localAudioTrack = pubs.first.track;
              debugPrint("[CHAV-LIVEKIT] Local mic enabled via setMicrophoneEnabled, SID: ${pubs.first.sid}");
            }
          }
        } catch (e) {
          debugPrint("[CHAV-LIVEKIT ERROR] Failed to publish local audio track: $e");
        }
      }

      isConnected = true;
      isConnecting = false;
      
      // Initialize STT and start background recording automatically
      SpeechTranslationService().onLocalSpeech = _handleLocalSpeech;
      SpeechTranslationService().init();
      SpeechTranslationService().startListening();

      notifyListeners();
    } catch (e) {
      isConnecting = false;
      isConnected = false;
      connectionError = e.toString();
      debugPrint("[LiveKit Log ERROR] MeetingController ConnectWithToken Error: $e");
      notifyListeners();
    }
  }

  void _onRoomStateChanged() {
    notifyListeners();
  }

  void handleDataReceived(DataReceivedEvent event) {
    try {
      final text = utf8.decode(event.data);
      final map = json.decode(text);
      if (map is Map<String, dynamic> && map.containsKey('type')) {
        final type = map['type'] as String;
        switch (type) {
          case 'room_control':
            final action = map['action'] as String;
            if (action == 'end_call') {
              roomControlAction = 'end_call';
              notifyListeners();
            }
            break;
          case 'location':
            final city = map['city'] as String?;
            final senderIdentity = event.participant?.identity ?? 'Unknown';
            final senderName = event.participant?.name ?? senderIdentity;
            if (city != null) {
              participantLocations[senderIdentity] = {
                'name': senderName,
                'city': city,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              };
              notifyListeners();
            }
            break;
          case 'whiteboard_toggle':
            _isWhiteboardOpen = map['open'] as bool;
            notifyListeners();
            break;
          case 'chat':
            final msgText = map['text'] as String;
            final msgId = map['id'] as String? ?? '';
            final sender = map['sender'] as String? ?? '';
            if (msgId.isNotEmpty && _seenMessageIds.contains(msgId)) break;
            if (msgId.isNotEmpty) _seenMessageIds.add(msgId);
            messages.add(ChatMessage(msgText, false, DateFormat('hh:mm a').format(DateTime.now()),
                id: msgId, senderName: sender));
            notifyListeners();
            break;
          case 'ai_summary':
            aiSummary = map['summary'] as String;
            break;
          case 'meeting_description':
            meetingDescription = map['description'] as String;
            notifyListeners();
            break;
          case 'caption':
            final text = map['text'] as String;
            final isFinal = map['isFinal'] as bool;
            final lang = map['lang'] as String? ?? 'en-US';
            final cSpeaker = map['speaker'] as String? ?? (isDoctor ? "Patient" : "Doctor");
            _processIncomingCaption(text, isFinal, cSpeaker, lang, isLocal: false);
            break;
          case 'draw_start':
            final color = Color(map['color'] as int);
            final strokeWidth = (map['strokeWidth'] as num).toDouble();
            final x = (map['x'] as num).toDouble();
            final y = (map['y'] as num).toDouble();
            currentRemoteStroke = SharedStroke(
              points: [StrokePoint(x, y)],
              color: color,
              strokeWidth: strokeWidth,
            );
            strokes.add(currentRemoteStroke!);
            notifyListeners();
            break;
          case 'draw_update':
            final x = (map['x'] as num).toDouble();
            final y = (map['y'] as num).toDouble();
            if (currentRemoteStroke != null) {
              currentRemoteStroke!.points.add(StrokePoint(x, y));
              notifyListeners();
            }
            break;
          case 'draw_end':
            currentRemoteStroke = null;
            notifyListeners();
            break;
          case 'draw_clear':
            strokes.clear();
            _redoStack.clear(); // NEW
            currentRemoteStroke = null;
            notifyListeners();
            break;
          // NEW: remote undo
          case 'draw_undo':
            if (strokes.isNotEmpty) {
              _redoStack.add(strokes.removeLast());
              notifyListeners();
            }
            break;
          // NEW: remote redo
          case 'draw_redo':
            if (_redoStack.isNotEmpty) {
              strokes.add(_redoStack.removeLast());
              notifyListeners();
            }
            break;
          case 'transcript_entry':
            final tId = map['id'] as String? ?? '${map['speaker']}_${map['time']}_${map['text']}';
            final tSpeaker = map['speaker'] as String? ?? 'Participant';
            final tText = map['text'] as String? ?? '';
            final tTime = map['time'] as String? ?? DateFormat('hh:mm a').format(DateTime.now());
            if (tText.isNotEmpty && !_seenTranscriptIds.contains(tId)) {
              _seenTranscriptIds.add(tId);
              callTranscriptLog.add({
                'id': tId,
                'speaker': tSpeaker,
                'text': tText,
                'time': tTime,
              });
              debugPrint("[CHAV-TRANSCRIPT] Received & added remote transcript_entry [$tSpeaker - $tTime]: '$tText'");
              _updateTranscriptInDescription();
            }
            break;
          case 'transcript_history':
            final log = map['log'] as List<dynamic>?;
            if (log != null) {
              int count = 0;
              for (final entry in log) {
                if (entry is Map<String, dynamic>) {
                  final tId = entry['id'] as String? ?? '${entry['speaker']}_${entry['time']}_${entry['text']}';
                  final tSpeaker = entry['speaker'] as String? ?? 'Participant';
                  final tText = entry['text'] as String? ?? '';
                  final tTime = entry['time'] as String? ?? '';
                  if (tText.isNotEmpty && !_seenTranscriptIds.contains(tId)) {
                    _seenTranscriptIds.add(tId);
                    callTranscriptLog.add({
                      'id': tId,
                      'speaker': tSpeaker,
                      'text': tText,
                      'time': tTime,
                    });
                    count++;
                  }
                }
              }
              debugPrint("[CHAV-TRANSCRIPT] Synced $count transcript entries from remote transcript_history");
              _updateTranscriptInDescription();
            }
            break;
          case 'wb_bg_chunk':
            final chunkIndex = map['chunkIndex'] as int;
            final totalChunks = map['totalChunks'] as int;
            final data = map['data'] as String;
            _wbBgChunks[chunkIndex] = data;
            _wbBgTotalChunks = totalChunks;

            if (_wbBgChunks.length == _wbBgTotalChunks) {
              final fullB64Buffer = StringBuffer();
              for (int i = 0; i < _wbBgTotalChunks; i++) {
                if (_wbBgChunks.containsKey(i)) {
                  fullB64Buffer.write(_wbBgChunks[i]);
                }
              }
              whiteboardBgImageBytes = base64Decode(fullB64Buffer.toString());
              _wbBgChunks.clear();
              _wbBgTotalChunks = 0;
              notifyListeners();
            }
            break;
          // Receive a shared whiteboard PNG snapshot or background image from a remote participant
          case 'whiteboard_bg_image':
            final b64 = map['data'] as String;
            whiteboardBgImageBytes = base64Decode(b64);
            notifyListeners();
            break;
          case 'whiteboard_image':
            final b64 = map['data'] as String;
            final imgBytes = base64Decode(b64);
            whiteboardBgImageBytes = imgBytes;
            messages.add(ChatMessage(
              '📋 Whiteboard snapshot',
              false,
              DateFormat('hh:mm a').format(DateTime.now()),
              fileType: ChatFileType.image,
              fileBytes: imgBytes,
              fileName: 'whiteboard.png',
            ));
            notifyListeners();
            break;
          case 'chat_file_chunk':
            final cfId = map['id'] as String;
            final cfName = map['fileName'] as String;
            final cfSize = (map['fileSize'] as num).toInt();
            final cfChunkIdx = (map['chunkIndex'] as num).toInt();
            final cfTotalChunks = (map['totalChunks'] as num).toInt();
            final cfData = map['data'] as String;
            final cfSender = map['sender'] as String? ?? '';
            if (_seenMessageIds.contains(cfId)) break;
            _incomingChatFileChunks.putIfAbsent(cfId, () => List.filled(cfTotalChunks, null));
            _incomingChatFileNames[cfId] = cfName;
            _incomingChatFileSizes[cfId] = cfSize;
            _incomingChatSenderNames[cfId] = cfSender;
            _incomingChatFileChunks[cfId]![cfChunkIdx] = cfData;
            if (_incomingChatFileChunks[cfId]!.every((c) => c != null)) {
              _seenMessageIds.add(cfId);
              final fullB64 = _incomingChatFileChunks[cfId]!.join('');
              final cfBytes = base64Decode(fullB64);
              messages.add(ChatMessage(
                cfName,
                false,
                DateFormat('hh:mm a').format(DateTime.now()),
                id: cfId,
                senderName: cfSender,
                fileType: ChatMessage.detectType(cfName),
                fileBytes: cfBytes,
                fileName: cfName,
                fileSize: cfSize,
              ));
              _incomingChatFileChunks.remove(cfId);
              _incomingChatFileNames.remove(cfId);
              _incomingChatFileSizes.remove(cfId);
              _incomingChatSenderNames.remove(cfId);
              notifyListeners();
            }
            break;
          case 'chat_history':
            final historyList = map['messages'] as List;
            bool added = false;
            for (final msgMap in historyList) {
              final hId = msgMap['id'] as String? ?? '';
              if (hId.isNotEmpty && _seenMessageIds.contains(hId)) continue;
              if (hId.isNotEmpty) _seenMessageIds.add(hId);
              messages.add(ChatMessage(
                msgMap['text'] as String,
                false,
                msgMap['time'] as String,
                id: hId,
                senderName: msgMap['senderName'] as String? ?? '',
              ));
              added = true;
            }
            if (added) notifyListeners();
            break;
        }
      } else {
        // Fallback for raw text chat
        messages.add(ChatMessage(text, false, DateFormat('hh:mm a').format(DateTime.now())));
        notifyListeners();
      }
    } catch (e) {
      // Decode error, treat as raw message
      final text = utf8.decode(event.data);
      messages.add(ChatMessage(text, false, DateFormat('hh:mm a').format(DateTime.now())));
      notifyListeners();
    }
  }

  Future<void> sendChatMessage(String text) async {
    if (room?.localParticipant == null) return;
    final msgId = '${DateTime.now().millisecondsSinceEpoch}_local';
    final senderName = isDoctor ? 'Doctor' : 'Patient';
    messages.add(ChatMessage(text, true, DateFormat('hh:mm a').format(DateTime.now()),
        id: msgId, senderName: senderName));
    notifyListeners();
    try {
      final payload = json.encode({'type': 'chat', 'id': msgId, 'text': text, 'sender': senderName});
      await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
    } catch (e) {
      debugPrint('Failed to send chat message: $e');
    }
  }

  /// Sends a file (image, document, etc.) to all participants via chunked data channel.
  Future<void> sendFileMessage(String fileName, Uint8List bytes) async {
    const maxBytes = 25 * 1024 * 1024; // 25 MB
    if (bytes.length > maxBytes) throw Exception('File too large (max 25 MB).');

    final id = '${DateTime.now().millisecondsSinceEpoch}_file';
    final senderName = isDoctor ? 'Doctor' : 'Patient';
    final fileType = ChatMessage.detectType(fileName);

    // Add to local chat immediately
    messages.add(ChatMessage(
      fileName,
      true,
      DateFormat('hh:mm a').format(DateTime.now()),
      id: id,
      senderName: senderName,
      fileType: fileType,
      fileBytes: bytes,
      fileName: fileName,
      fileSize: bytes.length,
    ));
    notifyListeners();

    if (room?.localParticipant == null) return;

    // Chunk and send
    final b64 = base64Encode(bytes);
    const chunkSize = 12000;
    final totalChunks = (b64.length / chunkSize).ceil();
    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize).clamp(0, b64.length);
      try {
        final payload = json.encode({
          'type': 'chat_file_chunk',
          'id': id,
          'fileName': fileName,
          'fileSize': bytes.length,
          'chunkIndex': i,
          'totalChunks': totalChunks,
          'data': b64.substring(start, end),
          'sender': senderName,
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint('Failed to send chat file chunk $i: $e');
      }
    }
  }

  /// Sends existing text chat history, meeting description, and whiteboard background image to a newly joined participant.
  Future<void> _sendChatHistoryToNewParticipant() async {
    if (room?.localParticipant == null) return;
    try {
      if (meetingDescription != null && meetingDescription!.isNotEmpty) {
        final descPayload = json.encode({'type': 'meeting_description', 'description': meetingDescription});
        await room!.localParticipant!.publishData(utf8.encode(descPayload), reliable: true);
      }

      if (whiteboardBgImageBytes != null) {
        final b64 = base64Encode(whiteboardBgImageBytes!);
        const chunkSize = 12000;
        final totalChunks = (b64.length / chunkSize).ceil();
        for (int i = 0; i < totalChunks; i++) {
          final start = i * chunkSize;
          final end = (start + chunkSize).clamp(0, b64.length);
          final payload = json.encode({
            'type': 'wb_bg_chunk',
            'chunkIndex': i,
            'totalChunks': totalChunks,
            'data': b64.substring(start, end),
          });
          await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
        }
      }

      if (callTranscriptLog.isNotEmpty) {
        final payload = json.encode({
          'type': 'transcript_history',
          'log': callTranscriptLog,
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      }

      final textMsgs = messages.where((m) => m.fileType == ChatFileType.text).toList();
      if (textMsgs.isNotEmpty) {
        final history = textMsgs.map((m) => {
          'id': m.id,
          'text': m.text,
          'time': m.time,
          'senderName': m.senderName,
        }).toList();
        final payload = json.encode({'type': 'chat_history', 'messages': history});
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      }
    } catch (e) {
      debugPrint('Failed to send info to new participant: $e');
    }
  }

  Future<void> sendAiSummary(String summary) async {
    if (room?.localParticipant == null) return;
    try {
      final payload = json.encode({
        'type': 'ai_summary',
        'summary': summary,
      });
      await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
    } catch (e) {
      debugPrint("Failed to send AI summary: $e");
    }
  }

  /// Shares a whiteboard PNG snapshot to all participants via the data channel.
  /// The PNG is base64-encoded and sent as a 'whiteboard_image' message.
  /// Also adds it to the local chat as a sent image bubble.
  Future<void> sendWhiteboardImage(Uint8List pngBytes) async {
    // Add to local chat immediately as a sent image
    messages.add(ChatMessage(
      '📋 Whiteboard snapshot',
      true,
      DateFormat('hh:mm a').format(DateTime.now()),
      fileType: ChatFileType.image,
      fileBytes: pngBytes,
      fileName: 'whiteboard.png',
    ));
    notifyListeners();

    if (room?.localParticipant == null) return;
    try {
      final b64 = base64Encode(pngBytes);
      final payload = json.encode({'type': 'whiteboard_image', 'data': b64});
      // publishData has a max payload size — split if needed (LiveKit limit: ~65 KB per chunk)
      // For whiteboards, the PNG is typically small enough at reasonable canvas sizes.
      await room!.localParticipant!.publishData(
        utf8.encode(payload),
        reliable: true,
      );
    } catch (e) {
      debugPrint("Failed to send whiteboard image: $e");
    }
  }

  Future<void> startLocalStroke(double nx, double ny, Color color, double width) async {
    final newStroke = SharedStroke(
      points: [StrokePoint(nx, ny)],
      color: color,
      strokeWidth: width,
    );
    strokes.add(newStroke);
    _redoStack.clear(); // NEW: any new stroke clears the redo history
    notifyListeners();

    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'draw_start',
          'color': color.value,
          'strokeWidth': width,
          'x': nx,
          'y': ny,
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint("Failed to send draw_start: $e");
      }
    }
  }

  Future<void> updateLocalStroke(double nx, double ny) async {
    if (strokes.isNotEmpty) {
      strokes.last.points.add(StrokePoint(nx, ny));
      notifyListeners();
    }

    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'draw_update',
          'x': nx,
          'y': ny,
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: false); // Unreliable is fine for fast drawings
      } catch (e) {
        debugPrint("Failed to send draw_update: $e");
      }
    }
  }

  Future<void> endLocalStroke() async {
    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'draw_end',
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint("Failed to send draw_end: $e");
      }
    }
  }

  /// Undo: moves last stroke to redo stack and broadcasts to remote peers.
  Future<void> undoLastStroke() async {
    if (strokes.isEmpty) return;
    _redoStack.add(strokes.removeLast());
    notifyListeners();
    if (room?.localParticipant != null) {
      try {
        await room!.localParticipant!.publishData(
          utf8.encode(json.encode({'type': 'draw_undo'})),
          reliable: true,
        );
      } catch (e) {
        debugPrint("Failed to send draw_undo: $e");
      }
    }
  }

  /// Redo: restores last undone stroke and broadcasts to remote peers.
  Future<void> redoLastStroke() async {
    if (_redoStack.isEmpty) return;
    strokes.add(_redoStack.removeLast());
    notifyListeners();
    if (room?.localParticipant != null) {
      try {
        await room!.localParticipant!.publishData(
          utf8.encode(json.encode({'type': 'draw_redo'})),
          reliable: true,
        );
      } catch (e) {
        debugPrint("Failed to send draw_redo: $e");
      }
    }
  }

  Future<void> clearWhiteboard() async {
    strokes.clear();
    _redoStack.clear(); // NEW
    currentRemoteStroke = null;
    notifyListeners();

    if (room?.localParticipant != null) {
      try {
        final payload = json.encode({
          'type': 'draw_clear',
        });
        await room!.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      } catch (e) {
        debugPrint("Failed to send draw_clear: $e");
      }
    }
  }

  Future<void> toggleVideo() async {
    isVideoOn = !isVideoOn;
    notifyListeners();

    try {
      if (room?.localParticipant != null) {
        if (isVideoOn) {
          cameraError = null;
          await room!.localParticipant!.setCameraEnabled(true);
          final pubs = room!.localParticipant!.videoTrackPublications;
          if (pubs.isNotEmpty) {
            localVideoTrack = pubs.first.track;
            await localVideoTrack?.unmute();
          }
          cameraError = null;
        } else {
          await room!.localParticipant!.setCameraEnabled(false);
          localVideoTrack = null;
        }
      } else {
        if (!isVideoOn) {
          await localVideoTrack?.mute();
          await localVideoTrack?.stop();
          localVideoTrack?.dispose();
          localVideoTrack = null;
        } else {
          cameraError = null;
          localVideoTrack?.dispose();
          localVideoTrack = await LocalVideoTrack.createCameraTrack();
          cameraError = null;
        }
      }
      notifyListeners();
    } catch (e) {
      cameraError = e.toString();
      debugPrint("Toggle video error: $e");
      notifyListeners();
    }
  }

  Future<void> toggleAudio() async {
    isAudioOn = !isAudioOn;
    notifyListeners();

    try {
      if (room?.localParticipant != null) {
        await room!.localParticipant!.setMicrophoneEnabled(isAudioOn);
      } else {
        if (!isAudioOn) {
          await localAudioTrack?.mute();
        } else {
          localAudioTrack?.dispose();
          localAudioTrack = await LocalAudioTrack.create();
        }
      }
    } catch (e) {
      debugPrint("Toggle audio error: $e");
    }
  }

  Future<void> disconnect() async {
    if (!isConnected) return;
    
    try {
      SpeechTranslationService().stopListening();
      _listener?.dispose();
      _listener = null;
      await room?.disconnect();
      await room?.dispose();
      room = null;
    } catch (e) {
      debugPrint("Disconnect error: $e");
    } finally {
      isConnected = false;
      isConnecting = false;
      strokes.clear();
      _redoStack.clear();
      messages.clear();
      _seenMessageIds.clear();
      _incomingChatFileChunks.clear();
      _incomingChatFileNames.clear();
      _incomingChatFileSizes.clear();
      _incomingChatSenderNames.clear();
      currentRemoteStroke = null;
      notifyListeners();
    }
  }
}
