import 'package:flutter_test/flutter_test.dart';

double resolveWindHoldSign(String windDirectionValue) {
  final normalized = windDirectionValue.trim().toLowerCase();
  if (normalized.contains('from e') || normalized.contains('east')) {
    return -1.0;
  }
  if (normalized.contains('from w') || normalized.contains('west')) {
    return 1.0;
  }
  return 1.0;
}

void main() {
  test('wind hold flips with wind direction', () {
    expect(resolveWindHoldSign('From W'), 1.0);
    expect(resolveWindHoldSign('From E'), -1.0);
  });
}
