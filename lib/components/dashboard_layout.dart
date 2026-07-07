import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DashboardLayout extends StatelessWidget {
  final Widget child;

  const DashboardLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: Container(
        color: const Color(0xFF0B1120),
        child: child,
      ).animate().fadeIn(duration: 600.ms),
    );
  }
}
