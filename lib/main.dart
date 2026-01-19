import 'package:flutter/material.dart';

void main() {
  runApp(const ColdBoreApp());
}

class ColdBoreApp extends StatelessWidget {
  const ColdBoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cold Bore',
      theme: ThemeData(useMaterial3: true),
      home: const UnlockScreen(),
    );
  }
}

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _unlock() async {
    if (_busy) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // TEMPORARY: biometrics disabled (local_auth removed)
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unlock failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cold Bore',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _unlock,
                child: Text(_busy ? 'Unlocking…' : 'Unlock'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'App Loaded Successfully',
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}
