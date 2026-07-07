import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import '../services/location_service.dart';

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
  bool _locating = false;
  double? _lat;
  double? _lng;

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _fetchLocation() async {
    setState(() => _locating = true);
    try {
      final fix = await LocationService.getFix();
      setState(() { _lat = fix.lat; _lng = fix.lng; });
      _snack('Site location captured');
    } catch (e) {
      _snack(e.toString());
    } finally {
      setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.addCustomer({
        'name': _name.text.trim(),
        'company': _company.text.trim().isEmpty ? null : _company.text.trim(),
        'mobile': _mobile.text.trim(),
        'address': _address.text.trim(),
        'type': _type,
        'otp_channel': _channel,
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
      });
      _snack('Customer saved');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(e.toString().contains('duplicate') ? 'This mobile number already exists in the company customer list.' : 'Error: ' + e.toString());
    } finally {
      setState(() => _busy = false);
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
              decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _company,
              decoration: const InputDecoration(labelText: 'Company', border: OutlineInputBorder()),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              decoration: const InputDecoration(labelText: 'Mobile *', prefixText: '+91 ', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().length != 10) ? 'Enter 10-digit number' : null,
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'customer', child: Text('Customer')),
                DropdownMenuItem(value: 'channel_partner', child: Text('Channel Partner')),
                DropdownMenuItem(value: 'prospect', child: Text('Prospect')),
                ],
              onChanged: (v) => setState(() => _type = v!),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _channel,
              decoration: const InputDecoration(labelText: 'OTP channel (used during visits)', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                DropdownMenuItem(value: 'sms', child: Text('SMS')),
                ],
              onChanged: (v) => setState(() => _channel = v!),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _locating ? null : _fetchLocation,
              icon: const Icon(Icons.my_location),
              label: Text(_locating ? 'Fetching location...' : (_lat == null ? 'Fetch site location' : 'Update site location')),
              ),
            if (_lat != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Saved: ' + _lat!.toStringAsFixed(5) + ', ' + _lng!.toStringAsFixed(5), style: const TextStyle(color: Colors.green)),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving...' : 'Save Customer'),
              ),
            ],
          ),
        ),
      );
  }
}
