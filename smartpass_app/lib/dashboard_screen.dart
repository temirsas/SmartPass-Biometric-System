import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'qr_screen.dart';
import 'purchase_screen.dart';
import 'topup_screen.dart';
import 'login_screen.dart';
import 'face_capture_screen.dart'; // <-- Импорт нашего нового экрана камеры

class DashboardScreen extends StatefulWidget {
  final int userId;
  final String phone;
  final double initialBalance;
  final String totpSecret;

  const DashboardScreen({
    super.key,
    required this.userId,
    required this.phone,
    required this.initialBalance,
    required this.totpSecret,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late double _currentBalance;

  @override
  void initState() {
    super.initState();
    _currentBalance = widget.initialBalance;
  }

  // Обновление баланса с сервера
  Future<void> _refreshUserData() async {
    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:8000/users/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': widget.phone}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _currentBalance = data['balance'].toDouble();
        });
      }
    } catch (e) {
      debugPrint("Ошибка обновления данных: $e");
    }
  }

  // Вызов "Банковской" камеры для привязки лица
  Future<void> _pickAndUploadFace() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceCaptureScreen(userId: widget.userId),
      ),
    );

    // Если фото успешно отправлено, показываем зеленую плашку
    if (result == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ Лицо успешно привязано к аккаунту!'),
            backgroundColor: Colors.green
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartPass', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          // Кнопка выхода из аккаунта
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Выйти из аккаунта',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshUserData,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  // Карточка баланса
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Ваш баланс', style: TextStyle(fontSize: 16, color: Colors.grey)),
                            IconButton(
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (context) => TopUpScreen(userId: widget.userId)));
                                _refreshUserData(); // Обновляем после возврата
                              },
                              icon: const Icon(Icons.add_circle, color: Colors.blueAccent, size: 28),
                            ),
                          ],
                        ),
                        Text('${_currentBalance.toStringAsFixed(0)} сом', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (context) => PurchaseScreen(userId: widget.userId)));
                              _refreshUserData(); // Обновляем после возврата
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black12, elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Купить проездной', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Кнопка QR-билета
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => QrScreen(userId: widget.userId, totpSecret: widget.totpSecret)));
                    },
                    icon: const Icon(Icons.qr_code_2, size: 28, color: Colors.white),
                    label: const Text('Создать QR-билет', style: TextStyle(fontSize: 18, color: Colors.white)),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                  const SizedBox(height: 16),

                  // Кнопка привязки биометрии
                  OutlinedButton.icon(
                    onPressed: _pickAndUploadFace,
                    icon: const Icon(Icons.face, size: 24, color: Colors.black),
                    label: const Text('Привязать биометрию'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}