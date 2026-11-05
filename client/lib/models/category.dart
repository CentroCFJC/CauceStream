import 'experience.dart';

class Category {
  final String id;
  final String name;
  final List<Experience> experiences;
  final DateTime? modifiedTime;

  const Category({
    required this.id,
    required this.name,
    required this.experiences,
    this.modifiedTime,
  });
}
