class BrowserItem {
  final String id;
  final String name;
  final bool isFolder;
  final String? fileUrl;
  final String? thumbnailUrl;
  final String? fileType;
  final String? folderId;

  const BrowserItem({
    required this.id,
    required this.name,
    required this.isFolder,
    this.fileUrl,
    this.thumbnailUrl,
    this.fileType,
    this.folderId,
  });
}
