import 'dart:convert';

class Profile {
  final String id;
  final String name;
  final List<String> blockedPackages;
  final bool scheduleEnabled;
  final String? scheduleStart; // "HH:MM" 24-hour
  final String? scheduleEnd;   // "HH:MM" 24-hour

  const Profile({
    required this.id,
    required this.name,
    required this.blockedPackages,
    this.scheduleEnabled = false,
    this.scheduleStart,
    this.scheduleEnd,
  });

  Profile copyWith({
    String? name,
    List<String>? blockedPackages,
    bool? scheduleEnabled,
    String? scheduleStart,
    String? scheduleEnd,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      blockedPackages: blockedPackages ?? this.blockedPackages,
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      scheduleStart: scheduleStart ?? this.scheduleStart,
      scheduleEnd: scheduleEnd ?? this.scheduleEnd,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'blockedPackages': blockedPackages,
        'scheduleEnabled': scheduleEnabled,
        'scheduleStart': scheduleStart,
        'scheduleEnd': scheduleEnd,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String,
        blockedPackages: List<String>.from(json['blockedPackages'] as List),
        scheduleEnabled: (json['scheduleEnabled'] as bool?) ?? false,
        scheduleStart: json['scheduleStart'] as String?,
        scheduleEnd: json['scheduleEnd'] as String?,
      );

  static List<Profile> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((e) => Profile.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<Profile> profiles) {
    return jsonEncode(profiles.map((p) => p.toJson()).toList());
  }
}
