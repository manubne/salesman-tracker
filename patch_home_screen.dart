import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api.dart';
import '../services/location_service.dart';
import 'customers_screen.dart';
import 'orders_screen.dart';
import 'visit_form_screen.dart';
import 'visit_verify_screen.dart';
import 'visit_report_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _visits = [];
  Map<String, dynamic>? _attendance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final visits = await Api.todayVisits();
      final att = await Api.todayAttendance();
      setState(() { _visits = visits; _attendance = att; });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleDay() async {
    final started = _attendance?['day_start_at'] != null;
    final ended = _attendance?['day_end_at'] != null;
    if (started && ended) return;
    _snack(started ? 'Ending day — getting GPS…' : 'Starting day — getting GPS…');
    try {
      final fix = await LocationService.getFix();
      if (started) {
        await Api.dayEnd(fix);
      } else {
        await Api.dayStart(fix);
      }
      _refresh();
    } catch (e) {
      _snack('$e');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Color _statusColor(String s) => switch (s) {
        'verified' => Colors.blue,
        'completed' => Colors.green,
        'missed' => Colors.red,
        _ => Colors.orange,
      };

  @override
  Widget build(BuildContext context) {
    final started = _attendance?['day_start_at'] != null;
    final ended = _attendance?['day_end_at'] != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Visits"),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Orders',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrdersScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Customers',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CustomersScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: ListTile(
                      leading: Icon(
                        ended ? Icons.check_circle : (started ? Icons.timer : Icons.play_circle),
                        color: ended ? Colors.green : (started ? Colors.blue : Colors.grey),
                      ),
                      title: Text(ended
                          ? 'Day completed'
                          : (started ? 'On duty' : 'Day not started')),
                      trailing: (started && ended)
                          ? null
                          : FilledButton(
                              onPressed: _toggleDay,
                              child: Text(started ? 'End Day' : 'Start Day'),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_visits.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: Text('No visits planned for today.\nTap + to create one.')),
                    ),
                  ..._visits.map((v) {
                    final c = v['customers'] ?? {};
                    final time = DateFormat('h:mm a')
                        .format(DateTime.parse(v['scheduled_at']).toLocal());
                    final status = v['status'] as String;
                    return Card(
                      child: ListTile(
                        title: Text('${c['name'] ?? ''} ${c['company'] != null ? '— ${c['company']}' : ''}'),
                        subtitle: Text('$time · ${v['purpose']}'),
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(status).withOpacity(.15),
                          child: Icon(Icons.location_on, color: _statusColor(status)),
                        ),
                        trailing: switch (status) {
                          'planned' => FilledButton(
                              child: const Text('Verify'),
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => VisitVerifyScreen(visit: v)));
                                _refresh();
                              },
                            ),
                          'verified' => OutlinedButton(
                              child: const Text('Report'),
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => VisitReportScreen(visit: v)));
                                _refresh();
                              },
                            ),
                          _ => Chip(
                              label: Text(status),
                              backgroundColor: _statusColor(status).withOpacity(.15),
                            ),
                        },
                      ),
                    );
                  }),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const VisitFormScreen()));
          _refresh();
        },
      ),
    );
  }
}
