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
  int cashValueAmount = 0;
  int RemainingtoDispenseG = 9999;
  int totalUtdQr = 0;
  int QrDispenseCounterTel = 0;
  int UtdCash = 0;
  int CashCounter = 0;
  int cashValue_ = 0;
  int CASHDispenseCounter_ = 0;
  bool isDispenseCash = false;
  String hexString = '';

  int control = 0; // 0/1
  int TotalCash_ = 0;
  int TotalToken_ = 0;

  bool isPrevFlag = true;
  bool isAllowed = false;

  int TotalCashPrev_ = 0;
  int TotalTokenPrev_ = 0;
  int SoldOutRemainingCoin = 0;

  String HexGetStatusIN = "";
  String HexGetStatusOUT = "";

  String HexGetStatusINPrev = "";
  String HexGetStatusOUTPrev = "";

  String HexQrRequestDispenseIN = "";
  String HexQrRequestDispenseOUT = "";

  String HexQrDispenseIN = "";
  String HexQrDispenseOUT = "";

  String HexQrDispenseTelemetryIN = "";
  String HexQrDispenseTelemetryOUT = "";

  String HexSoldOutIN = "";
  String HexSoldOutOUT = "";

  bool IsPCBAlive = true;
  int RetriesPCBAlive = 0;

  int MainRetries = 0;
  bool IsGetStatusReceive = false;

  List<String> _logsDispensing = [];
  String AlllogsDispensing = "";
  List<int> sentreqcommand = [];

  List<String> _logsGetStatus = [];
  String AlllogsGetStatus = "";

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

  final _rand = Random();

  int generateRandomByte() {
    int value;
    do {
      value = _rand.nextInt(256); // 0–255
    } while (value == 0xAA || value == 0xDD);
    return value;
  }

  final _rand = Random();

  int generateRandomByte() {
    int value;
    do {
      value = _rand.nextInt(256); // 0–255
    } while (value == 0xAA || value == 0xDD);
    return value;
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

  void _addLog(String message) {
    _logsDispensing.add(message);
    if (_logsDispensing.length > 200) {
      _logsDispensing.removeAt(0); // keep last 200 lines (avoid memory bloat)
    }
  }

  void _addGetStatusLog(String message) {
    _logsGetStatus.add(message);
    if (_logsGetStatus.length > 200) {
      _logsGetStatus.removeAt(0); // keep last 200 lines (avoid memory bloat)
    }
  }

  void ResetLogDispensing() {
    AlllogsDispensing = "";
    _logsDispensing = [];
    _logsGetStatus = [];
    TotalCashPrev_ = 0;
    TotalTokenPrev_ = 0;
    HexGetStatusIN = "";
    HexGetStatusOUT = "";
    HexGetStatusINPrev = "";
    HexGetStatusOUTPrev = "";
    HexQrRequestDispenseIN = "";
    HexQrRequestDispenseOUT = "";
    HexQrDispenseIN = "";
    HexQrDispenseOUT = "";
    HexQrDispenseTelemetryIN = "";
    HexQrDispenseTelemetryOUT = "";
    HexSoldOutIN = "";
    HexSoldOutOUT = "";
  }

  void CheckPCBAlive() async {
    const int maxRetries = 30; // Maximum retries
    print('Start Checking Connection port');

    // Retry until isCompleteDispense becomes true or retries exceed maxRetries
    while (RetriesPCBAlive < maxRetries) {
      await Future.delayed(Duration(milliseconds: 1000));
      print('Counting : ${RetriesPCBAlive}');
      RetriesPCBAlive++;
    }

    IsPCBAlive = false;
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

  Future<bool> CheckUTD() async {
    return true;
  }

  // Send data to the serial port
  Future<void> sendData(Uint8List data) async {
    print('GET STATUS');
    Uint8List newcommand =
        Uint8List.fromList([0xAA, 0x04, 0x01, 0xD1, 0x04, 0xD0, 0xDD]);

    print(
        'OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    HexGetStatusOUTPrev =
        newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
    _addGetStatusLog("GET STATUS\n"
        "OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}\n"
        "");
    await Future.delayed(Duration(milliseconds: 250));
    //retrial
    const int maxRetries = 2; // Maximum retries
    int retrygetstatus = 0; // Maximum retries
    while (retrygetstatus < maxRetries) {
      if (IsGetStatusReceive) {
        await Future.delayed(Duration(milliseconds: 250));
        print('QR Request Dispense');
        await _port!.write(data);
        print(
            'OUT >>>: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

        HexQrRequestDispenseOUT =
            data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      }

      await _port!.write(newcommand);

      _addGetStatusLog("Retry :${retrygetstatus}\n"
          "OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}"
          "\n\n");
      await Future.delayed(Duration(milliseconds: 2500));
      retrygetstatus++;
    }

    if (retrygetstatus == 2) {
      AlllogsGetStatus = _logsGetStatus.join("\n");
      MainRetries = 30;
    }
  }

  List<int> _buffer = [];
  Timer? _timeoutTimer;

  Future<void> _handleIncomingData(Uint8List data) async {
    _buffer.addAll(data);

    // Reset timeout each time new data is received
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(Duration(seconds: 1), () {
      // print('Timeout! Clearing buffer.');
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

        // print(
        //     '✅ Complete Message Received: ${message.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
        // print('✅ Passed!');
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

    Uint8List ReqResponseNotAccept = Uint8List.fromList([
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
      0x00,
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

    Uint8List pcToPollingPCBres = Uint8List.fromList([
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
    Uint8List pcToPollingPCBresaccept =
        Uint8List.fromList([0xAA, 0x05, 0x02, 0x01, 0x85, 0x17, 0x94, 0xDD]);

    // print(
    //     'Processing message: ${message.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    await Future.delayed(
        Duration(milliseconds: 10)); // Simulate async processing
    final Uint8List data;

    data = message;
    //Polling
    LogStorage.logMessage('Data >>> ${data}');

    if (_listEquals(data, aftersoldout)) {
      await _port!.write(aftersoldoutres);
      await Future.delayed(Duration(milliseconds: 200));
      await _port!.write(pcToPollingPCBres);
      print(
          'OUT >>>: ${aftersoldoutres.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('');
    } else if (_listEquals(data, pollingPCB)) {
      print('Polling (PCB TO PC)');
      // Send the reply message
      RetriesPCBAlive = 0;
      print(
          'IN <<<>: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      await _port!.write(pcToPollingPCB);
      print(
          'OUT >>>: ${pcToPollingPCB.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      await Future.delayed(Duration(milliseconds: 200));
      await _port!.write(pcToPollingPCBres);
      print('Polling (PC TO PCB)');
      print(
          'OUT >>>: ${pcToPollingPCBres.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      //
      // await Future.delayed(Duration(milliseconds: 200));
      // await _port!.write(newcommand);

      // print(
      //     'OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
    //GET STATUS
    else if (data.isNotEmpty &&
        data[0] == 0xAA &&
        data[1] == 0x0C &&
        data[2] == 0x02 &&
        data[3] == 0xD1 &&
        data[4] == 0x04) {
      int totalCashUTD = data[5] |
          (data[6] << 8) |
          (data[7] << 16) |
          (data[8] << 24); // 6th-9th byte

      int tokenDispenseUTD = data[9] |
          (data[10] << 8) |
          (data[11] << 16) |
          (data[12] << 24); // 6th-9th byte

      TotalCash_ = totalCashUTD;
      TotalToken_ = tokenDispenseUTD;
      IsGetStatusReceive = true;

      if (isPrevFlag) {
        HexGetStatusINPrev =
            data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
        TotalCashPrev_ = totalCashUTD;
        TotalTokenPrev_ = tokenDispenseUTD;
      }
      control = 1;
      print(
          'IN <<<: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      HexGetStatusIN =
          data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      _addGetStatusLog("GET STATUS\n"
          "IN <<<: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}\n"
          "Total Cash UTD: $totalCashUTD\n"
          "Token Dispense UTD: $tokenDispenseUTD\n\n\n");

      await Future.delayed(Duration(milliseconds: 200));
      control = await 0;
      print("Total Cash UTD: $totalCashUTD");
      print("Token Dispense UTD: $tokenDispenseUTD");
      print('');
      print('');
      print('');
    }
    //status1
    else if (_listEquals(data, status1Request)) {
      // print('Expected response received (status 1). Sending reply...');

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
      // print('Expected response received (status 2). Sending reply...');

      // Send the reply message
      _port!.write(statusResponse);
      LogStorage.logMessage('Android OUT >>>: ${statusResponse.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    //Request qr
    else if (_listEquals(data, ReqResponse)) {
      isAllowed = true;
      print(
          'IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
      HexQrRequestDispenseIN =
          data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      print('Allow dispense: true');
      // Send the reply message
      print('');
      print('');
      print('');

      final discom = await createDispenseCommand();

      _port!.write(discom);

      HexQrDispenseOUT =
          discom.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      print(
          'OUT >>>: ${discom.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    //Request qr not accepted
    else if (_listEquals(data, ReqResponseNotAccept)) {
      isAllowed = false;
      HexQrRequestDispenseIN =
          data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      print(
          'IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data

      print('Allow dispense: false');
    } else if (data.isNotEmpty &&
        data[0] == 0xAA &&
        data[1] == 0x0F &&
        data[2] == 0x02 &&
        data[3] == 0xD1 &&
        data[4] == 0x02) {
      print(
          'IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
      if (data[13] == 0x01) {
        isAllowed = true;
        print('Allow dispense : true');
        HexQrDispenseIN =
            data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      } else {
        isAllowed = false;
        print('Allow dispense : false');
        HexQrDispenseIN =
            data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      }
      print('');
      print('');
      print('');
    } else if (data.length >= 18 &&
        data[0] == 0xAA &&
        data[1] == 0x0F &&
        data[2] == 0x02 &&
        data[3] == 0x14 &&
        data[4] == 0x1C &&
        data[5] == 0x03) {
      // print('Expected response received (soldout). Sending reply...');
      isSoldOut = true;
      isDispensing = false;
      myHomePageKey.currentState?.setSoldout();

      HexSoldOutIN =
          data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      if (isQr == false) {
        LogStorage.logMessage('isQR = $isQr');
        myHomePageKey.currentState?.InsertCash('Failed', 0, 0, 0, 0);
      }
      // Send the reply message
      _port!.write(resSoldOut2);

      HexSoldOutOUT =
          resSoldOut2.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      print(
          'OUT >>>: ${resSoldOut2.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    // Dispensing Check if the response starts with the valid start byte
    else if (data.isNotEmpty &&
        data[0] == 0xAA &&
        data[1] == 0x0C &&
        data[2] == 0x02 &&
        data[3] == 0xD1 &&
        data[4] == 0x20) {
      print("Dispensing.");
      print(
          'IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
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

        _addLog("Dispensing.\n\n"
            " IN <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}\n"
            "OUT >>>: ${dispensing.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}\n"
            "Cash Value: $cashValue\n"
            "Total Needed: $totalNeeded\n"
            "Remaining: $RemainingtoDispense\n"
            "\n\n");

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

      print("");
      print("");
      print("");
    }
    //UTD QR
    else if (data.isNotEmpty &&
        data[0] == 0xAA &&
        data[1] == 0x13 &&
        data[2] == 0x02 &&
        data[3] == 0xD1 &&
        data[4] == 0x05) {
      print("QR Dispense Telemetry");
      print(
          'IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
      isDispensing = false;
      // Check if the response length is correct
      HexQrDispenseTelemetryIN =
          data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

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

      print(
          'OUT >>>: ${qrteldis.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      HexQrDispenseTelemetryOUT =
          qrteldis.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      totalUtdQr = UTDQRDispenseCounter;
      QrDispenseCounterTel = QRDispenseCounter;

      if (QRDispenseCounter > 0) {
        LogStorage.logMessage('QRDispenseCounter >>> ${QRDispenseCounter}');
        isCompleteDispense = true;
      }

      print("");
      print("");
      print("");
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
        data[5] == sentreqcommand[5] &&
        data[6] == sentreqcommand[6] &&
        data[7] == sentreqcommand[7] &&
        data[8] == sentreqcommand[8] &&
        data[9] == sentreqcommand[9] &&
        data[10] == sentreqcommand[10]) {
      if (data[13] == 0x01) {

        LogStorage.logMessage('Mother board receive signal and dispense');
      } else {
        LogStorage.logMessage('Mother board not able receive signal and dispense');
      }
      print("Accepted request receive ");
    } else if (_listEquals(data, pcToPollingPCBresaccept)) {
      print(
          'IN <<<: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('');
      print('');
    } else {
      // print("Unknown Comm detected");
      //   unknownReply[3] = data[3];
      //   _port!.write(unknownReply);
      print(
          'IN unknown <<<: ${unknownReply.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
  }

  Future<void> listenForResponse() async {
    // SerialPortReader reader = SerialPortReader(port);
    // Stream<Uint8List> responseStream = reader.stream;
    LogStorage.logMessage('Start Listening');
    // Define the expected request and the response

    _port!.inputStream?.listen((Uint8List data) async {
      // print(
      //     'IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
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
    print('Sending RequestDispense20');

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
  Future<Result> main(int command, int cashValue) async {
    isPrevFlag = true;
    isQr = true;
    isDispensing = false;
    IsGetStatusReceive = false;

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

    // Assign the random byte
    // requestDispense[5] = generateRandomByte();
    // requestDispense[6] = generateRandomByte();
    // requestDispense[7] = generateRandomByte();
    // requestDispense[8] = generateRandomByte();
    // requestDispense[9] = generateRandomByte();
    // requestDispense[10] = generateRandomByte();

    int checksum = requestDispense
        .sublist(
            1,
            requestDispense.length -
                2) // skip header & last two (checksum + footer)
        .reduce((a, b) => a ^ b);

    // Assign the checksum to the second last element
    requestDispense[11] = checksum;
    // Send data based on command
    if (command > 0) {
      dispenseAmount = command;
      cashValueAmount = cashValue;
      await sendData(requestDispense);
    } else {

      LogStorage.logMessage('Unknown command');
    }

    const int maxRetries = 30; // Maximum retries

    // Retry until isCompleteDispense becomes true or retries exceed maxRetries
    while (MainRetries < maxRetries) {
      if (isCompleteDispense) {
        // If isCompleteDispense becomes true, return 'Completed'
        isCompleteDispense = false; // Reset the flag for future operations
        isQr = false;
        isDispensing = false;
        IsGetStatusReceive = false;
        MainRetries = 0;

        print('GET STATUS');
        Uint8List newcommand =
            Uint8List.fromList([0xAA, 0x04, 0x01, 0xD1, 0x04, 0xD0, 0xDD]);

        print(
            'OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
        HexGetStatusOUT = newcommand
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(' ');

        isPrevFlag = false;

        await _port!.write(newcommand);
        await Future.delayed(Duration(milliseconds: 200));

        var logs = _logsDispensing;

        String allLogsDispensingTemp;
        if (logs.isEmpty) {
          allLogsDispensingTemp = "";
        } else if (logs.length == 1) {
          allLogsDispensingTemp = logs.first;
        } else {
          allLogsDispensingTemp = [logs.first, logs.last].join("\n");
        }
        AlllogsDispensing = allLogsDispensingTemp;

        // +10
        //      100             110
        //      100             105
        //      100             100
        if (TotalToken_ > TotalTokenPrev_) {
          print('');
          int dispensedtoken = TotalToken_ - TotalTokenPrev_;
          SoldOutRemainingCoin = dispenseAmount - dispensedtoken;
          return Result(success: true, message: '0', utdQr: totalUtdQr);

          // if (dispenseAmount == dispensedtoken) {
          //   // exactly amount of token dispense based on user request
          //   return Result(success: true, message: '0', utdQr: totalUtdQr);
          // } else {
          //   //assume soldout, partial dispense, after complete dispense utd is updated(increased)
          //   // but not all
          //   return Result(success: false, message: '1', utdQr: 0);
          // }
        } else {
          print('');
          print('');
          // print('Total Token: ${TotalToken_}');
          // print('Previous Total Token: ${TotalTokenPrev_}');
          return Result(success: false, message: '2', utdQr: totalUtdQr);
        }
      }

      if (isSoldOut) {
        isSoldOut = false;
        isCompleteDispense = false;
        isQr = false;
        isDispensing = false;
        IsGetStatusReceive = false;
        MainRetries = 0;
        // RemainingtoDispenseG = 9999;

        print('GET STATUS');
        Uint8List newcommand =
            Uint8List.fromList([0xAA, 0x04, 0x01, 0xD1, 0x04, 0xD0, 0xDD]);

        print(
            'OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
        HexGetStatusOUT = newcommand
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(' ');

        isPrevFlag = false;
        await _port!.write(newcommand);
        await Future.delayed(Duration(milliseconds: 200));

        var logs = _logsDispensing;

        String allLogsDispensingTemp;
        if (logs.isEmpty) {
          allLogsDispensingTemp = "";
        } else if (logs.length == 1) {
          allLogsDispensingTemp = logs.first;
        } else {
          allLogsDispensingTemp = [logs.first, logs.last].join("\n");
        }
        AlllogsDispensing = allLogsDispensingTemp;
        // let say, rm 10 = 10 token
        //      5             100          105
        int dispensedtoken = TotalToken_ - TotalTokenPrev_;
        //      5                 10               5
        SoldOutRemainingCoin = dispenseAmount - dispensedtoken;

        return Result(success: false, message: '1', utdQr: 0);
      }

      // Wait for the specified interval before retrying
      await Future.delayed(Duration(milliseconds: 1000));
      if (isDispensing) {
        MainRetries = 0;
      } else {
        MainRetries++;
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

    // Assign the random byte
    command[5] = generateRandomByte();
    command[6] = generateRandomByte();
    command[7] = generateRandomByte();
    command[8] = generateRandomByte();
    command[9] = generateRandomByte();
    command[10] = generateRandomByte();

    command[13] = dispenseAmount & 0xFF; // Extract lower 8 bits
    command[14] = (dispenseAmount >> 8) & 0xFF; // Extract upper 8 bits

    int scaledAmount = cashValueAmount * 100;

    command[11] = scaledAmount & 0xFF; // lower 8 bits
    command[12] = (scaledAmount >> 8) & 0xFF; // upper 8 bits

    LogStorage.logMessage(' Dispense amount >>> $dispenseAmount');
    // Recalculate checksum using XOR from index 1 to index 14 (excluding the checksum byte)
    int checksum = command
        .sublist(
            1, command.length - 2) // skip header & last two (checksum + footer)
        .reduce((a, b) => a ^ b);

    // Assign the checksum to the second last element
    command[15] = checksum;
    //aa 0f 02 d1 02 00 00 00 5e 66 d5 00 00 01 0a 00 38 dd
    sentreqcommand.addAll([
      0xAA,
      0x0F,
      0x02,
      0xD1,
      0x02,
      command[5],
      command[6],
      command[7],
      command[8],
      command[9],
      command[10]
    ]);
    // Convert to Uint8List and return
    print('QR dispense amount ${dispenseAmount}');
    return Uint8List.fromList(command);
  }
}
