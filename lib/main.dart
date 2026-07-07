import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'components/virtual_waiting_room.dart';
import 'components/consultation_view.dart';
import 'components/dashboard_layout.dart';

void main() {
  runApp(const ChavApp());
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) {
        final qp = state.uri.queryParameters;
        return DashboardLayout(
          child: VirtualWaitingRoom(
            initialRoom: qp['room'],
            initialUrl: qp['url'],
            initialKey: qp['key'],
            initialSecret: qp['secret'],
          ),
        );
      },
    ),
        GoRoute(
      path: '/consultation',
      builder: (context, state) {
        final qp = state.uri.queryParameters;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        
        final url = qp['url'] ?? extra['url'] ?? 'ws://localhost:7880';
        final token = qp['token'] ?? extra['token'] ?? '';
        final room = qp['room'] ?? extra['room'] ?? '';
        final apiKey = qp['apiKey'] ?? extra['apiKey'] ?? '';
        final apiSecret = qp['apiSecret'] ?? extra['apiSecret'] ?? '';
        final initialVideoOn = qp['initialVideoOn'] ?? extra['initialVideoOn'] ?? 'true';
        final initialAudioOn = qp['initialAudioOn'] ?? extra['initialAudioOn'] ?? 'true';
        final publicUrl = qp['publicUrl'] ?? extra['publicUrl'] ?? '';
        final isDoctor = (qp['isDoctor'] ?? extra['isDoctor'] ?? 'false') == 'true';
        
        return DashboardLayout(
          child: ConsultationView(
            url: url,
            token: token,
            room: room,
            apiKey: apiKey,
            apiSecret: apiSecret,
            initialVideoOn: initialVideoOn == 'true',
            initialAudioOn: initialAudioOn == 'true',
            publicUrl: publicUrl,
            isDoctor: isDoctor,
          ),
        );
      },
     ),

  ],
);

class ChavApp extends StatelessWidget {
  const ChavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CHAV Flutter',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: Colors.indigo,
        colorScheme: const ColorScheme.dark(
          primary: Colors.indigoAccent,
          secondary: Colors.pinkAccent,
        ),
      ),
      routerConfig: _router,
    );
  }
}
