class UnlockGraceTracker {
  UnlockGraceTracker._();

  static final Stopwatch _elapsed = Stopwatch();

  static void markUnlocked() {
    _elapsed
      ..reset()
      ..start();
  }

  static void clear() {
    _elapsed
      ..stop()
      ..reset();
  }

  static bool canBypass(int gracePeriodMinutes) {
    if (gracePeriodMinutes <= 0) return false;
    return _elapsed.isRunning &&
        _elapsed.elapsed <= Duration(minutes: gracePeriodMinutes);
  }
}
