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

/// App shell with a bottom navigation bar (Today / Orders / Customers / Profile).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TodayScreen(),
          OrdersScreen(),
          CustomersScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Today's visits + attendance (first tab).
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
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
      setState(() {
        _visits = visits;
        _attendance = att;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleDay() async {
    final started = _attendance?['day_start_at'] != null;
    final ended = _attendance?['day_end_at'] != null;
    if (started && ended) return;
    _snack(
      started ? 'Ending day — getting GPS…' : 'Starting day — getting GPS…',
    );
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
      appBar: AppBar(title: const Text("Today's Visits")),
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
                        ended
                            ? Icons.check_circle
                            : (started ? Icons.timer : Icons.play_circle),
                        color: ended
                            ? Colors.green
                            : (started ? Colors.blue : Colors.grey),
                      ),
                      title: Text(
                        ended
                            ? 'Day completed'
                            : (started ? 'On duty' : 'Day not started'),
                      ),
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
                      child: Center(
                        child: Text(
                          'No visits planned for today.\nTap “Plan visit” to create one.',
                        ),
                      ),
                    ),
                  ..._visits.map((v) {
                    final c = v['customers'] ?? {};
                    final time = DateFormat(
                      'h:mm a',
                    ).format(DateTime.parse(v['scheduled_at']).toLocal());
                    final status = v['status'] as String;
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${c['name'] ?? ''} ${c['company'] != null ? '— ${c['company']}' : ''}',
                        ),
                        subtitle: Text('$time · ${v['purpose']}'),
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(
                            status,
                          ).withOpacity(.15),
                          child: Icon(
                            Icons.location_on,
                            color: _statusColor(status),
                          ),
                        ),
                        trailing: switch (status) {
                          'planned' => FilledButton(
                            child: const Text('Verify'),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VisitVerifyScreen(visit: v),
                                ),
                              );
                              _refresh();
                            },
                          ),
                          'verified' => OutlinedButton(
                            child: const Text('Report'),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VisitReportScreen(visit: v),
                                ),
                              );
                              _refresh();
                            },
                          ),
                          _ => Chip(
                            label: Text(status),
                            backgroundColor: _statusColor(
                              status,
                            ).withOpacity(.15),
                          ),
                        },
                      ),
                    );
                  }),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Plan visit'),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VisitFormScreen()),
          );
          _refresh();
        },
      ),
    );
  }
}

/// Profile / options tab.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = Supabase.instance.client.auth.currentUser!.id;
      final rows = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', id);
      if (mounted && rows.isNotEmpty)
        setState(() => _me = Map<String, dynamic>.from(rows.first));
    } catch (_) {}
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need your mobile OTP to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final phone = Supabase.instance.client.auth.currentUser?.phone ?? '';
    final name = (_me?['name'] as String?)?.trim();
    final role = (_me?['role'] as String?) ?? 'sales';
    final territory = _me?['territory'] as String?;
    final initial = (name != null && name.isNotEmpty)
        ? name[0].toUpperCase()
        : '?';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Center(
            child: CircleAvatar(
              radius: 42,
              backgroundColor: const Color(0xFF1F4E79),
              child: Text(
                initial,
                style: const TextStyle(fontSize: 34, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              name?.isNotEmpty == true ? name! : 'Sales person',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Center(
            child: Text(
              '+$phone',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Chip(label: Text(role.toUpperCase()))),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Role'),
            subtitle: Text(role),
          ),
          if (territory != null && territory.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Territory'),
              subtitle: Text(territory),
            ),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Mobile'),
            subtitle: Text('+$phone'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Quote alerts (coming soon)'),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Salesman Tracker'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log out', style: TextStyle(color: Colors.red)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}
