// @dart=3.3
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'dart:async';

// JS Interop definitions for SpeechRecognition API
@JS('SpeechRecognition')
extension type SpeechRecognition._(JSObject _) implements JSObject {
  external factory SpeechRecognition();
  external set continuous(bool value);
  external set interimResults(bool value);
  external set maxAlternatives(int value);
  external set lang(String value);
  external void start();
  external void stop();
  
  external set onstart(JSFunction value);
  external set onaudiostart(JSFunction value);
  external set onspeechstart(JSFunction value);
  external set onspeechend(JSFunction value);
  external set onaudioend(JSFunction value);
  external set onresult(JSFunction value);
  external set onend(JSFunction value);
  external set onnomatch(JSFunction value);
  external set onerror(JSFunction value);
}

@JS('webkitSpeechRecognition')
extension type WebkitSpeechRecognition._(JSObject _) implements SpeechRecognition {
  external factory WebkitSpeechRecognition();
}

class SpeechTranslationService {
  static final SpeechTranslationService _instance = SpeechTranslationService._internal();
  factory SpeechTranslationService() => _instance;
  SpeechTranslationService._internal();

  SpeechRecognition? _recognition;
  bool isListening = false;
  bool _isInit = false;
  String currentSpokenLanguage = 'en-US';
  
  // Callback when local speech is transcribed (String text, bool isFinal)
  Function(String, bool)? onLocalSpeech;
  
  // Callback when an error occurs
  Function(String)? onSpeechError;

  void init() {
    if (!kIsWeb || _isInit) return;
    try {
      // Check if SpeechRecognition or webkitSpeechRecognition is available
      final windowJs = web.window as JSObject;
      bool hasSpeechRecognition = windowJs.hasProperty('SpeechRecognition'.toJS).toDart;
      bool hasWebkitSpeechRecognition = windowJs.hasProperty('webkitSpeechRecognition'.toJS).toDart;

      if (!hasSpeechRecognition && !hasWebkitSpeechRecognition) {
        debugPrint('SpeechRecognition not supported in this browser.');
        if (onSpeechError != null) onSpeechError!('Speech Recognition is not supported in this browser.');
        return;
      }
      
      _recognition = hasSpeechRecognition ? SpeechRecognition() : WebkitSpeechRecognition();
      _recognition!.continuous = true;
      _recognition!.interimResults = true;
      _recognition!.maxAlternatives = 1;
      _recognition!.lang = currentSpokenLanguage;
      
      // Events
      _recognition!.onstart = (web.Event event) {
        debugPrint('Recognition started');
      }.toJS;

      _recognition!.onaudiostart = (web.Event event) {
        debugPrint('Audio started');
      }.toJS;
      
      _recognition!.onspeechstart = (web.Event event) {
        debugPrint('Speech Started');
      }.toJS;

      _recognition!.onspeechend = (web.Event event) {
        debugPrint('Speech Ended');
      }.toJS;

      _recognition!.onaudioend = (web.Event event) {
        debugPrint('Audio ended');
      }.toJS;

      _recognition!.onresult = (JSAny event) {
        try {
          final eventJs = event as JSObject;
          final resultsList = eventJs['results'] as JSObject?;
          if (resultsList != null) {
            final length = (resultsList['length'] as JSNumber).toDartInt;
            
            if (length > 0) {
              final lastResult = resultsList.getProperty((length - 1).toJS) as JSObject?;
              final isFinal = (lastResult?.getProperty('isFinal'.toJS) as JSBoolean?)?.toDart ?? false;
              
              final alternative = lastResult?.getProperty(0.toJS) as JSObject?;
              final transcript = (alternative?.getProperty('transcript'.toJS) as JSString?)?.toDart ?? '';
              
              debugPrint('Transcript received: "$transcript" (isFinal: $isFinal)');
              
              if (onLocalSpeech != null) {
                 onLocalSpeech!(transcript.trim(), isFinal);
              }
            }
          }
        } catch (e) {
          debugPrint("STT Parse Error: $e");
          if (onSpeechError != null) onSpeechError!("STT Error: $e");
        }
      }.toJS;
      
      _recognition!.onend = (web.Event event) {
        debugPrint('Recognition stopped');
        // Auto-restart if we are supposed to be listening
        if (isListening) {
          try {
            debugPrint('Restarting recognition...');
            _recognition!.start();
          } catch (e) {
            debugPrint('SpeechRecognition restart error: $e');
          }
        }
      }.toJS;

      _recognition!.onnomatch = (web.Event event) {
        debugPrint('No match found');
        if (onSpeechError != null) onSpeechError!('No speech detected.');
      }.toJS;

      _recognition!.onerror = (JSAny event) {
        final error = ((event as JSObject)['error'] as JSString?)?.toDart;
        debugPrint('SpeechRecognition error: $error');
        
        if (error == 'not-allowed') {
          stopListening();
          if (onSpeechError != null) onSpeechError!('Microphone permission denied.');
        } else if (error == 'language-not-supported' || error == 'service-not-allowed') {
          stopListening();
          if (onSpeechError != null) onSpeechError!('Speech recognition is not supported for the selected language in this browser.');
        } else if (error == 'network') {
          stopListening();
          if (onSpeechError != null) onSpeechError!('Network error occurred during speech recognition.');
        } else if (error == 'aborted') {
          // Typically happens when stopped manually, no need to show an error message
          stopListening();
        } else if (error == 'no-speech') {
          // just ignore or notify
          debugPrint('No speech heard...');
        } else {
          stopListening();
          if (onSpeechError != null) onSpeechError!('Unable to access microphone: $error');
        }
      }.toJS;
      
      _isInit = true;
    } catch (e) {
      debugPrint('SpeechRecognition initialization error: $e');
      if (onSpeechError != null) onSpeechError!('Browser does not support Web Speech API.');
    }
  }

  void startListening() {
    if (!_isInit) init();
    if (isListening) return; // Prevent duplicate instances
    isListening = true;
    try {
      _recognition?.start();
    } catch (e) {
      debugPrint('SpeechRecognition start error: $e');
    }
  }

  void stopListening() {
    isListening = false;
    try {
      _recognition?.stop();
    } catch (e) {
      debugPrint('SpeechRecognition stop error: $e');
    }
  }

  void setSpokenLanguage(String langCode) {
    if (currentSpokenLanguage == langCode) return;
    currentSpokenLanguage = langCode;
    
    if (_recognition != null) {
      bool wasListening = isListening;
      stopListening();
      
      // Destroy and recreate the recognition object to apply the language change reliably
      Future.delayed(const Duration(milliseconds: 300), () {
        _isInit = false; // Force re-init
        if (wasListening) {
          startListening();
        }
      });
    }
  }

  Future<String> translateText(String text, String targetLang) async {
    if (text.trim().isEmpty) return text;
    if (targetLang.toLowerCase() == 'en') {
      return text;
    }

    // 1. Try our Smart Server translation proxy (port 3000)
    try {
      String host = 'localhost';
      if (kIsWeb) {
        final loc = web.window.location.hostname;
        if (loc.isNotEmpty) {
          host = loc;
        }
      }
      final serverUrl = 'http://$host:3000/api/translate?text=${Uri.encodeComponent(text)}&target=${Uri.encodeComponent(targetLang)}';
      final response = await http.get(Uri.parse(serverUrl)).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final translated = data['translated']?.toString();
        if (translated != null && translated.trim().isNotEmpty) {
          debugPrint('Translation completed via server: "$translated"');
          return translated;
        }
      }
    } catch (e) {
      debugPrint("Server translation proxy error: $e");
    }

    // 2. Direct fallback to MyMemory API (with CORS support)
    try {
      final mmUrl = 'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=autodetect|${Uri.encodeComponent(targetLang)}';
      final response = await http.get(Uri.parse(mmUrl)).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final translated = data['responseData']?['translatedText']?.toString();
        if (translated != null && translated.trim().isNotEmpty) {
          debugPrint('Translation completed via MyMemory: "$translated"');
          return translated;
        }
      }
    } catch (e) {
      debugPrint("MyMemory fallback error: $e");
    }

    return text;
  }
}
