import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api.dart';
import '../services/location_service.dart';

/// Post-verification report: requirement/order + photos + notes.
class VisitReportScreen extends StatefulWidget {
  final Map<String, dynamic> visit;
  const VisitReportScreen({super.key, required this.visit});
  @override
  State<VisitReportScreen> createState() => _VisitReportScreenState();
}

class _VisitReportScreenState extends State<VisitReportScreen> {
  final _product = TextEditingController();
  final _quantity = TextEditingController();
  final _value = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _followUp;
  final List<Uint8List> _photos = [];
  bool _hasRequirement = false;
  bool _busy = false;

  @override
  void dispose() {
    _product.dispose();
    _quantity.dispose();
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= 5) return;
    // Camera only — no gallery, so photos can't be reused
    final img = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (img != null) {
      final bytes = await img.readAsBytes();
      if (mounted) setState(() => _photos.add(bytes));
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final visitId = widget.visit['id'] as String;
      if (_hasRequirement && _product.text.trim().isNotEmpty) {
        await Api.addRequirement({
          'visit_id': visitId,
          'customer_id': widget.visit['customer_id'],
          'product': _product.text.trim(),
          'quantity': _quantity.text.trim(),
          'expected_value': double.tryParse(_value.text.trim()),
          'follow_up_date': _followUp?.toIso8601String().substring(0, 10),
        });
      }
      if (_photos.isNotEmpty) {
        final fix = await LocationService.getFix(maxWaitSeconds: 10);
        for (final bytes in _photos) {
          await Api.uploadVisitPhoto(visitId, bytes, fix);
        }
      }
      await Api.completeVisit(
        visitId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.visit['customers'] ?? {};
    return Scaffold(
      appBar: AppBar(title: Text('Report: ${c['name'] ?? ''}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Customer has a requirement / order'),
            value: _hasRequirement,
            onChanged: (v) => setState(() => _hasRequirement = v),
          ),
          if (_hasRequirement) ...[
            TextField(
              controller: _product,
              decoration: const InputDecoration(
                labelText: 'Product / requirement *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _value,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Expected value (₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              title: Text(
                _followUp == null
                    ? 'Set follow-up date'
                    : 'Follow-up: ${_followUp!.toIso8601String().substring(0, 10)}',
              ),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _followUp = d);
              },
            ),
            const SizedBox(height: 12),
          ],
          const Divider(),
          Row(
            children: [
              Text(
                'Photos (${_photos.length}/5)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: _takePhoto,
                icon: const Icon(Icons.camera_alt),
              ),
            ],
          ),
          if (_photos.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _photos
                    .map(
                      (bytes) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            bytes,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Submitting…' : 'Complete Visit'),
          ),
        ],
      ),
    );
  }
}
