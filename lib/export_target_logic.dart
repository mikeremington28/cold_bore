bool shouldCreateColdBoreExportTarget({
  required String? rifleId,
  required String? ammoId,
  required bool hasLoggedColdBore,
}) {
  if (!hasLoggedColdBore) return false;

  final normalizedRifleId = rifleId?.trim();
  final normalizedAmmoId = ammoId?.trim();

  final hasRifle = normalizedRifleId != null &&
      normalizedRifleId.isNotEmpty &&
      normalizedRifleId != 'none-rifle' &&
      normalizedRifleId != '-';

  final hasAmmo = normalizedAmmoId != null &&
      normalizedAmmoId.isNotEmpty &&
      normalizedAmmoId != 'none-ammo' &&
      normalizedAmmoId != '-';

  return hasRifle && hasAmmo;
}
