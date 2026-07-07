import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

String generateLiveKitToken({
  required String roomName,
  required String participantName,
  String apiKey = 'devkey',      // Your in-house LiveKit Key (from livekit.yaml)
  String apiSecret = 'secret',   // Your in-house LiveKit Secret
}) {
  final jwt = JWT({
    'iss': apiKey,
    'sub': participantName,
    'nbf': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'exp': (DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000),
    'video': {
      'room': roomName,
      'roomJoin': true,
      'canPublish': true,
      'canSubscribe': true,
    }
  });

  return jwt.sign(SecretKey(apiSecret));
}
 