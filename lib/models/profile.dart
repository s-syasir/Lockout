import 'dart:convert';

class Profile {
  final String id;
  final String name;
  final List<String> blockedPackages;

  const Profile({
    required this.id,
    required this.name,
    required this.blockedPackages,
  });

  Profile copyWith({String? name, List<String>? blockedPackages}) {
    return Profile(
      id: id,
      name: name ?? this.name,
      blockedPackages: blockedPackages ?? this.blockedPackages,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'blockedPackages': blockedPackages,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String,
        blockedPackages: List<String>.from(json['blockedPackages'] as List),
      );

  static List<Profile> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((e) => Profile.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<Profile> profiles) {
    return jsonEncode(profiles.map((p) => p.toJson()).toList());
  }
}
