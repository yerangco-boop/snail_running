/// 연속 러닝 일수: 오늘까지(오늘 아직 안 뛰었으면 어제까지) 하루도 빠짐없이 이어진 날 수.
/// 오늘 아직 안 뛰었어도 어제까지 이어졌다면 연속을 끊지 않고 그대로 보여 준다.
int computeStreakDays(Iterable<DateTime> workoutDates, DateTime today) {
  final days = <DateTime>{
    for (final d in workoutDates) DateTime(d.year, d.month, d.day),
  };
  var cursor = DateTime(today.year, today.month, today.day);
  if (!days.contains(cursor)) {
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  var count = 0;
  while (days.contains(cursor)) {
    count++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return count;
}
