import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';

class RoleSelection extends StatelessWidget {
  const RoleSelection({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated Deep Space Gradient Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .custom(duration: 5000.ms, builder: (context, value, child) {
               return Container(
                 decoration: BoxDecoration(
                   gradient: RadialGradient(
                     center: Alignment(value * 0.2, value * 0.2),
                     radius: 1.5,
                     colors: const [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                   ),
                 ),
               );
             }),
          ),
          
          // Glassmorphic Card
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1E3F96).withOpacity(0.1),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF1E3F96).withOpacity(0.2), blurRadius: 40, spreadRadius: 10)
                          ]
                        ),
                        child: const Icon(Icons.local_hospital_rounded, size: 70, color: Color(0xFF1E3F96))
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scaleXY(end: 1.05, duration: 2000.ms, curve: Curves.easeInOut),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Select Your Role',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Join the secure teleconsultation platform',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                      const SizedBox(height: 48),
                      
                      // Doctor Button
                      ElevatedButton.icon(
                        onPressed: () => context.go('/doctor'),
                        icon: const Icon(Icons.medical_services, size: 24),
                        label: const Text('Join as Doctor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: const Color(0xFF1E3F96),
                          foregroundColor: Colors.white,
                          elevation: 10,
                          shadowColor: const Color(0xFF1E3F96).withOpacity(0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
                      
                      const SizedBox(height: 20),
                      
                      // Patient Button
                      ElevatedButton.icon(
                        onPressed: () => context.go('/patient'),
                        icon: const Icon(Icons.personal_injury, size: 24),
                        label: const Text('Join as Patient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: Colors.white.withOpacity(0.05),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          side: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                      ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 800.ms).scaleXY(begin: 0.95),
        ],
      ),
    );
  }
}
