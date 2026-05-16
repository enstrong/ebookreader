import 'package:ebookreader/screens/admin/admin_main_screen.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/bookmarks/bookmarks_screen.dart';
import 'screens/user/user_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
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

  @override
  void initState() {
    super.initState();
    _loadUserSession();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('token');
    final savedRole = prefs.getString('role');
    await _themeController.load();

    setState(() {
      token = savedToken;
      role = savedRole;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    Widget startScreen;

    if (token != null && role != null) {
      if (role == 'ADMIN') {
        startScreen = AdminMainScreen(token: token!);
      } else {
        startScreen = UserHome(token: token!);
      }
    } else {
      startScreen = const LoginScreen();
    }

    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) {
        final palette = _themeController.palette;
        return AppThemeScope(
          controller: _themeController,
          child: MaterialApp(
            title: 'EBook Reader',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.themeData(palette),
            home: startScreen,
            routes: {
              '/login': (_) => const LoginScreen(),
              '/register': (_) => const RegisterScreen(),
              '/home': (_) => HomeScreen(token: token ?? ''),
              '/admin': (_) => AdminMainScreen(token: token ?? ''),
              '/bookmarks': (_) => BookmarksScreen(token: token ?? ''),
            },
          ),
        );
      },
    );
  }
}
