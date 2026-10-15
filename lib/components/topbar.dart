import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class TopBar extends StatefulWidget {
  const TopBar({super.key});

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _shakeController;
  bool _searchFocused = false;

  final _metrics = [
    {'icon': Icons.calendar_today_rounded, 'value': 12, 'color': Colors.white54},
    {'icon': Icons.people_rounded,         'value': 3,  'color': Colors.pinkAccent},
    {'icon': Icons.video_call_rounded,     'value': 2,  'color': Colors.indigoAccent},
    {'icon': Icons.access_time_rounded,    'value': 6,  'color': Colors.greenAccent},
  ];

  @override
  void initState() {
    super.initState();

    // Breathing animation for the live-dot
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Gentle periodic shake for the notification bell
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    // Shake every 6 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _runBellShake();
    });
  }

  void _runBellShake() async {
    if (!mounted) return;
    await _shakeController.forward();
    _shakeController.reset();
    // Repeat
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) _runBellShake();
    });
  }

  @override
  void dispose() {
    _breathController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: [
          // ── Animated Search Bar ─────────────────────────────────────────
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _searchFocused
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: _searchFocused
                    ? Border.all(color: Colors.indigoAccent.withValues(alpha: 0.5))
                    : null,
                boxShadow: _searchFocused
                    ? [
                        BoxShadow(
                          color: Colors.indigoAccent.withValues(alpha: 0.15),
                          blurRadius: 12,
                        )
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _searchFocused ? 0.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.search_rounded,
                      color: _searchFocused ? Colors.indigoAccent : Colors.white54,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onTap: () => setState(() => _searchFocused = true),
                      onTapOutside: (_) => setState(() => _searchFocused = false),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Search patients, appointments...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05),

          const SizedBox(width: 24),

          // ── Animated Metrics ────────────────────────────────────────────
          Row(
            children: _metrics.asMap().entries.map((entry) {
              final idx = entry.key;
              final m = entry.value;
              final target = m['value'] as int;
              final color = m['color'] as Color;
              final icon = m['icon'] as IconData;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: target),
                  duration: Duration(milliseconds: 800 + idx * 150),
                  curve: Curves.easeOutCubic,
                  builder: (_, val, __) => Row(
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 5),
                      Text(
                        '$val',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(delay: (idx * 100 + 200).ms, duration: 400.ms)
                    .slideY(begin: 0.3, delay: (idx * 100 + 200).ms, duration: 400.ms),
              );
            }).toList(),
          ),

          // ── Live Patient Badge ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Text(
                  'Maria Santos',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 8),
                // Breathing live dot
                AnimatedBuilder(
                  animation: _breathController,
                  builder: (_, __) => Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.greenAccent.withValues(
                            alpha: 0.6 + _breathController.value * 0.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.greenAccent.withValues(
                                alpha: _breathController.value * 0.6,
                              ),
                              blurRadius: 6,
                              spreadRadius: 1,
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'in now',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(delay: 300.ms, duration: 500.ms)
              .slideX(begin: 0.05, delay: 300.ms),

          const SizedBox(width: 20),

          // ── Notification Bell ───────────────────────────────────────────
          AnimatedBuilder(
            animation: _shakeController,
            builder: (_, child) {
              final shake = (_shakeController.value < 0.5
                      ? _shakeController.value
                      : 1 - _shakeController.value) *
                  2;
              return Transform.rotate(
                angle: shake * 0.2,
                child: child,
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.notifications_rounded, color: Colors.white54, size: 24),
                Positioned(
                  right: -5,
                  top: -5,
                  child: AnimatedBuilder(
                    animation: _breathController,
                    builder: (_, __) => Transform.scale(
                      scale: 1.0 + _breathController.value * 0.1,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.pinkAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.pinkAccent.withValues(
                                  alpha: _breathController.value * 0.6),
                              blurRadius: 6,
                            )
                          ],
                        ),
                        child: const Text(
                          '3',
                          style: TextStyle(
                            color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(width: 16),

          // ── Settings ────────────────────────────────────────────────────
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 0),
              duration: const Duration(milliseconds: 300),
              builder: (_, val, child) => Transform.rotate(angle: val, child: child),
              child: const Icon(Icons.settings_rounded, color: Colors.white54, size: 22),
            ),
          ).animate().fadeIn(delay: 450.ms),

          const SizedBox(width: 24),

          // ── Profile ─────────────────────────────────────────────────────
          Row(
            children: [
              // Avatar with subtle glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigoAccent.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ],
                ),
                child: const CircleAvatar(
                  backgroundColor: Colors.indigoAccent,
                  child: Text(
                    'DR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dr. Amanulla Belg',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Text(
                    'General Physician',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 20),
            ],
          )
              .animate()
              .fadeIn(delay: 500.ms, duration: 500.ms)
              .slideX(begin: 0.05, delay: 500.ms),
        ],
      ),
    );
  }
}
