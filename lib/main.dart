import 'dart:convert';
import 'constants/api_constants.dart';
import 'screens/demo/demo_start_screen.dart';

import 'package:ebookreader/screens/admin/admin_main_screen.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/bookmarks/bookmarks_screen.dart';
import 'screens/user/user_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!ApiConstants.demoMode) await dotenv.load(fileName: ".env");
  if (!kIsWeb)
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.ebookreader.audio',
      androidNotificationChannelName: 'Audiobook playback',
      androidNotificationOngoing: true,
    );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? token;
  String? role;
  bool isLoading = true;
  final AppThemeController _themeController = AppThemeController();
  final AppLanguageController _languageController = AppLanguageController();

  @override
  void initState() {
    super.initState();
    _loadUserSession();
  }

  @override
  void dispose() {
    _themeController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  Future<void> _loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    var savedToken = prefs.getString('token');
    var savedRole = prefs.getString('role');

    if (savedToken != null && _isExpiredJwt(savedToken)) {
      await prefs.remove('token');
      await prefs.remove('role');
      await prefs.remove('username');
      await prefs.remove('email');
      savedToken = null;
      savedRole = null;
    }

    await _themeController.load();
    if (ApiConstants.demoMode && !prefs.containsKey('app_language')) {
      await prefs.setString('app_language', 'en');
    }
    await _languageController.load();

    setState(() {
      token = savedToken;
      role = savedRole;
      isLoading = false;
    });
  }

  bool _isExpiredJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return true;

    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final jsonPayload = json.decode(payload);
      if (jsonPayload is! Map) return true;

      final expiration = jsonPayload['exp'];
      if (expiration is! num) return true;

      return DateTime.now().millisecondsSinceEpoch >= expiration * 1000;
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const MaterialApp(home: _StartupLoadingScreen());
    }

    Widget startScreen;

    if (ApiConstants.demoMode) {
      startScreen = const DemoStartScreen();
    } else if (token != null && role != null) {
      if (role == 'ADMIN') {
        startScreen = AdminMainScreen(token: token!);
      } else {
        startScreen = UserHome(token: token!);
      }
    } else {
      startScreen = const LoginScreen();
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_themeController, _languageController]),
      builder: (context, _) {
        final palette = _themeController.palette;
        return AppThemeScope(
          controller: _themeController,
          child: AppLanguageScope(
            controller: _languageController,
            child: MaterialApp(
              title: 'EBook Reader',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.themeData(palette),
              builder: (context, child) => _KeyboardWarmupGate(
                child: _KeyboardDismissScope(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              home: startScreen,
              routes: {
                '/login': (_) => ApiConstants.demoMode
                    ? const DemoStartScreen()
                    : const LoginScreen(),
                '/register': (_) => const RegisterScreen(),
                '/home': (_) => HomeScreen(token: token ?? ''),
                '/admin': (_) => AdminMainScreen(token: token ?? ''),
                '/bookmarks': (_) => BookmarksScreen(token: token ?? ''),
              },
            ),
          ),
        );
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  final String message;

  const _StartupLoadingScreen({this.message = 'Loading...'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _KeyboardWarmupGate extends StatefulWidget {
  final Widget child;

  const _KeyboardWarmupGate({required this.child});

  @override
  State<_KeyboardWarmupGate> createState() => _KeyboardWarmupGateState();
}

class _KeyboardWarmupGateState extends State<_KeyboardWarmupGate> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'keyboard-warmup');
  final TextEditingController _controller = TextEditingController();
  bool _isWarmed = !_shouldWarmKeyboard;

  @override
  void initState() {
    super.initState();
    if (_shouldWarmKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _warmKeyboard());
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _warmKeyboard() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      _focusNode.requestFocus();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;

      _focusNode.unfocus();
      await SystemChannels.textInput
          .invokeMethod<void>('TextInput.hide')
          .timeout(const Duration(milliseconds: 300), onTimeout: () {});
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } catch (_) {
      _focusNode.unfocus();
    } finally {
      if (mounted) {
        setState(() => _isWarmed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: -200,
          top: -200,
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: EditableText(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(fontSize: 1, color: Colors.transparent),
              cursorColor: Colors.transparent,
              backgroundCursorColor: Colors.transparent,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
            ),
          ),
        ),
        if (!_isWarmed)
          Positioned.fill(
            child: _StartupLoadingScreen(
              message: context.tr(
                'Подготавливаем клавиатуру...',
                en: 'Preparing keyboard...',
              ),
            ),
          ),
      ],
    );
  }
}

bool get _shouldWarmKeyboard {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

class _KeyboardDismissScope extends StatelessWidget {
  final Widget child;

  const _KeyboardDismissScope({required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null) return;

        final focusedContext = focus.context;
        final renderObject = focusedContext?.findRenderObject();
        if (renderObject is RenderBox) {
          final offset = renderObject.localToGlobal(Offset.zero);
          final focusedBounds = offset & renderObject.size;
          if (focusedBounds.contains(event.position)) {
            return;
          }
        }

        focus.unfocus();
      },
      child: child,
    );
  }
}
