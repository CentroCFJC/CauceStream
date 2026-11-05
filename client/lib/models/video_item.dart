class VideoItem {
  final String id;
  final String name;
  final String fileUrl;
  final String? thumbnailUrl;
  final String? duration;
  final String type;

  const VideoItem({
    required this.id,
    required this.name,
    required this.fileUrl,
    this.thumbnailUrl,
    this.duration,
    this.type = 'video',
  });
}
