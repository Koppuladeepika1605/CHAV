import 'package:flutter/material.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          // Search Bar
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.white54, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search patients, appointments...',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(width: 24),
          
          // Context Metrics
          Row(
            children: [
              _buildMetric(Icons.calendar_today, '12', Colors.white54),
              const SizedBox(width: 12),
              _buildMetric(Icons.people, '3', Colors.pinkAccent),
              const SizedBox(width: 12),
              _buildMetric(Icons.video_call, '2', Colors.indigoAccent),
              const SizedBox(width: 12),
              _buildMetric(Icons.access_time, '6', Colors.greenAccent),
            ],
          ),
          
          const SizedBox(width: 24),
          
          // Active Patient
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Text('Maria Santos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Text('in now', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
              ],
            ),
          ),
          
          const SizedBox(width: 24),
          
          // Actions
          Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications, color: Colors.white54),
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.pinkAccent, shape: BoxShape.circle),
                  child: const Text('3', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          const Icon(Icons.settings, color: Colors.white54),
          
          const SizedBox(width: 24),
          
          // Profile
          const Row(
            children: [
              CircleAvatar(backgroundColor: Colors.indigoAccent, child: Text('DR', style: TextStyle(color: Colors.white))),
              SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dr. Amanulla Belg', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('General Physician', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
              SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down, color: Colors.white54),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMetric(IconData icon, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
