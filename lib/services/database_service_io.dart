import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/workout_record.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._();
  static DatabaseService get instance => _instance;
  DatabaseService._();

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'snail_running.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE workouts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          distance_km REAL NOT NULL,
          duration_seconds INTEGER NOT NULL,
          avg_pace_sec REAL NOT NULL,
          avg_cadence INTEGER NOT NULL DEFAULT 0,
          calories_burned REAL NOT NULL DEFAULT 0
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE workouts ADD COLUMN avg_cadence INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE workouts ADD COLUMN calories_burned REAL NOT NULL DEFAULT 0');
        }
      },
    );
  }

  Future<int> insertWorkout(WorkoutRecord record) async {
    final db = await _database;
    return db.insert('workouts', record.toMap());
  }

  Future<List<WorkoutRecord>> getWorkouts() async {
    final db = await _database;
    final maps = await db.query('workouts', orderBy: 'date DESC');
    return maps.map(WorkoutRecord.fromMap).toList();
  }

  Future<void> deleteWorkout(int id) async {
    final db = await _database;
    await db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }
}
