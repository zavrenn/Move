import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class MoveDatabase {
  MoveDatabase._();

  static final MoveDatabase instance = MoveDatabase._();
  static const _databaseName = 'move.db';
  static const _databaseVersion = 4;
  static const _logsTable = 'movement_logs';
  static const _stepsTable = 'daily_steps';
  static const _sleepTable = 'daily_sleep';
  static const _sleepMigrationTable = 'daily_sleep_v4';

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final databasePath = await getDatabasesPath();
    final db = await openDatabase(
      path.join(databasePath, _databaseName),
      version: _databaseVersion,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE $_logsTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            movement_id TEXT NOT NULL,
            metric TEXT NOT NULL CHECK(metric IN ('reps', 'duration')),
            amount INTEGER NOT NULL CHECK(amount > 0),
            side TEXT CHECK(side IS NULL OR side IN ('left', 'right', 'both')),
            note TEXT,
            performed_at INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_logs_performed_at ON $_logsTable(performed_at DESC)',
        );
        await _createStepsTable(database);
        await _createSleepTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createStepsTable(database);
        if (oldVersion < 3) {
          await _createSleepTable(database);
        } else if (oldVersion < 4) {
          await _migrateSleepTableWithoutDuration(database);
        }
      },
    );
    _database = db;
    return db;
  }

  Future<List<MovementLog>> getAllLogs() async {
    final db = await database;
    final rows = await db.query(
      _logsTable,
      orderBy: 'performed_at DESC, id DESC',
    );
    return rows.map(MovementLog.fromDatabase).toList();
  }

  Future<MovementLog> insertLog(MovementLog log) async {
    final db = await database;
    final id = await db.insert(_logsTable, log.toDatabaseMap());
    return log.copyWith(id: id);
  }

  Future<void> updateLog(MovementLog log) async {
    if (log.id == null) return;
    final db = await database;
    await db.update(
      _logsTable,
      log.toDatabaseMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<void> deleteLog(int id) async {
    final db = await database;
    await db.delete(_logsTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DailyStepCount>> getDailySteps() async {
    final db = await database;
    final rows = await db.query(_stepsTable, orderBy: 'date_key DESC');
    return rows.map(DailyStepCount.fromDatabase).toList();
  }

  Future<void> upsertDailySteps(List<DailyStepCount> values) async {
    if (values.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final value in values) {
      batch.insert(
        _stepsTable,
        value.toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<DailySleepRecord>> getDailySleep() async {
    final db = await database;
    final rows = await db.query(_sleepTable, orderBy: 'date_key DESC');
    return rows.map(DailySleepRecord.fromDatabase).toList();
  }

  Future<void> replaceDailySleepRange({
    required DateTime startDate,
    required DateTime endDate,
    required List<DailySleepRecord> values,
  }) async {
    final startKey = _dateKey(startDate);
    final endKey = _dateKey(endDate);
    if (startKey > endKey) {
      throw ArgumentError.value(
        startDate,
        'startDate',
        'Must precede endDate.',
      );
    }
    for (final value in values) {
      if (value.dateKey < startKey || value.dateKey > endKey) {
        throw ArgumentError.value(
          value.date,
          'values',
          'Sleep record falls outside the replacement range.',
        );
      }
    }
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        _sleepTable,
        where: 'date_key BETWEEN ? AND ?',
        whereArgs: [startKey, endKey],
      );
      for (final value in values) {
        await transaction.insert(
          _sleepTable,
          value.toDatabaseMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  static Future<void> _createStepsTable(Database database) {
    return database.execute('''
      CREATE TABLE $_stepsTable (
        date_key INTEGER PRIMARY KEY,
        steps INTEGER NOT NULL CHECK(steps >= 0),
        synced_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createSleepTable(
    Database database, {
    String tableName = _sleepTable,
  }) {
    return database.execute('''
      CREATE TABLE $tableName (
        date_key INTEGER PRIMARY KEY,
        sleep_start INTEGER NOT NULL,
        sleep_end INTEGER NOT NULL,
        synced_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _migrateSleepTableWithoutDuration(
    Database database,
  ) async {
    await _createSleepTable(database, tableName: _sleepMigrationTable);
    await database.execute('''
      INSERT INTO $_sleepMigrationTable (
        date_key,
        sleep_start,
        sleep_end,
        synced_at
      )
      SELECT date_key, sleep_start, sleep_end, synced_at
      FROM $_sleepTable
    ''');
    await database.execute('DROP TABLE $_sleepTable');
    await database.execute(
      'ALTER TABLE $_sleepMigrationTable RENAME TO $_sleepTable',
    );
  }

  static int _dateKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;
}
