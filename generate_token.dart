import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

void main() {
  final jwt = JWT({
    'iss': 'devkey',
    'sub': 'doctor_123',
    'nbf': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'exp': (DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000),
    'video': {
      'room': 'my-consultation-room',
      'roomJoin': true,
      'canPublish': true,
      'canSubscribe': true,
    }
  });

  // Sign it with the default dev secret provided by LiveKit Server
  final token = jwt.sign(SecretKey('secret'));
  
  print('\n=== YOUR SECURE LIVEKIT TOKEN ===\n');
  print(token);
  print('\n=================================\n');
  print('Copy the token above and use it in your app to connect to the server!');
}
