import 'package:flutter/material.dart';
import '../../constants/api_constants.dart';
import '../demo/demo_controls.dart';
import 'package:ebookreader/screens/home/home_screen.dart';
import 'package:ebookreader/screens/profile/profile_screen.dart';
import 'package:ebookreader/screens/recommendations/for_you_screen.dart';
import 'package:ebookreader/services/storage_service.dart';
import 'package:ebookreader/theme/app_theme.dart';

/// Корневой экран для обычного пользователя.
///
/// Реализует нижнюю навигационную панель с тремя вкладками:
/// рекомендации, библиотека доступных книг и профиль пользователя.
class UserHome extends StatefulWidget {
  final String token;
  const UserHome({super.key, required this.token});

  @override
  State<UserHome> createState() => _UserHomeState();
}

class _UserHomeState extends State<UserHome> {
  int _selectedIndex = ApiConstants.demoMode ? 1 : 0;
  final StorageService _storage = StorageService();
  String? _currentToken;

  @override
  void initState() {
    super.initState();
    _currentToken = widget.token;
  }

  Future<void> _updateToken() async {
    final token = await _storage.getToken();
    if (token != null && token != _currentToken) {
      setState(() {
        _currentToken = token;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final token = _currentToken ?? widget.token;
    final screens = [
      ForYouScreen(key: const PageStorageKey('for-you-home'), token: token),
      HomeScreen(
        key: const PageStorageKey('reading-library-home'),
        token: token,
        libraryOnly: true,
        title: context.tr('Библиотека'),
        subtitle: context.tr('Для чтения и прослушивания'),
      ),
      ProfileScreen(token: token),
    ];

    return Scaffold(
      appBar: ApiConstants.demoMode ? DemoControls(token: token) : null,
      backgroundColor: palette.background,
      body: Container(
        decoration: BoxDecoration(color: palette.background),
        child: IndexedStack(index: _selectedIndex, children: screens),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) async {
            await _updateToken();
            if (!mounted) return;
            setState(() => _selectedIndex = index);
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: palette.accent,
          unselectedItemColor: palette.mutedText,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
          items: [
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.explore_outlined, size: 26),
              ),
              activeIcon: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.explore, size: 26),
              ),
              label: context.tr('Для вас'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.auto_stories_outlined, size: 26),
              ),
              activeIcon: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.auto_stories, size: 26),
              ),
              label: context.tr('Библиотека'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.person_outline, size: 26),
              ),
              activeIcon: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.person, size: 26),
              ),
              label: context.tr('Профиль'),
            ),
          ],
        ),
      ),
    );
  }
}
