import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:tbcc/utils/HelperFunction/commonUtility.dart';
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

class Communication {
  UsbDevice? _device;
  UsbPort? _port;
  final String portName = Platform.isAndroid ? '/dev/ttyS3' : 'COM5';

  bool isConnected = false;
  bool isQr = false;
  bool isSoldOut = false;
  bool isCompleteDispense = false;
  bool isDispensing = false;
  int dispenseAmount = 0;
  int RemainingtoDispenseG = 9999;
  int totalUtdQr = 0;
  int UtdCash = 0;
  int CashCounter = 0;
  int cashValue_ = 0;
  int CASHDispenseCounter_ = 0;
  bool isDispenseCash = false;
  String hexString = '';
  List<int> sentreqcommand = [];
  // List<String> logMessage = [];

  DateTime currentDateTime = DateTime.now();
  //init

  Communication(UsbDevice? testPort) {
    try {
      findAndOpenDevice(testPort);

       LogStorage.logMessage('Start Communication isconnected >>> $isConnected');

      Future.delayed(Duration(seconds: 3), () {
        setupCommunication();

        LogStorage.logMessage('Start Communication isconnected Test 2 >>> $isConnected');
      });

      Future.delayed(Duration(seconds: 5), () {
        listenForResponse();
      });
    } catch (e) {
      throw Exception(e);
    }
  }
  Future<void> setupCommunication() async {
    if (_port != null) {
      await _port!.setPortParameters(
        38400, // Set the baud rate (e.g., 115200)
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      LogStorage.logMessage('Serial communication configured!');

    }
  }

  Future<bool> findAndOpenDevice(UsbDevice? init) async {
    try {
      // List all devices connected via USB
      List<UsbDevice> devices = await UsbSerial.listDevices();
      LogStorage.logMessage('Devices >>> $devices');

      // Find the device by its Vendor ID and Product ID
      if (init == null) {
        _device =
            // null as UsbDevice; //testing
            devices.firstWhere(
          (device) => device.vid == 0x1A86 && device.pid == 0x7523,

          // device.vid == 0x1A86 && device.pid == 0x7523, // Vendor ID: 1a86, Product ID: 7523
          orElse: () => throw Exception("USB Serial device not found!"),

        );
      } else {
        _device = init;
      }

      if (_device == null) {
        LogStorage.logMessage('No device initialized!');
        return false;
      }
    } catch (e) {
      LogStorage.logMessage('Error - $e');
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
          LogStorage.logMessage('Device opened successfully!');

          return true;
        } else {
          LogStorage.logMessage('Failed to open the device.');
          return false;
        }
      } else {
        LogStorage.logMessage('Device not found.');
        return false;
      }
    } catch (e) {
      LogStorage.logMessage('Error - $e');
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
      LogStorage.logMessage(
          'Android OUT >>> ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'
      );
    } catch (e) {
      LogStorage.logMessage('Error - $e');
    }
  }

  List<int> _buffer = [];
  Timer? _timeoutTimer;

  Future<void> _handleIncomingData(Uint8List data) async {
    _buffer.addAll(data);

    // Reset timeout each time new data is received
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(Duration(seconds: 1), () {
      print('Timeout! Clearing buffer.');
      _buffer.clear();
    });

    while (_buffer.isNotEmpty) {
      // Ensure start byte is correct
      while (_buffer.isNotEmpty && _buffer[0] != 0xAA) {
        LogStorage.logMessage('❌ Invalid start byte: ${_buffer[0].toRadixString(16)}. Discarding...');
        _buffer.removeAt(0);
        await Future.delayed(
            Duration(milliseconds: 10)); // Allow async processing
      }

      if (_buffer.length < 3) {
        return; // Not enough data to determine length
      }

      int length = _buffer[1];
      int expectedLength =
          length + 3; // Total message size including header and end byte

      if (_buffer.length >= expectedLength) {
        // We received enough bytes, check the end byte
        if (_buffer[expectedLength - 1] != 0xDD) {
          LogStorage.logMessage('❌ Error: Invalid end byte, discarding entire buffer.');
          _buffer.clear();
          return;
        }

        // ✅ Valid complete message received
        List<int> message = _buffer.sublist(0, expectedLength);
        _buffer.removeRange(0, expectedLength);


        LogStorage.logMessage('✅ Complete Message Received: ${message.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

        await _processMessage(Uint8List.fromList(message));

        // Clear buffer after processing a full message
        _buffer.clear();
      } else if (_buffer.contains(0xDD)) {
        // ❌ If `0xDD` is found early and length is invalid, clear buffer

        LogStorage.logMessage('${currentDateTime}:❌ Error: Found end byte `0xDD` but length is invalid. Clearing buffer.');

        _buffer.clear();
        return;
      } else {
        await Future.delayed(
            Duration(milliseconds: 150)); // Allow time for next data chunk
        return; // Wait for more data
      }
    }
  }

  Future<void> _processMessage(Uint8List message) async {
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
      0x0F,
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
      0x0F,
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
      0xAA,
      0xF0,
      0x02,
      0x14,
      0x1C,
      0x03,
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
      0x06,
      0xDD
    ]);

// Second sequence
    Uint8List resSoldOut2 =
        Uint8List.fromList([0xAA, 0x03, 0x01, 0x14, 0x16, 0xDD]);

    Uint8List unknownReply =
        Uint8List.fromList([0xAA, 0x03, 0x01, 0x00, 0x02, 0xDD]);

    Uint8List dispensing =
        Uint8List.fromList([0xAA, 0x03, 0x01, 0xD1, 0x20, 0xF3, 0xDD]);

    Uint8List cashteldis =
        Uint8List.fromList([0xAA, 0x04, 0x01, 0xD1, 0x06, 0xD2, 0xDD]);

    Uint8List qrteldis =
        Uint8List.fromList([0xAA, 0x04, 0x02, 0xD1, 0x05, 0xD1, 0xDD]);
    //aa 03 02 19 18 dd
    Uint8List aftersoldout =
        Uint8List.fromList([0xAA, 0x03, 0x02, 0x19, 0x18, 0xDD]);
    Uint8List aftersoldoutres =
        Uint8List.fromList([0xAA, 0x05, 0x01, 0x19, 0x00, 0x00, 0x1D, 0xDD]);
    Uint8List qrdisres = Uint8List.fromList([
      0xAA,
      0x0F,
      0x02,
      0xD1,
      0x02,
      0x00,
      0x00,
      0x00,
      0x5E,
      0x66,
      0x48,
      0x00,
      0x00
    ]);

    Uint8List aftersoldoutres2 = Uint8List.fromList([
      0xAA,
      0x0B,
      0x01,
      0x01,
      0x41,
      0x30,
      0x30,
      0x30,
      0x30,
      0x32,
      0x33,
      0x36,
      0x7D,
      0xDD
    ]);
    Uint8List aftersoldoutaccept2 =
        Uint8List.fromList([0xAA, 0x05, 0x02, 0x01, 0x85, 0x17, 0x94, 0xDD]);
    //AA 05 02 01 85 17 94 DD

    //AA 05 01 19 00 00 1D DD
    LogStorage.logMessage('Processing message >>> ${message.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

    await Future.delayed(
        Duration(milliseconds: 10)); // Simulate async processing
    final Uint8List data;

    data = message;
    //Polling
    LogStorage.logMessage('Data >>> ${data}');

    if (_listEquals(data, aftersoldout)) {
      await _port!.write(aftersoldoutres);
      await Future.delayed(Duration(milliseconds: 200));
      await _port!.write(aftersoldoutres2);

      LogStorage.logMessage('Android OUT >>>: ${aftersoldoutres.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

    } else if (_listEquals(data, pollingPCB)) {
      LogStorage.logMessage('Expected response received (polling). Sending reply...');
      // Send the reply message
      await _port!.write(pcToPollingPCB);

      LogStorage.logMessage('Android OUT >>>: ${pcToPollingPCB.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      await Future.delayed(Duration(milliseconds: 200));
      await _port!.write(aftersoldoutres2);

      LogStorage.logMessage('Android OUT >>>: ${aftersoldoutres2.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    //status1
    else if (_listEquals(data, status1Request)) {
      LogStorage.logMessage('List Equal = ${_listEquals(data, status1Request)}');
      LogStorage.logMessage('Expected response received (status 1). Sending reply...');

      if (isQr == false && isDispenseCash == false) {
        myHomePageKey.currentState?.setLatestFailedTrx();
      }
      // Send the reply message
      _port!.write(statusResponse);
      LogStorage.logMessage('Android OUT >>>: ${statusResponse.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
    //status2
    //status1
    else if (_listEquals(data, status2Request)) {
      LogStorage.logMessage('The Hex are not Equal:  ${_listEquals(data, status2Request)}');
      LogStorage.logMessage('Expected response received (status 2). Sending reply...');

      // Send the reply message
      _port!.write(statusResponse);
      LogStorage.logMessage('Android OUT >>>: ${statusResponse.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    //Req
    else if (_listEquals(data, ReqResponse)) {
      LogStorage.logMessage('The Hex are not Equal:  ${_listEquals(data, ReqResponse)}');
      LogStorage.logMessage('Expected response received (request_Dispense). Sending reply...');

      final discom = await createDispenseCommand();
      // Send the reply message
      _port!.write(discom);
      LogStorage.logMessage('Android OUT >>>: ${discom.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

    } else if (data.length >= 18 &&
        data[0] == 0xAA &&
        data[1] == 0x0F &&
        data[2] == 0x02 &&
        data[3] == 0x14 &&
        data[4] == 0x1C &&
        data[5] == 0x03) {

      LogStorage.logMessage('Expected response received (soldout). Sending reply...');

      isSoldOut = true;
      isDispensing = false;
      myHomePageKey.currentState?.setSoldout();

      if (isQr == false) {
        LogStorage.logMessage('isQR = $isQr');
        myHomePageKey.currentState?.InsertCash('Failed', 0, 0, 0, 0);
      }
      // Send the reply message
      _port!.write(resSoldOut2);
      LogStorage.logMessage('Android OUT >>>: ${resSoldOut2.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

    }

    // Dispensing Check if the response starts with the valid start byte
    else if (data.isNotEmpty &&
        data[0] == 0xAA &&
        data[1] == 0x0C &&
        data[2] == 0x02 &&
        data[3] == 0xD1 &&
        data[4] == 0x20) {
      LogStorage.logMessage('Dispensing.');

      isDispensing = true;
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

        LogStorage.logMessage('Cash Value: $cashValue');
        LogStorage.logMessage('Total Needed to Dispense: $totalNeeded');
        LogStorage.logMessage('Remaining to Dispense: $RemainingtoDispense');


        RemainingtoDispenseG = RemainingtoDispense;
        // Send the reply message
        _port!.write(dispensing);

        LogStorage.logMessage('Android OUT >>>: ${dispensing.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
        // if(RemainingtoDispense == 0 && cashValue == 0)
        //   {
        //     isCompleteDispense = true;
        //   }

        if (RemainingtoDispense > 0 && cashValue > 0) {
          myHomePageKey.currentState?.InsertCash('Dispensing', 0, 0, 0, 0);
          isDispenseCash = true;
          cashValue_ = cashValue;
          LogStorage.logMessage('cash dispensing true');
        }

        myHomePageKey.currentState?.remainingToDispense(RemainingtoDispense);
        LogStorage.logMessage('Remaining to Dispense >>> $RemainingtoDispense');
      } else {
        LogStorage.logMessage('Invalid response length.');
      }
    }
    //UTD QR
    else if (data.isNotEmpty &&
        data[0] == 0xAA &&
        data[1] == 0x13 &&
        data[2] == 0x02 &&
        data[3] == 0xD1 &&
        data[4] == 0x05) {

      LogStorage.logMessage('Stages >>> Dispensed, QR UTD.');
      isDispensing = false;
      // Check if the response length is correct

      // Decode dynamic data
      int QRDispenseCounter = data[14] | (data[15] << 8);

      int UTDQRDispenseCounter = data[16] |
          (data[17] << 8) |
          (data[18] << 16) |
          (data[19] << 24); // Correct byte order for little-endian

      // Print decoded values
      LogStorage.logMessage('Qr Dispense Counter >>> $QRDispenseCounter');
      LogStorage.logMessage('UTD QR Dispense Counter >>> $UTDQRDispenseCounter');

      // Send the reply message
      _port!.write(qrteldis);
      LogStorage.logMessage('Android OUT >>>: ${qrteldis.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      totalUtdQr = UTDQRDispenseCounter;

      LogStorage.logMessage('totalUtdQr >>>: ${totalUtdQr}');

      if (QRDispenseCounter > 0) {
        LogStorage.logMessage('QRDispenseCounter >>> ${QRDispenseCounter}');
        isCompleteDispense = true;
      }
    }

    //UTD cash
    else if (data.isNotEmpty &&
        data[0] == 0xAA &&
        data[1] == 0x19 &&
        data[2] == 0x02 &&
        data[3] == 0xD1 &&
        data[4] == 0x06) {
      hexString = data
          .map((byte) =>
              '0x${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}')
          .join(' ');

      LogStorage.logMessage('Stage >>> Dispensed, Cash UTD here.');
      LogStorage.logMessage('Data Length >>> ${data.length})');

      isDispenseCash = true;
      isDispensing = false;
      // Check if the response length is correct
      if (data.length == 28) {
        // Decode dynamic data
        int CASHDispenseCounter = data[11] | (data[12] << 8);

        int UTDCASHDispenseCounter = data[13] |
            (data[14] << 8) |
            (data[15] << 16) |
            (data[16] << 24); // 10th-11th byte

        int CASHCounter = data[18] |
            (data[19] << 8) |
            (data[20] << 16) |
            (data[21] << 24); // 10th-11th byte

        int UTDCASHCounter = data[22] |
            (data[23] << 8) |
            (data[24] << 16) |
            (data[25] << 24); // 10th-11th byte

        // Print decoded values
        LogStorage.logMessage('Cash Dispense Counter >>> $CASHDispenseCounter');
        LogStorage.logMessage('UTD Cash Dispense Counter >>> $UTDCASHDispenseCounter');
        LogStorage.logMessage('Cash Counter >>> $CASHCounter');
        LogStorage.logMessage('UTD Cash Counter >>> $UTDCASHCounter');

        // Send the reply message
        _port!.write(cashteldis);
        LogStorage.logMessage('Android OUT >>>: ${cashteldis.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

        if (CASHDispenseCounter > 0 && UTDCASHDispenseCounter > 0) {
          myHomePageKey.currentState?.InsertCash(
              'Completed',
              UTDCASHDispenseCounter,
              CASHCounter,
              CASHDispenseCounter,
              UTDCASHCounter);
          isCompleteDispense = true;
          LogStorage.logMessage('cash dispense complete true');

          CASHDispenseCounter_ = CASHDispenseCounter;
          CashCounter = CASHCounter;
          UtdCash = UTDCASHDispenseCounter;
        }
      } else {
        LogStorage.logMessage('Invalid response length.');

      }
    }
    //req res
    //aa 0f 02 d1 02 00 00 00 5e 66 d5 00 00 01 0a 00 38 dd
    else if (data.isNotEmpty &&
        data[0] == 0xAA &&
        data[1] == 0x0F &&
        data[2] == 0x02 &&
        data[3] == 0xD1 &&
        data[4] == 0x02 &&
        data[5] == 0x00 &&
        data[6] == 0x00 &&
        data[7] == 0x00 &&
        data[8] == 0x5E &&
        data[9] == 0x66 &&
        data[10] == sentreqcommand[10]) {
      if (data[13] == 0x01) {

        LogStorage.logMessage('Mother board receive signal and dispense');
      } else {
        LogStorage.logMessage('Mother board not able receive signal and dispense');
      }
      LogStorage.logMessage('Accepted request receive');
      // print("Accepted request receive ");
    } else if (_listEquals(data, aftersoldoutaccept2)) {
      print('new ***');
      LogStorage.logMessage(' The Hex are not Equal >>> ${_listEquals(data, aftersoldoutaccept2)}');
    } else {
      LogStorage.logMessage('Unknown Communication detected');
      //print("Unknown Comm detected");
      unknownReply[3] = data[3];
      _port!.write(unknownReply);
      LogStorage.logMessage('Android OUT >>>: ${unknownReply.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
  }

  Future<void> listenForResponse() async {
    // SerialPortReader reader = SerialPortReader(port);
    // Stream<Uint8List> responseStream = reader.stream;
    LogStorage.logMessage('Start Listening');
    // Define the expected request and the response

    _port!.inputStream?.listen((Uint8List data) async {
      LogStorage.logMessage('MainBoard IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      _handleIncomingData(data);
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
    LogStorage.logMessage('Sending RequestDispense20 || dispenseAmount >>> $dispenseAmount');

    await sendData(requestDispense);

    const int maxRetries = 30; // Maximum retries
    int retries = 0;

    // Retry until isCompleteDispense becomes true or retries exceed maxRetries
    while (retries < maxRetries) {
      if (isCompleteDispense) {
        // If isCompleteDispense becomes true, return 'Completed'
        isCompleteDispense = false; // Reset the flag for future operations
        isQr = false;

        LogStorage.logMessage('maxRetries >>> $maxRetries || retries >>> $retries after result return $totalUtdQr');

        return Result(success: true, message: '0', utdQr: totalUtdQr);
      }

      if (isSoldOut) {
        isSoldOut = false;
        isCompleteDispense = false;
        isQr = false;
        LogStorage.logMessage('isSoldOut >>> $isSoldOut');
        return Result(success: false, message: '1', utdQr: 0);
      }

      // Wait for the specified interval before retrying
      await Future.delayed(Duration(milliseconds: 2000));
      retries++;
      LogStorage.logMessage('$retries');
    }

    isQr = false;
    // If retries exceed maxRetries, return 'Failed'
    return Result(success: false, message: '2', utdQr: 0);
  }

  // Main function to control the flow of communication
  Future<Result> main(int command) async {
    isQr = true;
    isDispensing = false;
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
    if (command > 0) {
      dispenseAmount = command;

      await sendData(requestDispense);
    } else {

      LogStorage.logMessage('Unknown command');
    }

    // Optional: Disconnect after communication
    // await Future.delayed(Duration(milliseconds: timing)); // Adjust if needed
    // comm.disconnect();

    const int maxRetries = 30; // Maximum retries
    int retries = 0;

    // Retry until isCompleteDispense becomes true or retries exceed maxRetries
    while (retries < maxRetries) {
      // if(RemainingtoDispenseG == 0)
      //   {
      //     isCompleteDispense = true;
      //   }
      LogStorage.logMessage('maxRetries >>> $maxRetries || retries >>> $retries');

      if (isCompleteDispense) {
        // If isCompleteDispense becomes true, return 'Completed'
        isCompleteDispense = false; // Reset the flag for future operations
        isQr = false;
        isDispensing = false;
        // RemainingtoDispenseG = 9999;
        LogStorage.logMessage('Status Complete Dispense >>> $isCompleteDispense');
        LogStorage.logMessage('After result return $totalUtdQr');
        return Result(success: true, message: '0', utdQr: totalUtdQr);
      }

      if (isSoldOut) {
        isSoldOut = false;
        isCompleteDispense = false;
        isQr = false;
        isDispensing = false;
        // RemainingtoDispenseG = 9999;
        return Result(success: false, message: '1', utdQr: 0);
      }

      // Wait for the specified interval before retrying
      await Future.delayed(Duration(milliseconds: 1000));
      if (isDispensing) {
        retries = 0;
      } else {
        retries++;
      }
    }

    isQr = false;

    // If retries exceed maxRetries, return 'Failed'
    // message: 2 is refund , 3 no refund
    LogStorage.logMessage('Message = isDispensing >>> $isDispensing [IF isDispensing = 2 mean Refund and 3 mean No Refund]');
    return Result(success: false, message: isDispensing ? '3' : '2', utdQr: 0);
  }

  //help & reply generator

  Future<Uint8List> createDispenseCommand() async {
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
      randomByte =
          Random().nextInt(256); // Generates a random number from 0 to 255
    } while (randomByte == 0xAA || randomByte == 0xDD);

    // Assign the random byte
    command[10] = randomByte;

    command[13] = dispenseAmount & 0xFF; // Extract lower 8 bits
    command[14] = (dispenseAmount >> 8) & 0xFF; // Extract upper 8 bits

    LogStorage.logMessage(' Dispense amount >>> $dispenseAmount');
    // Recalculate checksum using XOR from index 1 to index 14 (excluding the checksum byte)
    int checksum = command.sublist(1, 15).reduce((a, b) => a ^ b);

    // Assign the checksum to the second last element
    command[15] = checksum;
    //aa 0f 02 d1 02 00 00 00 5e 66 d5 00 00 01 0a 00 38 dd
    sentreqcommand.addAll([
      0xAA,
      0x0F,
      0x02,
      0xD1,
      0x02,
      0x00,
      0x00,
      0x00,
      0x5E,
      0x66,
      command[10]
    ]);
    // Convert to Uint8List and return
    return Uint8List.fromList(command);
  }
}
