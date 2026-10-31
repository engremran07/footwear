import '../constants/collections.dart';

class FinancialMinorUnitMigration {
  FinancialMinorUnitMigration._();

  static const companionField = 'financial_minor_units';
  static const maximumMajorUnits = 90000000000000.0;

  static const _schema = <String, List<_FinancialField>>{
    'shops': [
      _FinancialField('balance', required: true),
      _FinancialField('bad_debt_amount'),
      _FinancialField('last_transaction_amount'),
    ],
    'transactions': [
      _FinancialField('amount', required: true),
      _FinancialField('edit_request_new_amount'),
      _FinancialField('items.*.unit_price'),
      _FinancialField('items.*.subtotal'),
      _FinancialField('edit_history.*.previous_amount'),
      _FinancialField('edit_history.*.new_amount'),
    ],
    'invoices': [
      _FinancialField('total', required: true),
      _FinancialField('subtotal'),
      _FinancialField('discount'),
      _FinancialField('amount_received'),
      _FinancialField('outstanding_amount'),
      _FinancialField('credit_note_total'),
      _FinancialField('shop_balance_before'),
      _FinancialField('shop_balance_after'),
      _FinancialField('items.*.unit_price'),
      _FinancialField('items.*.subtotal'),
    ],
  };

  static String collectionKeyForFirestorePath(String collectionPath) {
    if (collectionPath == Collections.shops) return 'shops';
    if (collectionPath == Collections.transactions) return 'transactions';
    if (collectionPath == Collections.invoices) return 'invoices';
    throw ArgumentError.value(
      collectionPath,
      'collectionPath',
      'Not a financial Firestore collection.',
    );
  }

  static int toMinorUnits(num amount) {
    final major = amount.toDouble();
    if (!major.isFinite || major.abs() > maximumMajorUnits) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Amount is outside the safe range.',
      );
    }

    final scaled = major * 100;
    final rounded = scaled.round();
    if ((scaled - rounded).abs() > 0.000001) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Amount contains sub-cent precision.',
      );
    }
    return rounded;
  }

  static double readMajorAmount(
    num? majorUnits,
    Map<String, dynamic>? companions,
    String fieldPath,
  ) {
    final minorUnits = companions?[fieldPath];
    if (minorUnits is int) {
      if (majorUnits == null) return minorUnits / 100;
      try {
        if (toMinorUnits(majorUnits) == minorUnits) {
          return minorUnits / 100;
        }
      } on ArgumentError {
        return majorUnits.toDouble();
      }
    }
    return majorUnits?.toDouble() ?? 0;
  }

  static Map<String, dynamic> withMinorUnits(
    String collection,
    Map<String, dynamic> document,
  ) {
    final fields = _schema[collection];
    if (fields == null) {
      throw ArgumentError.value(
        collection,
        'collection',
        'Not a financial collection.',
      );
    }

    final values = <String, int>{};
    final exceptions = <FinancialMigrationException>[];
    final documentId = document['__id'] as String? ?? '';
    for (final field in fields) {
      _collectFieldValues(
        document: document,
        collection: collection,
        documentId: documentId,
        field: field,
        values: values,
        exceptions: exceptions,
      );
    }
    if (exceptions.isNotEmpty) {
      final exception = exceptions.first;
      throw ArgumentError(
        'Cannot write $collection financial data at ${exception.fieldPath}: '
        '${exception.code}.',
      );
    }

    final existing = document[companionField];
    final existingValues = <String, dynamic>{};
    if (existing != null) {
      if (existing is! Map) {
        throw ArgumentError('Existing financial minor-unit data is malformed.');
      }
      existingValues.addAll(Map<String, dynamic>.from(existing));
      for (final entry in existingValues.entries) {
        if (entry.value is! int || values[entry.key] != entry.value) {
          throw ArgumentError(
            'Existing financial minor-unit value conflicts at ${entry.key}.',
          );
        }
      }
    }

    return {
      ...document,
      companionField: {...values, ...existingValues},
    };
  }

  static Map<String, int> companionsAfterUpdate(
    String collection,
    Map<String, dynamic> currentDocument,
    Map<String, dynamic> financialFieldUpdates,
  ) {
    final nextDocument = Map<String, dynamic>.from(currentDocument)
      ..remove(companionField)
      ..addAll(financialFieldUpdates);
    final updated = withMinorUnits(collection, nextDocument);
    return Map<String, int>.from(updated[companionField] as Map);
  }

  static Map<String, int> companionsForBackfill(
    String collection,
    Map<String, dynamic> document,
  ) {
    final authoritativeDocument = Map<String, dynamic>.from(document)
      ..remove(companionField);
    final updated = withMinorUnits(collection, authoritativeDocument);
    return Map<String, int>.from(updated[companionField] as Map);
  }

  static bool hasCurrentCompanions(
    Map<String, dynamic> document,
    Map<String, int> expected,
  ) {
    final existing = document[companionField];
    return existing is Map &&
        existing.length == expected.length &&
        expected.entries.every(
          (entry) =>
              existing[entry.key] is int && existing[entry.key] == entry.value,
        );
  }

  static void validateBackfillPlan({
    required FinancialMinorUnitMigrationPlan plan,
    required String tenantId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty || plan.tenantId != normalizedTenantId) {
      throw StateError(
        'Financial backfill requires a preview for the active workspace',
      );
    }
    if (!plan.isClean) {
      throw StateError(
        'Financial backfill requires a clean verified backup preview',
      );
    }
  }

  static void validateActiveTenantDocument({
    required bool exists,
    required Map<String, dynamic>? data,
  }) {
    if (!exists || data?['active'] != true) {
      throw StateError('workspace-disabled');
    }
  }

  static FinancialMinorUnitMigrationPlan preview({
    required String tenantId,
    required Map<String, dynamic> collections,
  }) {
    if (tenantId.trim().isEmpty) {
      throw ArgumentError.value(
        tenantId,
        'tenantId',
        'A concrete tenant is required.',
      );
    }

    final documents = <FinancialMigrationDocument>[];
    final exceptions = <FinancialMigrationException>[];
    var documentCount = 0;
    var convertibleDocumentCount = 0;
    var alreadyMigratedDocumentCount = 0;

    for (final collection in _schema.keys) {
      final rawDocuments = collections[collection];
      if (rawDocuments is! List) {
        exceptions.add(
          FinancialMigrationException(
            code: FinancialMigrationException.missingCollection,
            collection: collection,
          ),
        );
        continue;
      }

      final seenIds = <String>{};
      final duplicateIds = <String>{};
      final acceptedIds = <String, bool>{};
      for (final rawDocument in rawDocuments) {
        documentCount++;
        if (rawDocument is! Map) {
          exceptions.add(
            FinancialMigrationException(
              code: FinancialMigrationException.invalidDocument,
              collection: collection,
            ),
          );
          continue;
        }

        final document = Map<String, dynamic>.from(rawDocument);
        final documentId = document['__id'];
        if (documentId is! String || documentId.trim().isEmpty) {
          exceptions.add(
            FinancialMigrationException(
              code: FinancialMigrationException.invalidDocument,
              collection: collection,
            ),
          );
          continue;
        }
        if (!seenIds.add(documentId)) {
          if (duplicateIds.add(documentId)) {
            final wasAlreadyMigrated = acceptedIds[documentId];
            if (wasAlreadyMigrated != null) {
              convertibleDocumentCount--;
              if (wasAlreadyMigrated) alreadyMigratedDocumentCount--;
            }
            documents.removeWhere(
              (planned) =>
                  planned.collection == collection &&
                  planned.documentId == documentId,
            );
            exceptions.add(
              FinancialMigrationException(
                code: FinancialMigrationException.duplicateDocument,
                collection: collection,
                documentId: documentId,
              ),
            );
          }
          continue;
        }

        if (document['tenant_id'] != tenantId) {
          exceptions.add(
            FinancialMigrationException(
              code: FinancialMigrationException.crossTenant,
              collection: collection,
              documentId: documentId,
            ),
          );
          continue;
        }

        final values = <String, int>{};
        final documentExceptions = <FinancialMigrationException>[];
        for (final field in _schema[collection]!) {
          _collectFieldValues(
            document: document,
            collection: collection,
            documentId: documentId,
            field: field,
            values: values,
            exceptions: documentExceptions,
          );
        }

        final existing = document[companionField];
        if (existing != null) {
          if (existing is! Map) {
            documentExceptions.add(
              FinancialMigrationException(
                code: FinancialMigrationException.companionConflict,
                collection: collection,
                documentId: documentId,
                fieldPath: companionField,
              ),
            );
          } else {
            final existingValues = Map<String, dynamic>.from(existing);
            for (final entry in existingValues.entries) {
              if (entry.value is! int || values[entry.key] != entry.value) {
                documentExceptions.add(
                  FinancialMigrationException(
                    code: FinancialMigrationException.companionConflict,
                    collection: collection,
                    documentId: documentId,
                    fieldPath: '$companionField.${entry.key}',
                  ),
                );
              }
            }
            values.removeWhere((key, value) => existingValues.containsKey(key));
          }
        }

        if (documentExceptions.isNotEmpty) {
          exceptions.addAll(documentExceptions);
          continue;
        }

        convertibleDocumentCount++;
        if (values.isEmpty) {
          alreadyMigratedDocumentCount++;
          acceptedIds[documentId] = true;
        } else {
          acceptedIds[documentId] = false;
          documents.add(
            FinancialMigrationDocument(
              collection: collection,
              documentId: documentId,
              financialMinorUnits: values,
            ),
          );
        }
      }
    }

    return FinancialMinorUnitMigrationPlan(
      tenantId: tenantId,
      documents: documents,
      exceptions: exceptions,
      documentCount: documentCount,
      convertibleDocumentCount: convertibleDocumentCount,
      alreadyMigratedDocumentCount: alreadyMigratedDocumentCount,
      companionFieldCount: documents.fold(
        0,
        (count, document) => count + document.financialMinorUnits.length,
      ),
    );
  }

  static void _collectFieldValues({
    required Map<String, dynamic> document,
    required String collection,
    required String documentId,
    required _FinancialField field,
    required Map<String, int> values,
    required List<FinancialMigrationException> exceptions,
  }) {
    final segments = field.path.split('.');
    _walkField(
      current: document,
      segments: segments,
      segmentIndex: 0,
      outputPath: const [],
      collection: collection,
      documentId: documentId,
      field: field,
      values: values,
      exceptions: exceptions,
      found: false,
    );
  }

  static void _walkField({
    required dynamic current,
    required List<String> segments,
    required int segmentIndex,
    required List<String> outputPath,
    required String collection,
    required String documentId,
    required _FinancialField field,
    required Map<String, int> values,
    required List<FinancialMigrationException> exceptions,
    required bool found,
  }) {
    final segment = segments[segmentIndex];
    final isLeaf = segmentIndex == segments.length - 1;
    if (segment == '*') {
      if (current == null && !found) return;
      if (current is! List) {
        exceptions.add(
          FinancialMigrationException(
            code: FinancialMigrationException.invalidStructure,
            collection: collection,
            documentId: documentId,
            fieldPath: outputPath.join('.'),
          ),
        );
        return;
      }
      for (var index = 0; index < current.length; index++) {
        final item = current[index];
        if (item is! Map) {
          exceptions.add(
            FinancialMigrationException(
              code: FinancialMigrationException.invalidStructure,
              collection: collection,
              documentId: documentId,
              fieldPath: [...outputPath, '$index'].join('.'),
            ),
          );
          continue;
        }
        _walkField(
          current: item,
          segments: segments,
          segmentIndex: segmentIndex + 1,
          outputPath: [...outputPath, '$index'],
          collection: collection,
          documentId: documentId,
          field: field,
          values: values,
          exceptions: exceptions,
          found: true,
        );
      }
      return;
    }

    if (current is! Map || !current.containsKey(segment)) {
      if (field.required && !found && segmentIndex == 0) {
        exceptions.add(
          FinancialMigrationException(
            code: FinancialMigrationException.missingAmount,
            collection: collection,
            documentId: documentId,
            fieldPath: field.path,
          ),
        );
      }
      return;
    }
    final value = current[segment];
    final path = [...outputPath, segment];
    if (!isLeaf) {
      if (value == null) return;
      _walkField(
        current: value,
        segments: segments,
        segmentIndex: segmentIndex + 1,
        outputPath: path,
        collection: collection,
        documentId: documentId,
        field: field,
        values: values,
        exceptions: exceptions,
        found: true,
      );
      return;
    }
    if (value == null && !field.required) return;
    if (value is! num) {
      exceptions.add(
        FinancialMigrationException(
          code: FinancialMigrationException.invalidAmount,
          collection: collection,
          documentId: documentId,
          fieldPath: path.join('.'),
        ),
      );
      return;
    }
    try {
      values[path.join('.')] = toMinorUnits(value);
    } on ArgumentError {
      exceptions.add(
        FinancialMigrationException(
          code: FinancialMigrationException.invalidAmount,
          collection: collection,
          documentId: documentId,
          fieldPath: path.join('.'),
        ),
      );
    }
  }
}

class FinancialMinorUnitMigrationPlan {
  FinancialMinorUnitMigrationPlan({
    required this.tenantId,
    required List<FinancialMigrationDocument> documents,
    required List<FinancialMigrationException> exceptions,
    required this.documentCount,
    required this.convertibleDocumentCount,
    required this.alreadyMigratedDocumentCount,
    required this.companionFieldCount,
  }) : documents = List.unmodifiable(documents),
       exceptions = List.unmodifiable(exceptions);

  final String tenantId;
  final List<FinancialMigrationDocument> documents;
  final List<FinancialMigrationException> exceptions;
  final int documentCount;
  final int convertibleDocumentCount;
  final int alreadyMigratedDocumentCount;
  final int companionFieldCount;

  int get eligibleDocumentCount => convertibleDocumentCount;
  bool get isClean => exceptions.isEmpty;
}

class FinancialMigrationDocument {
  FinancialMigrationDocument({
    required this.collection,
    required this.documentId,
    required Map<String, int> financialMinorUnits,
  }) : financialMinorUnits = Map.unmodifiable(financialMinorUnits);

  final String collection;
  final String documentId;
  final Map<String, int> financialMinorUnits;
}

class FinancialMigrationException {
  const FinancialMigrationException({
    required this.code,
    required this.collection,
    this.documentId = '',
    this.fieldPath = '',
  });

  static const missingCollection = 'missing_collection';
  static const invalidDocument = 'invalid_document';
  static const duplicateDocument = 'duplicate_document';
  static const crossTenant = 'cross_tenant';
  static const missingAmount = 'missing_amount';
  static const invalidAmount = 'invalid_amount';
  static const invalidStructure = 'invalid_structure';
  static const companionConflict = 'companion_conflict';

  final String code;
  final String collection;
  final String documentId;
  final String fieldPath;
}

class _FinancialField {
  const _FinancialField(this.path, {this.required = false});

  final String path;
  final bool required;
}
