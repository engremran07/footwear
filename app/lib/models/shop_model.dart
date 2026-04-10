import 'package:cloud_firestore/cloud_firestore.dart';

// =============================================================================
// ShopModel — canonical entity for retail shops / distribution points.
//
// FIRESTORE: stored in the 'customers' collection (legacy name). Use
// Collections.shops (= Collections.customers) to reference it.
//
// BALANCE SEMANTICS:
//   balance > 0  → shop owes money to us (accounts receivable)
//   balance = 0  → settled / no outstanding
//   balance < 0  → overpayment / credit on account
//
// BAD DEBT FIELDS (bad_debt, bad_debt_amount, bad_debt_date):
//   Set by ShopNotifier.markAsBadDebt() — admin only.
//   When flagged: balance is zeroed, write_off transaction is created.
//
// NOTE: Shops are the sole customer entity. Transaction and invoice docs
// reference this shop via shop_id only.
// =============================================================================
class ShopModel {
  final String id;
  final String name;
  final String routeId;
  final int routeNumber;
  final String? phone;
  final String? address;
  final String? area;
  final String? city;
  final String? contactName;
  final double balance;
  final String? notes;
  final double? latitude;
  final double? longitude;
  final bool active;
  final bool badDebt;
  final double badDebtAmount;
  final Timestamp? badDebtDate;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const ShopModel({
    required this.id,
    required this.name,
    required this.routeId,
    required this.routeNumber,
    this.phone,
    this.address,
    this.area,
    this.city,
    this.contactName,
    required this.balance,
    this.notes,
    this.latitude,
    this.longitude,
    required this.active,
    this.badDebt = false,
    this.badDebtAmount = 0,
    this.badDebtDate,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasOutstanding => balance > 0;

  factory ShopModel.fromJson(Map<String, dynamic> json, String docId) {
    return ShopModel(
      id: docId,
      name: json['name'] as String? ?? '',
      routeId: json['route_id'] as String? ?? '',
      routeNumber: json['route_number'] as int? ?? 0,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      area: json['area'] as String?,
      city: json['city'] as String?,
      contactName: json['contact_name'] as String?,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      active: json['active'] as bool? ?? true,
      badDebt: json['bad_debt'] as bool? ?? false,
      badDebtAmount: (json['bad_debt_amount'] as num?)?.toDouble() ?? 0,
      badDebtDate: json['bad_debt_date'] as Timestamp?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'route_id': routeId,
    'route_number': routeNumber,
    'phone': phone,
    'address': address,
    'area': area,
    'city': city,
    'contact_name': contactName,
    'balance': balance,
    'notes': notes,
    'latitude': latitude,
    'longitude': longitude,
    'active': active,
    'bad_debt': badDebt,
    'bad_debt_amount': badDebtAmount,
    if (badDebtDate != null) 'bad_debt_date': badDebtDate,
    'created_by': createdBy,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ShopModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
