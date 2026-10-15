import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with TickerProviderStateMixin {
  int? _hoveredIndex;
  bool _collapsed = false;
  late AnimationController _pulseController;

  final List<Map<String, dynamic>> _menuGroups = [
    {
      'title': 'OVERVIEW',
      'items': [
        {'name': 'Dashboard', 'icon': Icons.dashboard_rounded, 'badge': 0},
        {'name': 'Analytics', 'icon': Icons.bar_chart_rounded, 'badge': 0},
        {'name': 'Patient Overview', 'icon': Icons.people_rounded, 'badge': 0},
      ]
    },
    {
      'title': 'CLINICAL SERVICES',
      'items': [
        {'name': 'Appointments', 'icon': Icons.calendar_today_rounded, 'badge': 8},
        {'name': 'Health Records', 'icon': Icons.description_rounded, 'badge': 0},
        {'name': 'Prescriptions', 'icon': Icons.medication_rounded, 'badge': 0},
        {'name': 'Lab Results', 'icon': Icons.science_rounded, 'badge': 0},
        {'name': 'Vaccinations', 'icon': Icons.vaccines_rounded, 'badge': 0},
        {'name': 'Telemedicine', 'icon': Icons.video_call_rounded, 'badge': 0},
        {'name': 'Consultation', 'icon': Icons.medical_services_rounded, 'badge': 0, 'active': true},
      ]
    },
    {
      'title': 'MANAGEMENT',
      'items': [
        {'name': 'Staff', 'icon': Icons.badge_rounded, 'badge': 0},
        {'name': 'Task Board', 'icon': Icons.check_box_rounded, 'badge': 0},
        {'name': 'Vitals Monitor', 'icon': Icons.monitor_heart_rounded, 'badge': 0},
        {'name': 'Patients List', 'icon': Icons.list_alt_rounded, 'badge': 0},
      ]
    }
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      width: _collapsed ? 72 : 260,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Logo ─────────────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            padding: EdgeInsets.all(_collapsed ? 16 : 24),
            child: _collapsed
                ? Center(
                    child: const Text('P', style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: Colors.pinkAccent,
                    )).animate().fadeIn(delay: 150.ms),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                          children: [
                            const TextSpan(text: 'Pra', style: TextStyle(color: Colors.white)),
                            const TextSpan(text: 'CH', style: TextStyle(color: Colors.pinkAccent)),
                            const TextSpan(text: 'tiz', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ).animate().fadeIn(delay: 50.ms).slideX(begin: -0.1),
                      const SizedBox(height: 4),
                      const Text(
                        'A Product by CHAV',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ).animate().fadeIn(delay: 150.ms),
                    ],
                  ),
          ),

          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),

          // ── Menu ─────────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: _collapsed ? 8 : 12),
              children: _buildMenuWithStagger(),
            ),
          ),

          // ── Footer ───────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    mainAxisAlignment: _collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      AnimatedRotation(
                        turns: _collapsed ? 0.5 : 0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        child: const Icon(Icons.chevron_left_rounded, color: Colors.white54, size: 20),
                      ),
                      if (!_collapsed) ...[
                        const SizedBox(width: 8),
                        const Text('Collapse', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().slideX(begin: -0.05, duration: 400.ms, curve: Curves.easeOutCubic).fadeIn(duration: 400.ms);
  }

  List<Widget> _buildMenuWithStagger() {
    final widgets = <Widget>[];
    int globalIdx = 0;

    for (final group in _menuGroups) {
      final items = group['items'] as List<Map<String, dynamic>>;

      // Group title
      if (!_collapsed) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 20, bottom: 6),
            child: Text(
              group['title'] as String,
              style: const TextStyle(
                color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8,
              ),
            ),
          ).animate().fadeIn(delay: (globalIdx * 30 + 100).ms),
        );
      } else {
        widgets.add(const SizedBox(height: 12));
      }

      for (final item in items) {
        final delay = (globalIdx * 40 + 80).ms;
        final itemIndex = globalIdx;
        final isActive = item['active'] == true;
        final badge = item['badge'] as int;

        widgets.add(
          _buildMenuItem(
            item: item,
            isActive: isActive,
            badge: badge,
            delay: delay,
            itemIndex: itemIndex,
          ),
        );
        globalIdx++;
      }
    }
    return widgets;
  }

  Widget _buildMenuItem({
    required Map<String, dynamic> item,
    required bool isActive,
    required int badge,
    required Duration delay,
    required int itemIndex,
  }) {
    final isHovered = _hoveredIndex == itemIndex;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = itemIndex),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.indigoAccent.withValues(alpha: 0.15)
              : isHovered
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(color: Colors.indigoAccent.withValues(alpha: 0.35))
              : null,
        ),
        child: _collapsed
            ? Tooltip(
                message: item['name'] as String,
                child: _buildCollapsedItem(item, isActive, badge, itemIndex),
              )
            : _buildExpandedItem(item, isActive, badge, itemIndex),
      ),
    )
        .animate()
        .fadeIn(delay: delay, duration: 350.ms)
        .slideX(begin: -0.08, delay: delay, duration: 350.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildCollapsedItem(Map<String, dynamic> item, bool isActive, int badge, int itemIndex) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            item['icon'] as IconData,
            color: isActive ? Colors.indigoAccent : Colors.white54,
            size: 20,
          ),
        ),
        if (badge > 0)
          Positioned(
            right: -2, top: -2,
            child: _buildBadge(badge),
          ),
      ],
    );
  }

  Widget _buildExpandedItem(Map<String, dynamic> item, bool isActive, int badge, int itemIndex) {
    return ListTile(
      leading: Icon(
        item['icon'] as IconData,
        color: isActive ? Colors.indigoAccent : Colors.white54,
        size: 20,
      ),
      title: Text(
        item['name'] as String,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white70,
          fontSize: 13.5,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: badge > 0 ? _buildBadge(badge) : null,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () {},
    );
  }

  Widget _buildBadge(int count) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) => Transform.scale(
        scale: 1.0 + _pulseController.value * 0.12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.pinkAccent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.pinkAccent.withValues(alpha: _pulseController.value * 0.5),
                blurRadius: 8,
                spreadRadius: 1,
              )
            ],
          ),
          child: Text(
            '$count',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
