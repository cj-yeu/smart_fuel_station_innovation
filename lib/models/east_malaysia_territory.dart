enum EastMalaysiaTerritory {
  sabah(storageValue: 'sabah', displayLabel: 'Sabah'),
  sarawak(storageValue: 'sarawak', displayLabel: 'Sarawak'),
  labuan(storageValue: 'labuan', displayLabel: 'Labuan');

  final String storageValue;
  final String displayLabel;

  const EastMalaysiaTerritory({
    required this.storageValue,
    required this.displayLabel,
  });

  static EastMalaysiaTerritory fromStorageValue(String value) {
    for (final territory in values) {
      if (territory.storageValue == value) return territory;
    }

    throw ArgumentError.value(
      value,
      'value',
      'Unknown East Malaysia territory storage value.',
    );
  }
}
