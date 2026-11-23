import 'units_preferences.dart';

/// Utility class for pressure conversion based on user preference or device locale
class PressureUtils {
  /// Converts inHg to hPa (hectopascals)
  static double inHgToHpa(double inHg) {
    return inHg * 33.86389;
  }

  /// Converts hPa to inHg
  static double hpaToInHg(double hpa) {
    return hpa / 33.86389;
  }

  /// Converts inHg to mb (millibars) - same as hPa for most purposes
  static double inHgToMb(double inHg) {
    return inHg * 33.86389;
  }

  /// Converts mb to inHg
  static double mbToInHg(double mb) {
    return mb / 33.86389;
  }

  /// Converts hPa to mb (1 hPa = 1 mb, they're equivalent)
  static double hpaToMb(double hpa) {
    return hpa;
  }

  /// Converts mb to hPa
  static double mbToHpa(double mb) {
    return mb;
  }

  /// Formats pressure based on user preference or device locale
  /// All pressures stored internally as inHg, converted for display
  static String formatPressure(double? inHg, {int decimalPlaces = 2}) {
    if (inHg == null) return '-';

    final unit = UnitsPreferences.getPressureUnit();
    final pressure = switch (unit) {
      PressureUnit.inHg => inHg,
      PressureUnit.hPa => inHgToHpa(inHg),
      PressureUnit.mb => inHgToMb(inHg),
    };

    final symbol = UnitsPreferences.getPressureSymbol();
    return '${pressure.toStringAsFixed(decimalPlaces)} $symbol';
  }

  /// Gets the pressure value in the appropriate unit (without symbol)
  static double getPressureInLocalUnit(double inHg) {
    final unit = UnitsPreferences.getPressureUnit();
    return switch (unit) {
      PressureUnit.inHg => inHg,
      PressureUnit.hPa => inHgToHpa(inHg),
      PressureUnit.mb => inHgToMb(inHg),
    };
  }

  /// Gets the pressure unit symbol for the user's preference or device locale
  static String getPressureUnit() {
    return UnitsPreferences.getPressureSymbol();
  }

  /// Gets the pressure input label for input fields
  static String getPressureInputLabel() {
    return 'Pressure (${getPressureUnit()})';
  }

  /// Converts user input pressure (in local unit) to inHg for storage
  /// All pressures stored internally as inHg
  static double? convertInputToInHg(String input) {
    final parsed = double.tryParse(input.trim());
    if (parsed == null) return null;

    final unit = UnitsPreferences.getPressureUnit();
    return switch (unit) {
      PressureUnit.inHg => parsed,
      PressureUnit.hPa => hpaToInHg(parsed),
      PressureUnit.mb => mbToInHg(parsed),
    };
  }

  /// Converts stored inHg pressure to local unit for display in input field
  static String formatForInput(double? inHg, {int decimalPlaces = 2}) {
    if (inHg == null) return '';
    final localValue = getPressureInLocalUnit(inHg);
    return localValue.toStringAsFixed(decimalPlaces);
  }
}
