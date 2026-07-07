import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'location_service.dart';

final supa = Supabase.instance.client;

class Api {
  // ---------- Customers ----------
  static Future<List<Map<String, dynamic>>> customers({String? search}) async {
    var q = supa.from('customers').select();
    if (search != null && search.isNotEmpty) {
      q = q.or('name.ilike.%$search%,company.ilike.%$search%,mobile.ilike.%$search%');
    }
    return List<Map<String, dynamic>>.from(await q.order('name'));
  }

  static Future<Map<String, dynamic>> addCustomer(Map<String, dynamic> data) async {
    data['owner_user_id'] = supa.auth.currentUser!.id;
    final rows = await supa.from('customers').insert(data).select();
    return rows.first;
  }

  static Future<Map<String, dynamic>> customerOtp(String customerId, {String? code}) async {
    final res = await supa.functions.invoke('verify-customer-mobile', body: {
      'action': code == null ? 'request' : 'verify',
      'customer_id': customerId,
      if (code != null) 'code': code,
    });
    return Map<String, dynamic>.from(res.data);
  }

  // ---------- Visits ----------
  static Future<List<Map<String, dynamic>>> todayVisits() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59).toUtc().toIso8601String();
    return List<Map<String, dynamic>>.from(await supa
        .from('visits')
        .select('*, customers(name, company, mobile)')
        .gte('scheduled_at', start)
        .lte('scheduled_at', end)
        .order('scheduled_at'));
  }

  static Future<void> createVisit({
    required String customerId,
    required DateTime scheduledAt,
    required String purpose,
  }) async {
    await supa.from('visits').insert({
      'customer_id': customerId,
      'user_id': supa.auth.currentUser!.id,
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'purpose': purpose,
    });
  }

  static Future<Map<String, dynamic>> requestVisitOtp(String visitId, LocationFix fix) async {
    final res = await supa.functions.invoke('request-visit-otp', body: {
      'visit_id': visitId,
      'lat': fix.lat,
      'lng': fix.lng,
      'accuracy_m': fix.accuracyM,
      'mock_location': fix.mockLocation,
    });
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> verifyVisitOtp(
      String visitId, String code, LocationFix fix) async {
    final res = await supa.functions.invoke('verify-visit-otp', body: {
      'visit_id': visitId,
      'code': code,
      'lat': fix.lat,
      'lng': fix.lng,
      'accuracy_m': fix.accuracyM,
      'mock_location': fix.mockLocation,
    });
    return Map<String, dynamic>.from(res.data);
  }

  static Future<void> completeVisit(String visitId, {String? notes}) async {
    await supa.from('visits').update({
      'status': 'completed',
      if (notes != null) 'notes': notes,
    }).eq('id', visitId);
  }

  // ---------- Requirements ----------
  static Future<void> addRequirement(Map<String, dynamic> data) async {
    data['created_by'] = supa.auth.currentUser!.id;
    await supa.from('requirements').insert(data);
  }

  // ---------- Photos ----------
  static Future<void> uploadVisitPhoto(
      String visitId, List<int> bytes, LocationFix fix) async {
    final path = '$visitId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await supa.storage.from('visit-photos').uploadBinary(path, Uint8List.fromList(bytes));
    await supa.from('visit_photos').insert({
      'visit_id': visitId,
      'storage_path': path,
      'lat': fix.lat,
      'lng': fix.lng,
    });
  }

  // ---------- Attendance ----------
  static Future<Map<String, dynamic>?> todayAttendance() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await supa
        .from('attendance')
        .select()
        .eq('user_id', supa.auth.currentUser!.id)
        .eq('date', today);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  static Future<void> dayStart(LocationFix fix) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await supa.from('attendance').upsert({
      'user_id': supa.auth.currentUser!.id,
      'date': today,
      'day_start_at': DateTime.now().toUtc().toIso8601String(),
      'day_start_lat': fix.lat,
      'day_start_lng': fix.lng,
    }, onConflict: 'user_id,date');
  }

  static Future<void> dayEnd(LocationFix fix) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await supa.from('attendance').update({
      'day_end_at': DateTime.now().toUtc().toIso8601String(),
      'day_end_lat': fix.lat,
      'day_end_lng': fix.lng,
    }).eq('user_id', supa.auth.currentUser!.id).eq('date', today);
  }

  // ---------- Orders ----------
  static Future<List<Map<String, dynamic>>> orderCategories() async {
    return List<Map<String, dynamic>>.from(
        await supa.from('order_categories').select().eq('active', true).order('name'));
  }

  static Future<Map<String, dynamic>> createOrder({
    required String customerId,
    String? categoryId,
    double? sqft,
    String? notes,
  }) async {
    final rows = await supa.from('orders').insert({
      'customer_id': customerId,
      'created_by': supa.auth.currentUser!.id,
      if (categoryId != null) 'category_id': categoryId,
      if (sqft != null) 'sqft': sqft,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    }).select();
    return rows.first;
  }

  static Future<List<Map<String, dynamic>>> orders() async {
    return List<Map<String, dynamic>>.from(await supa
        .from('orders')
        .select('*, customers(name,company), order_categories(name)')
        .order('created_at', ascending: false)
        .limit(500));
  }

  static Future<void> updateOrder(String id, Map<String, dynamic> data) async {
    await supa.from('orders').update(data).eq('id', id);
  }

  static Future<void> uploadOrderFile(String orderId, List<int> bytes, String kind) async {
    final path = '$orderId/${kind}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await supa.storage.from('order-files').uploadBinary(path, Uint8List.fromList(bytes));
    await supa.from('order_files').insert({
      'order_id': orderId,
      'storage_path': path,
      'kind': kind,
      'uploaded_by': supa.auth.currentUser!.id,
    });
  }
}
