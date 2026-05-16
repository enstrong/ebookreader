import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { dark, sepia, light }

class AppPalette {
  final AppThemeMode mode;
  final Color background;
  final Color surface;
  final Color elevated;
  final Color text;
  final Color mutedText;
  final Color accent;
  final Color secondaryAccent;
  final Color border;
  final Color danger;
  final Color success;
  final Color warning;
  final Color highlight;
  final Color onAccent;

  const AppPalette({
    required this.mode,
    required this.background,
    required this.surface,
    required this.elevated,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.secondaryAccent,
    required this.border,
    required this.danger,
    required this.success,
    required this.warning,
    required this.highlight,
    required this.onAccent,
  });

  bool get isDark => mode == AppThemeMode.dark;

  LinearGradient get pageGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      background,
      surface,
      secondaryAccent.withValues(
        alpha: mode == AppThemeMode.dark ? 0.30 : 0.12,
      ),
    ],
  );

  LinearGradient get verticalGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [background, surface],
  );

  LinearGradient get accentGradient =>
      LinearGradient(colors: [accent, secondaryAccent]);

  LinearGradient get softGradient => LinearGradient(
    colors: [
      text.withValues(alpha: isDark ? 0.05 : 0.60),
      text.withValues(alpha: isDark ? 0.02 : 0.35),
    ],
  );
}

class AppTheme {
  static const dark = AppPalette(
    mode: AppThemeMode.dark,
    background: Color(0xFF0A0E27),
    surface: Color(0xFF1A1F3A),
    elevated: Color(0xFF10162F),
    text: Colors.white,
    mutedText: Color(0xFFB9C2D0),
    accent: Color(0xFF14FFEC),
    secondaryAccent: Color(0xFF0D7377),
    border: Color(0x22FFFFFF),
    danger: Color(0xFFFF6B9D),
    success: Color(0xFF7CFF6B),
    warning: Color(0xFFFFD166),
    highlight: Color(0x5514FFEC),
    onAccent: Color(0xFF071018),
  );

  static const sepia = AppPalette(
    mode: AppThemeMode.sepia,
    background: Color(0xFFF3E3C8),
    surface: Color(0xFFE7D0AA),
    elevated: Color(0xFFFFF4DE),
    text: Color(0xFF2B2118),
    mutedText: Color(0xFF725D45),
    accent: Color(0xFF9B5E1A),
    secondaryAccent: Color(0xFFC18424),
    border: Color(0x332B2118),
    danger: Color(0xFFB84545),
    success: Color(0xFF40743C),
    warning: Color(0xFFC18424),
    highlight: Color(0x66D9A441),
    onAccent: Color(0xFFFFF7EA),
  );

  static const light = AppPalette(
    mode: AppThemeMode.light,
    background: Color(0xFFF6F8F8),
    surface: Color(0xFFE8F0EF),
    elevated: Colors.white,
    text: Color(0xFF132022),
    mutedText: Color(0xFF617174),
    accent: Color(0xFF087A73),
    secondaryAccent: Color(0xFF14A7A0),
    border: Color(0x33132022),
    danger: Color(0xFFD9415D),
    success: Color(0xFF2C8C58),
    warning: Color(0xFFB47616),
    highlight: Color(0x5514A7A0),
    onAccent: Colors.white,
  );

  static AppPalette paletteFor(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.sepia:
        return sepia;
      case AppThemeMode.light:
        return light;
      case AppThemeMode.dark:
        return dark;
    }
  }

  static ThemeData themeData(AppPalette palette) {
    final brightness = palette.isDark ? Brightness.dark : Brightness.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      primary: palette.accent,
      secondary: palette.secondaryAccent,
      surface: palette.surface,
      error: palette.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      cardColor: palette.elevated,
      dividerColor: palette.border,
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(bodyColor: palette.text, displayColor: palette.text),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.text,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.text),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.elevated,
        textStyle: TextStyle(color: palette.text),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: palette.mutedText),
        hintStyle: TextStyle(color: palette.mutedText.withValues(alpha: 0.72)),
        filled: true,
        fillColor: palette.elevated.withValues(
          alpha: palette.isDark ? 0.10 : 0.68,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.accent, width: 1.6),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.elevated,
        modalBackgroundColor: palette.elevated,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        thumbColor: palette.accent,
        inactiveTrackColor: palette.border,
      ),
    );
  }
}

class AppThemeController extends ChangeNotifier {
  static const _storageKey = 'app_theme_mode';

  AppThemeMode _mode = AppThemeMode.dark;
  bool _isLoaded = false;

  AppThemeMode get mode => _mode;
  AppPalette get palette => AppTheme.paletteFor(_mode);
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _mode = AppThemeMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => AppThemeMode.dark,
    );
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode && _isLoaded) return;
    _mode = mode;
    _isLoaded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, mode.name);
  }
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope is missing above this context');
    return scope!.notifier!;
  }
}

extension AppThemeContext on BuildContext {
  AppThemeController get appTheme => AppThemeScope.of(this);
  AppPalette get palette => appTheme.palette;
}

class AppThemePicker extends StatelessWidget {
  final bool compact;

  const AppThemePicker({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final controller = context.appTheme;
    final palette = context.palette;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SegmentedButton<AppThemeMode>(
          showSelectedIcon: false,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return palette.accent.withValues(
                  alpha: palette.isDark ? 0.18 : 0.12,
                );
              }
              return palette.elevated.withValues(alpha: compact ? 0.55 : 0.85);
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return palette.accent;
              return palette.mutedText;
            }),
            side: WidgetStateProperty.all(BorderSide(color: palette.border)),
            visualDensity: compact
                ? VisualDensity.compact
                : VisualDensity.standard,
          ),
          segments: const [
            ButtonSegment(
              value: AppThemeMode.dark,
              icon: Icon(Icons.dark_mode_rounded),
              label: Text('Dark'),
            ),
            ButtonSegment(
              value: AppThemeMode.sepia,
              icon: Icon(Icons.auto_stories_rounded),
              label: Text('Sepia'),
            ),
            ButtonSegment(
              value: AppThemeMode.light,
              icon: Icon(Icons.light_mode_rounded),
              label: Text('Light'),
            ),
          ],
          selected: {controller.mode},
          onSelectionChanged: (selection) {
            controller.setMode(selection.first);
          },
        );
      },
    );
  }
}

void showAppThemeSheet(BuildContext context) {
  final palette = context.palette;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AppThemeScope(
      controller: context.appTheme,
      child: Builder(
        builder: (context) {
          final sheetPalette = context.palette;
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            decoration: BoxDecoration(
              color: sheetPalette.elevated,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: sheetPalette.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: palette.isDark ? 0.35 : 0.12,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: sheetPalette.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Тема приложения',
                    style: TextStyle(
                      color: sheetPalette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const AppThemePicker(),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
