import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/services.dart'; // For loading assets
import 'dart:io';

import 'package:tbcc/main.dart'; // For dealing with certificates

// Generate a unique client ID based on the device data and current timestamp


class MqttService {
  late MqttServerClient client;
  final String broker = 'transpireqr-api.transpire.com.my'; // Your broker address
  final int port = 8883; // Secure port for MQTT over SSL
  late String clientId;
  Function(String)? onMessageReceived; // Callback for handling messages
   String deviceCode;

  // Constructor with required named parameter
  MqttService({required this.deviceCode}) {
    clientId = 'flutter_${deviceCode.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
  }
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
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.onConnected = onConnected;


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
        print('Connected to MQTT broker. $deviceCode');
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

  void onConnected() {
    myHomePageKey.currentState?.onMqttConnected();
    print('MQTT Connected');
  }

  void onDisconnected() {
    myHomePageKey.currentState?.onMqttDisconnected();
    print('Disconnected from the MQTT broker.');
    Future.delayed(Duration(seconds: 5), () {
      connect(onMessageReceivedCallback: onMessageReceived); // Attempt to reconnect
    });
  }

  void startConnectionChecker() {
    Timer.periodic(Duration(minutes: 5), (timer) {
      if (client.connectionStatus!.state != MqttConnectionState.connected) {
        print("Connection lost! Reconnecting...");
        connect(onMessageReceivedCallback: onMessageReceived);
      }
      else{
        print("mqtt connection is stable");
      }
    });
  }

  bool connectionChecker() {

      if (client.connectionStatus!.state != MqttConnectionState.connected) {

        return true;
      }
      else{
        return false;
      }

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
