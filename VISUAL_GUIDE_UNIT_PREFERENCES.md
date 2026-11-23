# Visual Guide: Unit Preferences Feature

## User Interface - Settings Panel

```
┌──────────────────────────────────────────────────────────┐
│                   UNIT PREFERENCES                       │
├──────────────────────────────────────────────────────────┤
│                                                          │
│ Your device's region is set to use metric or imperial  │
│ units. You can override these preferences below.        │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ⚙️  TEMPERATURE              [Device Default: °F]     │
│  ◉ Celsius (°C)                                         │
│  ○ Fahrenheit (°F)                                      │
│                                                          │
│  ⚙️  WIND SPEED               [Custom] 🔵             │
│  ◉ Miles per Hour (mph)                                 │
│  ○ Kilometers per Hour (km/h)                           │
│  ○ Meters per Second (m/s)                              │
│                                                          │
│  ⚙️  BAROMETRIC PRESSURE      [Device Default]         │
│  ◉ Inches of Mercury (inHg)                             │
│  ○ Millibars (mb)                                       │
│  ○ Hectopascals (hPa)                                   │
│                                                          │
│                   ┌─────────────────┐                  │
│                   │ 🔄 Reset to     │                  │
│                   │ Device Settings │                  │
│                   └─────────────────┘                  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

## Weather Display Examples

### Example 1: Default US User (No Override)

```
Device Region: United States ⚙️
User Preferences: (None - using defaults)

┌─────────────────────────────┐
│   WEATHER CONDITIONS        │
├─────────────────────────────┤
│                             │
│ Temperature: 72.5°F ✓       │
│ Wind Speed: 10.5 mph ✓      │
│ Pressure: 29.92 inHg ✓      │
│                             │
│ ⚙️ Grab Weather             │
│                             │
└─────────────────────────────┘
```

### Example 2: UK User (Default - Device Locale)

```
Device Region: United Kingdom ⚙️
User Preferences: (None - using defaults)

┌─────────────────────────────┐
│   WEATHER CONDITIONS        │
├─────────────────────────────┤
│                             │
│ Temperature: 22.5°C ✓       │
│ Wind Speed: 16.9 km/h ✓     │
│ Pressure: 1013 mb ✓         │
│                             │
│ ⚙️ Grab Weather             │
│                             │
└─────────────────────────────┘
```

### Example 3: International User - Mixed Units

```
Device Region: United Kingdom ⚙️
User Preferences: 
  • Temperature: Fahrenheit (override)
  • Wind Speed: Meters per second (override)
  • Pressure: (default = mb)

┌─────────────────────────────┐
│   WEATHER CONDITIONS        │
├─────────────────────────────┤
│                             │
│ Temperature: 72.5°F [Custom]│
│ Wind Speed: 7.5 m/s [Custom]│
│ Pressure: 1013 mb [Default] │
│                             │
│ ⚙️ Grab Weather             │
│                             │
└─────────────────────────────┘
```

## Input Fields - Labels Change Dynamically

### Scenario A: Fahrenheit User

```
Input Field Labels (Fahrenheit User):

┌──────────────────────┐  ┌──────────────────────┐
│ Temp (°F)       [72.5]  │ Wind Speed (mph)[10.5]│
└──────────────────────┘  └──────────────────────┘

┌──────────────────────┐
│Pressure (inHg) [29.92]│
└──────────────────────┘
```

### Scenario B: Celsius User (Default)

```
Input Field Labels (Celsius User):

┌──────────────────────┐  ┌──────────────────────┐
│ Temp (°C)       [22.5]  │Wind Speed (km/h)[16.9]│
└──────────────────────┘  └──────────────────────┘

┌──────────────────────┐
│Pressure (mb)   [1013]  │
└──────────────────────┘
```

### Scenario C: Mixed Units User

```
Input Field Labels (Custom Preferences):

┌──────────────────────┐  ┌──────────────────────┐
│ Temp (°F)       [72.5]  │Wind Speed (m/s) [7.5]│
└──────────────────────┘  └──────────────────────┘

┌──────────────────────┐
│Pressure (mb)   [1013]  │
└──────────────────────┘
```

## Data Flow Diagram

### Complete User Journey

```
┌─────────────────────────────────────────────────────────┐
│ USER LAUNCHES APP                                       │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
        ┌─────────────────────────────┐
        │ Load Preferences from       │
        │ SharedPreferences           │
        └────────────────┬────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
              ▼                     ▼
        [Prefs Found]        [No Prefs]
              │                     │
              ▼                     ▼
     Use Saved Override       Detect Device
     (e.g., Celsius)          Locale
                               (US → °F)
                               (UK → °C)
              │                     │
              └──────────┬──────────┘
                         │
                         ▼
            ┌──────────────────────────┐
            │ Display Weather in       │
            │ User's Preferred Unit    │
            └──────────┬───────────────┘
                       │
           ┌───────────┴────────────┐
           │                        │
           ▼                        ▼
      User Views             User Opens Settings
      Weather               (Optional)
           │                        │
           │                        ▼
           │            ┌──────────────────────┐
           │            │ UnitsPreferencesPanel│
           │            └────────────┬─────────┘
           │                         │
           │                    ┌────┴────┐
           │                    │          │
           │                    ▼          ▼
           │              Change Unit   Reset All
           │              Override      (clear prefs)
           │                    │          │
           │                    ▼          ▼
           │            Save to Shared  Clear Storage
           │            Preferences      & Restart
           │                    │          │
           │                    ▼          ▼
           │            Display Updates Display Updates
           │            All Shows New    Uses Locale
           │            Preference       Again
           │                    │          │
           └────────────┬───────┴──────────┘
                        │
                        ▼
            ┌──────────────────────────┐
            │ User Views Weather in    │
            │ Their Preferred Units    │
            └──────────────────────────┘
```

## Decision Tree: Which Unit to Use?

```
                START
                  │
                  ▼
        ┌─────────────────────┐
        │ Check for User      │
        │ Override in Storage │
        └────┬────────────────┘
             │
        ┌────┴──────────────────────────┐
        │                               │
       YES                              NO
        │                               │
        ▼                               ▼
    ┌────────────┐           ┌──────────────────┐
    │Use Override │          │Detect Device     │
    │             │          │Locale & Region  │
    │• Celsius    │          │                  │
    │• mph        │          └────┬─────────────┘
    │• inHg       │                │
    └────┬────────┘        ┌───────┴────────┐
         │                 │                │
         │            ┌────┴─────┐      ┌───┴──────┐
         │            │           │      │          │
         │           US          Metric  Metric    Metric
         │       (or similar)              │        │
         │            │           │       │        │
         │            ▼           ▼       ▼        ▼
         │      ┌──────────┐ ┌──────┐ ┌──────┐ ┌──────┐
         │      │°F / mph  │ │°C    │ │km/h  │ │mb    │
         │      │inHg      │ │kph   │ │m/s   │ │hPa   │
         │      └──────────┘ └──────┘ └──────┘ └──────┘
         │            │           │       │        │
         └────────────┼───────────┘       └────────┘
                      │                       │
                      └───────────┬───────────┘
                                  │
                                  ▼
                        ┌────────────────────┐
                        │ DISPLAY TO USER    │
                        │ IN PREFERRED UNITS │
                        └────────────────────┘
```

## Session Data - Multiple Users Same Data

```
                 ┌────────────────────────┐
                 │   SESSION IN DATABASE  │
                 ├────────────────────────┤
                 │ temperatureF: 72.5     │
                 │ windSpeedMph: 10.5     │
                 │ pressureInHg: 29.92    │
                 └────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ US USER      │ │ UK USER      │ │ MIXED UNITS  │
    │ (°F, mph,   │ │ (Default °C, │ │ (°F, m/s,   │
    │  inHg)       │ │  km/h, mb)   │ │  mb)         │
    ├──────────────┤ ├──────────────┤ ├──────────────┤
    │ Sees:        │ │ Sees:        │ │ Sees:        │
    │ 72.5°F       │ │ 22.5°C       │ │ 72.5°F       │
    │ 10.5 mph     │ │ 16.9 km/h    │ │ 7.5 m/s      │
    │ 29.92 inHg   │ │ 1013 mb      │ │ 1013 mb      │
    └──────────────┘ └──────────────┘ └──────────────┘
         ✓                ✓                ✓
       Same data, different display!
```

## Settings Panel - States

### State 1: All Device Defaults

```
┌──────────────────────────────────┐
│ TEMPERATURE                      │
│ ⬜ Device Default: Fahrenheit (°F)
│                                  │
│ ◉ Celsius (°C)                   │
│ ○ Fahrenheit (°F)                │
└──────────────────────────────────┘

(Show indicator: NO override is set)
```

### State 2: Some Custom Preferences

```
┌──────────────────────────────────┐
│ TEMPERATURE          🔵 CUSTOM   │ ← Alert badge
│ ⬜ Device Default: Fahrenheit (°F)
│                                  │
│ ◉ Celsius (°C)                   │ ← User override
│ ○ Fahrenheit (°F)                │
└──────────────────────────────────┘

(Show indicator: Custom override is set)
```

### State 3: Ready to Reset

```
┌──────────────────────────────────┐
│ All have 🔵 CUSTOM badge         │
│                                  │
│ ┌──────────────────────────────┐ │
│ │ 🔄 RESET TO DEVICE SETTINGS │ │
│ └──────────────────────────────┘ │
│ (Button enabled & ready to tap)  │
└──────────────────────────────────┘
```

## Mobile Phone Integration

```
iPhone Settings → General → Language & Region
                                │
                                ▼
                        ┌──────────────────┐
                        │ Region: US      │
                        │ Calendar: Greg  │
                        └────────┬─────────┘
                                 │
                    ┌────────────┴──────────────┐
                    │                           │
                    ▼                           ▼
        ┌──────────────────────┐    ┌────────────────────┐
        │ iOS Native Apps      │    │ Cold Bore App      │
        │ (Weather, Health,    │    │                    │
        │  Calendar, etc)      │    │ Automatically      │
        │                      │    │ detects US region  │
        │ Show: °F, mph, inHg  │    │                    │
        │                      │    │ Shows: °F, mph,    │
        └──────────────────────┘    │        inHg ✓      │
                                    └────────────────────┘
```

## Conversion Examples

### Temperature

```
Same Physical Temperature - Different Displays:

Stored: 32°F (Freezing point of water)
      │
      ├─► US User Sees: 32°F ✓
      │
      ├─► UK User Sees: 0°C ✓
      │
      └─► User with Custom Preference: 0°C ✓

All are correct!
```

### Wind Speed

```
Same Physical Wind - Different Displays:

Stored: 10 mph
      │
      ├─► US User Sees: 10 mph ✓
      │
      ├─► UK User Sees: 16.09 km/h ✓
      │
      └─► User with m/s preference: 4.47 m/s ✓

All are correct!
```

### Pressure

```
Same Physical Pressure - Different Displays:

Stored: 29.92 inHg
      │
      ├─► US User Sees: 29.92 inHg ✓
      │
      ├─► UK User Sees: 1013 mb ✓
      │
      └─► User with hPa preference: 1013 hPa ✓

All are correct!
```

## User Journey Timeline

```
Day 1: User gets iPhone (US region)
  └─► Cold Bore app shows: °F, mph, inHg (default)

Day 2: User moves to UK
  └─► Manual update device region to UK
  └─► Cold Bore app shows: °C, km/h, mb (auto detected!)

Day 3: User wants Fahrenheit despite being in UK
  └─► Opens Settings → Unit Preferences
  └─► Selects Fahrenheit (override)
  └─► Cold Bore app shows: °F, km/h, mb (mixed!)

Day 4: User changes mind
  └─► Opens Settings → Reset to Device Settings
  └─► Cold Bore app shows: °C, km/h, mb (back to auto)

Day 5: User travels back to US but iPhone region still UK
  └─► Cold Bore shows: °C, km/h, mb
  └─► User manually sets to Fahrenheit (override)
  └─► Now shows: °F, km/h, mb (custom preference persists!)
```

---

## Summary

```
┌─────────────────────────────────────────────────────────┐
│          UNIT PREFERENCES AT A GLANCE                   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ ✅ Automatic Locale Detection                           │
│    └─ No configuration needed                           │
│                                                         │
│ ✅ User Override Capability                             │
│    └─ Full control, change any unit                     │
│                                                         │
│ ✅ Persistent Storage                                   │
│    └─ Preferences saved indefinitely                    │
│                                                         │
│ ✅ Easy Reset                                           │
│    └─ One tap to revert to device defaults              │
│                                                         │
│ ✅ Beautiful Settings Panel                             │
│    └─ Professional UI, easy to use                      │
│                                                         │
│ ✅ Covers All Units                                     │
│    └─ Temperature, Wind Speed, Pressure                 │
│                                                         │
│ ✅ Backward Compatible                                  │
│    └─ All existing data works unchanged                 │
│                                                         │
│ ✅ Zero Data Changes                                    │
│    └─ Internal storage unchanged                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```
