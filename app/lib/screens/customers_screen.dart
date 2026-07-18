import 'package:flutter/material.dart';
import '../services/api.dart';
import 'customer_form_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Map<String, dynamic>> _customers = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _customers = await Api.customers(search: _search);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search name, company, mobile…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _search = v;
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _customers.length,
                    itemBuilder: (_, i) {
                      final c = _customers[i];
                      final verified = c['mobile_verified_at'] != null;
                      return ListTile(
                        title: Text(c['name']),
                        subtitle: Text(
                          '${c['company'] ?? ''} · ${c['mobile']} · ${c['type']}',
                        ),
                        trailing: Icon(
                          verified ? Icons.verified : Icons.warning_amber,
                          color: verified ? Colors.green : Colors.orange,
                        ),
                        onTap: verified
                            ? null
                            : () async {
                                final ok = await showCustomerVerificationDialog(
                                  context,
                                  customerId: c['id'] as String,
                                  customerName: c['name'] as String,
                                  mobile: c['mobile'] as String,
                                );
                                if (ok) _load();
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.person_add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
          );
          _load();
        },
      ),
    );
  }
}
