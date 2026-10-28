import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/app_locale.dart';
import '../core/utils/role_names.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/transaction_model.dart';
import 'app_contextual_actions.dart';

List<AppContextualAction> transactionContextualActions({
  required BuildContext context,
  required WidgetRef ref,
  required TransactionModel transaction,
}) {
  final invoiceId = transaction.invoiceId;
  final hasInvoice = invoiceId != null && invoiceId.isNotEmpty;
  final hasShop = transaction.shopId.isNotEmpty;
  return [
    if (hasInvoice || hasShop)
      AppContextualAction(
        entity: ContextualEntity.transaction,
        id: ContextualActionId.viewDetails,
        label: tr('details', ref),
        icon: Icons.open_in_new,
        requiredCapability: AppCapability.viewHistory,
        onSelected: () => hasInvoice
            ? context.push('/invoices/$invoiceId')
            : context.push('/shops/${transaction.shopId}'),
      ),
    AppContextualAction(
      entity: ContextualEntity.transaction,
      id: ContextualActionId.copyReference,
      label: tr('copy_reference', ref),
      icon: Icons.copy_outlined,
      requiredCapability: AppCapability.viewHistory,
      onSelected: () => copyContextualText(
        context: context,
        ref: ref,
        text: transaction.invoiceNumber?.isNotEmpty == true
            ? transaction.invoiceNumber!
            : transaction.id,
      ),
    ),
  ];
}

List<AppContextualAction> routeContextualActions({
  required BuildContext context,
  required WidgetRef ref,
  required RouteModel route,
}) => [
  AppContextualAction(
    entity: ContextualEntity.route,
    id: ContextualActionId.viewDetails,
    label: tr('details', ref),
    icon: Icons.open_in_new,
    requiredCapability: AppCapability.viewRoutes,
    onSelected: () => context.push('/routes/${route.id}'),
  ),
  AppContextualAction(
    entity: ContextualEntity.route,
    id: ContextualActionId.copyReference,
    label: tr('copy_reference', ref),
    icon: Icons.copy_outlined,
    requiredCapability: AppCapability.viewRoutes,
    onSelected: () => copyContextualText(
      context: context,
      ref: ref,
      text: '${route.routeNumber} · ${route.name}',
    ),
  ),
];

List<AppContextualAction> shopContextualActions({
  required BuildContext context,
  required WidgetRef ref,
  required ShopModel shop,
}) => [
  AppContextualAction(
    entity: ContextualEntity.shop,
    id: ContextualActionId.viewDetails,
    label: tr('details', ref),
    icon: Icons.open_in_new,
    requiredCapability: AppCapability.viewShops,
    onSelected: () => context.push('/shops/${shop.id}'),
  ),
  AppContextualAction(
    entity: ContextualEntity.shop,
    id: ContextualActionId.edit,
    label: tr('edit', ref),
    icon: Icons.edit_outlined,
    requiredCapability: AppCapability.manageShops,
    onSelected: () => context.push('/shops/${shop.id}/edit'),
  ),
  AppContextualAction(
    entity: ContextualEntity.shop,
    id: ContextualActionId.createInvoice,
    label: tr('create_invoice', ref),
    icon: Icons.receipt_long_outlined,
    requiredCapability: AppCapability.createInvoice,
    onSelected: () => context.push('/invoices/new?shopId=${shop.id}'),
  ),
  if (shop.phone?.trim().isNotEmpty == true)
    AppContextualAction(
      entity: ContextualEntity.shop,
      id: ContextualActionId.copyPhone,
      label: tr('copy_phone', ref),
      icon: Icons.phone_outlined,
      requiredCapability: AppCapability.viewShops,
      onSelected: () => copyContextualText(
        context: context,
        ref: ref,
        text: shop.phone!.trim(),
      ),
    ),
];
