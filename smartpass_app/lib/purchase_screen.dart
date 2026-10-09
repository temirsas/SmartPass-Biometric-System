import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PurchaseScreen extends StatefulWidget {
  final int userId;

  const PurchaseScreen({super.key, required this.userId});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  bool _isPurchasing = false;

  final List<Map<String, dynamic>> tariffs = [
    {
      'id': 'unlimited_1',
      'name': '1 день Безлимит',
      'price': '50 сом',
      'icon': Icons.calendar_today,
    },
    {
      'id': 'unlimited_7',
      'name': '7 дней Безлимит',
      'price': '250 сом',
      'icon': Icons.date_range,
    },
    {
      'id': 'unlimited_30',
      'name': '30 дней Безлимит',
      'price': '800 сом',
      'icon': Icons.auto_awesome_motion,
    },
    {
      'id': 'ride_10',
      'name': 'Пакет на 10 поездок',
      'price': '150 сом',
      'icon': Icons.confirmation_number_outlined,
    },
  ];

  Future<void> _buyTariff(String subType, String name) async {
    setState(() => _isPurchasing = true);

    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:8000/subscriptions/purchase/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.userId, 'sub_type': subType}),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Тариф "$name" успешно активирован!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Возвращаемся на главную
      } else {
        // Читаем конкретную ошибку от нашего бэкенда (FastAPI)
        final errorData = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorData['detail'] ?? 'Ошибка при покупке');
      }
    } catch (e) {
      if (!mounted) return;
      // Убираем техническое слово "Exception:" из текста для красоты
      String errorMessage = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $errorMessage'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Купить проездной',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: tariffs.length,
            itemBuilder: (context, index) {
              final tariff = tariffs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.black,
                    child: Icon(tariff['icon'], color: Colors.white),
                  ),
                  title: Text(
                    tariff['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    'Стоимость: ${tariff['price']}',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _isPurchasing
                      ? null
                      : () => _buyTariff(tariff['id'], tariff['name']),
                ),
              );
            },
          ),
          if (_isPurchasing)
            const Center(child: CircularProgressIndicator(color: Colors.black)),
        ],
      ),
    );
  }
}
