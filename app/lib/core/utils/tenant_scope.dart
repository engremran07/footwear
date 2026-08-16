import 'package:cloud_firestore/cloud_firestore.dart';

class TenantScope {
  const TenantScope._();

  static const globalTenantId = '__global__';

  static String? normalize(String? tenantId) {
    final value = tenantId?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Map<String, dynamic> applyToData(
    Map<String, dynamic> data, {
    String? tenantId,
  }) {
    final normalized = normalize(tenantId);
    if (normalized == null) return data;
    final next = Map<String, dynamic>.from(data);
    next['tenant_id'] = normalized;
    return next;
  }

  static Map<String, dynamic> applyToDocument(
    Map<String, dynamic> data, {
    required String? tenantId,
  }) {
    return applyToData(data, tenantId: tenantId);
  }

  static bool matchesTenant(Map<String, dynamic>? data, String? tenantId) {
    final expectedTenantId = normalize(tenantId);
    if (expectedTenantId == null) return false;
    return normalize(data?['tenant_id'] as String?) == expectedTenantId;
  }

  static Query<Map<String, dynamic>> applyToQuery(
    Query<Map<String, dynamic>> query, {
    String? tenantId,
  }) {
    final normalized = normalize(tenantId);
    if (normalized == null) {
      return query.where('tenant_id', isEqualTo: '__tenant_missing__');
    }
    if (normalized == globalTenantId) {
      return query;
    }
    return query.where('tenant_id', isEqualTo: normalized);
  }

  static String? fromUserData(Map<String, dynamic>? userData) {
    return normalize(userData?['tenant_id'] as String?);
  }

  static Future<String?> resolveFromFirestore(
    FirebaseFirestore firestore,
    String uid,
  ) async {
    final snap = await firestore.collection('users').doc(uid).get();
    if (!snap.exists) return null;
    return fromUserData(snap.data());
  }
}
