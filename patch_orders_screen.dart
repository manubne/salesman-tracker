import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final o = await Api.orders();
      setState(() => _orders = o);
    } finally {
      setState(() => _loading = false);
    }
  }

  Color _stageColor(String s) => switch (s) {
        'need_quote' => Colors.orange,
        'quoted' => Colors.blue,
        'won' => Colors.green,
        'lost' => Colors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
                ? ListView(children: const [
                    Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: Text('No orders yet.\nTap + to create one.')))
                  ])
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: _orders.map((o) {
                      final c = o['customers'] ?? {};
                      final cat = o['order_categories']?['name'] ?? '—';
                      final stage = o['stage'] as String;
                      return Card(
                        child: ListTile(
                          title: Text(
                              '${c['name'] ?? ''} ${c['company'] != null ? '— ${c['company']}' : ''}'),
                          subtitle: Text(
                              '$cat · ${o['sqft'] != null ? '${o['sqft']} sq ft · ' : ''}visit: ${o['visit_status']}'),
                          trailing: Chip(
                            label: Text(stage.replaceAll('_', ' ')),
                            backgroundColor: _stageColor(stage).withOpacity(.15),
                            labelStyle: TextStyle(color: _stageColor(stage), fontSize: 12),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const OrderFormScreen()));
          _load();
        },
      ),
    );
  }
}

class OrderFormScreen extends StatefulWidget {
  const OrderFormScreen({super.key});
  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  final _form = GlobalKey<FormState>();
  final _sqft = TextEditingController();
  final _notes = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _cats = [];
  String? _customerId;
  String? _categoryId;
  bool _busy = false;

  String? _orderId;
  String _visitStatus = 'pending';
  int _photoCount = 0;
  bool _hasFloorPlan = false;

  @override
  void initState() {
    super.initState();
    Api.customers().then((c) => setState(() => _customers = c));
    Api.orderCategories().then((c) => setState(() => _cats = c));
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    if (_customerId == null) {
      _snack('Select a customer');
      return;
    }
    setState(() => _busy = true);
    try {
      final row = await Api.createOrder(
        customerId: _customerId!,
        categoryId: _categoryId,
        sqft: _sqft.text.trim().isEmpty ? null : double.tryParse(_sqft.text.trim()),
        notes: _notes.text.trim(),
      );
      setState(() => _orderId = row['id']);
      _snack('Order created');
    } catch (e) {
      _snack('Error: ' + e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _upload(String kind) async {
    final img = await ImagePicker().pickImage(
        source: kind == 'floor_plan' ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 70);
    if (img == null) return;
    setState(() => _busy = true);
    try {
      await Api.uploadOrderFile(_orderId!, await File(img.path).readAsBytes(), kind);
      setState(() {
        if (kind == 'floor_plan') {
          _hasFloorPlan = true;
        } else {
          _photoCount++;
        }
      });
      _snack(kind == 'floor_plan' ? 'Floor plan uploaded' : 'Photo added');
    } catch (e) {
      _snack('Upload failed: ' + e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _setVisit(String v) async {
    setState(() => _busy = true);
    try {
      await Api.updateOrder(_orderId!, {'visit_status': v});
      setState(() => _visitStatus = v);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _needQuote() async {
    setState(() => _busy = true);
    try {
      await Api.updateOrder(_orderId!, {'stage': 'need_quote'});
      _snack('Pushed to Need Quote');
      if (mounted) Navigator.pop(context);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _orderId != null;
    return Scaffold(
      appBar: AppBar(title: Text(created ? 'Order details' : 'New Order')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Order type', border: OutlineInputBorder()),
              items: _cats
                  .map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name'])))
                  .toList(),
              onChanged: created ? null : (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _customerId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Customer *', border: OutlineInputBorder()),
              items: _customers
                  .map((c) => DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text('${c['name']} ${c['company'] != null ? '(${c['company']})' : ''}'),
                      ))
                  .toList(),
              onChanged: created ? null : (v) => setState(() => _customerId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sqft,
              enabled: !created,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Premises area (sq ft)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              enabled: !created,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            if (!created)
              FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(_busy ? 'Saving…' : 'Create order'),
              ),
            if (created) ...[
              const Divider(height: 32),
              Text('Attachments', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _upload('floor_plan'),
                  icon: const Icon(Icons.description),
                  label: Text(_hasFloorPlan ? 'Floor plan ✔' : 'Floor plan'),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _upload('photo'),
                  icon: const Icon(Icons.photo_camera),
                  label: Text(_photoCount > 0 ? 'Photos ($_photoCount)' : 'Add photo'),
                )),
              ]),
              const Divider(height: 32),
              Text('Site visit', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'done', label: Text('Visit done'), icon: Icon(Icons.check)),
                  ButtonSegment(value: 'not_required', label: Text('Not required')),
                ],
                selected: _visitStatus == 'pending' ? <String>{} : {_visitStatus},
                emptySelectionAllowed: true,
                onSelectionChanged: _busy ? null : (s) { if (s.isNotEmpty) _setVisit(s.first); },
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: (_busy || _visitStatus == 'pending') ? null : _needQuote,
                icon: const Icon(Icons.request_quote),
                label: const Text('Push to Need Quote'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Save & close'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
