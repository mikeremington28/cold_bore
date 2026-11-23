import 'package:flutter/material.dart';
import 'units_preferences.dart';
import 'temperature_utils.dart';
import 'speed_utils.dart';
import 'pressure_utils.dart';

/// Widget for displaying and managing unit preferences
class UnitsPreferencesPanel extends StatefulWidget {
  final VoidCallback onChanged;

  const UnitsPreferencesPanel({Key? key, required this.onChanged})
      : super(key: key);

  @override
  State<UnitsPreferencesPanel> createState() => _UnitsPreferencesPanelState();
}

class _UnitsPreferencesPanelState extends State<UnitsPreferencesPanel> {
  late TemperatureUnit _tempUnit;
  late SpeedUnit _speedUnit;
  late PressureUnit _pressureUnit;

  @override
  void initState() {
    super.initState();
    _tempUnit = UnitsPreferences.getTemperatureUnit();
    _speedUnit = UnitsPreferences.getSpeedUnit();
    _pressureUnit = UnitsPreferences.getPressureUnit();
  }

  Future<void> _updateTemperatureUnit(TemperatureUnit? unit) async {
    if (unit == null) return;
    setState(() => _tempUnit = unit);
    await UnitsPreferences.setTemperatureUnit(unit);
    widget.onChanged();
  }

  Future<void> _updateSpeedUnit(SpeedUnit? unit) async {
    if (unit == null) return;
    setState(() => _speedUnit = unit);
    await UnitsPreferences.setSpeedUnit(unit);
    widget.onChanged();
  }

  Future<void> _updatePressureUnit(PressureUnit? unit) async {
    if (unit == null) return;
    setState(() => _pressureUnit = unit);
    await UnitsPreferences.setPressureUnit(unit);
    widget.onChanged();
  }

  Future<void> _resetToDefaults() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset to Device Settings?'),
        content: const Text(
          'This will reset all units to match your device\'s region settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (shouldReset == true) {
      await UnitsPreferences.clearAllOverrides();
      setState(() {
        _tempUnit = UnitsPreferences.getTemperatureUnit();
        _speedUnit = UnitsPreferences.getSpeedUnit();
        _pressureUnit = UnitsPreferences.getPressureUnit();
      });
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Units reset to device settings')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultTemp = UnitsPreferences.getDefaultTemperatureUnit();
    final defaultSpeed = UnitsPreferences.getDefaultSpeedUnit();
    final defaultPressure = UnitsPreferences.getDefaultPressureUnit();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Unit Preferences',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Your device\'s region is set to use metric or imperial units. '
            'You can override these preferences below.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        // Temperature Unit Selection
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Temperature',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    if (UnitsPreferences.hasTemperatureOverride())
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Custom',
                          style: TextStyle(fontSize: 10, color: Colors.blue),
                        ),
                      ),
                    if (!UnitsPreferences.hasTemperatureOverride()) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Device Default: ${UnitsPreferences.getTemperatureUnitName(defaultTemp)}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                ...TemperatureUnit.values.map((unit) {
                  return RadioListTile<TemperatureUnit>(
                    title:
                        Text(UnitsPreferences.getTemperatureUnitName(unit)),
                    value: unit,
                    groupValue: _tempUnit,
                    onChanged: _updateTemperatureUnit,
                    contentPadding: EdgeInsets.zero,
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Speed Unit Selection
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Wind Speed',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    if (UnitsPreferences.hasSpeedOverride())
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Custom',
                          style: TextStyle(fontSize: 10, color: Colors.blue),
                        ),
                      ),
                    if (!UnitsPreferences.hasSpeedOverride()) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Device Default: ${UnitsPreferences.getSpeedUnitName(defaultSpeed)}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                ...SpeedUnit.values.map((unit) {
                  return RadioListTile<SpeedUnit>(
                    title: Text(UnitsPreferences.getSpeedUnitName(unit)),
                    value: unit,
                    groupValue: _speedUnit,
                    onChanged: _updateSpeedUnit,
                    contentPadding: EdgeInsets.zero,
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Pressure Unit Selection
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Barometric Pressure',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    if (UnitsPreferences.hasPressureOverride())
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Custom',
                          style: TextStyle(fontSize: 10, color: Colors.blue),
                        ),
                      ),
                    if (!UnitsPreferences.hasPressureOverride()) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Device Default: ${UnitsPreferences.getPressureUnitName(defaultPressure)}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                ...PressureUnit.values.map((unit) {
                  return RadioListTile<PressureUnit>(
                    title: Text(UnitsPreferences.getPressureUnitName(unit)),
                    value: unit,
                    groupValue: _pressureUnit,
                    onChanged: _updatePressureUnit,
                    contentPadding: EdgeInsets.zero,
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Reset Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset to Device Settings'),
          ),
        ),
      ],
    );
  }
}
