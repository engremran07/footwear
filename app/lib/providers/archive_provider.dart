import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';
import '../core/utils/firestore_pagination.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../core/utils/tenant_scope.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import 'auth_provider.dart';

class ArchivedBusinessRecords {
  const ArchivedBusinessRecords({
    this.shops = const [],
    this.routes = const [],
    this.products = const [],
    this.variants = const [],
  });

  final List<ShopModel> shops;
  final List<RouteModel> routes;
  final List<ProductModel> products;
  final List<ProductVariantModel> variants;
}

final archivedBusinessRecordsProvider = FutureProvider<ArchivedBusinessRecords>(
  (ref) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null ||
        !PermissionPolicy.can(user, AppCapability.viewDataMaintenance)) {
      throw StateError('authorized workspace administration is required');
    }

    final tenantId = TenantScope.requireTenant(user.tenantId);
    final db = FirebaseFirestore.instance;

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadArchived(
      String collectionName,
    ) {
      final query = TenantScope.applyToQuery(
        db.collection(collectionName),
        tenantId: tenantId,
      ).where('active', isEqualTo: false);
      return fetchAllQueryDocuments(query);
    }

    final collections = await Future.wait([
      loadArchived(Collections.shops),
      loadArchived(Collections.routes),
      loadArchived(Collections.products),
      loadArchived(Collections.productVariants),
    ]);

    final shops =
        collections[0]
            .map((document) => ShopModel.fromJson(document.data(), document.id))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final routes =
        collections[1]
            .map(
              (document) => RouteModel.fromJson(document.data(), document.id),
            )
            .toList()
          ..sort((a, b) => a.routeNumber.compareTo(b.routeNumber));
    final products =
        collections[2]
            .map(
              (document) => ProductModel.fromJson(document.data(), document.id),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final variants =
        collections[3]
            .map(
              (document) =>
                  ProductVariantModel.fromJson(document.data(), document.id),
            )
            .toList()
          ..sort(
            (a, b) => a.variantName.toLowerCase().compareTo(
              b.variantName.toLowerCase(),
            ),
          );

    return ArchivedBusinessRecords(
      shops: shops,
      routes: routes,
      products: products,
      variants: variants,
    );
  },
);
