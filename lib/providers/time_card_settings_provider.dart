import 'package:flutter/material.dart';

import '../models/time_card_schedule.dart';
import '../services/time_card_settings_repository.dart';

class TimeCardSettingsProvider extends ChangeNotifier {
  TimeCardSettingsProvider({TimeCardSettingsRepository? repository})
      : _repository = repository ?? TimeCardSettingsRepository();

  final TimeCardSettingsRepository _repository;

  TimeCardSchedule schedule = TimeCardSchedule.defaults;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded || isLoading) return;
    await load();
  }

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      schedule = await _repository.load();
      _loaded = true;
    } catch (_) {
      errorMessage = 'Unable to load time card schedule.';
      schedule = TimeCardSchedule.defaults;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> save(TimeCardSchedule next) async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _repository.save(next);
      schedule = next;
      _loaded = true;
      return true;
    } catch (_) {
      errorMessage = 'Could not save time card schedule.';
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }
}
