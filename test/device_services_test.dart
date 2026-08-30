import 'package:flutter_test/flutter_test.dart';
import 'package:move/device_services.dart';
import 'package:move/models.dart';

void main() {
  test(
    'sleep sync includes exact replacement bounds and timing-only records',
    () {
      final sync = DailySleepSync.fromPlatform({
        'startDate': '2026-08-17',
        'endDate': '2026-08-30',
        'records': [
          {
            'date': '2026-08-30',
            'sleepStart': DateTime(2026, 8, 29, 23, 30).millisecondsSinceEpoch,
            'sleepEnd': DateTime(2026, 8, 30, 7, 30).millisecondsSinceEpoch,
          },
        ],
      });

      expect(sync.startDate, DateTime(2026, 8, 17));
      expect(sync.endDate, DateTime(2026, 8, 30));
      expect(sync.records, hasLength(1));
      expect(sync.records.single.date, DateTime(2026, 8, 30));
      expect(sync.records.single.sleepStart.hour, 23);
      expect(sync.records.single.sleepEnd.hour, 7);
      expect(
        sync.records.single.toDatabaseMap(),
        isNot(contains('asleep_minutes')),
      );
    },
  );

  test('sleep sync rejects a missing records snapshot', () {
    expect(
      () => DailySleepSync.fromPlatform({
        'startDate': '2026-08-17',
        'endDate': '2026-08-30',
      }),
      throwsFormatException,
    );
  });

  test('Samsung sleep target parser rejects missing values', () {
    expect(
      () => SamsungSleepTarget.fromPlatform({'bedtimeMinutes': 23 * 60 + 30}),
      throwsFormatException,
    );
  });

  test('Samsung sleep target parser rejects malformed values', () {
    expect(
      () => SamsungSleepTarget.fromPlatform({
        'bedtimeMinutes': 23.5,
        'wakeMinutes': 7 * 60 + 30,
      }),
      throwsFormatException,
    );
    expect(
      () => SamsungSleepTarget.fromPlatform({
        'bedtimeMinutes': 23 * 60 + 30,
        'wakeMinutes': 1440,
      }),
      throwsFormatException,
    );
  });
}
