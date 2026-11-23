import 'units_preferences.dart';

/// Utility class for speed/wind conversion based on user preference or device locale
class SpeedUtils {
  /// Converts MPH to KPH
  static double mphToKph(double mph) {
    return mph * 1.60934;
  }

  /// Converts KPH to MPH
  static double kphToMph(double kph) {
    return kph / 1.60934;
  }

  /// Converts MPH to M/S (meters per second)
  static double mphToMps(double mph) {
    return mph * 0.44704;
  }

  /// Converts M/S to MPH
  static double mpsToMph(double mps) {
    return mps / 0.44704;
  }

  /// Converts KPH to M/S
  static double kphToMps(double kph) {
    return kph / 3.6;
  }

  /// Converts M/S to KPH
  static double mpsToKph(double mps) {
    return mps * 3.6;
  }

  /// Formats speed based on user preference or device locale
  /// All speeds stored internally as MPH, converted for display
  static String formatSpeed(double? mph, {int decimalPlaces = 1}) {
    if (mph == null) return '-';

    final unit = UnitsPreferences.getSpeedUnit();
    final speed = switch (unit) {
      SpeedUnit.mph => mph,
      SpeedUnit.kph => mphToKph(mph),
      SpeedUnit.mps => mphToMps(mph),
    };

    final symbol = UnitsPreferences.getSpeedSymbol();
    return '${speed.toStringAsFixed(decimalPlaces)} $symbol';
  }

  /// Gets the speed value in the appropriate unit (without symbol)
  static double getSpeedInLocalUnit(double mph) {
    final unit = UnitsPreferences.getSpeedUnit();
    return switch (unit) {
      SpeedUnit.mph => mph,
      SpeedUnit.kph => mphToKph(mph),
      SpeedUnit.mps => mphToMps(mph),
    };
  }

  /// Gets the speed unit symbol for the user's preference or device locale
  static String getSpeedUnit() {
    return UnitsPreferences.getSpeedSymbol();
  }

  /// Gets the speed input label for input fields
  static String getSpeedInputLabel() {
    return 'Wind Speed (${getSpeedUnit()})';
  }

  /// Converts user input speed (in local unit) to MPH for storage
  /// All speeds stored internally as MPH
  static double? convertInputToMph(String input) {
    final parsed = double.tryParse(input.trim());
    if (parsed == null) return null;

    final unit = UnitsPreferences.getSpeedUnit();
    return switch (unit) {
      SpeedUnit.mph => parsed,
      SpeedUnit.kph => kphToMph(parsed),
      SpeedUnit.mps => mpsToMph(parsed),
    };
  }

  /// Converts stored MPH speed to local unit for display in input field
  static String formatForInput(double? mph, {int decimalPlaces = 1}) {
    if (mph == null) return '';
    final localValue = getSpeedInLocalUnit(mph);
    return localValue.toStringAsFixed(decimalPlaces);
  }
}
