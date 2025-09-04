import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

  //init
  Communication(UsbDevice? testPort) {
    try {
      findAndOpenDevice(testPort);

      print('isconnected $isConnected');

      Future.delayed(Duration(seconds: 3), () {
        setupCommunication();
        print('isconnected2 $isConnected');
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
      print('Serial communication configured!');
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

  Future<bool> findAndOpenDevice(UsbDevice? init) async {
    try {
      // List all devices connected via USB
      List<UsbDevice> devices = await UsbSerial.listDevices();
      print('Devices : $devices');
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
        return false;
      }
    } catch (e) {
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
          print('Device opened successfully!');
          return true;
        } else {
          print('Failed to open the device.');
          return false;
        }
      } else {
        print('Device not found');
        return false;
      }
    } catch (e) {
      throw Exception(e);
    }
  }

  // Connect to the serial port (only once)

  Future<bool> CheckUTD() async {
    return true;
  }

  // Send data to the serial port

  Future<void> sendData(Uint8List data) async {
    // STEP 1 Check PCB Alive Status:
    print('GET STATUS');
    Uint8List newcommand = Uint8List.fromList([0xAA, 0x04, 0x01, 0xD1, 0x04, 0xD0, 0xDD]);
    await _port!.write(newcommand);
    print('OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    HexGetStatusOUTPrev = newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

    _addGetStatusLog("GET STATUS\n"
        "OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}\n"
        "");
    // STEP 1 Check PCB Alive Status END

    await Future.delayed(Duration(milliseconds: 500));

    // Step 2 START Android to PCB - QR Dispense :
    int retryGetStatus = 0;
    const int maxRetries = 2; // Maximum retries
    bool isSuccess = false;

    // Retry START for Step 1 if the Status is failed to receive
    while (retryGetStatus < maxRetries) {
      // Step 2 LOGIC FLOW if status Received -- Android to PCB
      if (IsGetStatusReceive) {
        await Future.delayed(Duration(milliseconds: 250));
        print('QR Request Dispense');
        await _port!.write(data);
        print('OUT >>>: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

        HexQrRequestDispenseOUT = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

        IsGetStatusReceive = false;
        retryGetStatus = maxRetries; // if the receive response from pcb to android no need retry
        isSuccess = true;
        // Step 2 LOGIC FLOW if status Received -- Android to PCB END
      }

      _addGetStatusLog("Retry :${retryGetStatus}\n"
          "OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}"
          "\n\n");
      await _port!.write(newcommand);
      await Future.delayed(Duration(milliseconds: 500));
      retryGetStatus++;
    }
    // Retry END for Step 1 if the Status is failed to receive
    if (retryGetStatus == 2) {
      if (isSuccess) {
        AlllogsGetStatus = _logsGetStatus.join("\n");
      } else {
        AlllogsGetStatus = _logsGetStatus.join("\n");
        MainRetries = 30;
      }
    }
    // Step 2 END Android to PCB - QR Dispense
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
        print('❌ Invalid start byte: ${_buffer[0].toRadixString(16)}. Discarding...');
        _buffer.removeAt(0);
        await Future.delayed(Duration(milliseconds: 10)); // Allow async processing
      }

      if (_buffer.length < 3) {
        return; // Not enough data to determine length
      }

      int length = _buffer[1];
      int expectedLength = length + 3; // Total message size including header and end byte

      if (_buffer.length >= expectedLength) {
        // We received enough bytes, check the end byte
        if (_buffer[expectedLength - 1] != 0xDD) {
          print('❌ Error: Invalid end byte, discarding entire buffer.');
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
        print('❌ Error: Found end byte `0xDD` but length is invalid. Clearing buffer.');
        _buffer.clear();
        return;
      } else {
        await Future.delayed(Duration(milliseconds: 150)); // Allow time for next data chunk
        return; // Wait for more data
      }
    }
  }

  // Helper Function Listening Response FROM PCB
  Future<void> _processMessage(Uint8List data) async {
    Uint8List pollingPCB = Uint8List.fromList([0xAA, 0x03, 0x02, 0x10, 0x11, 0xDD]);
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

    Uint8List status1Request = Uint8List.fromList([0xAA, 0x0F, 0x02, 0x14, 0x1A, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xDD]);

    Uint8List status2Request = Uint8List.fromList([0xAA, 0x0F, 0x02, 0x14, 0x1B, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xDD]);

    Uint8List statusResponse = Uint8List.fromList([0xAA, 0x03, 0x01, 0x14, 0x16, 0xDD]);

    Uint8List ReqResponse = Uint8List.fromList([0xAA, 0x0B, 0x02, 0xD1, 0x01, 0x00, 0x00, 0x00, 0x35, 0xDE, 0xE4, 0x01, 0xD7, 0xDD]);

    Uint8List ReqResponseNotAccept = Uint8List.fromList([0xAA, 0x0B, 0x02, 0xD1, 0x01, 0x00, 0x00, 0x00, 0x35, 0xDE, 0xE4, 0x00, 0xD7, 0xDD]);

    //failed soldOut

    Uint8List resSoldOut = Uint8List.fromList([0xAA, 0xF0, 0x02, 0x14, 0x1C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x06, 0xDD]);

// Second sequence
    Uint8List resSoldOut2 = Uint8List.fromList([0xAA, 0x03, 0x01, 0x14, 0x16, 0xDD]);

    Uint8List unknownReply = Uint8List.fromList([0xAA, 0x03, 0x01, 0x00, 0x02, 0xDD]);

    Uint8List dispensing = Uint8List.fromList([0xAA, 0x03, 0x01, 0xD1, 0x20, 0xF3, 0xDD]);

    Uint8List cashteldis = Uint8List.fromList([0xAA, 0x04, 0x01, 0xD1, 0x06, 0xD2, 0xDD]);

    Uint8List qrteldis = Uint8List.fromList([0xAA, 0x04, 0x02, 0xD1, 0x05, 0xD1, 0xDD]);
    //aa 03 02 19 18 dd
    Uint8List aftersoldout = Uint8List.fromList([0xAA, 0x03, 0x02, 0x19, 0x18, 0xDD]);
    Uint8List aftersoldoutres = Uint8List.fromList([0xAA, 0x05, 0x01, 0x19, 0x00, 0x00, 0x1D, 0xDD]);
    Uint8List qrdisres = Uint8List.fromList([0xAA, 0x0F, 0x02, 0xD1, 0x02, 0x00, 0x00, 0x00, 0x5E, 0x66, 0x48, 0x00, 0x00]);

    Uint8List pcToPollingPCBres = Uint8List.fromList([0xAA, 0x0B, 0x01, 0x01, 0x41, 0x30, 0x30, 0x30, 0x30, 0x32, 0x33, 0x36, 0x7D, 0xDD]);
    Uint8List pcToPollingPCBresaccept = Uint8List.fromList([0xAA, 0x05, 0x02, 0x01, 0x85, 0x17, 0x94, 0xDD]);

    await Future.delayed(Duration(milliseconds: 10)); // Simulate async processing

    //Stage Compare the param with the List of Byte Provided by Mr Leong

    // Case 1 - after restart if sold out will go in this case condition
    if (_listEquals(data, aftersoldout)) {
      await _port!.write(aftersoldoutres);
      await Future.delayed(Duration(milliseconds: 200));
      await _port!.write(pcToPollingPCBres);
      print('OUT >>>: ${aftersoldoutres.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('');
      // Case 1 - after restart if sold out will go in this case condition END

      // Case 2 - Check PCB to keep alive 2.0
    } else if (_listEquals(data, pollingPCB)) {
      print('Polling (PCB TO PC)');
      // Send the reply message
      RetriesPCBAlive = 0;
      print('IN <<<>: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      await _port!.write(pcToPollingPCB);
      print('OUT >>>: ${pcToPollingPCB.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      await Future.delayed(Duration(milliseconds: 200));
      await _port!.write(pcToPollingPCBres);
      print('Polling (PC TO PCB)');
      print('OUT >>>: ${pcToPollingPCBres.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
    // Case 2 - Check PCB to keep alive 2.0 END
    //Case 3 - Get Status for Step 1 START
    else if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x0C && data[2] == 0x02 && data[3] == 0xD1 && data[4] == 0x04) {
      int totalCashUTD = data[5] | (data[6] << 8) | (data[7] << 16) | (data[8] << 24); // 6th-9th byte

      int tokenDispenseUTD = data[9] | (data[10] << 8) | (data[11] << 16) | (data[12] << 24); // 6th-9th byte

      TotalCash_ = totalCashUTD;
      TotalToken_ = tokenDispenseUTD;
      IsGetStatusReceive = true;

      if (isPrevFlag) {
        HexGetStatusINPrev = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
        TotalCashPrev_ = totalCashUTD;
        TotalTokenPrev_ = tokenDispenseUTD;
      }
      control = 1;
      print('IN <<<: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      HexGetStatusIN = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

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
    //Case 3 - Get Status for Step 1 END

    else if (_listEquals(data, status1Request)) {
      // print('Expected response received (status 1). Sending reply...');

      if (isQr == false && isDispenseCash == false) {
        myHomePageKey.currentState?.setLatestFailedTrx();
      }
      // Send the reply message
      _port!.write(statusResponse);
      print('OUT >>>: ${statusResponse.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
    //status2
    //status1
    else if (_listEquals(data, status2Request)) {
      // print('Expected response received (status 2). Sending reply...');

      // Send the reply message
      _port!.write(statusResponse);
      print('OUT >>>: ${statusResponse.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    //Request qr
    else if (_listEquals(data, ReqResponse)) {
      isAllowed = true;
      print('IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
      HexQrRequestDispenseIN = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      print('Allow dispense: true');
      // Send the reply message
      print('');
      print('');
      print('');

      // Step 3 Android to PCB -- Step asking dispenser dispense token out (allowed) START
      final discom = await createDispenseCommand();
      _port!.write(discom);
      // Step 3 Android to PCB -- Step asking dispenser dispense token out (allowed) END
      HexQrDispenseOUT = discom.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      print('OUT >>>: ${discom.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    //Request qr not accepted
    else if (_listEquals(data, ReqResponseNotAccept)) {
      isAllowed = false;
      HexQrRequestDispenseIN = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      print('IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data

      print('Allow dispense: false');
    } else if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x0F && data[2] == 0x02 && data[3] == 0xD1 && data[4] == 0x02) {
      print('IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
      if (data[13] == 0x01) {
        isAllowed = true;
        print('Allow dispense : true');
        HexQrDispenseIN = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      } else {
        isAllowed = false;
        print('Allow dispense : false');
        HexQrDispenseIN = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      }
      print('');
      print('');
      print('');
    } else if (data.length >= 18 && data[0] == 0xAA && data[1] == 0x0F && data[2] == 0x02 && data[3] == 0x14 && data[4] == 0x1C && data[5] == 0x03) {
      // print('Expected response received (soldout). Sending reply...');
      isSoldOut = true;
      isDispensing = false;
      myHomePageKey.currentState?.setSoldout();

      HexSoldOutIN = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      if (isQr == false) {
        myHomePageKey.currentState?.InsertCash('Failed', 0, 0, 0, 0);
      }
      // Send the reply message
      _port!.write(resSoldOut2);

      HexSoldOutOUT = resSoldOut2.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      print('OUT >>>: ${resSoldOut2.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    // Step 4 -- PCB dispense token depend on the Amount of user payment (for each token dispense) START
    else if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x0C && data[2] == 0x02 && data[3] == 0xD1 && data[4] == 0x20) {
      print("Dispensing.");
      print('IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
      isDispensing = true;

      // Check if the response length is correct
      if (data.length == 15) {
        // Decode dynamic data
        int cashValue = data[5] | (data[6] << 8) | (data[7] << 16) | (data[8] << 24); // 6th-9th byte

        int totalNeeded = data[9] | (data[10] << 8); // 10th-11th byte

        int RemainingtoDispense = data[11] | (data[12] << 8); // 12th-13th byte

        // Print decoded values
        print("Cash Value: $cashValue");
        print("Total Needed to Dispense: $totalNeeded");
        print("Remaining to Dispense: $RemainingtoDispense");

        RemainingtoDispenseG = RemainingtoDispense;
        // Send the reply message
        _port!.write(dispensing);
        print('OUT >>>: ${dispensing.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
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
          print('cash dispensing true');
        }

        myHomePageKey.currentState?.remainingToDispense(RemainingtoDispense);
      } else {
        print("Invalid response length.");
      }

      print("");
      print("");
      print("");
    }
    // Step 4 -- PCB dispense token depend on the Amount of user payment (for each token dispense) END

    // STEP 5 -- After complete dispense PCB to Android response QrUTD START
    else if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x13 && data[2] == 0x02 && data[3] == 0xD1 && data[4] == 0x05) {
      print("QR Dispense Telemetry");
      print('IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
      isDispensing = false;
      // Check if the response length is correct
      HexQrDispenseTelemetryIN = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      // Decode dynamic data
      int QRDispenseCounter = data[14] | (data[15] << 8);
      int UTDQRDispenseCounter = data[16] | (data[17] << 8) | (data[18] << 16) | (data[19] << 24); // Correct byte order for little-endian

      print("Qr Dispense Counter: $QRDispenseCounter");
      print("UTD qr Dispense Counter: $UTDQRDispenseCounter");

      // Send the reply message
      _port!.write(qrteldis);

      print('OUT >>>: ${qrteldis.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      HexQrDispenseTelemetryOUT = qrteldis.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      totalUtdQr = UTDQRDispenseCounter;
      QrDispenseCounterTel = QRDispenseCounter;

      if (QRDispenseCounter > 0) {
        isCompleteDispense = true;
      }

      print("");
      print("");
      print("");
    }
    // STEP 5 -- After complete dispense PCB to Android response QrUTD END
    // STEP 5.5 (Pay with Cash)-- After complete dispense PCB to Android response CashUTD START
    else if (data.isNotEmpty && data[0] == 0xAA && data[1] == 0x19 && data[2] == 0x02 && data[3] == 0xD1 && data[4] == 0x06) {
      hexString = data.map((byte) => '0x${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      print("Dispensed, Cash UTD here.");
      isDispenseCash = true;
      isDispensing = false;
      // Check if the response length is correct
      if (data.length == 28) {
        // Decode dynamic data
        int CASHDispenseCounter = data[11] | (data[12] << 8);

        int UTDCASHDispenseCounter = data[13] | (data[14] << 8) | (data[15] << 16) | (data[16] << 24); // 10th-11th byte

        int CASHCounter = data[18] | (data[19] << 8) | (data[20] << 16) | (data[21] << 24); // 10th-11th byte

        int UTDCASHCounter = data[22] | (data[23] << 8) | (data[24] << 16) | (data[25] << 24); // 10th-11th byte

        // Print decoded values
        print("Cash Dispense Counter: $CASHDispenseCounter");
        print("UTD Cash Dispense Counter: $UTDCASHDispenseCounter");
        print("Cash Counter: $CASHCounter");
        print("UTD Cash Counter: $UTDCASHCounter");

        // Send the reply message
        _port!.write(cashteldis);
        print('OUT >>>: ${cashteldis.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
        if (CASHDispenseCounter > 0 && UTDCASHDispenseCounter > 0) {
          myHomePageKey.currentState?.InsertCash('Completed', UTDCASHDispenseCounter, CASHCounter, CASHDispenseCounter, UTDCASHCounter);
          isCompleteDispense = true;

          print('cash dispense complete true');
          CASHDispenseCounter_ = CASHDispenseCounter;
          CashCounter = CASHCounter;
          UtdCash = UTDCASHDispenseCounter;
        }
      }
      // STEP 5.5 (Pay with Cash)-- After complete dispense PCB to Android response CashUTD END
      else {
        print("Invalid response length.");
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
        print("Mother board receive signal and dispense");
      } else {
        print("Mother board not able receive signal and dispense");
      }
      print("Accepted request receive ");
    } else if (_listEquals(data, pcToPollingPCBresaccept)) {
      print('IN <<<: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('');
      print('');
    } else {
      print('IN unknown <<<: ${unknownReply.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
    //Stage Compare the param with the List of Byte Provided by Mr Leong END
  }

  Future<void> listenForResponse() async {
    // SerialPortReader reader = SerialPortReader(port);
    // Stream<Uint8List> responseStream = reader.stream;
    print('Start Listening...');
    // Define the expected request and the response

    _port!.inputStream?.listen((Uint8List data) async {
      // print(
      //     'IN: <<< ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}'); // Print hex data
      _handleIncomingData(data);
    });
  }

  Future<Result> inject(int amount) async {
    isQr = true;
    Uint8List requestDispense = Uint8List.fromList([0xAA, 0x0A, 0x01, 0xD1, 0x01, 0x00, 0x00, 0x00, 0x35, 0xDE, 0xE4, 0xD4, 0xDD]);

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

        return Result(success: true, message: '0', utdQr: totalUtdQr);
      }

      if (isSoldOut) {
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
    return Result(success: false, message: '2', utdQr: 0);
  }

  // Main function to control the flow of communication / the whole Halolo program
  Future<Result> main(int command, int cashValue) async {
    isPrevFlag = true;
    isQr = true;
    isDispensing = false;
    IsGetStatusReceive = false;

    Uint8List requestDispense = Uint8List.fromList([0xAA, 0x0A, 0x01, 0xD1, 0x01, 0x00, 0x00, 0x00, 0x35, 0xDE, 0xE4, 0xD4, 0xDD]);

    int checksum = requestDispense
        .sublist(1, requestDispense.length - 2) // skip header & last two (checksum + footer)
        .reduce((a, b) => a ^ b);

    // Assign the checksum to the second last element
    requestDispense[11] = checksum;
    // Send data based on command
    if (command > 0) {
      dispenseAmount = command;
      cashValueAmount = cashValue;
      await sendData(requestDispense);
    } else {
      print('Unknown command');
    }

    // Step 6 After STEP 5 complete dispense validate the TokenDispenseUTD from the response of the PCB START
    const int maxRetries = 30;
    // Retry until isCompleteDispense becomes true or retries exceed maxRetries
    while (MainRetries < maxRetries) {
      if (isCompleteDispense) {
        // If isCompleteDispense (return in Step 5) becomes true, return 'Completed'
        isCompleteDispense = false; // Reset the flag for future operations
        isQr = false;
        isDispensing = false;
        IsGetStatusReceive = false;
        MainRetries = 0;

        print('GET STATUS');
        Uint8List newcommand = Uint8List.fromList([0xAA, 0x04, 0x01, 0xD1, 0x04, 0xD0, 0xDD]);

        print('OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
        HexGetStatusOUT = newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

        isPrevFlag = false;

        // The code checking the TokenUTD too fast so retry 3 times to double confirm PCB TokenUTD got update else return message = 2 for refund
        for (int i = 0; i < 3; i++) {
          await _port!.write(newcommand);
          await Future.delayed(Duration(milliseconds: 250));

          if (TotalToken_ > TotalTokenPrev_) {
            print('prev : $TotalTokenPrev_');
            print('current : $TotalToken_');
            print('CONDITION MEET');
            break;
          }
        }

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

        if (TotalToken_ > TotalTokenPrev_) {
          print('');
          int dispensedtoken = TotalToken_ - TotalTokenPrev_;
          SoldOutRemainingCoin = dispenseAmount - dispensedtoken;
          return Result(success: true, message: '0', utdQr: totalUtdQr);
        } else {
          print('');
          print('');
          print('prev : $TotalTokenPrev_');
          print('current : $TotalToken_');

          return Result(success: false, message: '2', utdQr: totalUtdQr); // 2 mean time out with refund
        }
      }
      // Step 4.5 During Step 4 Dispensing if no more token will return this status boolean START
      if (isSoldOut) {
        isSoldOut = false;
        isCompleteDispense = false;
        isQr = false;
        isDispensing = false;
        IsGetStatusReceive = false;
        MainRetries = 0;

        print('GET STATUS');
        Uint8List newcommand = Uint8List.fromList([0xAA, 0x04, 0x01, 0xD1, 0x04, 0xD0, 0xDD]);

        print('OUT >>>: ${newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
        HexGetStatusOUT = newcommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

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

        int dispensedtoken = TotalToken_ - TotalTokenPrev_;
        SoldOutRemainingCoin = dispenseAmount - dispensedtoken;

        return Result(success: false, message: '1', utdQr: 0);
      }
      // Step 4.5 During Step 4 Dispensing if no more token will return this status boolean END

      // Wait for the specified interval before retrying
      await Future.delayed(Duration(milliseconds: 1000));
      if (isDispensing) {
        MainRetries = 0;
      } else {
        MainRetries++;
      }
    }
    // Step 6 After STEP 5 complete dispense validate the TokenDispenseUTD from the response of the PCB START

    isQr = false;

    // If retries exceed maxRetries, return 'Failed'
    // message 3 = time out but no refund
    return Result(success: false, message: isDispensing ? '3' : '2', utdQr: 0);
  }

  // Step 3 Function -- help & reply generator
  Future<Uint8List> createDispenseCommand() async {
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
      0x6D,
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

    // Recalculate checksum using XOR from index 1 to index 14 (excluding the checksum byte)
    // skip header & last two (checksum + footer)
    int checksum = command.sublist(1, command.length - 2).reduce((a, b) => a ^ b);

    // Assign the checksum to the second last element
    command[15] = checksum;
    sentreqcommand.addAll([0xAA, 0x0F, 0x02, 0xD1, 0x02, command[5], command[6], command[7], command[8], command[9], command[10]]);
    // Convert to Uint8List and return
    print('QR dispense amount ${dispenseAmount}');
    return Uint8List.fromList(command);
  }
  // Step 3 Function END
}
