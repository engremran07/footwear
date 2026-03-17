import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryBatchModel {
  final String id;
  final String productId;
  final String? purchaseOrderId;
  final String? supplierId;
  final int qtyProduced;
  final int qtyPassed;
  final int qtyRejected;
  final double costTotal;
  final double costPerPair;
  final String status;
  final String source;
  final String? lastQcId;
  final String factory_;
  final String currency;
  final String? shipmentStatus;
  final String? shipmentOrigin;
  final String? shipmentDestination;
  final String? trackingNumber;
  final Timestamp? dispatchedAt;
  final Timestamp? completedAt;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const InventoryBatchModel({
    required this.id,
    required this.productId,
    this.purchaseOrderId,
    this.supplierId,
    required this.qtyProduced,
    required this.qtyPassed,
    required this.qtyRejected,
    required this.costTotal,
    required this.costPerPair,
    required this.status,
    required this.source,
    this.lastQcId,
    this.factory_ = 'pk',
    this.currency = 'PKR',
    this.shipmentStatus,
    this.shipmentOrigin,
    this.shipmentDestination,
    this.trackingNumber,
    this.dispatchedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventoryBatchModel.fromJson(
      Map<String, dynamic> json, String docId) {
    return InventoryBatchModel(
      id: docId,
      productId: json['product_id'] as String? ?? '',
      purchaseOrderId: json['purchase_order_id'] as String?,
      supplierId: json['supplier_id'] as String?,
      qtyProduced: json['qty_produced'] as int? ?? 0,
      qtyPassed: json['qty_passed'] as int? ?? 0,
      qtyRejected: json['qty_rejected'] as int? ?? 0,
      costTotal: (json['cost_total'] as num?)?.toDouble() ?? 0.0,
      costPerPair: (json['cost_per_pair'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'draft',
      source: json['source'] as String? ?? 'production',
      lastQcId: json['last_qc_id'] as String?,
      factory_: json['factory'] as String? ?? 'pk',
      currency: json['currency'] as String? ?? 'PKR',
      shipmentStatus: json['shipment_status'] as String?,
      shipmentOrigin: json['shipment_origin'] as String?,
      shipmentDestination: json['shipment_destination'] as String?,
      trackingNumber: json['tracking_number'] as String?,
      dispatchedAt: json['dispatched_at'] as Timestamp?,
      completedAt: json['completed_at'] as Timestamp?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'purchase_order_id': purchaseOrderId,
        'supplier_id': supplierId,
        'qty_produced': qtyProduced,
        'qty_passed': qtyPassed,
        'qty_rejected': qtyRejected,
        'cost_total': costTotal,
        'cost_per_pair': costPerPair,
        'status': status,
        'source': source,
        'last_qc_id': lastQcId,
        'factory': factory_,
        'currency': currency,
        'shipment_status': shipmentStatus,
        'shipment_origin': shipmentOrigin,
        'shipment_destination': shipmentDestination,
        'tracking_number': trackingNumber,
        'dispatched_at': dispatchedAt,
        'completed_at': completedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  InventoryBatchModel copyWith({
    String? id,
    String? productId,
    String? purchaseOrderId,
    String? supplierId,
    int? qtyProduced,
    int? qtyPassed,
    int? qtyRejected,
    double? costTotal,
    double? costPerPair,
    String? status,
    String? source,
    String? lastQcId,
    String? factory_,
    String? currency,
    String? shipmentStatus,
    String? shipmentOrigin,
    String? shipmentDestination,
    String? trackingNumber,
    Timestamp? dispatchedAt,
    Timestamp? completedAt,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return InventoryBatchModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
      supplierId: supplierId ?? this.supplierId,
      qtyProduced: qtyProduced ?? this.qtyProduced,
      qtyPassed: qtyPassed ?? this.qtyPassed,
      qtyRejected: qtyRejected ?? this.qtyRejected,
      costTotal: costTotal ?? this.costTotal,
      costPerPair: costPerPair ?? this.costPerPair,
      status: status ?? this.status,
      source: source ?? this.source,
      lastQcId: lastQcId ?? this.lastQcId,
      factory_: factory_ ?? this.factory_,
      currency: currency ?? this.currency,
      shipmentStatus: shipmentStatus ?? this.shipmentStatus,
      shipmentOrigin: shipmentOrigin ?? this.shipmentOrigin,
      shipmentDestination: shipmentDestination ?? this.shipmentDestination,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      dispatchedAt: dispatchedAt ?? this.dispatchedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
