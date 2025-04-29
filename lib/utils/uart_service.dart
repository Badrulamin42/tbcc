import 'package:flutter/services.dart';

class UartService {
  static const _method = MethodChannel('com.example/uart');
  static const _event = EventChannel('com.example/uartStream');

  static Future<void> send(String data) async {
    await _method.invokeMethod('sendUart', {'message': data});
  }

  static Stream<String> get uartStream =>
      _event.receiveBroadcastStream().map((event) => event.toString());
}
