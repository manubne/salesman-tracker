import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/location_service.dart';
import 'visit_report_screen.dart';

/// The core anti-bluff flow:
/// 1. Fresh GPS fix (<=50 m accuracy, mock-location check)
/// 2. Backend sends OTP to the CUSTOMER's phone
/// 3. Customer tells the code; sales person enters it
/// 4. Backend verifies, records location, sets flags
class VisitVerifyScreen extends StatefulWidget {
  final Map<String, dynamic> visit;
  const VisitVerifyScreen({super.key, required this.visit});
  @override
  State<VisitVerifyScreen> createState() => _VisitVerifyScreenState();
}

class _VisitVerifyScreenState extends State<VisitVerifyScreen> {
  final _code = TextEditingController();
  LocationFix? _fix;
  String _stage = 'gps'; // gps -> sending -> code -> done
  String? _error;
  String? _channel;
  bool _verifying = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _stage = 'gps';
      _error = null;
    });
    try {
      _fix = await LocationService.getFix();
      setState(() => _stage = 'sending');
      final res = await Api.requestVisitOtp(widget.visit['id'], _fix!);
      if (res['ok'] == true) {
        _channel = res['channel'];
        setState(() => _stage = 'code');
      } else {
        setState(() {
          _error = res['error'] ?? 'Failed to send code';
          _stage = 'error';
        });
      }
    } catch (e) {
      setState(() {
        _error = '$e';
        _stage = 'error';
      });
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit customer code.');
      return;
    }
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      // Fresh fix at entry time — this is the location that gets recorded
      final fix = await LocationService.getFix(maxWaitSeconds: 10);
      final res = await Api.verifyVisitOtp(
        widget.visit['id'],
        _code.text.trim(),
        fix,
      );
      if (res['ok'] == true) {
        setState(() => _stage = 'done');
      } else {
        setState(() => _error = res['error'] ?? 'Verification failed');
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.visit['customers'] ?? {};
    return Scaffold(
      appBar: AppBar(title: Text('Verify: ${c['name'] ?? 'Visit'}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_stage == 'gps') ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Text(
                'Getting your GPS location…',
                textAlign: TextAlign.center,
              ),
            ],
            if (_stage == 'sending') ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Text(
                'Sending code to the customer…',
                textAlign: TextAlign.center,
              ),
            ],
            if (_stage == 'code') ...[
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'A 6-digit code was sent to ${c['name'] ?? 'the customer'} '
                    'via ${_channel ?? 'message'}.\n\nAsk them for the code and enter it below.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'Customer code',
                  border: OutlineInputBorder(),
                ),
              ),
              FilledButton(
                onPressed: _verifying ? null : _verify,
                child: Text(_verifying ? 'Verifying…' : 'Verify Visit'),
              ),
              TextButton(
                onPressed: _verifying ? null : _start,
                child: const Text('Resend code'),
              ),
            ],
            if (_stage == 'done') ...[
              const Icon(Icons.verified, size: 96, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Visit verified!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VisitReportScreen(visit: widget.visit),
                  ),
                ),
                child: const Text('Fill visit report'),
              ),
            ],
            if (_stage == 'error') ...[
              const Icon(Icons.error_outline, size: 72, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error ?? 'Something went wrong',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _start, child: const Text('Try again')),
            ],
            if (_error != null && _stage == 'code')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
