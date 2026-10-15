import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../shared_state.dart';

class ClinicalPanel extends StatefulWidget {
  const ClinicalPanel({super.key});

  @override
  State<ClinicalPanel> createState() => _ClinicalPanelState();
}

class _ClinicalPanelState extends State<ClinicalPanel> {
  int activeTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C1322), // Deep dark navy slate
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Patient Info
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111A2C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB), // Vibrant blue avatar
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text('JC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('James Carter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E3A8A), // Dark blue badge
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'P-20240125-001', 
                                style: TextStyle(color: Color(0xFF93C5FD), fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('Pain near left chest, Pelvic salinity', style: TextStyle(color: Colors.white60, fontSize: 11.5)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildTag('28 Yrs - Male', color: const Color(0xFF162032), textColor: Colors.white70),
                            _buildTag('O+ve', color: const Color(0xFF052E16), textColor: const Color(0xFF22C55E), borderColor: const Color(0xFF22C55E).withOpacity(0.4)),
                            _buildTag('Cardiology', color: const Color(0xFF1E3A8A), textColor: const Color(0xFF93C5FD)),
                            _buildTag('25 Jan 2025, 07:00 AM', color: const Color(0xFF162032), textColor: Colors.white70),
                            _buildTag('Online Consultation', color: const Color(0xFF052E16), textColor: const Color(0xFF22C55E), borderColor: const Color(0xFF22C55E).withOpacity(0.4)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  'Vitals', 
                  'Complaint', 
                  'Diagnosis', 
                  'Medications', 
                  'Investigation', 
                  'Follow-Up', 
                  'Invoice', 
                  'Meeting Description'
                ].asMap().entries.map((entry) {
                  final idx = entry.key;
                  final title = entry.value;
                  final isActive = idx == activeTabIndex;
                  return GestureDetector(
                    onTap: () => setState(() => activeTabIndex = idx),
                    child: Container(
                      margin: const EdgeInsets.only(right: 28),
                      padding: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: isActive ? const Color(0xFF22C55E) : Colors.transparent, width: 2.5),
                        ),
                      ),
                      child: Text(
                        title,
                        style: TextStyle(
                          color: isActive ? const Color(0xFF22C55E) : Colors.white54,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Content
          Expanded(
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, {Color? color, Color? textColor, Color? borderColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? const Color(0xFF162032),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? Colors.white12),
      ),
      child: Text(text, style: TextStyle(color: textColor ?? Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildVitalsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'VITALS & BIOMETRICS', 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = 2;
              double childAspectRatio = 1.35;
              double valueFontSize = 32.0;
              
              if (constraints.maxWidth > 1100) {
                crossAxisCount = 6;
                childAspectRatio = 1.0;
                valueFontSize = 42.0;
              } else if (constraints.maxWidth > 800) {
                crossAxisCount = 3;
                childAspectRatio = 1.4;
              } else if (constraints.maxWidth > 400) {
                crossAxisCount = 2;
                childAspectRatio = 1.35;
              }
              
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                children: [
                  VitalCard(title: 'BLOOD\nPRESSURE', value: '120/80', unit: 'mmHg', colors: const [Color(0xFF3B82F6), Color(0xFF60A5FA)], valueFontSize: valueFontSize),
                  VitalCard(title: 'HEART RATE', value: '72', unit: 'bpm', colors: const [Color(0xFF22C55E), Color(0xFF4ADE80)], valueFontSize: valueFontSize),
                  VitalCard(title: 'TEMPERATURE', value: '98.6', unit: '°F', colors: const [Color(0xFF3B82F6), Color(0xFF60A5FA)], valueFontSize: valueFontSize),
                  VitalCard(title: 'SPO2', value: '98', unit: '%', colors: const [Color(0xFF22C55E), Color(0xFF4ADE80)], valueFontSize: valueFontSize),
                  VitalCard(title: 'RESP. RATE', value: '18', unit: 'br/min', colors: const [Color(0xFF22C55E), Color(0xFF4ADE80)], valueFontSize: valueFontSize),
                  VitalCard(title: 'WEIGHT', value: '74', unit: 'kg', colors: const [Color(0xFF22C55E), Color(0xFF4ADE80)], valueFontSize: valueFontSize),
                ],
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (activeTabIndex) {
      case 0:
        return _buildVitalsTab();
      case 1:
        return _buildComplaintTab();
      case 2:
        return _buildDiagnosisTab();
      case 3:
        return _buildMedicationsTab();
      case 4:
        return _buildInvestigationTab();
      case 5:
        return _buildFollowUpTab();
      case 6:
        return _buildInvoiceTab();
      case 7:
        return _buildMeetingDescriptionTab();
      default:
        return const Center(child: Text('Data Unavailable', style: TextStyle(color: Colors.white54)));
    }
  }

  Widget _buildComplaintTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CHIEF COMPLAINTS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          _buildComplaintItem('Chest Pain', 'Severe tightness in the left thoracic region, radiation to left shoulder, onset 3 hours ago.'),
          _buildComplaintItem('Shortness of Breath', 'Dyspnea reported during mild exertion or walking up stairs.'),
          _buildComplaintItem('Dizziness', 'Mild lightheadedness experienced during episodes of chest tightness.'),
        ],
      ),
    );
  }

  Widget _buildComplaintItem(String symptom, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(symptom, style: const TextStyle(color: Colors.pinkAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildDiagnosisTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CLINICAL DIAGNOSIS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          _buildDiagnosisItem('I20.9', 'Angina Pectoris, Unspecified', 'Primary', 'Stable angina pectoris provoked by physical exertion or acute stress.'),
          _buildDiagnosisItem('I10', 'Essential (Primary) Hypertension', 'Secondary', 'Long-standing blood pressure elevation, currently managed on pharmacotherapy.'),
        ],
      ),
    );
  }

  Widget _buildDiagnosisItem(String code, String desc, String type, String notes) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(code, style: const TextStyle(color: Colors.indigoAccent, fontSize: 15, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: type == 'Primary' ? Colors.redAccent.withOpacity(0.2) : Colors.white10, borderRadius: BorderRadius.circular(4)),
                child: Text(type, style: TextStyle(color: type == 'Primary' ? Colors.redAccent : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(desc, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(notes, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3)),
        ],
      ),
    );
  }

  Widget _buildMedicationsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PRESCRIPTION LOG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          _buildMedicationItem('Aspirin 81 mg', 'Oral Tablet', '1 Tablet Daily (Morning)', 'Take with food.', '30 Days'),
          _buildMedicationItem('Atorvastatin 20 mg', 'Oral Tablet', '1 Tablet Daily (Night)', 'Avoid grapefruit juice.', '90 Days'),
          _buildMedicationItem('Nitroglycerin 0.4 mg', 'Sublingual Tablet', '1 Tablet q5m prn', 'For acute chest pain. Max 3 doses.', 'As Needed'),
        ],
      ),
    );
  }

  Widget _buildMedicationItem(String name, String route, String freq, String inst, String dur) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(dur, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Route: $route  |  Frequency: $freq', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text('Instructions: $inst', style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildInvestigationTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ORDERED INVESTIGATIONS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          _buildInvestigationItem('12-Lead ECG', 'Cardiology Lab', 'Urgent', 'To evaluate ST-segment transitions during chest pain episodes.'),
          _buildInvestigationItem('Lipid Profile', 'Biochemistry Lab', 'Routine', 'Fasting lipid panel to assess cardiovascular risk profile.'),
          _buildInvestigationItem('Serum Troponin I', 'Emergency Lab', 'Stat', 'To rule out myocardial injury / infarction.'),
        ],
      ),
    );
  }

  Widget _buildInvestigationItem(String test, String dept, String priority, String purpose) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(test, style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: priority == 'Stat' ? Colors.redAccent.withOpacity(0.2) : Colors.white10, borderRadius: BorderRadius.circular(4)),
                child: Text(priority, style: TextStyle(color: priority == 'Stat' ? Colors.redAccent : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Dept: $dept', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text('Purpose: $purpose', style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3)),
        ],
      ),
    );
  }

  Widget _buildFollowUpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FOLLOW-UP SCHEDULE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.indigoAccent, size: 18),
                    SizedBox(width: 10),
                    Text('Next Visit: 08 Feb 2025, 10:00 AM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                SizedBox(height: 12),
                Text('Instructions:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                SizedBox(height: 6),
                Text('1. Bring latest ECG printout and blood lipid test reports.\n2. Please log blood pressure measurements twice daily.\n3. Return immediately to ER if chest pain occurs and does not subside after 1 dose of sublingual nitroglycerin.',
                  style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BILLING OVERVIEW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
            child: Column(
              children: [
                _buildInvoiceRow('Consultation Fee', '\$120.00'),
                _buildInvoiceRow('Telemedicine Surcharge', '\$15.00'),
                _buildInvoiceRow('Digital Charting Surcharge', '\$15.00'),
                const Divider(color: Colors.white24, height: 24),
                _buildInvoiceRow('Total Amount', '\$150.00', isTotal: true),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Status', style: TextStyle(color: Colors.white60, fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                      child: const Text('PAID VIA INS', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceRow(String item, String price, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(item, style: TextStyle(color: isTotal ? Colors.white : Colors.white70, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, fontSize: isTotal ? 15 : 13)),
          Text(price, style: TextStyle(color: isTotal ? Colors.indigoAccent : Colors.white, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, fontSize: isTotal ? 16 : 13)),
        ],
      ),
    );
  }

  Widget _buildMeetingDescriptionTab() {
    return AnimatedBuilder(
      animation: MeetingController(),
      builder: (context, _) {
        final desc = MeetingController().meetingDescription;
        final logs = MeetingController().callTranscriptLog;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_outlined, color: Colors.indigoAccent, size: 20),
                  const SizedBox(width: 10),
                  const Text('MEETING DESCRIPTION & TRANSCRIPT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.mic, color: Colors.greenAccent, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Automatic Background Speech Recording Active',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      desc != null && desc.isNotEmpty ? desc : 'Speech is being recorded in the background automatically...',
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                    ),
                    if (logs.isNotEmpty) ...[
                      const Divider(color: Colors.white12, height: 32),
                      const Text(
                        'Live Spoken Lines:',
                        style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...logs.map((item) {
                        final speaker = item['speaker'] ?? 'Speaker';
                        final time = item['time'] ?? '';
                        final text = item['text'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '[$speaker - $time]: ',
                                  style: const TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                TextSpan(
                                  text: text,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class VitalCard extends StatefulWidget {
  final String title;
  final String value;
  final String unit;
  final List<Color> colors;
  final double valueFontSize;

  const VitalCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.colors,
    this.valueFontSize = 34.0,
  });

  @override
  State<VitalCard> createState() => _VitalCardState();
}

class _VitalCardState extends State<VitalCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: AnimatedContainer(
        duration: 300.ms,
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(isHovered ? 1.02 : 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isHovered ? widget.colors.first.withOpacity(0.2) : Colors.black26, 
              blurRadius: isHovered ? 20 : 10, 
              offset: const Offset(0, 4)
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: const Color(0xFF161E2E), // Dark slate interior
            child: Stack(
              children: [
                // Top Glowing Edge
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: widget.colors),
                      boxShadow: [
                        BoxShadow(
                          color: widget.colors.first.withOpacity(0.6),
                          blurRadius: 16,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        )
                      ]
                    ),
                  ),
                ),
                // Card Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(widget.title, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, height: 1.3)),
                          ),
                          Text(widget.unit, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text(widget.value, style: TextStyle(color: Colors.white, fontSize: widget.valueFontSize, fontWeight: FontWeight.w900, height: 1.0))
                        .animate(target: isHovered ? 1 : 0)
                        .shimmer(duration: 1.seconds, color: Colors.white38),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.1),
    );
  }
}
