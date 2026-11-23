import 'package:flutter/material.dart';
import 'units_preferences.dart';

/// Utility class for temperature conversion based on device locale or user preference
class TemperatureUtils {
  /// Determines if the device uses Celsius based on system locale
  /// (This is what the app will use if no user override is set)
  static bool shouldUseCelsius() {
    final locale = WidgetsBinding.instance.window.locale;
    // Countries that use Celsius (this is the overwhelming majority)
    // We check if NOT a Fahrenheit country instead
    return !_isFahrenheitCountry(locale.countryCode?.toUpperCase());
  }

  /// Check if a country code uses Fahrenheit
  static bool _isFahrenheitCountry(String? countryCode) {
    if (countryCode == null) return false;
    // Only a few countries officially use Fahrenheit:
    // US, Bahamas, Belize, Cayman Islands, Federated States of Micronesia, Palau
    return const {'US', 'BS', 'BZ', 'KY', 'FM', 'PW'}.contains(countryCode);
  }

  /// Converts Fahrenheit to Celsius
  static double fahrenheitToCelsius(double fahrenheit) {
    return (fahrenheit - 32) * 5 / 9;
  }

  /// Converts Celsius to Fahrenheit
  static double celsiusToFahrenheit(double celsius) {
    return (celsius * 9 / 5) + 32;
  }

  /// Formats temperature based on user preference or device locale
  /// Returns temperature value and unit string (e.g., "72.5°F" or "22.5°C")
  static String formatTemperature(double? fahrenheit,
      {int decimalPlaces = 1}) {
    if (fahrenheit == null) return '-';

    final useCelsius =
        UnitsPreferences.getTemperatureUnit() == TemperatureUnit.celsius;
    final temp = useCelsius ? fahrenheitToCelsius(fahrenheit) : fahrenheit;
    final unit = useCelsius ? '°C' : '°F';

    return '${temp.toStringAsFixed(decimalPlaces)}$unit';
  }

  /// Gets the temperature value in the appropriate unit based on user preference or locale
  static double getTemperatureInLocalUnit(double fahrenheit) {
    final useCelsius =
        UnitsPreferences.getTemperatureUnit() == TemperatureUnit.celsius;
    return useCelsius ? fahrenheitToCelsius(fahrenheit) : fahrenheit;
  }

  /// Gets the temperature unit symbol for the user's preference or device locale
  static String getTemperatureUnit() {
    return UnitsPreferences.getTemperatureSymbol();
  }

  /// Gets the temperature unit label for input fields (e.g., "Temp (°C)" or "Temp (°F)")
  static String getTemperatureInputLabel() {
    return 'Temp (${getTemperatureUnit()})';
  }

  /// Converts user input temperature (in local unit) to Fahrenheit for storage
  static double? convertInputToFahrenheit(String input) {
    final parsed = double.tryParse(input.trim());
    if (parsed == null) return null;
    final useCelsius =
        UnitsPreferences.getTemperatureUnit() == TemperatureUnit.celsius;
    return useCelsius ? celsiusToFahrenheit(parsed) : parsed;
  }

  /// Converts stored Fahrenheit temperature to local unit for display in input field
  static String formatForInput(double? fahrenheit, {int decimalPlaces = 1}) {
    if (fahrenheit == null) return '';
    final localValue = getTemperatureInLocalUnit(fahrenheit);
    return localValue.toStringAsFixed(decimalPlaces);
  }
}

