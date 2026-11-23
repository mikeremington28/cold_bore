# Temperature Unit Localization - Test Scenarios

## What the User Requested
The user wanted the app to match the phone settings when it comes to weather display (Celsius vs Fahrenheit).

## What Was Implemented

### ✅ Automatic Locale Detection
The app now automatically detects the device's country/region and determines whether to use Celsius or Fahrenheit:
- **Celsius countries**: Most of the world (UK, Canada, Australia, Europe, Asia, etc.)
- **Fahrenheit countries**: US, Bahamas, Belize, Cayman Islands, Micronesia, Palau

### ✅ Temperature Display
All temperature displays throughout the app now show in the appropriate unit:

**Example 1: Session Export**
- Stored: `temperatureF: 72.5`
- Display (US device): `Weather: 72.5°F; ...`
- Display (UK device): `Weather: 22.5°C; ...`

**Example 2: Weather UI Card**
- Stored: `temperature: 72.5`
- Display (US): `Temperature: 72.5°F`
- Display (UK): `Temperature: 22.5°C`

**Example 3: Session List**
- Stored: `temperatureF: 72.5`
- Display (US): `72°F`
- Display (UK): `23°C`

**Example 4: PDF Export**
- Stored: `session.temperatureF: 72.5`
- Display in PDF (US): `Weather: 72.5°F | ...`
- Display in PDF (UK): `Weather: 22.5°C | ...`

### ✅ User Input
When users enter or receive weather data:

**Weather Fetched via GPS:**
- API returns: `72.5°F`
- Display in input field (US device): `72.5` with label "Temp (°F)"
- Display in input field (UK device): `22.5` with label "Temp (°C)"
- Stored internally as: `72.5°F` (consistent)

**Manual Temperature Entry:**
- User on UK device enters: `22.5`
- User on US device enters: `72.5`
- Both get stored internally as: `72.5°F`
- Both can be retrieved correctly in their local unit

### ✅ Data Consistency
- All data is stored internally in Fahrenheit (no changes to the database schema)
- Conversion happens only at the UI boundaries
- Existing data automatically displays in the user's local unit based on their device locale
- No data migration needed
- Backward compatible with all existing saved sessions

## Modified Locations in Code

1. **Text output formatting** (4 locations):
   - Session export text
   - Weather display UI card
   - Session list card summary
   - PDF export weather summary

2. **Input field interaction** (3 areas):
   - Input field label (dynamic unit display)
   - API response handling (convert to local unit for display)
   - User input parsing (convert to Fahrenheit for storage)

## Testing Checklist

After building and deploying:

- [ ] Test on US device: Temperatures display in °F
- [ ] Test on UK/Canada/Australia device: Temperatures display in °C
- [ ] Test weather fetch: GPS fetched temperatures display in correct unit
- [ ] Test manual entry: Manually entered temperatures are saved correctly
- [ ] Test PDF export: Exported PDFs show temperatures in device's local unit
- [ ] Test existing data: Old sessions show temperatures in correct unit based on device locale
- [ ] Test input field: Label shows correct unit based on device locale
- [ ] Test edge cases: Null temperatures handled gracefully
- [ ] Test precision: Decimal places formatted correctly (1 place for display, 0 for lists)

## Code Quality

- ✅ No external dependencies required (uses built-in Flutter APIs)
- ✅ Single source of truth (`TemperatureUtils` class)
- ✅ Well-documented with comments and docstrings
- ✅ Type-safe (uses Dart's type system)
- ✅ Performance: Minimal overhead (simple math operations)
- ✅ Maintainability: Easy to find and update (all conversions in one utility)
- ✅ Extensibility: Easy to add new features (manual override, caching, etc.)

## Example User Experience

### User in the United States
1. Opens app
2. Grants GPS location permission
3. Clicks "Grab Weather"
4. Sees: `Temperature: 72.5°F` (displayed in Fahrenheit)
5. Temperature field shows label "Temp (°F)"
6. Saves session
7. Can view in list as `72°F`
8. PDF export shows `72.5°F`

### User in the United Kingdom
1. Opens app
2. Grants GPS location permission
3. Clicks "Grab Weather"
4. Sees: `Temperature: 22.5°C` (displayed in Celsius)
5. Temperature field shows label "Temp (°C)"
6. Can manually enter: `22.5` (in Celsius)
7. Saves session
8. Can view in list as `23°C`
9. PDF export shows `22.5°C`

## Notes
- The app uses Open-Meteo API which has no rate limits and no authentication required
- API requests Fahrenheit to keep data consistent internally
- All conversions use standard formulas: C = (F - 32) × 5/9, F = (C × 9/5) + 32
- Locale detection uses `WidgetsBinding.instance.window.locale.countryCode`
- Future enhancement: User setting to override auto-detection if desired
