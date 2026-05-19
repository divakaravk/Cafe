import '../../models/models.dart';

/// Local NLP parser for processing voice orders offline.
/// Extracts items and quantities based on predefined number words and fuzzy matching.
class LocalParserService {
  // ─── Number words (Tamil + English + Hindi) ───────────────────
  static const Map<String, int> _numbers = {
    // English
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    // Tamil spoken
    'oru': 1, 'onnu': 1, 'ondru': 1, 'rendu': 2, 'randu': 2,
    'moonu': 3, 'naalu': 4, 'anju': 5, 'aaru': 6,
    'ezhu': 7, 'ettu': 8, 'onbadu': 9, 'pathu': 10,
    // Hindi
    'ek': 1, 'do': 2, 'teen': 3, 'char': 4, 'paanch': 5,
    'chhe': 6, 'saat': 7, 'aath': 8, 'nau': 9, 'das': 10,
    // Digits
    '1': 1, '2': 2, '3': 3, '4': 4, '5': 5,
    '6': 6, '7': 7, '8': 8, '9': 9, '10': 10,
  };

  // ─── Filler words to ignore ────────────────────────────────────
  static const _fillers = {
    'and', 'please', 'give', 'me', 'i', 'want', 'need',
    'order', 'some', 'a', 'an', 'the', 'also', 'with',
  };

  /// Main parse method: takes speech text and menu items, returns a list of orders.
  /// Format: [{'item': String, 'qty': int}]
  List<Map<String, dynamic>> parseOrder(String speech, List<Item> menu) {
    final words = speech
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_fillers.contains(w))
        .toList();

    final List<Map<String, dynamic>> results = [];
    int i = 0;

    while (i < words.length) {
      // Check if current word is a number
      if (_numbers.containsKey(words[i])) {
        final qty = _numbers[words[i]]!;
        // Look ahead for item name (1 or 2 words)
        final item = _findItem(words, i + 1, menu);
        if (item != null) {
          results.add({'item': item.itemName, 'qty': qty});
          i += 2; // skip number + item word
          continue;
        }
      }

      // Check if current word matches a menu item (qty defaults to 1)
      final item = _findItem(words, i, menu);
      if (item != null) {
        // Check if previous word was a number
        final prevQty = i > 0 ? _numbers[words[i - 1]] : null;
        if (prevQty == null) {
          // No number before — check if already added by number-first path
          final alreadyAdded = results.any((r) => r['item'] == item.itemName);
          if (!alreadyAdded) {
            results.add({'item': item.itemName, 'qty': 1});
          }
        }
      }
      i++;
    }

    return results;
  }

  // ─── Fuzzy item finder ─────────────────────────────────────────
  Item? _findItem(List<String> words, int startIdx, List<Item> menu) {
    if (startIdx >= words.length) return null;

    // Try 2-word match first (e.g. "pani puri", "mango juice")
    if (startIdx + 1 < words.length) {
      final twoWord = '${words[startIdx]} ${words[startIdx + 1]}';
      final match = _fuzzyMatch(twoWord, menu);
      if (match != null) return match;
    }

    // Try 1-word match
    return _fuzzyMatch(words[startIdx], menu);
  }

  Item? _fuzzyMatch(String spoken, List<Item> menu) {
    spoken = spoken.toLowerCase();

    for (final item in menu) {
      final name = item.itemName.toLowerCase();

      // Exact match
      if (name == spoken) return item;

      // Check variants as well
      if (item.hasVariants) {
        for (final v in item.variants) {
          final vName = v.variantName.toLowerCase();
          final fullVName = "${item.itemName} ${v.variantName}".toLowerCase();
          if (vName == spoken || fullVName == spoken) return item;
        }
      }

      // Contains match
      if (name.contains(spoken) || spoken.contains(name)) return item;

      // Starts-with match
      if (name.startsWith(spoken) || spoken.startsWith(name)) return item;

      // Fuzzy: similarity score
      if (spoken.length >= 3 && _similarity(spoken, name) > 0.6) return item;
    }
    return null;
  }

  // Simple character overlap similarity score
  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    int matches = 0;
    for (final ch in shorter.split('')) {
      if (longer.contains(ch)) matches++;
    }
    return matches / longer.length;
  }
}
