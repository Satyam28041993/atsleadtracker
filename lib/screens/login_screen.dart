import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/session_cache.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = true;

  /// Slow, continuous drift for the background orbs. Purely decorative.
  late final AnimationController _ambientController;

  /// One-shot entrance animation; [_FadeSlideIn] reads it with staggered
  /// intervals so the panels arrive in sequence rather than all at once.
  late final AnimationController _entranceController;

  AuthService get _auth => widget.authService ?? AuthService();

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _loadCachedEmail();
  }

  Future<void> _loadCachedEmail() async {
    final email = await SessionCache.readEmail();
    if (!mounted || email == null) return;
    _emailController.text = email;
    setState(() => _rememberMe = true);
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _entranceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email';
    }
    if (!value.contains('@')) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    return null;
  }

  String _messageForAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect email or password.';
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Authentication failed. Please try again.';
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageForAuthException(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width > 900;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0F172A), // Slate 900
              Color(0xFF1E3A8A), // Deep Blue
              Color(0xFF3B82F6), // Bright Blue
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Slowly drifting glow orbs. Decorative only — they sit behind
            // everything and never intercept pointer events.
            _AmbientOrb(
              controller: _ambientController,
              phase: 0,
              size: 300,
              color: const Color(0xFF2563EB),
              alignment: const Alignment(-1.1, -1.1),
            ),
            _AmbientOrb(
              controller: _ambientController,
              phase: 0.5,
              size: 400,
              color: const Color(0xFF1D4ED8),
              alignment: const Alignment(1.2, 1.2),
            ),
            _AmbientOrb(
              controller: _ambientController,
              phase: 0.25,
              size: 220,
              color: const Color(0xFF60A5FA),
              alignment: const Alignment(1.0, -0.9),
            ),

            Center(
              child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps [child] in the shared staggered entrance animation.
  Widget _enter(Widget child, {required double order}) {
    return _FadeSlideIn(
      controller: _entranceController,
      order: order,
      child: child,
    );
  }

  Widget _buildDesktopLayout() {
    return _FadeSlideIn(
      controller: _entranceController,
      order: 0,
      offset: const Offset(0, 0.06),
      child: _buildDesktopCard(),
    );
  }

  Widget _buildDesktopCard() {
    return Container(
      width: 1100,
      height: 700,
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 40,
            spreadRadius: -10,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            children: [
              // Left Marketing Section
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(60.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _enter(
                        Row(
                          children: [
                            Image.asset(
                              'Assets/ats_crm_icon.png',
                              height: 50,
                              width: 50,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.business,
                                      color: Colors.white, size: 50),
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              'ATS CRM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        order: 1,
                      ),
                      const SizedBox(height: 12),
                      _enter(
                        Text(
                          'Applied Technology Systems',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 18,
                            letterSpacing: 1,
                          ),
                        ),
                        order: 2,
                      ),
                      const SizedBox(height: 40),
                      _enter(
                        const Text(
                          "Manage Leads, Customers, Sales Pipeline,\nTasks and Business Operations from one\npowerful platform.",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.4,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        order: 3,
                      ),
                      const SizedBox(height: 40),
                      for (final (i, label) in const [
                        'Lead Tracking',
                        'Customer Management',
                        'Follow-up Scheduling',
                        'Team Collaboration',
                        'Analytics Dashboard',
                      ].indexed)
                        _enter(_buildFeatureItem(label), order: 4 + i * 0.6),
                    ],
                  ),
                ),
              ),

              // Right Login Section
              Expanded(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(48.0),
                      child: _buildLoginForm(),
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

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: _FadeSlideIn(
        controller: _entranceController,
        order: 0,
        offset: const Offset(0, 0.08),
        child: _buildMobileCard(),
      ),
    );
  }

  Widget _buildMobileCard() {
    return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              spreadRadius: 5,
            )
          ],
        ),
      child: _buildLoginForm(),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: Color(0xFFD4AF37),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Image.asset(
              'Assets/ats_crm_icon.png',
              height: 60,
              width: 60,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.business, color: Color(0xFF0B1020), size: 60),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Welcome Back',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0B1020),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to continue',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 40),
          _buildTextField(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            validator: _validateEmail,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          _buildTextField(
            controller: _passwordController,
            label: 'Password',
            icon: Icons.lock_outline,
            validator: _validatePassword,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[600],
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (val) {
                        setState(() {
                          _rememberMe = val ?? false;
                        });
                      },
                      activeColor: const Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Keep me signed in',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  // Forgot password action
                },
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildLoginButton(),
          const SizedBox(height: 40),
          Center(
            child: TextButton(
              onPressed: () {},
              child: const Text(
                'Support Contact',
                style: TextStyle(color: Color(0xFF2563EB)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '© 2026 Applied Technology Systems',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: Icon(icon, color: const Color(0xFF2563EB)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _submit,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Sign In',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A soft, slowly drifting colour blob behind the login card.
///
/// Driven by a single shared repeating controller — each orb just reads it at
/// a different [phase], so adding more of them costs no extra ticker.
class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({
    required this.controller,
    required this.phase,
    required this.size,
    required this.color,
    required this.alignment,
  });

  final AnimationController controller;

  /// 0–1 offset into the drift cycle, so orbs don't move in lockstep.
  final double phase;
  final double size;
  final Color color;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // Decorative: must never swallow taps meant for the form behind it.
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = (controller.value + phase) % 1.0;
            final angle = t * 2 * math.pi;
            final dx = math.cos(angle) * 0.08;
            final dy = math.sin(angle) * 0.10;
            final scale = 1 + math.sin(angle) * 0.06;

            return Align(
              alignment: Alignment(alignment.x + dx, alignment.y + dy),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withValues(alpha: 0.32),
                        color.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Fades and slides [child] in, staggered by [order].
///
/// All instances share one controller; [order] simply shifts which slice of it
/// this widget animates over, which keeps the sequence in sync and cheap.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({
    required this.controller,
    required this.child,
    this.order = 0,
    this.offset = const Offset(-0.05, 0),
  });

  final AnimationController controller;
  final Widget child;

  /// Position in the stagger; each step delays the start by ~7% of the run.
  final double order;

  /// Start position as a fraction of the child's size.
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final begin = (order * 0.07).clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: controller,
      curve: Interval(begin, (begin + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: offset, end: Offset.zero).animate(curve),
        child: child,
      ),
    );
  }
}
