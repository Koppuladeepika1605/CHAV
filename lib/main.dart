import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'components/role_selection.dart';
import 'components/virtual_waiting_room.dart';
import 'components/consultation_view.dart';
import 'shared_state.dart';
import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const ChavApp());
}

// Custom page transition — fade + slight slide up
CustomTransitionPage<T> _fadePage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final slideAnim = Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(fade);
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slideAnim, child: child),
      );
    },
  );
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) {
        return const RoleSelection();
      },
    ),
    GoRoute(
      path: '/doctor',
      builder: (context, state) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: VirtualWaitingRoom(
            initialRoom: state.uri.queryParameters['room'],
            initialUrl: state.uri.queryParameters['url'],
            initialKey: state.uri.queryParameters['apiKey'],
            initialSecret: state.uri.queryParameters['apiSecret'],
            initialDesc: state.uri.queryParameters['desc'],
            isDoctor: true,
          ),
        );
      },
    ),
    GoRoute(
      path: '/patient',
      builder: (context, state) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: VirtualWaitingRoom(
            initialRoom: state.uri.queryParameters['room'],
            initialUrl: state.uri.queryParameters['url'],
            initialKey: state.uri.queryParameters['apiKey'],
            initialSecret: state.uri.queryParameters['apiSecret'],
            initialDesc: state.uri.queryParameters['desc'],
            isDoctor: false,
          ),
        );
      },
    ),
    GoRoute(
      path: '/consultation',
      pageBuilder: (context, state) {
        final url = state.uri.queryParameters['url'];
        final token = state.uri.queryParameters['token'];
        final isDoctorStr = state.uri.queryParameters['isDoctor'];
        final desc = state.uri.queryParameters['desc'];
        debugPrint('ROUTER PARSED isDoctor: $isDoctorStr from URI: ${state.uri}');
        final isDoctor = isDoctorStr == 'true';
        
        final room = state.uri.queryParameters['room'];
        
        // Setup the meeting controller for our new architecture
        MeetingController().setRoleAndSummary(isDoctor: isDoctor, meetingDescriptionText: desc);

        return _fadePage(
          context: context,
          state: state,
          child: Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: ConsultationView(
              url: url,
              token: token,
              room: room ?? 'my-consultation-room',
            ),
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
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: Colors.indigo,
        colorScheme: const ColorScheme.dark(
          primary: Colors.indigoAccent,
          secondary: Colors.pinkAccent,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      routerConfig: _router,
    );
  }
}
