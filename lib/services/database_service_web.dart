import '../models/workout_record.dart';

// Web stub — sqflite는 웹 미지원, 모든 메서드 no-op
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._();
  static DatabaseService get instance => _instance;
  DatabaseService._();

  Future<int> insertWorkout(WorkoutRecord record) async => 0;
  Future<List<WorkoutRecord>> getWorkouts() async => [];
  Future<void> deleteWorkout(int id) async {}
}
