import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/services.dart'; // For loading assets
import 'dart:io';

import 'package:tbcc/main.dart'; // For dealing with certificates

// Generate a unique client ID based on the device data and current timestamp
String generateClientId() {
  final deviceData = 'TQR000001';
  return 'flutter_${deviceData.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
}

class MqttService {
  late MqttServerClient client;
  final String broker = 'transpireqr-api.transpire.com.my'; // Your broker address
  final int port = 8883; // Secure port for MQTT over SSL
  final String clientId = generateClientId(); // Unique client ID
  Function(String)? onMessageReceived; // Callback for handling messages

  // Loads a certificate from assets
  Future<List<int>> loadCertificate(String fileName) async {
    try {
      final cert = await rootBundle.load('assets/$fileName');
      return cert.buffer.asUint8List();
    } catch (e) {
      throw Exception("Error loading certificate: $e");
    }
  }

  // Connects to the MQTT broker using SSL/TLS
  Future<void> connect({Function(String)? onMessageReceivedCallback}) async {
    onMessageReceived = onMessageReceivedCallback;

    client = MqttServerClient.withPort(broker, clientId, port);
    client.logging(on: false); // debugging
    client.keepAlivePeriod = 60;
    client.secure = true; // Enable secure connection (SSL/TLS)
    client.onDisconnected = onDisconnected;
    client.autoReconnect = false;

    // Load the CA certificate (PEM file) if needed for validation
    try {
      final caCert = await loadCertificate('mqtt_key.crt'); // Load the PEM certificate
      final securityContext = SecurityContext.defaultContext;
      securityContext.setTrustedCertificatesBytes(caCert);

      client.onBadCertificate = (Object? certificate) {
        print("Bad certificate: $certificate");
        return true; // Allow for testing, not recommended in production.
      };

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      client.connectionMessage = connMessage;

      try {
        print('Connecting to MQTT broker...');
        await client.connect();
        print('Connected to MQTT broker.');
        print('Connection status: ${client.connectionStatus!.state}');

        subscribeToTopic('/TQR/$deviceCode'); // Replace with your topic
      } catch (e) {
        print('Connection failed: $e');
        client.disconnect();
      }
    } catch (e) {
      print('Error loading certificates: $e');
    }
  }

  // Handle the disconnect event
  void onDisconnected() {
    print('Disconnected from the MQTT broker.');
  }

  // Subscribe to a specific topic
  void subscribeToTopic(String topic) {
    if (client.connectionStatus!.state == MqttConnectionState.connected) {

      client.subscribe(topic, MqttQos.atMostOnce);

      client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? messages) {
        final MqttPublishMessage message = messages![0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(message.payload.message);



        if (onMessageReceived != null) {
          onMessageReceived!(payload); // Call the callback with the message
        }
      });
    } else {
      print('Cannot subscribe, client not connected.');
    }
  }

  // Disconnect from the broker
  void disconnect() {
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      client.unsubscribe('/TQR/$deviceCode');
      print('Unsubscribed from topic: /TQR/$deviceCode');
    }
    client.disconnect();
    print('Disconnected.');
  }
}
