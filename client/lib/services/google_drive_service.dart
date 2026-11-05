import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/browser_item.dart';
import '../models/category.dart';
import '../models/experience.dart';
import '../models/video_item.dart';

class GoogleDriveService {
  final http.Client _client;

  GoogleDriveService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Category>> fetchCatalog() async {
    final folderNames = await _listFolderNames();
    final categories = <Category>[];

    for (final folder in folderNames) {
      final subfolders = await _listSubfolders(folder['id']!);
      if (subfolders.isEmpty) continue;

      final experiences = <Experience>[];
      for (final sub in subfolders) {
        final coverUrl = await _findCover(sub['id']!);
        final isAdvanced = await _hasCauceJson(sub['id']!);
        experiences.add(Experience(
          id: sub['id']!,
          name: sub['name']!,
          category: folder['name']!,
          driveFolderId: sub['id']!,
          coverUrl: coverUrl,
          type: isAdvanced ? ExperienceType.advanced : ExperienceType.simple,
        ));
      }

      DateTime? modifiedTime;
      if (folder['modifiedTime'] != null && folder['modifiedTime']!.isNotEmpty) {
        modifiedTime = DateTime.tryParse(folder['modifiedTime']!);
      }

      categories.add(Category(
        id: folder['id']!,
        name: folder['name']!,
        experiences: experiences,
        modifiedTime: modifiedTime,
      ));
    }

    categories.sort((a, b) {
      final aName = a.name.toLowerCase().replaceAll(' ', '');
      final bName = b.name.toLowerCase().replaceAll(' ', '');
      if (aName == 'googletv') return -1;
      if (bName == 'googletv') return 1;
      return 0;
    });

    return categories;
  }

  Future<List<Map<String, String>>> _listFolderNames() async {
    final url = '${AppConfig.driveBaseUrl}/files'
        '?q=%27${AppConfig.driveFolderId}%27+in+parents'
        '+and+mimeType=%27application/vnd.google-apps.folder%27'
        '+and+trashed=false'
        '&key=${AppConfig.driveApiKey}'
        '&fields=files(id,name,modifiedTime)'
        '&orderBy=modifiedTime+desc';

    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List<dynamic>? ?? [];
        return files.map((f) => {
          'id': f['id'] as String,
          'name': f['name'] as String,
          'modifiedTime': f['modifiedTime'] as String? ?? '',
        }).toList();
      }
    } catch (_) {}

    return [];
  }

  Future<List<Map<String, String>>> _listSubfolders(String parentId) async {
    final url = '${AppConfig.driveBaseUrl}/files'
        '?q=%27$parentId%27+in+parents'
        '+and+mimeType=%27application/vnd.google-apps.folder%27'
        '+and+trashed=false'
        '&key=${AppConfig.driveApiKey}'
        '&fields=files(id,name)'
        '&orderBy=name';

    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List<dynamic>? ?? [];
        return files.map((f) => {
          'id': f['id'] as String,
          'name': f['name'] as String,
        }).toList();
      }
    } catch (_) {}

    return [];
  }

  Future<String?> _findCover(String folderId) async {
    final url = '${AppConfig.driveBaseUrl}/files'
        '?q=%27$folderId%27+in+parents'
        '+and+mimeType+contains+%27image%27'
        '+and+trashed=false'
        '&key=${AppConfig.driveApiKey}'
        '&fields=files(id,name)';

    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List<dynamic>? ?? [];

        for (final f in files) {
          final name = f['name'] as String;
          final lowerName = name.toLowerCase();
          final ext = lowerName.contains('.') ? lowerName.split('.').last : '';
          final baseName = lowerName.contains('.')
              ? lowerName.substring(0, lowerName.lastIndexOf('.'))
              : lowerName;

          if (baseName == 'portada' && ['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
            final fileId = f['id'] as String;
            return '${AppConfig.driveDownloadUrl}/$fileId?alt=media&key=${AppConfig.driveApiKey}';
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _hasCauceJson(String folderId) async {
    final url = '${AppConfig.driveBaseUrl}/files'
        '?q=name=%27cauce.json%27'
        '+and+%27$folderId%27+in+parents'
        '+and+trashed=false'
        '&key=${AppConfig.driveApiKey}'
        '&fields=files(id)';
    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List<dynamic>? ?? [];
        return files.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  Future<List<VideoItem>> listMediaInFolder(String folderId) async {
    final url = '${AppConfig.driveBaseUrl}/files'
        '?q=%27$folderId%27+in+parents'
        '+and+trashed=false'
        '&key=${AppConfig.driveApiKey}'
        '&fields=files(id,name,thumbnailLink,videoMediaMetadata)';

    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List<dynamic>? ?? [];
        final items = <VideoItem>[];

        for (final f in files) {
          final fileId = f['id'] as String;
          final fileName = f['name'] as String;
          final lowerName = fileName.toLowerCase();

          final String? type;
          final String cleanName;

          if (lowerName.endsWith('.mp4')) {
            type = 'video';
            cleanName = fileName.substring(0, fileName.length - 4);
          } else if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
            type = 'image';
            cleanName = _stripExtension(fileName);
          } else if (lowerName.endsWith('.png')) {
            type = 'image';
            cleanName = _stripExtension(fileName);
          } else if (lowerName.endsWith('.webp')) {
            type = 'image';
            cleanName = _stripExtension(fileName);
          } else if (lowerName.endsWith('.gif')) {
            type = 'gif';
            cleanName = _stripExtension(fileName);
          } else if (lowerName.endsWith('.pdf')) {
            type = 'pdf';
            cleanName = _stripExtension(fileName);
          } else {
            continue;
          }

          final fileUrl = '${AppConfig.driveDownloadUrl}/$fileId?alt=media&key=${AppConfig.driveApiKey}';
          final thumbnailUrl = f['thumbnailLink'] as String?;

          String? duration;
          if (type == 'video') {
            final metadata = f['videoMediaMetadata'] as Map<String, dynamic>?;
            if (metadata != null && metadata.containsKey('durationMillis')) {
              final millis = int.tryParse(metadata['durationMillis'].toString());
              if (millis != null) {
                duration = _formatDuration(millis);
              }
            }
          }

          items.add(VideoItem(
            id: fileId,
            name: cleanName,
            fileUrl: fileUrl,
            thumbnailUrl: thumbnailUrl,
            duration: duration,
            type: type,
          ));
        }

        return items;
      }
    } catch (_) {}

    return [];
  }

  /// Descarga un archivo de Google Drive a [destination] usando streaming.
  /// Escribe primero a un archivo temporal y lo renombra al final para evitar
  /// dejar un cache parcial si se interrumpe la descarga.
  Future<void> downloadFile(String fileUrl, File destination) async {
    final request = http.Request('GET', Uri.parse(fileUrl));
    final response = await _client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Descarga fallida: ${response.statusCode} ${response.reasonPhrase}');
    }

    final tempFile = File('${destination.path}.tmp');
    try {
      await response.stream.pipe(tempFile.openWrite());
      if (await destination.exists()) {
        await destination.delete();
      }
      await tempFile.rename(destination.path);
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  Future<List<BrowserItem>> listContents(String folderId) async {
    final folders = await _listSubfolders(folderId);
    final files = await listMediaInFolder(folderId);

    final items = <BrowserItem>[];

    for (final f in folders) {
      items.add(BrowserItem(
        id: f['id']!,
        name: f['name']!,
        isFolder: true,
        folderId: f['id']!,
      ));
    }

    for (final file in files) {
      items.add(BrowserItem(
        id: file.id,
        name: file.name,
        isFolder: false,
        fileUrl: file.fileUrl,
        thumbnailUrl: file.thumbnailUrl,
        fileType: file.type,
      ));
    }

    return items;
  }

  String _stripExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot > 0) return fileName.substring(0, dot);
    return fileName;
  }

  String _formatDuration(int millis) {
    final totalSeconds = millis ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _client.close();
  }
}
