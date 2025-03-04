import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      _controller.forward();
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size
    final Size screenSize = MediaQuery.of(context).size;
    final double screenWidth = screenSize.width;
    final double screenHeight = screenSize.height;

    // Calculate animation size based on screen dimensions
    // Use the smaller of width or height to ensure animation fits on screen
    final double animationSize = screenWidth < screenHeight 
        ? screenWidth * 0.7  // On portrait mode
        : screenHeight * 0.7; // On landscape mode

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400, // Maximum width for larger screens
              maxHeight: 400, // Maximum height for larger screens
            ),
            child: Lottie.asset(
              'assets/delivery_animation.json',
              controller: _controller,
              width: animationSize,
              height: animationSize,
              fit: BoxFit.contain,
              onLoaded: (composition) {
                _controller.duration = composition.duration;
              },
            ),
          ),
        ),
      ),
    );
  }
} 