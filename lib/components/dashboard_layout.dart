import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'sidebar.dart';
import 'topbar.dart';

class DashboardLayout extends StatelessWidget {
  final Widget child;

  const DashboardLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Updated to match global theme background
      body: Row(
        children: [
          const Sidebar(),
          Expanded(
            child: Column(
              children: [
                const TopBar(),
                Expanded(
                  child: child
                      .animate()
                      .fadeIn(duration: 450.ms, curve: Curves.easeOutCubic)
                      .slideY(begin: 0.03, duration: 450.ms, curve: Curves.easeOutCubic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
