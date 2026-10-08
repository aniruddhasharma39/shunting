import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'theme/app_theme.dart';
import 'services/user_session.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeShunt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        return SafeArea(
          top: false,
          bottom: true,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const VideoSplashScreen(),
    );
  }
}

class VideoSplashScreen extends StatefulWidget {
  const VideoSplashScreen({super.key});

  @override
  State<VideoSplashScreen> createState() => _VideoSplashScreenState();
}

class _VideoSplashScreenState extends State<VideoSplashScreen> {
  VideoPlayerController? _controller;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    
    // Start video and session check simultaneously
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. Initialize and play the video
    _controller = VideoPlayerController.asset('Splash_screen.mp4');
    try {
      await _controller!.initialize();
      _controller!.setVolume(0.0);
      if (mounted) setState(() {});
      _controller!.play();
    } catch (e) {
      // Ignore video errors and proceed to load
    }

    // 2. Run backend session load
    // We add a tiny 1.5s minimum delay so the video actually has time to show on screen
    // otherwise it would flash for 0.01 seconds and disappear instantly!
    final results = await Future.wait([
      UserSession().loadFromPreferences(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);
    
    final bool isLoggedIn = results[0] as bool;

    // 3. Skip directly to the appropriate screen without waiting for the full video!
    if (mounted && !_hasNavigated) {
      _hasNavigated = true;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => 
              isLoggedIn ? const MainScreen() : const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor, // Navy blue instead of black
      body: SizedBox.expand(
        child: _controller != null && _controller!.value.isInitialized
            ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              )
            : Center(
                child: Image.asset(
                  'safeshunt_rail_logo.png',
                  height: 64,
                  fit: BoxFit.contain,
                ),
              ),
      ),
    );
  }
}
