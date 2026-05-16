import 'package:flutter/material.dart';
import 'package:ebookreader/screens/home/home_screen.dart';
import 'package:ebookreader/screens/profile/profile_screen.dart';
import 'package:ebookreader/services/storage_service.dart';
import 'package:ebookreader/theme/app_theme.dart';

/// Корневой экран для обычного пользователя.
///
/// Реализует нижнюю навигационную панель с тремя вкладками:
/// каталог, библиотека доступных книг и профиль пользователя.
class UserHome extends StatefulWidget {
  final String token;
  const UserHome({super.key, required this.token});

  @override
  State<UserHome> createState() => _UserHomeState();
}

class _UserHomeState extends State<UserHome> {
  int _selectedIndex = 0;
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
    final List<Widget> screens = [
      HomeScreen(
        key: const ValueKey('catalog-home'),
        token: _currentToken ?? widget.token,
        title: 'Каталог',
        subtitle: 'Goodreads и рекомендации',
      ),
      HomeScreen(
        key: const ValueKey('reading-library-home'),
        token: _currentToken ?? widget.token,
        libraryOnly: true,
        title: 'Библиотека',
        subtitle: 'Для чтения и прослушивания',
      ),
      ProfileScreen(token: _currentToken ?? widget.token),
    ];

    return Scaffold(
      backgroundColor: palette.background,
      body: Container(
        decoration: BoxDecoration(gradient: palette.pageGradient),
        child: screens[_selectedIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.surface.withValues(alpha: 0.95),
              palette.background,
            ],
          ),
          border: Border(top: BorderSide(color: palette.border, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) async {
            await _updateToken();
            setState(() => _selectedIndex = index);
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: palette.accent,
          unselectedItemColor: palette.mutedText.withValues(alpha: 0.75),
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
          items: [
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: _selectedIndex == 0
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.accent.withValues(alpha: 0.2),
                            palette.secondaryAccent.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: palette.accent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      )
                    : null,
                child: const Icon(Icons.library_books_outlined, size: 26),
              ),
              activeIcon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.accent.withValues(alpha: 0.2),
                      palette.secondaryAccent.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.library_books, size: 26),
              ),
              label: 'Каталог',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: _selectedIndex == 1
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.accent.withValues(alpha: 0.2),
                            palette.secondaryAccent.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: palette.accent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      )
                    : null,
                child: const Icon(Icons.auto_stories_outlined, size: 26),
              ),
              activeIcon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.accent.withValues(alpha: 0.2),
                      palette.secondaryAccent.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_stories, size: 26),
              ),
              label: 'Библиотека',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: _selectedIndex == 2
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.accent.withValues(alpha: 0.2),
                            palette.secondaryAccent.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: palette.accent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      )
                    : null,
                child: const Icon(Icons.person_outline, size: 26),
              ),
              activeIcon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF14FFEC).withValues(alpha: 0.2),
                      const Color(0xFF0D7377).withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF14FFEC).withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.person, size: 26),
              ),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}
