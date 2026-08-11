import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/models/floater_config.dart';

void main() {
  test('FloaterConfig serializes to and from JSON', () {
    const config = FloaterConfig(cornerRadius: 16, size: 56, imagePath: 'ball.png');
    final json = config.toJson();
    final restored = FloaterConfig.fromJson(json);
    expect(restored.cornerRadius, 16);
    expect(restored.size, 56);
    expect(restored.imagePath, 'ball.png');
  });
}
