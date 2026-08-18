import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleDriveBackupFile {
  final String id;
  final String name;
  final DateTime? createdAt;
  final int size;
  final String tenantId;
  final String createdBy;
  final String scope;
  final List<String> routeIds;

  const GoogleDriveBackupFile({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.size,
    required this.tenantId,
    required this.createdBy,
    required this.scope,
    required this.routeIds,
  });
}

class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static const _driveFileScope = 'https://www.googleapis.com/auth/drive.file';
  static const _driveUploadUri =
      'https://www.googleapis.com/upload/drive/v3/files';
  static const _driveFilesUri = 'https://www.googleapis.com/drive/v3/files';
  static Future<void>? _initializeFuture;

  static Future<void> _initialize() {
    return _initializeFuture ??= GoogleSignIn.instance.initialize(
      clientId: _configuredValue('GOOGLE_DRIVE_CLIENT_ID'),
      serverClientId: _configuredValue('GOOGLE_DRIVE_SERVER_CLIENT_ID'),
    );
  }

  static String? _configuredValue(String name) {
    final value = String.fromEnvironment(name).trim();
    return value.isEmpty ? null : value;
  }

  static Future<Map<String, String>> _headers() async {
    await _initialize();
    var account = await GoogleSignIn.instance
        .attemptLightweightAuthentication();
    account ??= await GoogleSignIn.instance.authenticate(
      scopeHint: const [_driveFileScope],
    );
    final headers = await account.authorizationClient.authorizationHeaders(
      const [_driveFileScope],
      promptIfNecessary: true,
    );
    if (headers == null) {
      throw StateError('Google Drive authorization was not granted');
    }
    return headers;
  }

  static Future<GoogleDriveBackupFile> upload({
    required Uint8List bytes,
    required String fileName,
    required String tenantId,
    required String createdBy,
    required String checksum,
    required String scope,
    required List<String> routeIds,
  }) async {
    final authHeaders = await _headers();
    final boundary = 'shoeserp_${DateTime.now().microsecondsSinceEpoch}';
    final metadata = utf8.encode(
      jsonEncode({
        'name': fileName,
        'mimeType': 'application/json',
        'appProperties': {
          'shoeserp': 'true',
          'tenant_id': tenantId,
          'created_by': createdBy,
          'checksum': checksum,
          'scope': scope,
          'route_ids': routeIds.join(','),
        },
      }),
    );
    final prefix = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n',
    );
    final separator = utf8.encode(
      '\r\n--$boundary\r\n'
      'Content-Type: application/json\r\n\r\n',
    );
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    final body = Uint8List(
      prefix.length +
          metadata.length +
          separator.length +
          bytes.length +
          suffix.length,
    );
    var offset = 0;
    void append(List<int> part) {
      body.setRange(offset, offset + part.length, part);
      offset += part.length;
    }

    append(prefix);
    append(metadata);
    append(separator);
    append(bytes);
    append(suffix);

    final response = await http.post(
      Uri.parse(
        '$_driveUploadUri?uploadType=multipart&fields=id,name,createdTime,size',
      ),
      headers: {
        ...authHeaders,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google Drive upload failed (${response.statusCode})');
    }
    return _fileFromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<List<GoogleDriveBackupFile>> list({
    required String tenantId,
    String? createdBy,
  }) async {
    final authHeaders = await _headers();
    final filters = <String>[
      "appProperties has { key='shoeserp' and value='true' }",
      "appProperties has { key='tenant_id' and value='${_escapeQueryValue(tenantId)}' }",
      'trashed=false',
    ];
    if (createdBy != null && createdBy.trim().isNotEmpty) {
      filters.add(
        "appProperties has { key='created_by' and value='${_escapeQueryValue(createdBy)}' }",
      );
    }
    final query = Uri.encodeQueryComponent(filters.join(' and '));
    final response = await http.get(
      Uri.parse(
        '$_driveFilesUri?q=$query&orderBy=createdTime%20desc&fields=files(id,name,createdTime,size,appProperties)',
      ),
      headers: authHeaders,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google Drive listing failed (${response.statusCode})');
    }
    final files = (jsonDecode(response.body)['files'] as List<dynamic>? ?? []);
    return files.whereType<Map<String, dynamic>>().map(_fileFromJson).toList();
  }

  static Future<Uint8List> download({
    required String fileId,
    required String tenantId,
    String? createdBy,
  }) async {
    if (fileId.trim().isEmpty) throw ArgumentError('fileId must not be empty');
    final authHeaders = await _headers();
    final metadataResponse = await http.get(
      Uri.parse(
        '$_driveFilesUri/${Uri.encodeComponent(fileId)}?fields=id,appProperties,trashed',
      ),
      headers: authHeaders,
    );
    if (metadataResponse.statusCode < 200 ||
        metadataResponse.statusCode >= 300) {
      throw StateError(
        'Google Drive backup metadata lookup failed (${metadataResponse.statusCode})',
      );
    }
    final metadata = jsonDecode(metadataResponse.body) as Map<String, dynamic>;
    final properties =
        (metadata['appProperties'] as Map<String, dynamic>?) ?? {};
    if (metadata['trashed'] == true ||
        properties['shoeserp'] != 'true' ||
        properties['tenant_id'] != tenantId ||
        (createdBy != null && properties['created_by'] != createdBy)) {
      throw StateError('Google Drive backup is outside the permitted scope');
    }
    final response = await http.get(
      Uri.parse('$_driveFilesUri/${Uri.encodeComponent(fileId)}?alt=media'),
      headers: authHeaders,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google Drive download failed (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  static GoogleDriveBackupFile _fileFromJson(Map<String, dynamic> json) {
    return GoogleDriveBackupFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'backup.json',
      createdAt: DateTime.tryParse(json['createdTime'] as String? ?? ''),
      size: int.tryParse(json['size'] as String? ?? '') ?? 0,
      tenantId:
        ((json['appProperties'] as Map<String, dynamic>?)?['tenant_id']
          as String?) ??
        '',
      createdBy:
        ((json['appProperties'] as Map<String, dynamic>?)?['created_by']
          as String?) ??
        '',
      scope:
        ((json['appProperties'] as Map<String, dynamic>?)?['scope']
          as String?) ??
        'unknown',
      routeIds: ((json['appProperties'] as Map<String, dynamic>?)?['route_ids']
          as String? ??
        '')
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(),
    );
  }

    static String _escapeQueryValue(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}
