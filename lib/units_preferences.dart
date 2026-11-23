import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

/// Preference keys for unit selections
enum TemperatureUnit { celsius, fahrenheit }
enum SpeedUnit { mph, kph, mps } // mph, kilometers per hour, meters per second
enum PressureUnit { inHg, hPa, mb } // inHg, hectopascals, millibars

/// Manages user unit preferences with automatic locale detection fallback
class UnitsPreferences {
  static const String _prefKeyTemp = 'cold_bore.units.temperature';
  static const String _prefKeySpeed = 'cold_bore.units.speed';
  static const String _prefKeyPressure = 'cold_bore.units.pressure';

  static TemperatureUnit? _tempUnitOverride;
  static SpeedUnit? _speedUnitOverride;
  static PressureUnit? _pressureUnitOverride;

  /// Load preferences from storage
  static Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final tempStr = prefs.getString(_prefKeyTemp);
    if (tempStr != null) {
      _tempUnitOverride = TemperatureUnit.values.firstWhere(
        (e) => e.toString() == tempStr,
        orElse: () => TemperatureUnit.fahrenheit,
      );
    }

    final speedStr = prefs.getString(_prefKeySpeed);
    if (speedStr != null) {
      _speedUnitOverride = SpeedUnit.values.firstWhere(
        (e) => e.toString() == speedStr,
        orElse: () => SpeedUnit.mph,
      );
    }

    final pressureStr = prefs.getString(_prefKeyPressure);
    if (pressureStr != null) {
      _pressureUnitOverride = PressureUnit.values.firstWhere(
        (e) => e.toString() == pressureStr,
        orElse: () => PressureUnit.inHg,
      );
    }
  }

  /// Save unit preference to storage
  static Future<void> setTemperatureUnit(TemperatureUnit unit) async {
    _tempUnitOverride = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyTemp, unit.toString());
  }

  static Future<void> setSpeedUnit(SpeedUnit unit) async {
    _speedUnitOverride = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySpeed, unit.toString());
  }

  static Future<void> setPressureUnit(PressureUnit unit) async {
    _pressureUnitOverride = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyPressure, unit.toString());
  }

  /// Clear all overrides (revert to automatic locale detection)
  static Future<void> clearAllOverrides() async {
    _tempUnitOverride = null;
    _speedUnitOverride = null;
    _pressureUnitOverride = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyTemp);
    await prefs.remove(_prefKeySpeed);
    await prefs.remove(_prefKeyPressure);
  }

  /// Get the active temperature unit (override or auto-detect from locale)
  static TemperatureUnit getTemperatureUnit() {
    if (_tempUnitOverride != null) return _tempUnitOverride!;
    // Fall back to automatic detection based on locale
    return _isUseCelsiusLocale()
        ? TemperatureUnit.celsius
        : TemperatureUnit.fahrenheit;
  }

  /// Get the active speed unit (override or auto-detect from locale)
  static SpeedUnit getSpeedUnit() {
    if (_speedUnitOverride != null) return _speedUnitOverride!;
    // Fall back to automatic detection based on locale
    return _isUseCelsiusLocale() ? SpeedUnit.kph : SpeedUnit.mph;
  }

  /// Get the active pressure unit (override or auto-detect from locale)
  static PressureUnit getPressureUnit() {
    if (_pressureUnitOverride != null) return _pressureUnitOverride!;
    // Fall back to automatic detection based on locale
    return _isUseCelsiusLocale() ? PressureUnit.mb : PressureUnit.inHg;
  }

  /// Check if preference has been manually overridden
  static bool hasTemperatureOverride() => _tempUnitOverride != null;
  static bool hasSpeedOverride() => _speedUnitOverride != null;
  static bool hasPressureOverride() => _pressureUnitOverride != null;

  /// Get locale-based default (without override)
  static TemperatureUnit getDefaultTemperatureUnit() {
    return _isUseCelsiusLocale()
        ? TemperatureUnit.celsius
        : TemperatureUnit.fahrenheit;
  }

  static SpeedUnit getDefaultSpeedUnit() {
    return _isUseCelsiusLocale() ? SpeedUnit.kph : SpeedUnit.mph;
  }

  static PressureUnit getDefaultPressureUnit() {
    return _isUseCelsiusLocale() ? PressureUnit.mb : PressureUnit.inHg;
  }

  /// Private helper - check if locale uses metric (Celsius)
  static bool _isUseCelsiusLocale() {
    final locale = WidgetsBinding.instance.window.locale;
    final countryCode = locale.countryCode?.toUpperCase();
    // Only a few countries use Fahrenheit
    return !const {'US', 'BS', 'BZ', 'KY', 'FM', 'PW'}.contains(countryCode);
  }

  /// Get unit symbol for display
  static String getTemperatureSymbol() {
    return getTemperatureUnit() == TemperatureUnit.celsius ? '°C' : '°F';
  }

  static String getSpeedSymbol() {
    switch (getSpeedUnit()) {
      case SpeedUnit.mph:
        return 'mph';
      case SpeedUnit.kph:
        return 'km/h';
      case SpeedUnit.mps:
        return 'm/s';
    }
  }

  static String getPressureSymbol() {
    switch (getPressureUnit()) {
      case PressureUnit.inHg:
        return 'inHg';
      case PressureUnit.hPa:
        return 'hPa';
      case PressureUnit.mb:
        return 'mb';
    }
  }

  /// Get user-friendly unit names for settings UI
  static String getTemperatureUnitName(TemperatureUnit unit) {
    return unit == TemperatureUnit.celsius
        ? 'Celsius (°C)'
        : 'Fahrenheit (°F)';
  }

  static String getSpeedUnitName(SpeedUnit unit) {
    switch (unit) {
      case SpeedUnit.mph:
        return 'Miles per Hour (mph)';
      case SpeedUnit.kph:
        return 'Kilometers per Hour (km/h)';
      case SpeedUnit.mps:
        return 'Meters per Second (m/s)';
    }
  }

  static String getPressureUnitName(PressureUnit unit) {
    switch (unit) {
      case PressureUnit.inHg:
        return 'Inches of Mercury (inHg)';
      case PressureUnit.hPa:
        return 'Hectopascals (hPa)';
      case PressureUnit.mb:
        return 'Millibars (mb)';
    }
  }
}
