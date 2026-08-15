import 'package:flutter_test/flutter_test.dart';
import 'package:cold_bore/export_target_logic.dart';

void main() {
  group('cold bore export target creation', () {
    test('creates target only for logged rifle and ammo combos', () {
      expect(
        shouldCreateColdBoreExportTarget(
          rifleId: 'rifle-1',
          ammoId: 'ammo-1',
          hasLoggedColdBore: true,
        ),
        isTrue,
      );

      expect(
        shouldCreateColdBoreExportTarget(
          rifleId: 'rifle-1',
          ammoId: 'ammo-1',
          hasLoggedColdBore: false,
        ),
        isFalse,
      );

      expect(
        shouldCreateColdBoreExportTarget(
          rifleId: null,
          ammoId: 'ammo-1',
          hasLoggedColdBore: true,
        ),
        isFalse,
      );

      expect(
        shouldCreateColdBoreExportTarget(
          rifleId: 'rifle-1',
          ammoId: null,
          hasLoggedColdBore: true,
        ),
        isFalse,
      );
    });
  });
}
