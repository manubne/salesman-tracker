import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';

class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({super.key});
  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  List<Map<String, dynamic>> _customers = [];
  String? _customerId;
  DateTime _when = DateTime.now().add(const Duration(hours: 1));
  String _purpose = 'follow_up';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Api.customers(verifiedOnly: true).then((c) {
      if (mounted) setState(() => _customers = c);
    });
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (t == null) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_customerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a customer')));
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.createVisit(
        customerId: _customerId!,
        scheduledAt: _when,
        purpose: _purpose,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a Visit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _customerId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Customer *',
              border: OutlineInputBorder(),
            ),
            items: _customers
                .map(
                  (c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(
                      '${c['name']} ${c['company'] != null ? '(${c['company']})' : ''}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _customerId = v),
          ),
          if (_customers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Verify a customer mobile number before planning a visit.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            title: Text(DateFormat('EEE, d MMM · h:mm a').format(_when)),
            trailing: const Icon(Icons.calendar_month),
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _purpose,
            decoration: const InputDecoration(
              labelText: 'Purpose',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'new_order', child: Text('New order')),
              DropdownMenuItem(value: 'follow_up', child: Text('Follow-up')),
              DropdownMenuItem(
                value: 'payment_collection',
                child: Text('Payment collection'),
              ),
              DropdownMenuItem(value: 'demo', child: Text('Demo')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _purpose = v!),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Create Visit'),
          ),
        ],
      ),
    );
  }
}
