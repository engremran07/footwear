import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('covers tenant-scoped transaction ledger queries', () {
    final indexFile = File(
      '${Directory.current.path}/../firestore.indexes.json',
    );
    expect(
      indexFile.existsSync(),
      isTrue,
      reason: 'firestore.indexes.json should exist at the repo root.',
    );

    final root =
        jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
    final indexes = (root['indexes'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    final requiredChains = [
      ['tenant_id', 'shop_id', 'created_at'],
      ['tenant_id', 'route_id', 'created_at'],
      ['tenant_id', 'created_at'],
      ['tenant_id', 'edit_request_pending', 'created_at'],
      ['tenant_id', 'created_by', 'created_at'],
    ];

    for (final fields in requiredChains) {
      final containsExactSequence = indexes.any((entry) {
        final actual = (entry['fields'] as List<dynamic>?)
            ?.map(
              (field) => (field as Map<String, dynamic>)['fieldPath'] as String,
            )
            .toList();
        if (actual == null || actual.length < fields.length) return false;
        for (var i = 0; i < fields.length; i++) {
          if (actual[i] != fields[i]) return false;
        }
        return true;
      });

      expect(
        containsExactSequence,
        isTrue,
        reason:
            'Missing Firestore index for tenant-scoped ledger query: $fields',
      );
    }
  });
}
