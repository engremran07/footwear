import 'package:cloud_firestore/cloud_firestore.dart';

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
fetchAllQueryDocuments(
  Query<Map<String, dynamic>> query, {
  int pageSize = 500,
}) async {
  if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');

  final documents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument;
  while (true) {
    var pageQuery = query.limit(pageSize);
    if (lastDocument != null) {
      pageQuery = pageQuery.startAfterDocument(lastDocument);
    }
    final page = await pageQuery.get();
    documents.addAll(page.docs);
    if (page.docs.length < pageSize) return documents;
    lastDocument = page.docs.last;
  }
}
