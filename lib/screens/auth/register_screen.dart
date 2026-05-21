import 'package:flutter/material.dart';
import 'package:ebookreader/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ebookreader/screens/recommendations/recommendation_onboarding_screen.dart';
import 'package:ebookreader/theme/app_theme.dart';

/// Экран регистрации нового пользователя.
///
/// Позволяет создать аккаунт, указав имя пользователя, email и пароль.
/// Выполняет валидацию всех полей: минимальная длина имени пользователя,
/// корректность email, минимальная длина пароля и совпадение паролей.
/// После успешной регистрации автоматически направляет пользователя на домашний экран.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final username = _usernameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      final response = await _authService.register(username, email, password);

      final token = response['token']?.toString() ?? '';
      final role = response['role']?.toString() ?? 'USER';

      if (token.isEmpty) throw Exception('Токен не получен от сервера');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      await prefs.setString('role', role);

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => RecommendationOnboardingScreen(
            token: token,
            finishToHome: true,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Ошибка регистрации: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Container(
        decoration: BoxDecoration(gradient: palette.pageGradient),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 12,
                child: IconButton(
                  tooltip: 'Тема приложения',
                  onPressed: () => showAppThemeSheet(context),
                  icon: Icon(Icons.palette_rounded, color: palette.accent),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Back button
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(
                                Icons.arrow_back_ios_new,
                                color: palette.accent,
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Logo
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  const Color(
                                    0xFF14FFEC,
                                  ).withValues(alpha: 0.3),
                                  const Color(
                                    0xFF0D7377,
                                  ).withValues(alpha: 0.2),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF14FFEC,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 40,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person_add_rounded,
                              size: 56,
                              color: Color(0xFF14FFEC),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Title
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                            ).createShader(bounds),
                            child: const Text(
                              'Регистрация',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Присоединяйтесь к нашему сообществу читателей',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),

                          const SizedBox(height: 40),

                          // Username field
                          _buildGlassTextField(
                            controller: _usernameController,
                            label: 'Логин',
                            icon: Icons.person_outline,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите логин';
                              }
                              if (value.trim().length < 3) {
                                return 'Минимум 3 символа';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          // Email field
                          _buildGlassTextField(
                            controller: _emailController,
                            label: 'Email',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите email';
                              }
                              if (!value.trim().contains('@')) {
                                return 'Введите корректный email';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          // Password field
                          _buildGlassTextField(
                            controller: _passwordController,
                            label: 'Пароль',
                            icon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: palette.accent.withValues(alpha: 0.6),
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите пароль';
                              }
                              if (value.trim().length < 8) {
                                return 'Минимум 8 символов';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          // Confirm Password field
                          _buildGlassTextField(
                            controller: _confirmPasswordController,
                            label: 'Подтвердите пароль',
                            icon: Icons.lock_clock_outlined,
                            obscureText: _obscureConfirmPassword,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: palette.accent.withValues(alpha: 0.6),
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Подтвердите пароль';
                              }
                              if (value.trim() !=
                                  _passwordController.text.trim()) {
                                return 'Пароли не совпадают';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 32),

                          // Register button
                          Container(
                            width: double.infinity,
                            height: 58,
                            decoration: BoxDecoration(
                              gradient: palette.accentGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: palette.accent.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Зарегистрироваться',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Login link
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: RichText(
                              text: TextSpan(
                                text: 'Уже есть аккаунт? ',
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: 15,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Войти',
                                    style: TextStyle(
                                      color: palette.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon,
            color: const Color(0xFF14FFEC).withValues(alpha: 0.7),
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          errorStyle: const TextStyle(color: Color(0xFFFF6B9D)),
        ),
        validator: validator,
      ),
    );
  }
}
