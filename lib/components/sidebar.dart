import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final menuGroups = [
      {
        'title': 'OVERVIEW',
        'items': [
          {'name': 'Dashboard', 'icon': Icons.dashboard, 'badge': 0},
          {'name': 'Analytics', 'icon': Icons.bar_chart, 'badge': 0},
          {'name': 'Patient Overview', 'icon': Icons.people, 'badge': 0},
        ]
      },
      {
        'title': 'CLINICAL SERVICES',
        'items': [
          {'name': 'Appointments', 'icon': Icons.calendar_today, 'badge': 8},
          {'name': 'Health Records', 'icon': Icons.description, 'badge': 0},
          {'name': 'Prescriptions', 'icon': Icons.medication, 'badge': 0},
          {'name': 'Lab Results', 'icon': Icons.science, 'badge': 0},
          {'name': 'Vaccinations', 'icon': Icons.vaccines, 'badge': 0},
          {'name': 'Telemedicine', 'icon': Icons.video_call, 'badge': 0},
          {'name': 'Consultation', 'icon': Icons.medical_services, 'badge': 0, 'active': true},
        ]
      },
      {
        'title': 'MANAGEMENT',
        'items': [
          {'name': 'Staff', 'icon': Icons.badge, 'badge': 0},
          {'name': 'Task Board', 'icon': Icons.check_box, 'badge': 0},
          {'name': 'Vitals Monitor', 'icon': Icons.monitor_heart, 'badge': 0},
          {'name': 'Patients List', 'icon': Icons.list_alt, 'badge': 0},
        ]
      }
    ];

    return Container(
      width: 260,
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo Area
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(text: 'Pra', style: TextStyle(color: Colors.white)),
                      TextSpan(text: 'CH', style: TextStyle(color: Colors.pinkAccent)),
                      TextSpan(text: 'tiz', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                SizedBox(height: 4),
                Text('A Product by CHAV', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          
          // Menu Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: menuGroups.length,
              itemBuilder: (context, index) {
                final group = menuGroups[index];
                final items = group['items'] as List<Map<String, dynamic>>;
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 24, bottom: 8),
                      child: Text(
                        group['title'] as String,
                        style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...items.map((item) {
                      final isActive = item['active'] == true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.indigoAccent.withOpacity(0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isActive ? Border.all(color: Colors.indigoAccent.withOpacity(0.3)) : null,
                        ),
                        child: ListTile(
                          leading: Icon(item['icon'] as IconData, color: isActive ? Colors.indigoAccent : Colors.white54, size: 20),
                          title: Text(
                            item['name'] as String,
                            style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
                          ),
                          trailing: item['badge'] != 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.pinkAccent, borderRadius: BorderRadius.circular(12)),
                                  child: Text('${item['badge']}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                )
                              : null,
                          dense: true,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onTap: () {},
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white12))),
            child: Row(
              children: [
                const Icon(Icons.chevron_left, color: Colors.white54, size: 20),
                const SizedBox(width: 8),
                const Text('Collapse', style: TextStyle(color: Colors.white54)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
