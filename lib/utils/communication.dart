import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_usb/flutter_usb.dart';
import 'package:usb_serial/usb_serial.dart';
import '../main.dart';

bool _listEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class Result {
  final bool success;
  final String message;
  final int utdQr;
  Result({required this.success, required this.message, required this.utdQr});
}

class Communication  extends ChangeNotifier {
  UsbDevice? _device;
  UsbPort? _port;
  final String portName = Platform.isAndroid ? '/dev/ttyS3' : 'COM5';

  late SerialPort port;
  bool isConnected = false;
  bool isQr = false;
  bool isSoldOut = false;
  bool isCompleteDispense = false;
  int dispenseAmount = 0;
  int totalUtdQr= 0;
  int UtdCash = 0;
  int CashCounter = 0;
  int cashValue_ = 0;
  bool isDispenseCash = false;




  //init
  Communication(UsbDevice? testPort) {

    try {
    var open =  findAndOpenDevice(testPort);


    print('isconnected $isConnected');

      Future.delayed(Duration(seconds: 1), () {
        setupCommunication();
        notifyListeners(); // Notify listeners on change
        print('isconnected2 $isConnected');
      });

      if(isConnected){
        Future.delayed(Duration(seconds: 3), () {
          listenForResponse();
        });
      }

    }
    catch(e){
      throw Exception(e);
    }


  }
  void updateConnectionStatus(bool status) {
    isConnected = status;
    notifyListeners(); // Notify listeners on change
  }

  // Monitor the connection status in real-time
  void startConnectionMonitor() {
    Timer.periodic(Duration(seconds: 2), (timer) {
      bool status = checkConnection();
      if (status != isConnected) {
        updateConnectionStatus(status);
      }
    });
  }

  bool checkConnection() {
    // Add your logic to check connection status
    return _port != null;
  }
  Future<void> setupCommunication() async {
    if (_port != null) {
      await _port!.setPortParameters(
        38400, // Set the baud rate (e.g., 115200)
       UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
         UsbPort.PARITY_NONE,
      );
      print('Serial communication configured!');
    }
  }

  Future<bool> findAndOpenDevice(UsbDevice? init) async {

    try {
      // List all devices connected via USB
      List<UsbDevice> devices = await UsbSerial.listDevices();
      print('Devices : $devices');
      // Find the device by its Vendor ID and Product ID
      if(init == null) {
        _device =
        // null as UsbDevice; //testing
        devices.firstWhere(
            (device) =>
             device.vid == 0x1A86 && device.pid == 0x7523,

        // device.vid == 0x1A86 && device.pid == 0x7523, // Vendor ID: 1a86, Product ID: 7523
        orElse: () => throw Exception("USB Serial device not found!"),

      );
      } else{
        _device = init;
      }

      if (_device == null) {


       return false;
      }
    }
    catch(e){
      throw Exception(e);
    }


    // Open the device
    await openDevice(_device!);
    return true;
  }

  // Open the USB serial device
  Future<bool> openDevice(UsbDevice device) async {
    try {
      _port = await device.create();
      if (_port != null) {
        bool opened = await _port!.open();
        if (opened) {
          isConnected = true;
          print('Device opened successfully!');
          return true;
        } else {
          print('Failed to open the device.');
          return false;
        }
      }
      else {
        print('Device not found');
        return false;
      }
    }
    catch(e){
    throw Exception(e);
    }
  }

  // Connect to the serial port (only once)




  // Send data to the serial port
  Future<void> sendData(Uint8List data) async {
    // if (!isConnected) {
    //   print('Port is not connected. Please connect first.');
    //   return;
    // }

    try {
      _port!.write(data);
      print(
          'Data sent: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    } catch (e) {
      print('Error sending data: $e');
    }
  }

  // Read the response from the port
  Future<void> listenForResponse() async {
    // SerialPortReader reader = SerialPortReader(port);
    // Stream<Uint8List> responseStream = reader.stream;
    print('Start Listening...');
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

 

    _port!.inputStream?.listen((Uint8List data) async {
      print('Raw data: $data'); // Prints the raw data bytes
      print('Hex data: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data

      // Compare received data to the expected response

      //Polling

      if (_listEquals(data, pollingPCB)) {
        print('Expected response received (polling). Sending reply...');

        // Send the reply message
        _port!.write(pcToPollingPCB);
        print(
            'Reply sent: ${pcToPollingPCB.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }

      //status1
      if (_listEquals(data, status1Request) ||
          _listEquals(data, status2Request)) {
        print('Expected response received (status 1 or 2). Sending reply...');

        // Send the reply message
        _port!.write(statusResponse);
        print(
            'Reply sent: ${statusResponse.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }

      //Req
      if (_listEquals(data, ReqResponse)) {
        print('Expected response received (reqDis). Sending reply...');

        final discom = await createDispenseCommand();
        // Send the reply message
        _port!.write(discom);
        print(
            'Reply sent: ${discom.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }

      // handle soldout
      if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x0F && data[2] == 0x02 && data[3] == 0x14) {
        print('Expected response received (soldout). Sending reply...');
        isSoldOut = true;

        if(isQr == false && isDispenseCash == false){
          myHomePageKey.currentState?.setLatestFailedTrx();
        }

        if(isQr == false && isDispenseCash == true) {

          myHomePageKey.currentState?.InsertCash('Failed', 0, 0, 0);
        }
        // Send the reply message
        _port!.write(resSoldOut2);
        print(
            'Reply sent: ${resSoldOut2.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }

      // Dispensing Check if the response starts with the valid start byte
      if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x0C && data[2] == 0x02 && data[3] == 0xD1 && data[4] == 0x20) {
        print("Dispensing.");

        // Check if the response length is correct
        if (data.length == 15) {


          // Decode dynamic data
          int cashValue = data[5] |
          (data[6] << 8) |
          (data[7] << 16) |
          (data[8] << 24); // 6th-9th byte

          int totalNeeded = data[9] | (data[10] << 8); // 10th-11th byte

          int RemainingtoDispense = data[11] | (data[12] << 8); // 12th-13th byte

          // Print decoded values
          print("Cash Value: $cashValue");
          print("Total Needed to Dispense: $totalNeeded");
          print("Remaining to Dispense: $RemainingtoDispense");

          // if(RemainingtoDispense == 0 && cashValue == 0)
          //   {
          //     isCompleteDispense = true;
          //   }

          if(RemainingtoDispense > 0 && cashValue > 0){
            myHomePageKey.currentState?.InsertCash('Dispensing', 0, 0, 0);
            isDispenseCash = true;
            cashValue_ = cashValue;
            print('cash dispensing true');
          }

          myHomePageKey.currentState?.remainingToDispense(RemainingtoDispense);


        } else {
          print("Invalid response length.");
        }
      }
      //UTD QR
      if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x13 && data[2] == 0x02 && data[3] == 0xD1 && data[4] == 0x05
      ) {
        print("Dispensed, QR UTD here.");

        // Check if the response length is correct


          // Decode dynamic data
          int QRDispenseCounter = data[14] |
          (data[15] << 8);

          int UTDQRDispenseCounter = data[16] |
          (data[17] << 8) |
          (data[18] << 16) |
          (data[19] << 24); // Correct byte order for little-endian

          // Print decoded values
          print("Qr Dispense Counter: $QRDispenseCounter");
          print("UTD qr Dispense Counter: $UTDQRDispenseCounter");

        totalUtdQr = UTDQRDispenseCounter;

          if(QRDispenseCounter > 0)
            {
              isCompleteDispense = true;
            }


      }

      //UTD cash
      if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x19 && data[2] == 0x02 && data[3] == 0xD1 && data[4] == 0x06
      ) {
        print("Dispensed, Cash UTD here.");
        isDispenseCash = true;

        // Check if the response length is correct
        if (data.length == 28) {


          // Decode dynamic data
          int CASHDispenseCounter = data[11] |
          (data[12] << 8);


          int UTDCASHDispenseCounter = data[13] |
          (data[14] << 8)|
          (data[15] << 16) |
          (data[16] << 24); // 10th-11th byte

          int CASHCounter = data[18] |
          (data[19] << 8)|
          (data[20] << 16) |
          (data[21] << 24); // 10th-11th byte

          int UTDCASHCounter = data[22] |
          (data[23] << 8)|
          (data[24] << 16) |
          (data[25] << 24); // 10th-11th byte

          // Print decoded values
          print("Cash Dispense Counter: $CASHDispenseCounter");
          print("UTD Cash Dispense Counter: $UTDCASHDispenseCounter");
          print("Cash Counter: $CASHCounter");
          print("UTD Cash Counter: $UTDCASHCounter");


            if(CASHDispenseCounter > 0 && UTDCASHDispenseCounter > 0) {
              myHomePageKey.currentState?.InsertCash(
                  'Completed', UTDCASHCounter, CASHCounter,
                  CASHDispenseCounter);
              isCompleteDispense = true;

              print('cash dispense complete true');

              CashCounter = CASHCounter;
              UtdCash = UTDCASHDispenseCounter;
            }

        } else {
          print("Invalid response length.");
        }
      }


    });
  }

  Future<Result> inject(int amount) async {
    isQr = true;
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

    dispenseAmount = amount;
    print('Sending RequestDispense20');
    await sendData(requestDispense);


    const int maxRetries = 60; // Maximum retries
    int retries = 0;

    // Retry until isCompleteDispense becomes true or retries exceed maxRetries
    while (retries < maxRetries) {
      if (isCompleteDispense) {
        // If isCompleteDispense becomes true, return 'Completed'
        isCompleteDispense = false; // Reset the flag for future operations
        isQr = false;
        print('after result return $totalUtdQr');
        return Result(success: true, message: '0', utdQr: totalUtdQr);
      }

      if(isSoldOut) {
        isSoldOut = false;
        isCompleteDispense = false;
        isQr = false;

        return Result(success: false, message: '1', utdQr: 0);
      }

      // Wait for the specified interval before retrying
      await Future.delayed(Duration(milliseconds: 2000));
      retries++;
    }


    isQr = false;
    // If retries exceed maxRetries, return 'Failed'
    return Result(success: false, message: '2', utdQr : 0);
  }

  // Main function to control the flow of communication
  Future<Result> main(int command) async {
    isQr = true;

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
      if(command > 0) {
        dispenseAmount = command;

        await sendData(requestDispense);
      }
      else{
        print('Unknown command');
      }

    // Optional: Disconnect after communication
    // await Future.delayed(Duration(milliseconds: timing)); // Adjust if needed
    // comm.disconnect();



    const int maxRetries = 60; // Maximum retries
    int retries = 0;

    // Retry until isCompleteDispense becomes true or retries exceed maxRetries
    while (retries < maxRetries) {
      if (isCompleteDispense) {
        // If isCompleteDispense becomes true, return 'Completed'
        isCompleteDispense = false; // Reset the flag for future operations
        isQr = false;
        print('after result return $totalUtdQr');
        return Result(success: true, message: '0', utdQr: totalUtdQr);
      }

      if(isSoldOut) {
        isSoldOut = false;
        isCompleteDispense = false;
        isQr = false;

        return Result(success: false, message: '1', utdQr: 0);
      }

      // Wait for the specified interval before retrying
      await Future.delayed(Duration(milliseconds: 2000));
      retries++;
    }


    isQr = false;
    // If retries exceed maxRetries, return 'Failed'
    return Result(success: false, message: '2', utdQr : 0);
  }

  //help & reply generator

  Future<Uint8List> createDispenseCommand()  async {
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
      0x0A, //13th amount, default 10
      0x00,
      0x83,
      0xDD
      // Checksum placeholder (0x83 is example)
    ];

    int randomByte;

    // Generate a random byte excluding 0xAA and 0xDD
    do {
      randomByte = Random().nextInt(256); // Generates a random number from 0 to 255
    } while (randomByte == 0xAA || randomByte == 0xDD);

    // Assign the random byte
    command[10] = randomByte;

    command[13] = dispenseAmount & 0xFF;        // Extract lower 8 bits
    command[14] = (dispenseAmount >> 8) & 0xFF; // Extract upper 8 bits
    print('dispense amount $dispenseAmount');

    // Recalculate checksum using XOR from index 1 to index 14 (excluding the checksum byte)
    int checksum = command.sublist(1, 15).reduce((a, b) => a ^ b);

    // Assign the checksum to the second last element
    command[15] = checksum;

    // Convert to Uint8List and return
    return Uint8List.fromList(command);
  }

}
