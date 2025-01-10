import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'package:libserialport/libserialport.dart';

bool _listEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class Communication {
  final String portName = 'COM5'; // Replace with the actual port name
  late SerialPort port;
  bool isConnected = false;
  int dispenseAmount = 0;
  //init
  Communication() {
    port = SerialPort(portName);
    port.config = SerialPortConfig()
      ..baudRate = 38400
      ..stopBits = 1
      ..parity = SerialPortParity.none
      ..bits = 8;
  }

  // Connect to the serial port (only once)
  Future<bool> connect() async {
    if (isConnected) {
      print('Port is already connected.');
      return true;
    }

    try {
      if (!port.openReadWrite()) {
        print('Failed to open port: ${SerialPort.lastError}');
        return false;
      }

      isConnected = true;
      listenForResponse();
      print('Port opened successfully, Start Listening...');
      return true;
    } catch (e) {
      print('Error opening port: $e');
      return false;
    }
  }

  // Disconnect from the serial port (optional)
  void disconnect() {
    if (isConnected) {
      port.close();
      isConnected = false;
      print('Port closed.');
    } else {
      print('Port is already closed.');
    }
  }

  // Send data to the serial port
  Future<void> sendData(Uint8List data) async {
    // if (!isConnected) {
    //   print('Port is not connected. Please connect first.');
    //   return;
    // }

    try {
      port.write(data);
      print(
          'Data sent: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    } catch (e) {
      print('Error sending data: $e');
    }
  }

  // Read the response from the port
  Future<void> listenForResponse() async {
    SerialPortReader reader = SerialPortReader(port);
    Stream<Uint8List> responseStream = reader.stream;

    // Define the expected request and the response

    Uint8List pollingPCB =
        Uint8List.fromList([0xAA, 0x03, 0x02, 0x10, 0x11, 0xDD]);
    Uint8List pcToPollingPCB = Uint8List.fromList([
      0xAA,
      0x24,
      0x01,
      0x10,
      0x68,
      0x74,
      0x74,
      0x70,
      0x3A,
      0x2F,
      0x2F,
      0x6D,
      0x2E,
      0x6C,
      0x65,
      0x79,
      0x61,
      0x6F,
      0x79,
      0x61,
      0x6F,
      0x2E,
      0x63,
      0x6F,
      0x6D,
      0x2F,
      0x6C,
      0x79,
      0x79,
      0x2F,
      0x74,
      0x2F,
      0x31,
      0x32,
      0x33,
      0x34,
      0x35,
      0x36,
      0x37,
      0x38,
      0x2D,
      0xDD
    ]);

    Uint8List status1Request = Uint8List.fromList([
      0xAA,
      0xF0,
      0x02,
      0x14,
      0x1A,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x02,
      0xDD
    ]);

    Uint8List status2Request = Uint8List.fromList([
      0xAA,
      0xF0,
      0x02,
      0x14,
      0x1B,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x03,
      0xDD
    ]);

    Uint8List statusResponse =
        Uint8List.fromList([0xAA, 0x03, 0x01, 0x14, 0x16, 0xDD]);

    Uint8List ReqResponse = Uint8List.fromList([
      0xAA,
      0x0B,
      0x02,
      0xD1,
      0x01,
      0x00,
      0x00,
      0x00,
      0x35,
      0xDE,
      0xE4,
      0x01,
      0xD7,
      0xDD
    ]);

    //failed soldOut

    Uint8List resSoldOut = Uint8List.fromList([
      0xAA, 0xF0, 0x02, 0x14, 0x1C, 0x03, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x06, 0xDD
    ]);

// Second sequence
    Uint8List resSoldOut2 = Uint8List.fromList([
      0xAA, 0x03, 0x01, 0x14, 0x16, 0xDD
    ]);



    responseStream.listen((Uint8List data) {
      print(
          'Received data: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // Compare received data to the expected response

      //Polling

      if (_listEquals(data, pollingPCB)) {
        print('Expected response received (polling). Sending reply...');

        // Send the reply message
        port.write(pcToPollingPCB);
        print(
            'Reply sent: ${pcToPollingPCB.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }

      //status1
      if (_listEquals(data, status1Request) ||
          _listEquals(data, status2Request)) {
        print('Expected response received (status 1 or 2). Sending reply...');

        // Send the reply message
        port.write(statusResponse);
        print(
            'Reply sent: ${statusResponse.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }

      //Req
      if (_listEquals(data, ReqResponse)) {
        print('Expected response received (reqDis). Sending reply...');

        final discom = createDispenseCommand();
        // Send the reply message
        port.write(discom);
        print(
            'Reply sent: ${discom.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }

      // if()
    });
  }

  // Main function to control the flow of communication
  Future<String> main(String command) async {
    // // Connect to the port once
    // bool connected = await comm.connect();
    // if (!connected) {
    //   print('Failed to connect to the port.');
    //   return 'Failed';
    // }

    // Start listening for responses in the background

    // Define data to send
    Uint8List requestDispense = Uint8List.fromList([
      0xAA,
      0x0A,
      0x01,
      0xD1,
      0x01,
      0x00,
      0x00,
      0x00,
      0x35,
      0xDE,
      0xE4,
      0xD4,
      0xDD
    ]);

    // Send data based on command
    if (command == 'Req10') {
      dispenseAmount = 10;
      print('Sending RequestDispense10');
      await sendData(requestDispense);
    }
    else if(command == 'Req20'){
      dispenseAmount = 20;
      print('Sending RequestDispense20');
      await sendData(requestDispense);
    }
    else if(command == 'Req50'){
      dispenseAmount = 50;
      print('Sending RequestDispense50');
      await sendData(requestDispense);
    }
    else if(command == 'Req100'){
      dispenseAmount = 100;
      print('Sending RequestDispense100');
      await sendData(requestDispense);
    }

    else {
      print('Unknown command');
    }

    // Optional: Disconnect after communication
    await Future.delayed(Duration(milliseconds: 3000)); // Adjust if needed
    // comm.disconnect();

    return 'Completed';
  }

  //help & reply generator

  Uint8List createDispenseCommand() {
    // Base command structure with fixed part and placeholders
    List<int> command = [
      0xAA,
      0x0E,
      0x01,
      0xD1,
      0x02,
      0x00,
      0x00,
      0x00,
      0x5E,
      0x66,
      // Fixed part
      0x6D, //10th
      // Random byte (placeholder)
      0x00,
      0x00,
      0x0A, //13th amount, dafault 10
      0x00,
      0x83,
      0xDD
      // Checksum placeholder (0x83 is example)
    ];

    // Generate a random byte for the placeholder
    int randomByte =
        Random().nextInt(256); // Generates a random number from 0 to 255
    command[10] = randomByte;

    //set amount
    if(dispenseAmount == 10){
      command[13] = 0x0A;
    }
    else if(dispenseAmount == 20){
      command[13] = 0x14; // Set the 10th element to hexadecimal 0x14
    }
    else if(dispenseAmount == 50){
      command[10] = 0x32; // Set the 10th element to hexadecimal 0x14
    }
    else if(dispenseAmount == 100){
      command[10] = 0x64; // Set the 10th element to hexadecimal 0x14
    }
    else {
      command[13] = 0x00;
    }


    // Calculate checksum using XOR from index 1 to index 14 (excluding the checksum byte)
    int checksum = command.sublist(1, 15).reduce((a, b) => a ^ b);

    // Assign the checksum to the second last element
    command[15] = checksum;

    // Convert to Uint8List and return
    return Uint8List.fromList(command);
  }
}
