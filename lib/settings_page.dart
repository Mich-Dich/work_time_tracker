import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // Import main.dart to access MyApp

class SettingsPage extends StatelessWidget {
  SettingsPage({super.key});

  final List<Color> _colorPresets = [
    const Color(0xFF00F5FF), // Cyan
    const Color(0xFF7B61FF), // Purple
    const Color(0xFF00FF88), // Green
    const Color(0xFFFF5757), // Red
    const Color(0xFFFFB74D), // Orange
    const Color(0xFFFFEB3B), // Yellow
    const Color(0xFF9C27B0), // Deep Purple
    const Color(0xFFE91E63), // Pink
    const Color(0xFF4CAF50), // Light Green
    const Color(0xFF2196F3), // Blue
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFFFF9800), // Amber
    const Color(0xFF795548), // Brown
    const Color(0xFF607D8B), // Blue Grey
    const Color(0xFF8BC34A), // Lime
    const Color(0xFFCDDC39), // Light Green
    const Color(0xFFFFC107), // Amber
    const Color(0xFFFF5722), // Deep Orange
    const Color(0xFF673AB7), // Deep Purple
    const Color(0xFF3F51B5), // Indigo
  ];

  Future<void> _onColorSelected(Color color, BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('primary_color', color.value);
    
    // Update the app theme using the MyApp.of method
    final appState = MyApp.of(context);
    if (appState != null) {
      appState.updatePrimaryColor(color);
    }
    
    // Show confirmation
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: color,
          content: const Text(
            'Primary color updated',
            style: TextStyle(color: Colors.black),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = Theme.of(context).colorScheme.primary;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Primary Color',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select a color for the app theme',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _colorPresets.length,
              itemBuilder: (context, index) {
                final color = _colorPresets[index];
                return GestureDetector(
                  onTap: () => _onColorSelected(color, context),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: currentColor.value == color.value 
                            ? Colors.white 
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: currentColor.value == color.value
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
