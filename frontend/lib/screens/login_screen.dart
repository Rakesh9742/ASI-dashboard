import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:html' as html;
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'main_navigation_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _isZohoLoading = false;
  bool _obscurePassword = true;
  AnimationController? _animationController;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupZohoLoginListener();
  }

  void _setupZohoLoginListener() {
    // Listen for Zoho login success message from OAuth callback
    // Check for postMessage from OAuth callback window
    try {
      html.window.addEventListener('message', (event) {
        try {
          final messageEvent = event as html.MessageEvent;
          print('Received message event: ${messageEvent.data}');
          final data = messageEvent.data;
          if (data is Map && data['type'] == 'ZOHO_LOGIN_SUCCESS') {
            print('Zoho login success detected! Token: ${data['token']?.toString().substring(0, 20)}...');
            print('User data: ${data['user']}');
            _handleZohoLoginSuccess(
              data['token'] as String, 
              Map<String, dynamic>.from(data['user'] as Map)
            );
          } else {
            print('Message received but not ZOHO_LOGIN_SUCCESS. Type: ${data is Map ? data['type'] : 'unknown'}');
          }
        } catch (e) {
          print('Error handling Zoho login message: $e');
          print('Stack trace: ${StackTrace.current}');
        }
      });
      
      // Also check localStorage periodically for Zoho login token (fallback)
      _checkLocalStorageForZohoToken();
    } catch (e) {
      print('Error setting up Zoho login listener: $e');
    }
  }

  void _checkLocalStorageForZohoToken() {
    // Check localStorage every 2 seconds for Zoho login token (fallback method)
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      try {
        final token = html.window.localStorage['zoho_login_token'];
        final userJson = html.window.localStorage['zoho_login_user'];
        if (token != null && userJson != null) {
          final user = json.decode(userJson) as Map<String, dynamic>;
          html.window.localStorage.remove('zoho_login_token');
          html.window.localStorage.remove('zoho_login_user');
          _handleZohoLoginSuccess(token, user);
        } else {
          // Check again after 2 more seconds
          _checkLocalStorageForZohoToken();
        }
      } catch (e) {
        // Ignore errors
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeIn),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeOutCubic),
    );
    
    // Start animation after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _animationController != null) {
        _animationController!.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await ref.read(authProvider.notifier).login(
            _usernameController.text.trim(),
            _passwordController.text,
          );

      if (result && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Login failed: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleZohoLogin() async {
    setState(() {
      _isZohoLoading = true;
    });

    try {
      // Get Zoho OAuth login URL
      final response = await _apiService.getZohoLoginAuthUrl();
      final authUrl = response['authUrl'] as String;

      // Open OAuth URL in a popup window for proper postMessage communication
      // Use html.window.open() instead of launchUrl for web
      try {
        html.window.open(
          authUrl,
          'zoho_oauth',
          'width=600,height=700,scrollbars=yes,resizable=yes',
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please complete Zoho login in the popup window'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        // Fallback to launchUrl if window.open fails
        final uri = Uri.parse(authUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please complete Zoho login in the browser'),
                duration: Duration(seconds: 5),
              ),
            );
          }
        } else {
          _showError('Could not open browser for Zoho login');
        }
      }
    } catch (e) {
      _showError('Failed to start Zoho login: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isZohoLoading = false;
        });
      }
    }
  }

  Future<void> _handleZohoLoginSuccess(String token, Map<String, dynamic> user) async {
    try {
      print('Handling Zoho login success...');
      print('Token length: ${token.length}');
      print('User data: $user');
      
      setState(() {
        _isZohoLoading = false;
      });

      // Ensure user has required fields
      final userData = Map<String, dynamic>.from(user);
      if (!userData.containsKey('role') || userData['role'] == null) {
        print('Warning: User role not found, defaulting to admin');
        userData['role'] = 'admin'; // Default to admin for Zoho users
      }

      // Save token and user to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setString('auth_user', json.encode(userData));
      print('Saved token and user to SharedPreferences');

      // Update auth state using the notifier
      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.updateState(AuthState(
        isAuthenticated: true,
        token: token,
        user: userData,
      ));
      print('Updated auth state. Is authenticated: ${ref.read(authProvider).isAuthenticated}');

      // Wait a bit for state to propagate
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        // Verify auth state was updated
        final currentAuthState = ref.read(authProvider);
        print('Current auth state after update: isAuthenticated=${currentAuthState.isAuthenticated}, hasToken=${currentAuthState.token != null}, hasUser=${currentAuthState.user != null}');
        
        if (currentAuthState.isAuthenticated) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Login successful! Redirecting to dashboard...'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // AuthWrapper will automatically show MainNavigationScreen when auth state changes
          // But we can also manually navigate to ensure it happens immediately
          print('Navigating to MainNavigationScreen...');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
            (route) => false, // Remove all previous routes
          );
          print('Navigation completed');
        } else {
          print('ERROR: Auth state not updated properly!');
          _showError('Authentication state not updated. Please try again.');
        }
      } else {
        print('Widget not mounted, cannot navigate');
      }
    } catch (e, stackTrace) {
      print('Error in _handleZohoLoginSuccess: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        _showError('Failed to complete Zoho login: $e');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple.shade50,
              Colors.white,
              Colors.teal.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: size.width > 600 ? 80 : 24.0,
                vertical: 32.0,
              ),
              child: _fadeAnimation != null && _slideAnimation != null
                  ? FadeTransition(
                      opacity: _fadeAnimation!,
                      child: SlideTransition(
                        position: _slideAnimation!,
                        child: _buildLoginContent(theme, size),
                      ),
                    )
                  : _buildLoginContent(theme, size),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginContent(ThemeData theme, Size size) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        
        // Logo Section
        _buildLogoSection(theme),
        
        const SizedBox(height: 40),
        
        // Login Card
        _buildLoginCard(theme, size),
      ],
    );
  }

  Widget _buildLogoSection(ThemeData theme) {
    return Column(
      children: [
        Text(
          'ASI Dashboard',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.bold,
            foreground: Paint()
              ..shader = LinearGradient(
                colors: [
                  Colors.purple.shade600,
                  Colors.blue.shade600,
                  Colors.teal.shade600,
                ],
              ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Chip Design Management System',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(ThemeData theme, Size size) {
    return Container(
      constraints: BoxConstraints(maxWidth: 450),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.purple.shade600,
                          Colors.teal.shade600,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome back! Please enter your credentials',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),

              // Username Field
              _buildTextField(
                controller: _usernameController,
                label: 'Username or Email',
                hint: 'Enter your username or email',
                icon: Icons.person_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your username or email';
                  }
                  return null;
                },
                theme: theme,
              ),
              const SizedBox(height: 20),

              // Password Field
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'Enter your password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                onFieldSubmitted: (_) => _handleLogin(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  return null;
                },
                theme: theme,
              ),
              const SizedBox(height: 24),

              // Divider with "OR"
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),

              const SizedBox(height: 24),

              // Zoho Login Button
              Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.shade600,
                      Colors.blue.shade700,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade600.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _isZohoLoading ? null : _handleZohoLogin,
                  icon: _isZohoLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.cloud, color: Colors.white),
                  label: Text(
                    _isZohoLoading ? 'Connecting...' : 'Login with Zoho',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Regular Login Button
              Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.purple.shade600,
                      Colors.blue.shade600,
                      Colors.teal.shade600,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.shade600.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required ThemeData theme,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: obscureText ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: TextStyle(
        color: Colors.grey.shade900,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(icon, color: Colors.purple.shade600),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
        ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.purple.shade600,
                                  width: 2,
                                ),
                              ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400, width: 2),
        ),
        labelStyle: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 15,
        ),
        floatingLabelStyle: TextStyle(
          color: Colors.purple.shade600,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

}
