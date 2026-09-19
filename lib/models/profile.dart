import 'dart:convert';

// One scheduled window on one weekday. [day] is 1=Monday .. 7=Sunday
// (matches DateTime.monday..DateTime.sunday), so it can be compared directly
// against DateTime.now().weekday.
class DaySchedule {
  final int day;
  final String start; // "HH:MM" 24-hour
  final String end;   // "HH:MM" 24-hour

  const DaySchedule({required this.day, required this.start, required this.end});

  Map<String, dynamic> toJson() => {'day': day, 'start': start, 'end': end};

  factory DaySchedule.fromJson(Map<String, dynamic> json) => DaySchedule(
        day: json['day'] as int,
        start: json['start'] as String,
        end: json['end'] as String,
      );
}

class Profile {
  final String id;
  final String name;
  final List<String> blockedPackages;
  final bool scheduleEnabled;
  final List<DaySchedule> schedule; // one entry per active weekday, at most 7

  const Profile({
    required this.id,
    required this.name,
    required this.blockedPackages,
    this.scheduleEnabled = false,
    this.schedule = const [],
  });

  Profile copyWith({
    String? name,
    List<String>? blockedPackages,
    bool? scheduleEnabled,
    List<DaySchedule>? schedule,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      blockedPackages: blockedPackages ?? this.blockedPackages,
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      schedule: schedule ?? this.schedule,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'blockedPackages': blockedPackages,
        'scheduleEnabled': scheduleEnabled,
        'schedule': schedule.map((d) => d.toJson()).toList(),
      };

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String,
      blockedPackages: List<String>.from(json['blockedPackages'] as List),
      scheduleEnabled: (json['scheduleEnabled'] as bool?) ?? false,
      schedule: _scheduleFromJson(json),
    );
  }

  // Profiles saved before per-day scheduling only had a single daily
  // scheduleStart/scheduleEnd pair. Spread that across all 7 days so an
  // existing schedule keeps firing exactly as it did before.
  static List<DaySchedule> _scheduleFromJson(Map<String, dynamic> json) {
    if (json['schedule'] != null) {
      return (json['schedule'] as List)
          .map((e) => DaySchedule.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final oldStart = json['scheduleStart'] as String?;
    final oldEnd = json['scheduleEnd'] as String?;
    if (oldStart == null || oldEnd == null) return [];
    return List.generate(7, (i) => DaySchedule(day: i + 1, start: oldStart, end: oldEnd));
  }

  static List<Profile> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((e) => Profile.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<Profile> profiles) {
    return jsonEncode(profiles.map((p) => p.toJson()).toList());
  }
}
