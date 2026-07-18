import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key});
  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  String _type = 'customer';
  String _channel = 'whatsapp';
  bool _busy = false;
  String? _savedCustomerId;

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _mobile.dispose();
    _address.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_savedCustomerId == null) {
        final customer = await Api.addCustomer({
          'name': _name.text.trim(),
          'company': _company.text.trim().isEmpty ? null : _company.text.trim(),
          'mobile': _mobile.text.trim(),
          'address': _address.text.trim(),
          'type': _type,
          'otp_channel': _channel,
        });
        _savedCustomerId = customer['id'] as String;
      }

      if (!mounted) return;
      final verified = await showCustomerVerificationDialog(
        context,
        customerId: _savedCustomerId!,
        customerName: _name.text.trim(),
        mobile: _mobile.text.trim(),
      );
      if (!mounted) return;
      _snack(
        verified
            ? 'Customer saved and mobile verified'
            : 'Customer saved. Verify the mobile before planning a visit.',
      );
      Navigator.pop(context);
    } catch (e) {
      _snack(
        e.toString().contains('duplicate')
            ? 'This mobile number already exists in the company customer list.'
            : 'Error: ' + e.toString(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Customer')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _company,
              decoration: const InputDecoration(
                labelText: 'Company',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                labelText: 'Mobile *',
                prefixText: '+91 ',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length != 10)
                  ? 'Enter 10-digit number'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'customer', child: Text('Customer')),
                DropdownMenuItem(
                  value: 'channel_partner',
                  child: Text('Channel Partner'),
                ),
                DropdownMenuItem(value: 'prospect', child: Text('Prospect')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _channel,
              decoration: const InputDecoration(
                labelText: 'OTP channel (used during visits)',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                DropdownMenuItem(value: 'sms', child: Text('SMS')),
              ],
              onChanged: (v) => setState(() => _channel = v!),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(
                _busy
                    ? 'Saving...'
                    : (_savedCustomerId == null
                          ? 'Save & Verify Mobile'
                          : 'Verify Mobile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showCustomerVerificationDialog(
  BuildContext context, {
  required String customerId,
  required String customerName,
  required String mobile,
}) async {
  try {
    final result = await Api.customerOtp(customerId);
    if (!context.mounted) return false;
    if (result['already_verified'] == true) return true;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _CustomerOtpDialog(
            customerId: customerId,
            customerName: customerName,
            mobile: mobile,
            channel: result['channel']?.toString() ?? 'message',
          ),
        ) ??
        false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send verification code: $e')),
      );
    }
    return false;
  }
}

class _CustomerOtpDialog extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String mobile;
  final String channel;

  const _CustomerOtpDialog({
    required this.customerId,
    required this.customerName,
    required this.mobile,
    required this.channel,
  });

  @override
  State<_CustomerOtpDialog> createState() => _CustomerOtpDialogState();
}

class _CustomerOtpDialogState extends State<_CustomerOtpDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await Api.customerOtp(
        widget.customerId,
        code: _code.text.trim(),
      );
      if (result['ok'] == true && mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Incorrect or expired code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.customerOtp(widget.customerId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('A new code was sent.')));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not resend the code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final masked = widget.mobile.length >= 4
        ? '******${widget.mobile.substring(widget.mobile.length - 4)}'
        : widget.mobile;
    return AlertDialog(
      title: const Text('Verify customer mobile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A code was sent to ${widget.customerName} at +91 $masked via ${widget.channel}.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: '6-digit code',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Verify later'),
        ),
        TextButton(
          onPressed: _busy ? null : _resend,
          child: const Text('Resend'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(_busy ? 'Checking...' : 'Verify'),
        ),
      ],
    );
  }
}
