# Developer Guide: Unit Preferences System

## Architecture

The unit preference system consists of three layers:

```
┌─────────────────────────────────────────────┐
│          UI Layer                           │
│  UnitsPreferencesPanel (Settings Widget)    │
├─────────────────────────────────────────────┤
│          Utility Layer                      │
│  TemperatureUtils | SpeedUtils | ...        │
├─────────────────────────────────────────────┤
│          Preference Layer                   │
│  UnitsPreferences (Storage & Detection)     │
├─────────────────────────────────────────────┤
│          Persistence Layer                  │
│  SharedPreferences (Device Local Storage)   │
└─────────────────────────────────────────────┘
```

## Core Files

### 1. `units_preferences.dart` (Core)

The foundation - manages all preference storage, retrieval, and fallback logic.

**Key Methods**:
```dart
// Loading
loadPreferences()           // Load from SharedPreferences on app start

// Setting preferences
setTemperatureUnit(TemperatureUnit)
setSpeedUnit(SpeedUnit)
setPressureUnit(PressureUnit)

// Getting active unit (with fallback)
getTemperatureUnit()        // Returns override or device default
getSpeedUnit()
getPressureUnit()

// Checking override status
hasTemperatureOverride()
hasSpeedOverride()
hasPressureOverride()

// Getting defaults without override
getDefaultTemperatureUnit()
getDefaultSpeedUnit()
getDefaultPressureUnit()

// Display symbols
getTemperatureSymbol()      // "°C" or "°F"
getSpeedSymbol()            // "mph", "km/h", or "m/s"
getPressureSymbol()         // "inHg", "mb", or "hPa"

// User-friendly names
getTemperatureUnitName()    // "Celsius (°C)"
getSpeedUnitName()
getPressureUnitName()
```

### 2. `temperature_utils.dart` (Updated)

Extends the previous implementation to use `UnitsPreferences`.

```dart
TemperatureUtils.formatTemperature(72.5)    // Uses current preference
TemperatureUtils.formatForInput(72.5)       // For input fields
TemperatureUtils.convertInputToFahrenheit("22.5") // User input → storage
TemperatureUtils.getTemperatureInputLabel() // Dynamic label
TemperatureUtils.getTemperatureInLocalUnit(72.5) // Raw value conversion
```

### 3. `speed_utils.dart` (New)

Handles wind speed conversion and formatting.

```dart
SpeedUtils.formatSpeed(10.5)                // Formatted display
SpeedUtils.formatForInput(10.5)             // For input fields
SpeedUtils.convertInputToMph("16.9")        // User input → storage
SpeedUtils.getSpeedInputLabel()             // Dynamic label
SpeedUtils.getSpeedInLocalUnit(10.5)        // Raw value conversion

// Raw conversions (always available)
SpeedUtils.mphToKph(10.5)
SpeedUtils.kphToMps(16.9)
// ... etc
```

### 4. `pressure_utils.dart` (New)

Handles barometric pressure conversion and formatting.

```dart
PressureUtils.formatPressure(29.92)         // Formatted display
PressureUtils.formatForInput(29.92)         // For input fields
PressureUtils.convertInputToInHg("1013")    // User input → storage
PressureUtils.getPressureInputLabel()       // Dynamic label
PressureUtils.getPressureInLocalUnit(29.92) // Raw value conversion

// Raw conversions (always available)
PressureUtils.inHgToHpa(29.92)
PressureUtils.hpaToMb(1013)
// ... etc
```

### 5. `units_preferences_panel.dart` (UI Widget)

Ready-to-use settings widget for changing preferences.

```dart
UnitsPreferencesPanel(
  onChanged: () {
    setState(() {}); // Rebuild when preferences change
  }
)
```

## Integration Checklist

### Step 1: Initialize on App Start

```dart
// In main.dart main() function:
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UnitsPreferences.loadPreferences(); // Add this line
  runApp(const MyApp());
}
```

### Step 2: Add Imports

```dart
// In any file that displays/inputs units:
import 'units_preferences.dart';
import 'temperature_utils.dart';
import 'speed_utils.dart';
import 'pressure_utils.dart';
```

### Step 3: Update Temperature Displays

```dart
// BEFORE
Text('${temp.toStringAsFixed(1)}°F')

// AFTER
Text(TemperatureUtils.formatTemperature(temp))
```

### Step 4: Update Speed Displays

```dart
// BEFORE
Text('${wind.toStringAsFixed(1)} mph')

// AFTER
Text(SpeedUtils.formatSpeed(wind))
```

### Step 5: Update Pressure Displays

```dart
// BEFORE
Text('${pressure.toStringAsFixed(2)} inHg')

// AFTER
Text(PressureUtils.formatPressure(pressure))
```

### Step 6: Update Input Field Labels

```dart
// BEFORE
decoration: InputDecoration(labelText: 'Temp (°F)')

// AFTER
decoration: InputDecoration(labelText: TemperatureUtils.getTemperatureInputLabel())
```

### Step 7: Update Input Parsing

```dart
// BEFORE
double? temp = double.tryParse(_tempField.text);

// AFTER
double? temp = TemperatureUtils.convertInputToFahrenheit(_tempField.text);
```

### Step 8: Add Settings UI

```dart
// In your settings/preferences screen:
UnitsPreferencesPanel(
  onChanged: () {
    setState(() {}); // Rebuild to show updated units
    // Or trigger data refresh if needed
  }
)
```

## Usage Examples

### Example 1: Displaying All Weather Data

```dart
// Storage (internally):
double temperatureF = 72.5;
double windSpeedMph = 10.5;
double pressureInHg = 29.92;

// Display (respects user preferences):
Text('${TemperatureUtils.formatTemperature(temperatureF)}, '
     '${SpeedUtils.formatSpeed(windSpeedMph)}, '
     '${PressureUtils.formatPressure(pressureInHg)}')

// Output examples:
// US user: "72.5°F, 10.5 mph, 29.92 inHg"
// UK user: "22.5°C, 16.9 km/h, 1013 mb"
// If UK user overrides to Fahrenheit: "72.5°F, 16.9 km/h, 1013 mb"
```

### Example 2: Input Processing

```dart
// User enters weather data via form:
final tempInput = _temperatureField.text;
final windInput = _windSpeedField.text;
final pressureInput = _pressureField.text;

// Convert from local unit to storage unit:
final tempF = TemperatureUtils.convertInputToFahrenheit(tempInput);
final windMph = SpeedUtils.convertInputToMph(windInput);
final pressureInHg = PressureUtils.convertInputToInHg(pressureInput);

// All are now in storage units, ready to save:
session.temperatureF = tempF;
session.windSpeedMph = windMph;
session.pressureInHg = pressureInHg;
```

### Example 3: Populating Input Fields

```dart
// When editing existing data:
final session = sessions[0];

// Convert from storage to display unit:
_tempField.text = TemperatureUtils.formatForInput(session.temperatureF);
_windField.text = SpeedUtils.formatForInput(session.windSpeedMph);
_pressureField.text = PressureUtils.formatForInput(session.pressureInHg);

// User sees values in their preferred unit:
// If Celsius preference: "22.5" (not "72.5")
// If mph preference: "10.5" (not "16.9")
```

### Example 4: Conditional Logic Based on Preferences

```dart
// If you need to change behavior based on units:
if (UnitsPreferences.getTemperatureUnit() == TemperatureUnit.celsius) {
  // Do something for Celsius users
} else {
  // Do something for Fahrenheit users
}

// Get the actual symbol for dynamic UI:
final tempSymbol = UnitsPreferences.getTemperatureSymbol();
final speedSymbol = UnitsPreferences.getSpeedSymbol();
```

## Adding New Unit Types

To add support for a new unit (e.g., Elevation in feet/meters):

### 1. Add to `UnitsPreferences`

```dart
enum ElevationUnit { feet, meters }

class UnitsPreferences {
  static const String _prefKeyElevation = 'cold_bore.units.elevation';
  static ElevationUnit? _elevationUnitOverride;

  static Future<void> setElevationUnit(ElevationUnit unit) async {
    _elevationUnitOverride = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyElevation, unit.toString());
  }

  static ElevationUnit getElevationUnit() {
    if (_elevationUnitOverride != null) return _elevationUnitOverride!;
    return _isUseCelsiusLocale() ? ElevationUnit.meters : ElevationUnit.feet;
  }

  static String getElevationSymbol() {
    switch (getElevationUnit()) {
      case ElevationUnit.feet:
        return 'ft';
      case ElevationUnit.meters:
        return 'm';
    }
  }
}
```

### 2. Create Utility Class

```dart
// elevation_utils.dart
import 'units_preferences.dart';

class ElevationUtils {
  static double feetToMeters(double feet) => feet * 0.3048;
  static double metersToFeet(double meters) => meters / 0.3048;

  static String formatElevation(double? feet, {int decimalPlaces = 1}) {
    if (feet == null) return '-';
    final unit = UnitsPreferences.getElevationUnit();
    final value = unit == ElevationUnit.meters ? feetToMeters(feet) : feet;
    final symbol = UnitsPreferences.getElevationSymbol();
    return '${value.toStringAsFixed(decimalPlaces)} $symbol';
  }
  // ... etc
}
```

### 3. Update Settings Panel

Add to `UnitsPreferencesPanel` widget:

```dart
// Elevation Unit Selection
Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Elevation', style: TextStyle(...)),
        const SizedBox(height: 12),
        ...ElevationUnit.values.map((unit) {
          return RadioListTile<ElevationUnit>(
            title: Text(UnitsPreferences.getElevationUnitName(unit)),
            value: unit,
            groupValue: _elevationUnit,
            onChanged: _updateElevationUnit,
          );
        }),
      ],
    ),
  ),
)
```

## Performance Considerations

### Preference Access
```dart
// GOOD: Called once per build
String label = UnitsPreferences.getTemperatureSymbol();

// ACCEPTABLE: Called multiple times (but cheap)
Text(TemperatureUtils.formatTemperature(72.5))
```

### Optimization Options

**Option 1: Cache in Provider/Riverpod**
```dart
// If performance becomes an issue:
final unitPreferencesProvider = StateNotifierProvider<UnitsNotifier, UnitsState>(...);
```

**Option 2: Local Widget Cache**
```dart
class MyWidget extends StatefulWidget {
  late TemperatureUnit _tempUnit;
  
  @override
  void initState() {
    _tempUnit = UnitsPreferences.getTemperatureUnit();
  }
}
```

**Current**: Fine as-is (minimal overhead)

## Testing

### Unit Tests

```dart
// test/units_preferences_test.dart
test('convertTemperature_shouldConvertCelsiusToFahrenheit', () async {
  await UnitsPreferences.setTemperatureUnit(TemperatureUnit.celsius);
  final fahrenheit = TemperatureUtils.convertInputToFahrenheit('0');
  expect(fahrenheit, 32);
});

test('formatTemperature_shouldUsePreference', () async {
  await UnitsPreferences.setTemperatureUnit(TemperatureUnit.celsius);
  final formatted = TemperatureUtils.formatTemperature(32);
  expect(formatted, '0.0°C');
});
```

### Widget Tests

```dart
// test/units_preferences_panel_test.dart
testWidgets('panel_shouldShowAllOptions', (WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: UnitsPreferencesPanel(onChanged: () {}),
    ),
  ));
  
  expect(find.text('Celsius (°C)'), findsOneWidget);
  expect(find.text('Fahrenheit (°F)'), findsOneWidget);
});
```

## Troubleshooting

### Preferences Not Loading
```dart
// Add logging:
debugPrint('Loading units preference...');
await UnitsPreferences.loadPreferences();
debugPrint('Temp unit: ${UnitsPreferences.getTemperatureUnit()}');
```

### Display Not Updating After Change
```dart
// Ensure widget rebuilds:
UnitsPreferencesPanel(
  onChanged: () {
    setState(() {}); // Force rebuild
  }
)
```

### Conversion Accuracy
```dart
// Verify formulas:
print(TemperatureUtils.fahrenheitToCelsius(32)); // Should be 0.0
print(TemperatureUtils.celsiusToFahrenheit(0)); // Should be 32.0
```

## API Reference

See `USER_UNIT_PREFERENCES_GUIDE.md` for end-user documentation.

## Version History

- **v1.0** - Initial implementation with Temperature, Speed, Pressure
- **v2.0** (planned) - Add Elevation, Distance, Velocity units

## Related Files

- `units_preferences.dart` - Core preference management
- `temperature_utils.dart` - Temperature utilities
- `speed_utils.dart` - Speed utilities
- `pressure_utils.dart` - Pressure utilities
- `units_preferences_panel.dart` - Settings UI widget
- `USER_UNIT_PREFERENCES_GUIDE.md` - User guide
