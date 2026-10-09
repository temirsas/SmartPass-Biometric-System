import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:otp/otp.dart';
import 'dart:convert';
import 'dart:async';

class QrScreen extends StatefulWidget {
  final int userId;
  final String totpSecret;

  const QrScreen({super.key, required this.userId, required this.totpSecret});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  late Timer _timer;
  String _qrData = "";
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _generateQrData();
    // Запускаем таймер, который тикает каждую секунду
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      // TOTP обновляется каждые 30 секунд (в 0 и 30 секунд каждой минуты)
      final seconds = now.second;
      final remaining = 30 - (seconds % 30);

      setState(() {
        _secondsLeft = remaining;
      });

      // Если код только что обновился — генерируем новый QR
      if (remaining == 30) {
        _generateQrData();
      }
    });
  }

  void _generateQrData() {
    // Генерируем 6-значный код
    final code = OTP.generateTOTPCodeString(
      widget.totpSecret,
      DateTime.now().millisecondsSinceEpoch,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );

    // Упаковываем в JSON для валидатора
    final dataMap = {"user_id": widget.userId, "totp_code": code};

    setState(() {
      _qrData = jsonEncode(dataMap);
    });
  }

  @override
  void dispose() {
    _timer.cancel(); // Обязательно убиваем таймер при закрытии экрана
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Ваш билет',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Поднесите QR-код к валидатору',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 40),

              // Сам QR-код
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(26),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _qrData,
                  version: QrVersions.auto,
                  size: 250.0,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Индикатор времени жизни кода
              Text(
                'Код обновится через: $_secondsLeft сек',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // Прогресс-бар для красоты
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: _secondsLeft / 30,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.blueAccent,
                  ),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
