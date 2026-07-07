import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Login screen — mobile number + OTP only, with a polished resend flow
/// (60s cooldown countdown, friendly errors, change-number).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobile = TextEditingController();
  final _code = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _timer;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _mobile.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_resendIn <= 1) { t.cancel(); setState(() => _resendIn = 0); }
      else { setState(() => _resendIn--); }
    });
  }

  String _friendly(Object e) {
    final s = e.toString();
    final m = RegExp(r'after (\d+) seconds').firstMatch(s);
    if (m != null) return 'Please wait ${m.group(1)}s before requesting a new code.';
    if (s.contains('rate limit') || s.contains('Too many')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    return 'Could not send the code. Check the number and try again.';
  }

  Future<void> _sendOtp() async {
    if (_mobile.text.trim().length != 10) {
      setState(() => _error = 'Enter a valid 10-digit mobile number.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth
          .signInWithOtp(phone: '+91${_mobile.text.trim()}');
      setState(() => _otpSent = true);
      _startCooldown();
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 4) {
      setState(() => _error = 'Enter the OTP you received.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.sms,
        phone: '+91${_mobile.text.trim()}',
        token: _code.text.trim(),
      );
    } catch (e) {
      setState(() => _error = 'Incorrect or expired code. Try again or resend.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    _timer?.cancel();
    setState(() { _otpSent = false; _code.clear(); _error = null; _resendIn = 0; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.location_on, size: 64, color: Color(0xFF1F4E79)),
                const SizedBox(height: 8),
                Text('Salesman Tracker',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                    _otpSent
                        ? 'Enter the code sent to +91 ${_mobile.text.trim()}'
                        : 'Sign in with your mobile number',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  enabled: !_otpSent,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  decoration: const InputDecoration(
                    labelText: 'Mobile number',
                    prefixText: '+91 ',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    decoration: const InputDecoration(
                      labelText: 'Enter OTP',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : (_otpSent ? _verify : _sendOtp),
                  child: Text(_busy
                      ? 'Please wait…'
                      : (_otpSent ? 'Verify & Login' : 'Send OTP')),
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: (_busy || _resendIn > 0) ? null : _sendOtp,
                    child: Text(_resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _changeNumber,
                    child: const Text('Change number'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
