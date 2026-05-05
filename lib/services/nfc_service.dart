import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

// NFC tag read/write for Lockout profile triggers.
//
// We store the profile ID as a plain text NDEF record.
// Any NTAG213 tag works (~$0.50 each).
//
// iOS constraint: CoreNFC requires the app to be in the FOREGROUND.
// The user must open Lockout, then tap the tag.
// Android: NFC dispatch launches the app from anywhere.
class NfcService {
  static const _recordType = 'lockout:profile';

  // Reads a tag and returns the profile ID written on it.
  // Returns null if the tag has no Lockout record.
  static Future<String?> readTag() async {
    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) return null;

    await FlutterNfcKit.poll(timeout: const Duration(seconds: 20));
    try {
      final records = await FlutterNfcKit.readNDEFRecords(cached: false);
      for (final record in records) {
        if (record is ndef.TextRecord) {
          final text = record.text ?? '';
          if (text.startsWith('$_recordType:')) {
            return text.substring('$_recordType:'.length);
          }
        }
      }
      return null;
    } finally {
      await FlutterNfcKit.finish();
    }
  }

  // Writes a profile ID to a writable NFC tag.
  static Future<void> writeTag(String profileId) async {
    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      throw StateError('NFC not available');
    }

    final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 20));
    if (tag.ndefWritable != true) {
      await FlutterNfcKit.finish();
      throw StateError('Tag is not writable');
    }

    try {
      await FlutterNfcKit.writeNDEFRecords([
        ndef.TextRecord(
          text: '$_recordType:$profileId',
          language: 'en',
        ),
      ]);
    } finally {
      await FlutterNfcKit.finish();
    }
  }

  // Cancels an in-progress poll (e.g. user tapped Cancel during write).
  static Future<void> cancelNfc() async {
    try {
      await FlutterNfcKit.finish();
    } catch (_) {}
  }

  static Future<bool> get isAvailable async {
    try {
      final a = await FlutterNfcKit.nfcAvailability;
      return a == NFCAvailability.available;
    } catch (_) {
      return false;
    }
  }
}
