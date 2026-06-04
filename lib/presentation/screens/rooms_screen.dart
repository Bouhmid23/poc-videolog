import 'package:flutter/material.dart';

import '../../theme.dart';
import 'connect.dart';

class RoomsScreen extends StatelessWidget {
  const RoomsScreen({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context) {
    const roomName = 'poc-room';

    return Scaffold(
      appBar: AppBar(title: const Text('Rooms sportives')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choisis ta session', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Les rooms permettent du coaching live + télémétrie.', style: TextStyle(color: LKColors.textSecondary)),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: LKColors.primary.withValues(alpha: 0.15),
                      ),
                      child: const Icon(Icons.videocam_rounded, color: LKColors.primary),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(roomName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text('Room de test - simulation athlète', style: TextStyle(color: LKColors.textSecondary)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConnectPage(
                              initialUsername: username,
                              roomName: roomName,
                            ),
                          ),
                        );
                      },
                      child: const Text('Rejoindre'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
