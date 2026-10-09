import 'package:flutter/material.dart';
import 'login_screen.dart';

void main() {
  runApp(const SmartPassApp());
}

class SmartPassApp extends StatelessWidget {
  const SmartPassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartPass',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        primaryColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        fontFamily: '.SF Pro Display',
      ),
      home: const LoginScreen(),
    );
  }
}
