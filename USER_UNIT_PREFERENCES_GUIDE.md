# User-Customizable Unit Preferences

## Overview

The Cold Bore app now includes a comprehensive unit preference system that:

1. **Automatically matches your device's region settings** (US = Fahrenheit, most of world = Metric)
2. **Allows manual override** for users who prefer different units
3. **Persists preferences** across app restarts
4. **Covers all measurement units** used in the app

## Supported Units

### Temperature
- **Celsius (°C)** - Default for most countries
- **Fahrenheit (°F)** - Default for US, Bahamas, Belize, Cayman Islands, Micronesia, Palau

### Wind Speed
- **Miles Per Hour (mph)** - Default for Fahrenheit countries
- **Kilometers Per Hour (km/h)** - Default for Celsius countries
- **Meters Per Second (m/s)** - Alternative metric option

### Barometric Pressure
- **Inches of Mercury (inHg)** - Default for Fahrenheit countries
- **Millibars (mb)** - Default for Celsius countries
- **Hectopascals (hPa)** - Alternative (equivalent to mb)

## How It Works

### Default Behavior (No Override Set)

```
Device Region: United States
  ├─ Temperature: Fahrenheit
  ├─ Wind Speed: MPH
  └─ Pressure: inHg

Device Region: United Kingdom
  ├─ Temperature: Celsius
  ├─ Wind Speed: km/h
  └─ Pressure: mb
```

### With User Override

```
Device Region: United States
User Override: Celsius (temperature only)
  ├─ Temperature: Celsius ← Overridden
  ├─ Wind Speed: MPH ← Using device default
  └─ Pressure: inHg ← Using device default

Device Region: United Kingdom
User Override: Fahrenheit (temperature only)
  ├─ Temperature: Fahrenheit ← Overridden
  ├─ Wind Speed: km/h ← Using device default
  └─ Pressure: mb ← Using device default
```

## Accessing Unit Preferences

### In the App

1. **Open Settings** (or Preferences screen)
2. **Scroll to "Unit Preferences"** section
3. **Select your preferred units** for:
   - Temperature
   - Wind Speed
   - Barometric Pressure
4. **Button: "Reset to Device Settings"** - Reverts all to automatic detection

### In Code

```dart
import 'units_preferences.dart';
import 'temperature_utils.dart';
import 'speed_utils.dart';
import 'pressure_utils.dart';

// Check what units are currently active
TemperatureUnit tempUnit = UnitsPreferences.getTemperatureUnit();
SpeedUnit speedUnit = UnitsPreferences.getSpeedUnit();
PressureUnit pressureUnit = UnitsPreferences.getPressureUnit();

// Format values with current preferences
String tempDisplay = TemperatureUtils.formatTemperature(72.5); // "22.5°C" or "72.5°F"
String speedDisplay = SpeedUtils.formatSpeed(10.5);            // "16.9 km/h" or "10.5 mph"
String pressureDisplay = PressureUtils.formatPressure(29.92);  // "1013 mb" or "29.92 inHg"

// Get unit symbols
String tempSymbol = UnitsPreferences.getTemperatureSymbol();      // "°C" or "°F"
String speedSymbol = UnitsPreferences.getSpeedSymbol();          // "km/h", "mph", or "m/s"
String pressureSymbol = UnitsPreferences.getPressureSymbol();    // "inHg", "mb", or "hPa"
```

## User Scenarios

### Scenario 1: US User Who Prefers Metric

```
Device Setting: United States (Fahrenheit by default)
User Preference Override:
  - Temperature: Celsius
  - Wind Speed: km/h
  - Pressure: mb

Result:
  - All measurements display in metric
  - Preferences persist across app restarts
  - Can reset to device defaults anytime
```

### Scenario 2: International User Visiting US

```
Device Setting: United Kingdom (Celsius by default)
Visiting: United States
Need: Fahrenheit to match local weather apps

Action:
  - Open Settings → Unit Preferences
  - Select Fahrenheit (temporary override)
  - App remembers preference
  - Later can reset to device settings

Result:
  - App displays Fahrenheit while in US
  - Easy to change back when returning home
```

### Scenario 3: Precision Shooter Who Wants Specific Units

```
Device Setting: US (Fahrenheit/mph/inHg)
Shooter Preference: Mixed units for ballistics
  - Temperature: Celsius (for ballistic tables)
  - Wind Speed: Meters per second (for precision)
  - Pressure: hPa (scientific accuracy)

Result:
  - Customized for shooter's needs
  - Each measurement in their preferred unit
  - Preferences always available in settings
```

## Data Storage & Persistence

### Storage Details

- **Storage Method**: `SharedPreferences` (device local storage)
- **Keys Used**:
  - `cold_bore.units.temperature`
  - `cold_bore.units.speed`
  - `cold_bore.units.pressure`
- **Lifetime**: Until user explicitly changes or resets
- **Persistence**: Survives app restart

### Clearing Preferences

**Option 1: Individual Override**
```
User changes override → Automatically persisted
```

**Option 2: Reset All to Device Defaults**
```
Tap "Reset to Device Settings" button → All prefs cleared
App reverts to automatic locale detection
```

## Technical Implementation

### Core Classes

1. **`UnitsPreferences`** (`units_preferences.dart`)
   - Manages all unit preference storage and retrieval
   - Handles override logic and fallback to locale detection

2. **`TemperatureUtils`** (`temperature_utils.dart`)
   - Temperature conversion and formatting
   - Respects `UnitsPreferences` settings

3. **`SpeedUtils`** (`speed_utils.dart`)
   - Wind speed conversion and formatting
   - Respects `UnitsPreferences` settings

4. **`PressureUtils`** (`pressure_utils.dart`)
   - Pressure conversion and formatting
   - Respects `UnitsPreferences` settings

5. **`UnitsPreferencesPanel`** (`units_preferences_panel.dart`)
   - Settings UI widget for changing preferences
   - Shows current settings and device defaults

### Internal Storage Format

All data is stored in a single system to maintain consistency:

```dart
// Temperature: Always stored as Fahrenheit (internally)
double temperatureF = 72.5;

// Speed: Always stored as MPH (internally)
double windSpeedMph = 10.5;

// Pressure: Always stored as inHg (internally)
double pressureInHg = 29.92;

// Conversion happens only at display/input boundaries
// Storage format never changes
```

## Example Usage in UI

### Display Temperature
```dart
// Before (hardcoded)
Text('Temperature: ${temp.toStringAsFixed(1)}°F')

// After (respects preferences)
Text('Temperature: ${TemperatureUtils.formatTemperature(temp)}')
```

### Display Wind
```dart
// Before (hardcoded)
Text('Wind: ${wind.toStringAsFixed(1)} mph')

// After (respects preferences)
Text('Wind: ${SpeedUtils.formatSpeed(wind)}')
```

### Input Field Labels
```dart
// Before (hardcoded)
labelText: 'Temp (°F)'

// After (dynamic)
labelText: TemperatureUtils.getTemperatureInputLabel()
labelText: SpeedUtils.getSpeedInputLabel()
labelText: PressureUtils.getPressureInputLabel()
```

## Conversion Formulas

### Temperature
- C → F: `(C × 9/5) + 32`
- F → C: `(F - 32) × 5/9`

### Speed
- mph → km/h: `mph × 1.60934`
- mph → m/s: `mph × 0.44704`
- km/h → m/s: `km/h ÷ 3.6`

### Pressure
- inHg → hPa: `inHg × 33.86389`
- inHg → mb: `inHg × 33.86389`
- hPa ↔ mb: Equivalent (1:1 ratio)

## Initialization

The app needs to load preferences at startup:

```dart
// In main() or app initialization:
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UnitsPreferences.loadPreferences(); // Load saved preferences
  runApp(const MyApp());
}
```

## Testing Unit Preferences

### Manual Testing

**Test 1: Default Behavior**
1. Start app fresh (no preferences saved)
2. Check units match device region ✓

**Test 2: Override Temperature**
1. Open settings → Temperature preference
2. Select different unit
3. Verify displays change ✓
4. Close and restart app ✓
5. Verify preference persisted ✓

**Test 3: Reset to Defaults**
1. Set custom preferences
2. Tap "Reset to Device Settings"
3. Verify all units revert to device defaults ✓

**Test 4: Input Conversion**
1. Override temperature to Celsius
2. Enter temperature in input field
3. Verify converts correctly to Fahrenheit for storage ✓

**Test 5: Different Regions**
1. Test on US device ✓
2. Test on UK device ✓
3. Test on Australian device ✓
4. Test on Japanese device ✓

## Migration from Previous Version

**Previous Version**: Hardcoded Fahrenheit
**New Version**: Automatic locale detection + user override

### No Migration Needed
- All existing data stored as Fahrenheit (unchanged)
- Existing data automatically displays in user's preferred unit
- Preferences start with device defaults (automatic)
- Users can override anytime

## Future Enhancements

Possible future improvements:
1. **Elevation Units** - Add feet/meters preference
2. **Distance Units** - Add yards/meters preference
3. **Velocity Units** - Add FPS/MPS preference for ballistics
4. **Preset Profiles** - "US Standard", "Metric", "Mixed" presets
5. **Cloud Sync** - Sync preferences across devices

## Troubleshooting

### Units Not Changing After Update
- Ensure `UnitsPreferences.loadPreferences()` is called on app startup
- Check that utilities are using `UnitsPreferences` methods

### Preferences Not Persisting
- Verify `SharedPreferences` is working properly
- Check device has storage permission
- Try "Reset to Device Settings" button

### Wrong Units Displaying
- Verify user's device region is set correctly
- Check if override is accidentally set
- Look at "Device Default" indicator in settings

## Support

For issues with unit preferences:
1. Check "Device Settings" section in app settings
2. Try "Reset to Device Settings" button
3. Verify device region is correctly set
4. Report issue with:
   - Device type (iPhone/iPad)
   - iOS version
   - Device region setting
   - Selected unit preferences
