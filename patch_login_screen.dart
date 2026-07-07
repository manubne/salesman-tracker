import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

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
  String? _error;

  Future<void> _sendOtp() async {
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: '+91' + _mobile.text.trim());
      setState(() => _otpSent = true);
    } catch (e) {
      setState(() => _error = 'Could not send code. Please try again.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.verifyOTP(type: OtpType.sms, phone: '+91' + _mobile.text.trim(), token: _code.text.trim());
    } catch (e) {
      setState(() => _error = 'Incorrect or expired code');
    } finally {
      setState(() => _busy = false);
    }
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
                Text('Salesman Tracker', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Sign in with your mobile number', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  enabled: !_otpSent,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ', border: OutlineInputBorder()),
                  ),
                if (_otpSent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Enter OTP', border: OutlineInputBorder()),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                    ),
                  ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : (_otpSent ? _verify : _sendOtp),
                  child: Text(_busy ? 'Please wait...' : (_otpSent ? 'Verify & Login' : 'Send OTP')),
                  ),
                if (_otpSent)
                TextButton(
                  onPressed: _busy ? null : _sendOtp,
                  child: const Text('Resend code'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
