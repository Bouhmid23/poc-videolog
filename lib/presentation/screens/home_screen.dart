import 'package:flutter/material.dart';
import '../../theme.dart';
import 'rooms_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context) {
    final kpis = <Map<String, String>>[
      {'label': 'Charge d\'entraînement', 'value': '78%', 'delta': '+6% semaine'},
      {'label': 'Sessions', 'value': '12', 'delta': '4 cette semaine'},
      {'label': 'Cardio moyen', 'value': '162 bpm', 'delta': '-3 bpm'},
      {'label': 'Score technique', 'value': '91', 'delta': '+4 pts'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [LKColors.primary.withValues(alpha: 0.22), LKColors.surfaceElevated],
                ),
                border: Border.all(color: LKColors.border),
              ),
              child: Row(
                children: [
                  const CircleAvatar(radius: 26, child: Icon(Icons.directions_run, size: 26)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Salut $username 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text('Prêt pour ta prochaine session sport aujourd\'hui ?', style: TextStyle(color: LKColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Indicateurs de performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            GridView.builder(
              itemCount: kpis.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (context, index) {
                final item = kpis[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(item['label']!, style: const TextStyle(color: LKColors.textSecondary, fontSize: 11)),
                        Text(item['value']!, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                        Text(item['delta']!, style: const TextStyle(color: LKColors.success, fontSize: 10)),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.event_available_outlined, color: LKColors.secondary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Prochaine séance: Coaching Room à 18:30', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(onPressed: () {}, child: const Text('Détails')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RoomsScreen(username: username)),
                ),
                icon: const Icon(Icons.sports_score_outlined),
                label: const Text('Entrer dans une room'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}