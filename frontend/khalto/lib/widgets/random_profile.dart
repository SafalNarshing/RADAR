import 'dart:math';

/// Deterministic placeholder identity (name + avatar) for a given seed,
/// used until posts are wired to real profile data.
class RandomProfile {
  static const List<String> _firstNames = [
    'Nicolle', 'Jarly', 'Owen', 'Maya', 'Leo', 'Sasha', 'Theo', 'Priya',
    'Diego', 'Elena', 'Marcus', 'Ivy', 'Noah', 'Zara', 'Felix', 'Amara',
  ];

  static const List<String> _lastNames = [
    'Comas', 'Garcia', 'Bennett', 'Cruz', 'Nolan', 'Reyes', 'Whitfield',
    'Okafor', 'Santos', 'Park', 'Delgado', 'Torres', 'Blake', 'Hart',
  ];

  static ({String name, String avatarUrl}) forSeed(String seed) {
    final rnd = Random(seed.hashCode);
    final first = _firstNames[rnd.nextInt(_firstNames.length)];
    final last = _lastNames[rnd.nextInt(_lastNames.length)];
    final avatarId = rnd.nextInt(70) + 1;
    return (
      name: '$first $last',
      avatarUrl: 'https://i.pravatar.cc/150?img=$avatarId',
    );
  }
}
