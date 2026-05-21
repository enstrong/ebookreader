import 'package:flutter/material.dart';
import 'package:ebookreader/services/user_service.dart';
import 'package:ebookreader/services/storage_service.dart';
import 'package:ebookreader/screens/bookmarks/bookmarks_screen.dart';
import 'package:ebookreader/screens/profile/rated_books_screen.dart';
import 'package:ebookreader/screens/auth/login_screen.dart';
import 'package:ebookreader/theme/app_theme.dart';

/// Экран профиля пользователя.
///
/// Отображает имя пользователя, никнейм, email и роль в системе.
/// Позволяет изменить никнейм, обновить пароль, перейти к сохранённым книгам
/// или выйти из системы. После смены никнейма автоматически
/// обновляет JWT-токен, если сервер вернул новый.
class ProfileScreen extends StatefulWidget {
  final String token;

  const ProfileScreen({super.key, required this.token});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final StorageService _storage = StorageService();

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  late String _currentToken;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _animController.forward();
    _currentToken = widget.token;
    _loadProfile();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _userService.getProfile(_currentToken);
      print('Загружен профиль: $profile');
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка загрузки профиля: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки профиля: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final palette = context.palette;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Выход из системы',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Вы действительно хотите выйти из своего аккаунта?',
          style: TextStyle(color: palette.text.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: TextStyle(color: palette.mutedText)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _storage.clearToken();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Выйти', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showNicknameDialog() {
    final palette = context.palette;
    final controller = TextEditingController(text: _profile?['nickname'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Смена имени пользователя',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: palette.text),
          decoration: InputDecoration(
            labelText: 'Введите новое имя',
            labelStyle: TextStyle(color: palette.mutedText),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.accent, width: 2),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: TextStyle(color: palette.mutedText)),
          ),
          ElevatedButton(
            onPressed: () async {
              final nickname = controller.text.trim();
              if (nickname.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Никнейм не может быть пустым'),
                    backgroundColor: Colors.red.shade600,
                  ),
                );
                return;
              }

              try {
                // ✅ Получаем ответ с новым токеном
                final response = await _userService.updateNickname(
                  _currentToken,
                  nickname,
                );

                // ✅ Обновляем токен, если он пришел в ответе
                if (response['token'] != null) {
                  final newToken = response['token'];
                  await _storage.saveToken(newToken);
                  setState(() {
                    _currentToken = newToken;
                  });
                  print('✅ Токен обновлен после смены никнейма');
                }

                if (!context.mounted) return;
                Navigator.pop(context);
                _loadProfile();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Никнейм успешно обновлён'),
                    backgroundColor: Colors.green.shade600,
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ошибка: $e'),
                    backgroundColor: Colors.red.shade600,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showPasswordDialog() {
    final palette = context.palette;
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: palette.elevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Изменить пароль',
            style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldPasswordController,
                  obscureText: obscureOld,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: 'Старый пароль',
                    labelStyle: TextStyle(color: palette.mutedText),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.accent, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureOld ? Icons.visibility : Icons.visibility_off,
                        color: palette.accent,
                      ),
                      onPressed: () => setState(() => obscureOld = !obscureOld),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPasswordController,
                  obscureText: obscureNew,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: 'Новый пароль',
                    labelStyle: TextStyle(color: palette.mutedText),
                    helperText: 'Минимум 8 символов',
                    helperStyle: TextStyle(color: palette.mutedText),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.accent, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNew ? Icons.visibility : Icons.visibility_off,
                        color: palette.accent,
                      ),
                      onPressed: () => setState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirm,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: 'Подтвердите пароль',
                    labelStyle: TextStyle(color: palette.mutedText),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.accent, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: palette.accent,
                      ),
                      onPressed: () =>
                          setState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена', style: TextStyle(color: palette.mutedText)),
            ),
            ElevatedButton(
              onPressed: () async {
                final oldPassword = oldPasswordController.text;
                final newPassword = newPasswordController.text;
                final confirmPassword = confirmPasswordController.text;

                if (oldPassword.isEmpty ||
                    newPassword.isEmpty ||
                    confirmPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Все поля должны быть заполнены'),
                      backgroundColor: Colors.red.shade600,
                    ),
                  );
                  return;
                }

                if (newPassword.length < 8) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Пароль должен содержать минимум 8 символов',
                      ),
                      backgroundColor: Colors.red.shade600,
                    ),
                  );
                  return;
                }

                if (newPassword != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Пароли не совпадают'),
                      backgroundColor: Colors.red.shade600,
                    ),
                  );
                  return;
                }

                try {
                  await _userService.changePassword(
                    widget.token,
                    oldPassword,
                    newPassword,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Пароль успешно изменён'),
                      backgroundColor: Colors.green.shade600,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка: $e'),
                      backgroundColor: Colors.red.shade600,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Изменить'),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitial() {
    final nickname = _profile?['nickname'] ?? '';
    final username = _profile?['username'] ?? 'User';

    if (nickname.isNotEmpty) return nickname[0].toUpperCase();
    if (username.isNotEmpty) return username[0].toUpperCase();
    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    final nickname = _profile?['nickname'] ?? '';
    final username = _profile?['username'] ?? 'User';
    final email = _profile?['email'] ?? '';
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      body: Container(
        decoration: BoxDecoration(gradient: palette.pageGradient),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: palette.accent),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),

                        // Profile Avatar with Animation
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: palette.accentGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: palette.accent.withValues(alpha: 0.28),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [palette.elevated, palette.surface],
                                ),
                              ),
                              child: Text(
                                _getInitial(),
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: palette.accent,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // User Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                palette.accent.withValues(alpha: 0.22),
                                palette.secondaryAccent.withValues(alpha: 0.14),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: palette.accent.withValues(alpha: 0.42),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person,
                                color: palette.accent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ПОЛЬЗОВАТЕЛЬ',
                                style: TextStyle(
                                  color: palette.accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Username
                        ShaderMask(
                          shaderCallback: (bounds) =>
                              palette.accentGradient.createShader(bounds),
                          child: Text(
                            nickname.isNotEmpty ? nickname : username,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Email
                        if (email.isNotEmpty)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.email_outlined,
                                color: palette.mutedText,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: palette.mutedText,
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 48),

                        // Menu Items
                        _buildMenuItem(
                          icon: Icons.palette_rounded,
                          title: 'Тема приложения',
                          description: _themeLabel(context.appTheme.mode),
                          onTap: () => showAppThemeSheet(context),
                        ),

                        const SizedBox(height: 16),

                        _buildMenuItem(
                          icon: Icons.library_books_rounded,
                          title: 'Сохранённые книги',
                          description: 'Сохранённые книги',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    BookmarksScreen(token: widget.token),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        _buildMenuItem(
                          icon: Icons.star_rate_rounded,
                          title: 'Оценённые книги',
                          description: 'История оценок и сигналов рекомендаций',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RatedBooksScreen(token: _currentToken),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        _buildMenuItem(
                          icon: Icons.person_outline,
                          title: 'Смена имени пользователя',
                          description: nickname.isNotEmpty
                              ? nickname
                              : 'Не установлен',
                          onTap: _showNicknameDialog,
                        ),

                        const SizedBox(height: 16),

                        _buildMenuItem(
                          icon: Icons.lock_outline,
                          title: 'Сменить пароль',
                          description: 'Обновить пароль',
                          onTap: _showPasswordDialog,
                        ),

                        const SizedBox(height: 48),

                        // Logout Button
                        Container(
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.red.shade600,
                                Colors.red.shade800,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _logout,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Выйти из системы',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            palette.text.withValues(alpha: palette.isDark ? 0.05 : 0.18),
            palette.text.withValues(alpha: palette.isDark ? 0.02 : 0.08),
          ],
        ),
        border: Border.all(color: palette.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    palette.accent.withValues(alpha: 0.3),
                    palette.secondaryAccent.withValues(alpha: 0.2),
                  ],
                ),
              ),
              child: Icon(icon, color: palette.accent, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(color: palette.mutedText, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: palette.mutedText.withValues(alpha: 0.55),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _themeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.sepia:
        return 'Sepia';
      case AppThemeMode.light:
        return 'Light';
    }
  }
}
