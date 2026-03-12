import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_file.dart';

/// Immutable state for editorial metadata.
class EditorialState {
  final bool isEditorial;
  final bool isAI;
  final String city;
  final String country;
  final DateTime? date;

  const EditorialState({
    this.isEditorial = false,
    this.isAI = false,
    this.city = '',
    this.country = '',
    this.date,
  });

  EditorialState copyWith({
    bool? isEditorial,
    bool? isAI,
    String? city,
    String? country,
    Object? date = _sentinel,
  }) {
    return EditorialState(
      isEditorial: isEditorial ?? this.isEditorial,
      isAI: isAI ?? this.isAI,
      city: city ?? this.city,
      country: country ?? this.country,
      date: date == _sentinel ? this.date : date as DateTime?,
    );
  }
}

const _sentinel = Object();

class EditorialStateNotifier extends Notifier<EditorialState> {
  @override
  EditorialState build() => const EditorialState();

  void setEditorial(bool value) =>
      state = state.copyWith(isEditorial: value);

  void setAI(bool value) =>
      state = state.copyWith(isAI: value);

  void setCity(String value) =>
      state = state.copyWith(city: value);

  void setCountry(String value) =>
      state = state.copyWith(country: value);

  void setDate(DateTime? value) =>
      state = state.copyWith(date: value);

  /// Sync editorial state from a selected AppFile.
  void syncFromFile(AppFile? file) {
    if (file == null) {
      state = const EditorialState();
      return;
    }
    state = EditorialState(
      isEditorial: file.isEditorial,
      isAI: file.tags.contains(AppTags.aiGenerated),
      city: file.editorialCity ?? '',
      country: file.editorialCountry ?? '',
      date: file.editorialDate != null
          ? DateTime.fromMillisecondsSinceEpoch(file.editorialDate!)
          : null,
    );
  }

  /// Reset to defaults (e.g. when selecting a local file not in DB).
  void reset() => state = const EditorialState();
}

final editorialStateProvider =
    NotifierProvider<EditorialStateNotifier, EditorialState>(
  () => EditorialStateNotifier(),
);
