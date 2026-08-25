import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/assessment_draft.dart';

/// Local-only storage for an authenticated user's unfinished new assessment.
///
/// Supabase remains the authoritative record for completed assessments. This
/// repository intentionally stores no credentials, company data, provider
/// payloads, or validated-site status. A restored draft must be revalidated
/// before it can be submitted as a validated assessment.
class AssessmentDraftRepository {
  static const _databaseName = 'smart_fuel_station_local.db';
  static const _tableName = 'assessment_drafts';

  Database? _database;

  Future<AssessmentDraft?> loadDraft(String userId) async {
    final normalizedUserId = _requireUserId(userId);
    final database = await _openDatabase();
    final rows = await database.query(
      _tableName,
      where: 'user_id = ?',
      whereArgs: [normalizedUserId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AssessmentDraft.fromDatabaseRow(
      Map<String, Object?>.from(rows.single),
    );
  }

  Future<void> saveDraft(String userId, AssessmentDraft draft) async {
    final normalizedUserId = _requireUserId(userId);
    final database = await _openDatabase();
    await database.insert(
      _tableName,
      draft.toDatabaseRow(userId: normalizedUserId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDraft(String userId) async {
    final normalizedUserId = _requireUserId(userId);
    final database = await _openDatabase();
    await database.delete(
      _tableName,
      where: 'user_id = ?',
      whereArgs: [normalizedUserId],
    );
  }

  Future<Database> _openDatabase() async {
    final existing = _database;
    if (existing != null) return existing;

    final databasePath = path.join(await getDatabasesPath(), _databaseName);
    final database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE $_tableName (
            user_id TEXT PRIMARY KEY NOT NULL,
            location_name TEXT NOT NULL,
            population_density TEXT NOT NULL,
            registered_vehicle_count TEXT NOT NULL,
            nearby_fuel_stations TEXT NOT NULL,
            competitor_distance_km TEXT NOT NULL,
            traffic_level INTEGER NOT NULL,
            road_accessibility INTEGER NOT NULL,
            commercial_activity INTEGER NOT NULL,
            residential_activity INTEGER NOT NULL,
            land_accessibility INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
        ''');
      },
    );
    _database = database;
    return database;
  }

  String _requireUserId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'userId',
        'An authenticated user is required.',
      );
    }
    return normalized;
  }
}
