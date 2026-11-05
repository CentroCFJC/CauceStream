enum ExperienceType {
  simple,
  advanced,
}

class Experience {
  final String id;
  final String name;
  final String category;
  final String driveFolderId;
  final String? coverUrl;
  final ExperienceType type;

  const Experience({
    required this.id,
    required this.name,
    required this.category,
    required this.driveFolderId,
    this.coverUrl,
    this.type = ExperienceType.simple,
  });
}
