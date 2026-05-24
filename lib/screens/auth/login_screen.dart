import 'package:ebookreader/screens/admin/admin_main_screen.dart';
import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/screens/recommendations/recommendation_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:ebookreader/services/auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ebookreader/screens/user/user_home.dart';
import 'package:ebookreader/screens/auth/register_screen.dart';
import 'package:ebookreader/theme/app_theme.dart';

/// Экран входа в систему.
///
/// Позволяет пользователю аутентифицироваться по имени пользователя
/// или email и паролю. После успешного входа направляет пользователя
/// на соответствующий экран в зависимости от роли (USER или ADMIN).
/// При запуске проверяет доступность сервера и уведомляет пользователя при недоступности.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _googleSignInInitialized = false;
  bool _obscurePassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  bool get _isAuthBusy => _isLoading || _isGoogleLoading;

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
    _testConnection();
  }

  Future<void> _testConnection() async {
    final isConnected = await _authService.testConnection();
    if (!mounted) return;

    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text(
                'Не удается подключиться к серверу. Проверьте интернет-соединение',
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
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
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      final response = await _authService.login(username, password);
      await _completeAuth(response);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showAuthError(e);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      await _ensureGoogleSignInInitialized();

      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw Exception('Google вход недоступен на этой платформе');
      }

      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google не вернул ID token');
      }

      final response = await _authService.loginWithGoogle(idToken);
      await _completeAuth(response);
    } on GoogleSignInException catch (e) {
      if (mounted) setState(() => _isGoogleLoading = false);
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _showAuthError(
          Exception(e.description ?? 'Не удалось войти через Google'),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isGoogleLoading = false);
      _showAuthError(e);
    }
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;

    final webClientId = ApiConstants.googleWebClientId;
    if (webClientId.isEmpty) {
      throw Exception('GOOGLE_WEB_CLIENT_ID не задан в .env');
    }

    String? clientId;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosClientId = ApiConstants.googleIosClientId;
      if (iosClientId.isEmpty) {
        throw Exception('GOOGLE_IOS_CLIENT_ID не задан в .env');
      }
      clientId = iosClientId;
    }

    await GoogleSignIn.instance.initialize(
      clientId: clientId,
      serverClientId: webClientId,
    );
    _googleSignInInitialized = true;
  }

  Future<void> _completeAuth(Map<String, dynamic> response) async {
    final token = response['token']?.toString() ?? '';
    final role = response['role']?.toString() ?? 'USER';
    final usernameFromServer = response['username']?.toString() ?? '';
    final email = response['email']?.toString() ?? '';
    final isNewUser = response['isNewUser'] == true;

    if (token.isEmpty) throw Exception('Токен не получен от сервера');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('role', role);
    await prefs.setString('username', usernameFromServer);
    await prefs.setString('email', email);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text('С возвращением, $usernameFromServer!'),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final Widget nextScreen = isNewUser
        ? RecommendationOnboardingScreen(token: token, finishToHome: true)
        : role == 'ADMIN'
        ? AdminMainScreen(token: token)
        : UserHome(token: token);

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => nextScreen),
      (route) => false,
    );
  }

  void _showAuthError(Object error) {
    if (!mounted) return;

    final errorMessage = error.toString().replaceAll('Exception:', '').trim();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(errorMessage)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
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
                          // Animated Logo
                          TweenAnimationBuilder(
                            duration: const Duration(milliseconds: 800),
                            tween: Tween<double>(begin: 0, end: 1),
                            builder: (context, double value, child) {
                              return Transform.scale(
                                scale: value,
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        palette.accent.withValues(alpha: 0.28),
                                        palette.secondaryAccent.withValues(
                                          alpha: 0.18,
                                        ),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: palette.accent.withValues(
                                          alpha: 0.22,
                                        ),
                                        blurRadius: 40,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.auto_stories_rounded,
                                    size: 64,
                                    color: palette.accent,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 48),

                          // Title
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [palette.accent, palette.secondaryAccent],
                            ).createShader(bounds),
                            child: Text(
                              'EBook Reader',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: palette.text,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Войдите, чтобы продолжить чтение',
                            style: TextStyle(
                              fontSize: 16,
                              color: palette.mutedText,
                              letterSpacing: 0.5,
                            ),
                          ),

                          const SizedBox(height: 48),

                          // Username field
                          _buildGlassTextField(
                            controller: _usernameController,
                            label: 'Email или логин',
                            hint: 'example@mail.com',
                            icon: Icons.person_outline,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите email или имя пользователя';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Password field
                          _buildGlassTextField(
                            controller: _passwordController,
                            label: 'Пароль',
                            hint: '••••••••',
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
                              return null;
                            },
                          ),

                          const SizedBox(height: 40),

                          // Login button
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
                              onPressed: _isAuthBusy ? null : _login,
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
                                      'Войти',
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

                          _buildGoogleButton(),

                          const SizedBox(height: 24),

                          // Register link
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: RichText(
                              text: TextSpan(
                                text: 'Нет аккаунта? ',
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: 15,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Зарегистрироваться',
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

  Widget _buildGoogleButton() {
    final palette = context.palette;
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton(
        onPressed: _isAuthBusy ? null : _loginWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: palette.elevated.withValues(
            alpha: palette.isDark ? 0.92 : 1,
          ),
          foregroundColor: palette.text,
          side: BorderSide(color: palette.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isGoogleLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: palette.accent,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _GoogleLogo(size: 22),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Войти через Google',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            palette.elevated.withValues(alpha: palette.isDark ? 0.16 : 0.92),
            palette.surface.withValues(alpha: palette.isDark ? 0.08 : 0.62),
          ],
        ),
        border: Border.all(color: palette.border, width: 1.5),
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
        style: TextStyle(color: palette.text, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: palette.mutedText, fontSize: 14),
          hintStyle: TextStyle(color: palette.mutedText.withValues(alpha: 0.7)),
          prefixIcon: Icon(icon, color: palette.accent.withValues(alpha: 0.75)),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          errorStyle: TextStyle(color: palette.danger),
        ),
        validator: validator,
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _GoogleLogoPainter());
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.16;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);

    Paint arcPaint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      arcRect,
      -0.12,
      1.38,
      false,
      arcPaint(const Color(0xFF4285F4)),
    );
    canvas.drawArc(
      arcRect,
      1.28,
      1.18,
      false,
      arcPaint(const Color(0xFF34A853)),
    );
    canvas.drawArc(
      arcRect,
      2.44,
      1.05,
      false,
      arcPaint(const Color(0xFFFBBC05)),
    );
    canvas.drawArc(
      arcRect,
      3.47,
      1.48,
      false,
      arcPaint(const Color(0xFFEA4335)),
    );

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square;
    final centerY = size.height * 0.52;
    canvas.drawLine(
      Offset(size.width * 0.52, centerY),
      Offset(size.width * 0.96, centerY),
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
