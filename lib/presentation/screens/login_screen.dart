import 'package:flutter/material.dart';
import '../../theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _rememberMe = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir email et mot de passe.')),
      );
      return;
    }

    final displayName = email.split('@').first;
    await Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(username: displayName)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [LKColors.background, Color(0xFF0F1C37), LKColors.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: LKColors.border),
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: LKColors.primary.withValues(alpha: 0.15),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Image.asset('images/v.png'),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Videolog Sport', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text('Performance · Coaching · Live', style: TextStyle(color: LKColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Connexion', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text('Accès fictif en attendant l\'API auth.', style: TextStyle(color: LKColors.textSecondary)),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'athlete@videolog.app',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Mot de passe',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                            const SizedBox(height: 10),
                            CheckboxListTile(
                              value: _rememberMe,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Se souvenir de moi', style: TextStyle(fontSize: 14)),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (value) => setState(() => _rememberMe = value ?? true),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _login,
                              icon: const Icon(Icons.login),
                              label: const Text('Se connecter'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}