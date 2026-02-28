import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'screens/splash/splash_screen.dart';

class FoodTokRoot extends StatelessWidget {
  const FoodTokRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MakanMap',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const SplashScreen(),
    );
  }
}