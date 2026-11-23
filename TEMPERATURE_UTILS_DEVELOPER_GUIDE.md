# Temperature Utils Usage Guide

## For Developers

### Quick Reference

#### Display a temperature with appropriate unit:
```dart
import 'temperature_utils.dart';

// Simple formatting
String formatted = TemperatureUtils.formatTemperature(72.5); // "22.5°C" or "72.5°F"
String formatted = TemperatureUtils.formatTemperature(72.5, decimalPlaces: 0); // "23°C" or "73°F"
String formatted = TemperatureUtils.formatTemperature(null); // "-"

// Get raw value in local unit (without formatting)
double localTemp = TemperatureUtils.getTemperatureInLocalUnit(72.5);

// Get unit symbol
String unit = TemperatureUtils.getTemperatureUnit(); // "°C" or "°F"
```

#### Handle user input:
```dart
// Convert user input from local unit to Fahrenheit for storage
double? fahrenheit = TemperatureUtils.convertInputToFahrenheit("22.5"); // On Celsius device: converts to 72.5°F
double? fahrenheit = TemperatureUtils.convertInputToFahrenheit("72.5"); // On US device: stays 72.5°F

// Format stored Fahrenheit value for input field display
String forInput = TemperatureUtils.formatForInput(72.5); // "22.5" (on Celsius device) or "72.5" (on US device)
```

#### Update input field labels:
```dart
// Get the appropriate label for temperature input fields
String label = TemperatureUtils.getTemperatureInputLabel(); // "Temp (°C)" or "Temp (°F)"
```

#### Check device locale:
```dart
// Determine if Celsius should be used
bool useCelsius = TemperatureUtils.shouldUseCelsius(); // true for most countries

// Manual conversions
double celsius = TemperatureUtils.fahrenheitToCelsius(72.5); // 22.5
double fahrenheit = TemperatureUtils.celsiusToFahrenheit(22.5); // 72.5
```

## Adding New Temperature Displays

If you add a new temperature display location:

1. **For read-only display** (e.g., text showing current temperature):
   ```dart
   Text('Temperature: ${TemperatureUtils.formatTemperature(sessionTemp)}')
   ```

2. **For user input** (e.g., text field):
   ```dart
   decoration: InputDecoration(
     labelText: TemperatureUtils.getTemperatureInputLabel(),
   ),
   ```

3. **When saving user input**:
   ```dart
   double? fahrenheit = TemperatureUtils.convertInputToFahrenheit(textFieldValue);
   ```

4. **When showing stored value in input field**:
   ```dart
   textController.text = TemperatureUtils.formatForInput(storedFahrenheit);
   ```

## API Integration

The app currently uses Open-Meteo API (`api.open-meteo.com`), which is requested with:
```
temperature_unit=fahrenheit&wind_speed_unit=mph
```

This ensures the API returns data in Fahrenheit, which matches the app's internal storage. The UI conversion happens only when displaying to users.

If you change to a different weather API:
1. Keep requesting temperatures in Fahrenheit (or convert the API response to Fahrenheit)
2. Store internally as Fahrenheit
3. Use `TemperatureUtils` for all display/input conversions

## Testing in Different Locales

To test the feature in different locales without changing your device settings:

1. **Temporarily modify** `shouldUseCelsius()` to return a hardcoded value for testing:
   ```dart
   static bool shouldUseCelsius() {
     // return true; // Force Celsius for testing
     // return false; // Force Fahrenheit for testing
     final locale = WidgetsBinding.instance.window.locale;
     return !_isFahrenheitCountry(locale.countryCode?.toUpperCase());
   }
   ```

2. Or simulate different country codes during testing.

## Performance Considerations

- `shouldUseCelsius()` queries the device locale via `WidgetsBinding.instance.window.locale` each time it's called
- This is a cheap operation (single property access)
- If performance is a concern, the result could be cached in `main()` or a provider
- For now, the per-call cost is negligible and ensures the app respects locale changes without requiring app restart

## Future Enhancements

Possible future improvements:
1. Add user preference to override automatic locale detection (Settings page option)
2. Cache the locale preference to reduce repeated locale lookups
3. Support for additional units (Kelvin) if needed
4. Internationalized temperature labels/formats
