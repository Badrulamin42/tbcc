import 'dart:typed_data';
import 'dart:async';
import 'package:libserialport/libserialport.dart';


class Communication {
  // Open the USB serial port, send data, and read reply
  Future<String> openPort() async {
    // Replace 'COM5' with the actual port name
    SerialPort port = SerialPort('COM5');
    port.config = SerialPortConfig()
      ..baudRate = 38400
      ..stopBits = 1
      ..parity = SerialPortParity.none
      ..bits = 8;


    if (!port.openReadWrite()) {
      print('Failed to open port: ${SerialPort.lastError}');
      return 'Failed to open port';
    }

    try {
      // Define the data
      port.flush();
      Uint8List RequestDispense10 = Uint8List.fromList([0xAA, 0x0A, 0x01, 0xD1, 0x01, 0x00, 0x00, 0x00, 0x35, 0xDE, 0xE4, 0xD4, 0xDD]);
      Uint8List Dispense10 = Uint8List.fromList([0xAA, 0x0E, 0x01, 0xD1, 0x02, 0x00, 0x00, 0x00, 0x5E, 0x66, 0x6D, 0x00, 0x00, 0x0A, 0x00, 0x83, 0xDD]);

      // Start reading from the port immediately
      SerialPortReader reader = SerialPortReader(port);
      Stream<Uint8List> responseStream = reader.stream;

      // Send the first data (RequestDispense10)
      print('Sending RequestDispense10');
      Uint8List testData = Uint8List.fromList([0x01, 0x02, 0x03]);
      port.write(RequestDispense10);
      print('Sending bytes: ${RequestDispense10.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      print('RequestDispense10 sent successfully');
      port.close();
      // Give the device some time to respond
      // await Future.delayed(Duration(milliseconds: 200)); // Adjust the delay as needed

      bool responseReceived = false;
      await for (var data in responseStream) {
        // Ensure the data is not empty
        if (data.isEmpty) {
          continue;
        }

        print('Received response: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

        // Check if the response matches the expected reply
        Uint8List expectedResponse = Uint8List.fromList([0xAA, 0x0A, 0x01, 0xD1, 0x01, 0x00, 0x00, 0x00, 0x35, 0xD3, 0xE4, 0xD4, 0xDD]);
        if (data.length == expectedResponse.length && _listEquals(data, expectedResponse)) {
          print('Expected response received');
          responseReceived = true;
          break; // Exit the loop once the expected response is received
        }
      }

      if (responseReceived) {
        // Send the second data (Dispense10) after receiving the correct reply
        print('Sending Dispense10');
        port.write(Dispense10);
        print('Dispense10 sent successfully');
      } else {
        print('Error: Did not receive the expected response');
      }

    } catch (e) {
      print('Error sending data: $e');
    } finally {
      // Close the port after use
      port.close();
      print('Port closed');
    }

    return 'Completed';
  }

  // Helper function to compare two lists of Uint8List
  bool _listEquals(Uint8List list1, Uint8List list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }
}
