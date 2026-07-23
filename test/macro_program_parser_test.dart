import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_program_parser.dart';

void main() {
  test('find image with feature and minMatches round-trip', () {
    final steps = [
      {
        'type': 'find',
        'image': 'btn.jpg',
        'feature': 'akaze',
        'minMatches': 8,
        'threshold': 0.85,
        'children': <Map<String, dynamic>>[
          {'type': 'click'},
        ],
      },
    ];
    final code = MacroProgramParser.serialize(steps);
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.first['feature'], 'akaze');
    expect(parsed.first['minMatches'], 8);
    expect(parsed.first['image'], 'btn.jpg');
  });
}
