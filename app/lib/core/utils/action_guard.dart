class ActionGuard {
  bool _locked = false;

  bool get isLocked => _locked;

  bool tryStart() {
    if (_locked) return false;
    _locked = true;
    return true;
  }

  void finish() {
    _locked = false;
  }
}
