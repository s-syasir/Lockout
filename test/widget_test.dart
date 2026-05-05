import 'package:flutter_test/flutter_test.dart';
import 'package:lockout/models/profile.dart';

void main() {
  group('Profile serialization', () {
    test('toJson / fromJson roundtrip', () {
      const profile = Profile(
        id: '123e4567-e89b-12d3-a456-426614174000',
        name: 'Focus',
        blockedPackages: ['com.instagram.android', 'com.twitter.android'],
      );
      final restored = Profile.fromJson(profile.toJson());
      expect(restored.id, profile.id);
      expect(restored.name, profile.name);
      expect(restored.blockedPackages, profile.blockedPackages);
    });

    test('listToJson / listFromJson roundtrip', () {
      final profiles = [
        const Profile(id: 'a', name: 'Focus', blockedPackages: ['com.example.a']),
        const Profile(id: 'b', name: 'Bedtime', blockedPackages: []),
      ];
      final restored = Profile.listFromJson(Profile.listToJson(profiles));
      expect(restored.length, 2);
      expect(restored[0].id, 'a');
      expect(restored[0].blockedPackages, ['com.example.a']);
      expect(restored[1].name, 'Bedtime');
      expect(restored[1].blockedPackages, isEmpty);
    });

    test('listFromJson handles empty list', () {
      expect(Profile.listFromJson('[]'), isEmpty);
    });

    test('copyWith replaces only the named fields', () {
      const p = Profile(id: 'x', name: 'Work', blockedPackages: ['com.pkg']);
      final copy = p.copyWith(name: 'Updated');
      expect(copy.id, 'x');
      expect(copy.name, 'Updated');
      expect(copy.blockedPackages, ['com.pkg']);
    });

    test('copyWith with blockedPackages replaces list', () {
      const p = Profile(id: 'y', name: 'Bedtime', blockedPackages: ['a', 'b']);
      final copy = p.copyWith(blockedPackages: ['c']);
      expect(copy.blockedPackages, ['c']);
      expect(copy.name, 'Bedtime');
    });
  });
}
