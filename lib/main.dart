import 'dart:async';
import 'dart:convert'; // For JSON encoding/decoding
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, MethodChannel, PlatformException, SystemNavigator, TextInputFormatter, rootBundle;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usb_serial/usb_serial.dart';

import 'utils//RSA.dart'; // Import the signature utility file
import 'utils/communication.dart';
import 'utils/mqtt_service.dart'; // Import the MQTT service class

const String appTag = "com.example.tbcc";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

final GlobalKey<_MyHomePageState> myHomePageKey = GlobalKey<_MyHomePageState>(); // Create the GlobalKey
bool isLoading = false; //qr
bool isGeneralLoading = false;
bool isLoadingboot = false;

String port = '';

class IntegerInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Allow only digits
    final newText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    return newValue.copyWith(text: newText, selection: TextSelection.collapsed(offset: newText.length));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const platform = MethodChannel('com.example.app/boot');

  // Initialize BootReceiver via MethodChannel
  static Future<void> initializeBootReceiver() async {
    try {
      await platform.invokeMethod('initializeBootReceiver');
    } on PlatformException catch (e) {
      print("Failed to initialize BootReceiver: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transpire Bytes Qr',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LoadingPage(), // Set the initial page to the loading page
    );
  }
}

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  _LoadingPageState createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  double _opacity = 0.0; // For controlling the fade-in animation
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 500), () {
      setState(() {
        _opacity = 1.0;
      });
    });
    _initializeApp(); // Call initialization logic
    MyApp.initializeBootReceiver();
  }

  // Simulate app initialization
  Future<void> _initializeApp() async {
    // Simulating a delay for tasks like API calls, authentication, etc.
    await Future.delayed(Duration(seconds: 3));

    // Navigate to the main page
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MyHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedOpacity(
              opacity: _opacity, // Changes from 0.0 to 1.0
              duration: Duration(seconds: 2), // Animation duration
              child: Image.asset(
                'assets/images/logo-tb.png', // Replace with your image path
                width: 600.0, // Adjust the size of the image
                height: 200.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key}) : super(key: myHomePageKey); // Pass the GlobalKey here

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class LoadingOverlay {
  static OverlayEntry? _overlayEntry;

  static void show(BuildContext context) {
    if (_overlayEntry != null) return; // Prevent multiple overlays

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _MyHomePageState extends State<MyHomePage> {
  String apiUrl = 'https://transpireqr-api.transpire.com.my/API/Exchange';
  late TextEditingController _controller; // Text editing controller
  final TransformationController _controllerzoom = TransformationController();
  String selectedAmount = ''; // Store the selected amount as state
  int selectedAmountCoin = 0; // Store the selected amount as state
  String? qrCodeImageUrl;
  String? refId = '';
  String? random = '';
  bool ReceivedPayment = false;
  bool CompletedDispense = false;
  bool FailedDispense = false;
  bool ClosingCall = false;
  bool isMachineFaulty = false;
  String Token = '';
  String Signature = '';
  String Errormsg = '';
  String ErrormsgConn = '';
  String ErrormsgInitConn = '';
  List<UsbDevice> myStringArray = [];
  String _backgroundImagePath = 'assets/images/bg.jpg';
  UsbDevice? selectedPort; // Declare it inside the method, ensuring it's not null
  bool isConnected = true;
  String UTDQR = '0';
  String qrCompanyname = '';
  String _savedText = ''; // Variable to store the saved text
  bool isDeviceFaulty = false;
  String injectAmountstr = '0.00';
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<Map<String, dynamic>> coinPriceList = [];
  List<Map<String, dynamic>> coinPriceListBonus = [];
  List<Map<String, dynamic>> coinPriceListNonQr = [];
  String deviceCode = ""; // Replace with the actual device code
  String machineId = ""; // Replace with the actual device code
  String rssi = '-39';
//set encryption obj
  String secretKey = ''; // Must be 32 characters
  String ivString = ''; // Must be 16 characters
  int remainingTodispenseAm = 0;
  int remainingTodispenseLast = 0; // Last Request amount
  String? _macAddress;
  String trxidinject = '';
  bool isLatestSoldout = false;
  bool isLatestQR = false;
  int latestCashValue = 0;
  String Datetime = '';
  bool mqttConnected = false;
  double _progress = 0.0;
  bool _downloading = false;
  String currentVersion = "";
  String key = "";
  Color regularColor = Color(0xFFFEE902);
  Color bonusColor = Color(0xFF4CAF50);
  Color cashColor = Color(0xFFD32F2F);
  bool _antiSpamButton = false; // Flag to prevent spamming
  Timer? _reconnectTimer;
  bool _isDialogOpen = false; // Prevent multiple dialogs
  bool _isSetLatestRunning = false; // Prevent multiple dialogs
  BuildContext? _dialogContext; // Store dialog context to close later
  String received = '';
  String _selectedImagePath = '';
  double _dragOffset = 0.0;
  double _backgroundOffsetY = 0.0; // FINAL position
  double _backgroundOffsetX = 0.0; // FINAL position
  double _previewOffsetY = 0.0; // Used inside dialog
  double _currentScale = 1.0; // FINAL scale
  double _previewScale = 1.0; // Used inside dialog

  List<String> _customNames = ['', '', '', '', ''];

  List<String> presetKeys = [
    'background_slot_1',
    'background_slot_2',
    'background_slot_3',
    'background_slot_4',
    'background_slot_5',
  ];

  @override
  void initState() {
    super.initState();
    List<UsbDevice> devices = [];
    UsbDevice? _device;
    UsbPort? _port;
    _loadBackgroundSettings();
    setState(() {
      isLoadingboot = true;
    });
    print('initState called');
    // resetsaveSoldout(true);
    loadSoldoutStatus();
    mqttConn(); // call mqtt
    initConnectivity();
    _reconnectTimer?.cancel();

    // UartService.uartStream.listen((data) {
    //   print("data uart $data");
    //   setState(() {
    //     received = data;
    //   });
    // });

    _reconnectTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      initConnectivity();
    });

    Future.delayed(Duration(seconds: 3), () {
      _getMacAddress();
      getKey();
    });

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    // final portName = ''; // 'COM5';
    // const platform = MethodChannel('com.example.serialport');
    // Wrap the code in a try-catch block to handle errors

    _loadSavedText(); // Load the saved text when the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // //testing
      // await saveFailedTrx("test123" , "10.00", "1000" );
      // await clearFailedTrx();
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        currentVersion = packageInfo.version;
      });
      // final prefs = await SharedPreferences.getInstance();
      // await prefs.remove('isLatestSoldout');
      // await prefs.remove('isLatestQR');
      // await prefs.remove('latestCashValue');
      print('test get trx failed ');
      List transactions = await getFailedTrx(); // Await the function call
      print(transactions); // Print the result

      try {
        communication = await Communication(null); // Ensure async initialization

        await Future.delayed(Duration(seconds: 3), () {
          if (communication!.isConnected == false) {
            print("Error opening port");

            // setState(() {
            //   ErrormsgInitConn = "Error opening port";
            // });
            _showErrorDialog();
            setState(() {
              isLoadingboot = false;
            });
          } else {
            communication.CheckPCBAlive();
            _snackBar('Port Connected');
          }
        });
      } catch (e) {
        setState(() {
          isLoadingboot = false;
        });
        print("Error opening port: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error opening port: $e")),
        );

        _showErrorDialog();

        setState(() {
          ErrormsgInitConn = e.toString();
        });
      }

      devices = await UsbSerial.listDevices();
      setState(() {
        myStringArray.addAll(devices); // Use addAll directly
      });
      setState(() {
        isLoadingboot = false;
      });
    });
  }

  void onMqttConnected() {
    setState(() {
      mqttConnected = true;
    });
  }

  void _setBackground(String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('background_image', imagePath);

    final matrix = _controllerzoom.value;
    final scale2 = matrix.getMaxScaleOnAxis();
    final offset = Offset(matrix.row0[3], matrix.row1[3]);

    await prefs.setDouble('background_scale', scale2);
    await prefs.setDouble('background_offset_x', offset.dx);
    await prefs.setDouble('background_offset_y', offset.dy);

    setState(() {
      _backgroundImagePath = imagePath;
      _currentScale = scale2;
      _backgroundOffsetY = offset.dy;
      _backgroundOffsetX = offset.dx;
    });
  }

  void _loadBackgroundSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedImagePath = prefs.getString('background_image') ?? 'assets/images/bg.jpg';
      _backgroundImagePath = prefs.getString('background_image') ?? 'assets/images/bg.jpg';
      _currentScale = prefs.getDouble('background_scale') ?? 1.0;
      _backgroundOffsetY = prefs.getDouble('background_offset_y') ?? 0.0;
    });
  }

  Future<void> _loadCustomNames() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? names = prefs.getStringList('background_custom_names');
    setState(() {
      _customNames = names ?? List.filled(5, '');
    });
  }

  late Stream<ConnectivityResult> _connectivityStream;

  void onMqttDisconnected() {
    setState(() {
      mqttConnected = false;
    });
  }

  String getFormattedDateTime() {
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    setState(() {
      Datetime = formatter.format(now);
    });
    return formatter.format(now);
  }

  Future<void> _getMacAddress() async {
    final info = NetworkInfo();
    String? mac = await info.getWifiBSSID(); // Gets the BSSID (MAC of the connected router)
    print('Mac Address : $mac');
    setState(() {
      _macAddress = mac ?? "Unknown";
    });
  }

  Future<void> resetsaveSoldout(bool isQrPayment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLatestSoldout', false); // Mark as sold out
    await prefs.setBool('isLatestQR', true); // Store QR payment status
    await prefs.setInt('remainingtoken', 0);
  }

  Future<void> saveSoldout(bool isQrPayment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLatestSoldout', true); // Mark as sold out
    await prefs.setBool('isLatestQR', isQrPayment); // Store QR payment status
    await prefs.setInt('remainingtoken', remainingTodispenseAm);
  }

  Future<void> saveFailedTrx(String trxid, String amount, String utdqr) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> failedTrxList = prefs.getStringList('failed_trx') ?? [];

    // Convert transaction details to a JSON string
    Map<String, dynamic> trxData = {
      'trxid': trxid,
      'amount': amount,
      'utdqr': utdqr,
    };

    failedTrxList.add(jsonEncode(trxData));

    await prefs.setStringList('failed_trx', failedTrxList);
  }

  Future<List> getFailedTrx() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> failedTrxList = prefs.getStringList('failed_trx') ?? [];

    return failedTrxList.map((trx) => jsonDecode(trx)).toList();
  }

  Future<void> clearFailedTrx() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('failed_trx');
  }

// Method to set default values for coinPriceList
  void _setDefaultCoinPriceList() {
    setState(() {
      coinPriceList = [
        {'coins': 10, 'price': 10},
        {'coins': 20, 'price': 20},
        {'coins': 50, 'price': 50},
        {'coins': 100, 'price': 100},
        // {'coins': 200, 'price': 200},
      ];
    });
  }

// Method to set default values for coinPriceListBonus
  void _setDefaultCoinPriceListBonus() {
    setState(() {
      coinPriceListBonus = [
        {'coins': 200, 'price': 200, 'bonus': 0, 'promoTitle': "🔥 Promotion! 🔥", 'promoText': "Pay at the counter only!"},
      ];
    });
  }

  // Method to set default values for coinPriceListNonQr
  void _setDefaultCoinPriceListNonQr() {
    setState(() {
      coinPriceListNonQr = [
        {'coins': 200, 'price': 200, 'bonus': 0, 'desc': "FREE CARTON PEPSI", 'cashPromoTitle': "🔥 Promotion! 🔥", 'cashPromoText': "Pay at the counter only!"},
      ];
    });
  }

  Future<void> antiSpamButton() async {
    if (_antiSpamButton) return; // Prevent multiple triggers

    setState(() {
      _antiSpamButton = true; // Set flag to true
    });

    Future.delayed(
        Duration(seconds: 1),
        () => setState(() {
              _antiSpamButton = false; // Set flag to true
            })); // Reset flag after delay
  }

  Future<void> _loadSavedText() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedText = prefs.getString('savedText');
    String? savedData = prefs.getString('coinPriceList');
    String? savedDataBonus = prefs.getString('coinPriceListBonus');
    String? savedDataNonQr = prefs.getString('coinPriceListNonQr');
    String? savedMachineID = prefs.getString('MachineID');
    String? savedDeviceCode = prefs.getString('DeviceCode');
    String? savedSecretKey = prefs.getString('SecretKey');
    String? savedIVString = prefs.getString('IVString');
    String? regularColorString = prefs.getString('RegularColor');
    String? bonusColorString = prefs.getString('BonusColor');
    String? cashColorString = prefs.getString('CashColor');

    Color regularColorz = regularColorString != null ? Color(int.parse(regularColorString, radix: 16)) : const Color(0xFFFEE902); // Default if null

    Color bonusColorz = bonusColorString != null ? Color(int.parse(bonusColorString, radix: 16)) : const Color(0xFFD32F2F); // Default if null

    Color cashColorz = cashColorString != null ? Color(int.parse(cashColorString, radix: 16)) : const Color(0xFF4CAF50); // Default if null

    List<dynamic> decodedBonusList = [];
    // Handle device code

    setState(() {
      regularColor = regularColorz;
      bonusColor = bonusColorz;
      cashColor = cashColorz;
      deviceCode = savedDeviceCode ?? 'TQR000001';
      machineId = savedMachineID ?? 'A001';
      secretKey = savedSecretKey ?? r'C0F535771682';
      //C0F535771682
      ivString = savedIVString ?? '0192006944061854';
    });
    print('test saved data');
    print(savedData);
    // Load Regular Coin Price List
    if (savedData != null && savedData.isNotEmpty) {
      try {
        List<dynamic> decodedList = jsonDecode(savedData);
        setState(() {
          coinPriceList = decodedList.map<Map<String, int>>((item) {
            return {
              'coins': (item['coins'] is int) ? item['coins'] : int.tryParse(item['coins'].toString()) ?? 0,
              'price': (item['price'] is int) ? item['price'] : int.tryParse(item['price'].toString()) ?? 0,
            };
          }).toList();
        });
      } catch (e) {
        print("Error parsing coinPriceList: $e");
        _setDefaultCoinPriceList(); // Set default if error occurs
      }
    } else {
      _setDefaultCoinPriceList(); // Set default if data is missing
    }

    if (savedDataBonus != null && savedDataBonus.isNotEmpty) {
      try {
        List<dynamic> decodedBonusList = jsonDecode(savedDataBonus);
        setState(() {
          coinPriceListBonus = decodedBonusList.map<Map<String, dynamic>>((item) {
            final promoTitle = item['promoTitle']?.toString()?.trim();

            return {
              'coins': (item['coins'] is int) ? item['coins'] : int.tryParse(item['coins'].toString()) ?? 0,
              'price': (item['price'] is int) ? item['price'] : int.tryParse(item['price'].toString()) ?? 0,
              'bonus': (item['bonus'] is int) ? item['bonus'] : int.tryParse(item['bonus'].toString()) ?? 0,
              'promoTitle': (promoTitle?.isNotEmpty ?? false) ? promoTitle : '🔥 Promotion! 🔥',
            };
          }).toList();
        });
      } catch (e) {
        print("Error parsing coinPriceListBonus: $e");
        _setDefaultCoinPriceListBonus(); // Set default if error occurs
      }
    } else {
      _setDefaultCoinPriceListBonus(); // Set default if data is missing
    }

    if (savedDataNonQr != null && savedDataNonQr.isNotEmpty) {
      try {
        List<dynamic> decodedBonusList = jsonDecode(savedDataNonQr);
        setState(() {
          coinPriceListNonQr = decodedBonusList.map<Map<String, dynamic>>((item) {
            final cashPromoTitle = item['cashPromoTitle']?.toString()?.trim();
            final cashPromoText = item['cashPromoText']?.toString()?.trim();

            return {
              'coins': (item['coins'] is int) ? item['coins'] : int.tryParse(item['coins'].toString()) ?? 0,
              'price': (item['price'] is int) ? item['price'] : int.tryParse(item['price'].toString()) ?? 0,
              'bonus': (item['bonus'] is int) ? item['bonus'] : int.tryParse(item['bonus'].toString()) ?? 0,
              'desc': item['desc']?.toString() ?? '',
              'cashPromoTitle': (cashPromoTitle?.isNotEmpty ?? false) ? cashPromoTitle : '🔥 Promotion! 🔥',
              'cashPromoText': (cashPromoText?.isNotEmpty ?? false) ? cashPromoText : 'Pay at the counter only!',
            };
          }).toList();
        });
      } catch (e) {
        print("Error parsing coinPriceListNonQr: $e");
        _setDefaultCoinPriceListNonQr(); // Set default if error occurs
      }
    } else {
      _setDefaultCoinPriceListNonQr(); // Set default if data is missing
    }

    // Load or Set Default Text
    if (savedText == null || savedText.isEmpty) {
      savedText = '1. Once the coins are dispensed, no refund request will be accepted.\n'
          '2. Any question feel free to contact: 0173990160.';
      await prefs.setString('savedText', savedText);
    }

    setState(() {
      _savedText = savedText!;
      _controller = TextEditingController(text: _savedText);
    });
    // mqttdispose();
    // mqttConn();
  }

  // Save text to shared preferences
  Future<void> _saveText(String text) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedText', text);
    setState(() {
      _savedText = text;
    });
  }

  void toggleLoadingDialog(BuildContext context, bool isLoading) {
    // Show the loading dialog first
    if (isLoading == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text("Loading..."),
            ],
          ),
        ),
      );
    } else {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> checkForUpdate(BuildContext context) async {
    setState(() {
      isGeneralLoading = true;
      _antiSpamButton = true; // Set flag to true
    });

    toggleLoadingDialog(context, true);
    try {
      final response = await http.get(Uri.parse("https://www.transpire.com.my/apk/halolopark/version.json"));

      if (response.statusCode == 200) {
        toggleLoadingDialog(context, false);
        setState(() {
          isGeneralLoading = false;
        });
        final data = jsonDecode(response.body);
        final latestVersion = data["version"];
        final apkUrl = data["download_url"];

        final packageInfo = await PackageInfo.fromPlatform();
        String currentVersion = packageInfo.version;

        if (latestVersion != currentVersion) {
          showDialog(
            context: context,
            barrierDismissible: false, // Prevents closing the dialog when clicking outside
            builder: (context) => AlertDialog(
              title: Text("Update Available"),
              content: Text("A new version ($latestVersion) is available. Update now?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text("Later")),
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      downloadAndInstallAPK(apkUrl);
                    },
                    child: Text("Update")),
              ],
            ),
          ).then((_) => setState(() {
                _antiSpamButton = false; // Set flag to true
              })); // Ensure flag resets even if dialog is dismissed
        } else {
          showDialog(
            context: context,
            barrierDismissible: false, // Prevents closing the dialog when clicking outside
            builder: (context) => AlertDialog(
              title: Text("App is updated to latest version"),
              content: Text("No update required."),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text("Okay")),
              ],
            ),
          ).then((_) => setState(() {
                _antiSpamButton = false; // Set flag to true
              })); // Ensure flag resets even if dialog is dismissed
        }
      } else {
        toggleLoadingDialog(context, false);
        setState(() {
          isGeneralLoading = false;
        });
        showDialog(
          context: context,
          barrierDismissible: false, // Prevents closing the dialog when clicking outside
          builder: (context) => AlertDialog(
            title: Text("Error checking update"),
            content: Text("500."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text("Okay")),
            ],
          ),
        ).then((_) => setState(() {
              _antiSpamButton = false; // Set flag to true
            })); // Ensure flag resets even if dialog is dismissed
      }
    } catch (e) {
      toggleLoadingDialog(context, false);
      setState(() {
        isGeneralLoading = false;
      });
      showDialog(
        context: context,
        barrierDismissible: false, // Prevents closing the dialog when clicking outside
        builder: (context) => AlertDialog(
          title: Text("Error 404"),
          content: Text("Check your internet connection."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("Okay")),
          ],
        ),
      ).then((_) => setState(() {
            _antiSpamButton = false; // Set flag to true
          })); // Ensure flag resets even if dialog is dismissed
    }
  }

  Future<void> downloadAndInstallAPK(String apkUrl) async {
    // Request permissions for Android 7
    if (await Permission.storage.request().isDenied) {
      print("Storage permission denied.");
      return;
    }
    void Function(void Function())? setDialogState;
    // Get download directory
    Directory tempDir = await getTemporaryDirectory();
    String savePath = "${tempDir.path}/app-release.apk";

    setState(() {
      _downloading = true;
      _progress = 0.0;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            setDialogState = setState; // Store the function reference
            return AlertDialog(
              title: Text("Downloading APK"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: _progress),
                  SizedBox(height: 10),
                  Text("${(_progress * 100).toStringAsFixed(0)}%"),
                ],
              ),
            );
          },
        );
      },
    );

    try {
      Dio dio = Dio();
      await dio.download(
        apkUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            double newProgress = received / total;

            // ✅ Update progress inside the existing dialog
            print('progress : $newProgress');
            setState(() {
              _progress = newProgress;
            });
            if (setDialogState != null) {
              setDialogState!(() {
                _progress = newProgress;
              });
            }
          }
        },
      );

      // ✅ Close dialog after download is complete

      Navigator.pop(context);

      print("Download complete. File saved at: $savePath");

      // ✅ Show a snackbar to notify the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download Complete! Tap to install.")),
      );

      // ✅ Open APK file
      OpenFile.open(savePath);
    } catch (e) {
      // ✅ Close dialog if an error occurs
      if (context.mounted) {
        Navigator.pop(context);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download Failed: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _downloading = false;
      });
    }
  }

  Future<void> _clearDataAndResetFlags(BuildContext context) async {
    // Example: Clear SharedPreferences data.
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await clearFailedTrx();
    await prefs.remove('isLatestSoldout');
    await prefs.remove('isLatestQR');

    setState(() {
      refId = '';
      random = '';
      trxidinject = '';
      isLatestSoldout = false;
      isLatestQR = false;
      latestCashValue = 0;
      ReceivedPayment = false;
      CompletedDispense = false;
      FailedDispense = false;
      ClosingCall = false;
      isMachineFaulty = false;
      Token = '';
      Signature = '';
      Errormsg = '';
      ErrormsgConn = '';
      ErrormsgInitConn = '';
    });

    Navigator.of(context).pop();
    exit(0);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('RegularColor', regularColor.value.toRadixString(16));
    await prefs.setString('BonusColor', bonusColor.value.toRadixString(16));
    await prefs.setString('CashColor', cashColor.value.toRadixString(16));
    // Convert all values to int explicitly
    List<Map<String, dynamic>> cleanedCoinPriceList = coinPriceList.map((item) {
      return {
        'coins': (item['coins'] is int) ? item['coins'] : int.tryParse(item['coins'].toString()) ?? 0,
        'price': (item['price'] is int) ? item['price'] : int.tryParse(item['price'].toString()) ?? 0,
      };
    }).toList();

    List<Map<String, dynamic>> cleanedCoinPriceListBonus = coinPriceListBonus.map((item) {
      return {
        'coins': (item['coins'] is int) ? item['coins'] : int.tryParse(item['coins'].toString()) ?? 0,
        'price': (item['price'] is int) ? item['price'] : int.tryParse(item['price'].toString()) ?? 0,
        'bonus': (item['bonus'] is int) ? item['bonus'] : int.tryParse(item['bonus'].toString()) ?? 0,
        'promoTitle': item['promoTitle'],
      };
    }).toList();

    List<Map<String, dynamic>> cleanedCoinPriceListNonQr = coinPriceListNonQr.map((item) {
      return {
        'coins': (item['coins'] is int) ? item['coins'] : int.tryParse(item['coins'].toString()) ?? 0,
        'price': (item['price'] is int) ? item['price'] : int.tryParse(item['price'].toString()) ?? 0,
        'bonus': (item['bonus'] is int) ? item['bonus'] : int.tryParse(item['bonus'].toString()) ?? 0,
        'desc': item['desc'],
        'cashPromoTitle': item['cashPromoTitle'],
        'cashPromoText': item['cashPromoText']
      };
    }).toList();

    // Save as JSON string
    prefs.setString('coinPriceList', jsonEncode(cleanedCoinPriceList));
    prefs.setString('coinPriceListBonus', jsonEncode(cleanedCoinPriceListBonus));
    prefs.setString('coinPriceListNonQr', jsonEncode(cleanedCoinPriceListNonQr));
  }

  Future<void> initConnectivity() async {
    late List<ConnectivityResult> result;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      result = await _connectivity.checkConnectivity();
      // print('internet : $result');
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t check connectivity status: $e')),
      );
      return;
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, discard the reply.
    if (!mounted) {
      return Future.value(null);
    }

    return _updateConnectionStatus(result);
  }

  Future<void> getKey() async {
    final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);
    final payloadtoken = {
      "commandcode": "RequestToken",
      "devicecode": deviceCode,
      "result": "false",
      "data": [
        {"key": encryptedKey}
      ]
    };

    final responsetoken = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode(payloadtoken),
    );

    if (responsetoken.statusCode == 200) {
      Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
      String token = parsedJson['data'][0]['token'];

      final payloadkey = {
        "commandcode": "GetKey",
        "devicecode": deviceCode,
        "result": "false",
      };

      final responsekey = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json', 'Token': token},
        body: json.encode(payloadkey),
      );
      // String sanitizedResponse = responsetoken.body.replaceAll("\r", "").replaceAll("\n", "");
      // Map<String, dynamic> parsedJson2 = jsonDecode(sanitizedResponse);

      // ✅ Fix unescaped newlines before decoding
      String sanitizedResponse = responsekey.body.replaceAll("\r", "").replaceAll("\n", "\\n");

// ✅ Decode the cleaned JSON
      Map<String, dynamic> parsedJson2 = jsonDecode(sanitizedResponse);
      // Map<String, dynamic> parsedJson2 =
      // jsonDecode(responsekey.body);

      String pkey = parsedJson2['data'][0]['privatekey'].replaceAll("\\n", "\n");

      setState(() {
        key = pkey;
      });
    }
  }

  Future<void> _updateConnectionStatus(List<ConnectivityResult> result) async {
    bool hasInternet = false;

    // Check if connected to Wi-Fi or mobile
    for (var connectivity in result) {
      if (connectivity == ConnectivityResult.mobile || connectivity == ConnectivityResult.wifi || connectivity == ConnectivityResult.ethernet) {
        // Added Ethernet check
        // Perform an internet check (e.g., ping Google)
        try {
          final response = await InternetAddress.lookup('8.8.8.8').timeout(Duration(seconds: 5));

          hasInternet = response.isNotEmpty && response[0].rawAddress.isNotEmpty;
        } catch (e) {
          hasInternet = false;
        }

        setState(() {
          isConnected = hasInternet; // Update connection status
        });
      } else {
        setState(() {
          isConnected = false; // Update connection status
        });
      }
      break; // No need to check further once internet is found
    }

    // If disconnected and dialog is not open, show dialog
    if (!isConnected && !_isDialogOpen) {
      _isDialogOpen = true;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          _dialogContext = dialogCtx; // Save dialog context for closing
          return AlertDialog(
            title: Text("No Connection"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cancel, color: Colors.red, size: 50),
                const SizedBox(height: 16),
                Text("Please make sure that you are connected."),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _isDialogOpen = false;
                  Navigator.pop(dialogCtx);
                },
                child: Text("Okay"),
              ),
            ],
          );
        },
      );
    }

    // If connected, close the dialog automatically
    if (isConnected && _isDialogOpen && _dialogContext != null) {
      Navigator.pop(_dialogContext!); // Close dialog
      _isDialogOpen = false;
      _dialogContext = null;
    }
  }

  int clickCount = 0; // Counter to track clicks

  void handleAdminButtonClick(BuildContext context) {
    clickCount++;
    if (clickCount == 3) {
      // Reset the counter
      clickCount = 0;
      // Show the password dialog
      _showPasswordDialog(context);
    }
  }
  // Request permissions

  String readPrivateKey(String filePath) {
    return File(filePath).readAsStringSync();
  }

  //load privatekey
  Future<String> loadPrivateKey() async {
    try {
      final rawData = await rootBundle.loadString('assets/private_key.txt');
      // Normalize and clean the data
      final sanitizedData = utf8.decode(rawData.codeUnits).replaceAll('\r\n', '\n').trim();
      return sanitizedData;
    } catch (e) {
      throw Exception("Error loading private key: $e");
    }
  }

  String extractCompanyName(String qrData) {
    Map<String, String> parsedData = parseTLV(qrData);

    String companyName = parsedData['59'] ?? 'Unknown'; // Tag 59 contains the company name
    return companyName;
  }

  Map<String, String> parseTLV(String data) {
    Map<String, String> result = {};
    int i = 0;

    while (i < data.length) {
      // Extract Tag (2 digits)
      String tag = data.substring(i, i + 2);
      i += 2;

      // Extract Length (2 digits)
      int length = int.parse(data.substring(i, i + 2));
      i += 2;

      // Extract Value (length of 'length')
      String value = data.substring(i, i + length);
      i += length;

      result[tag] = value;
    }

    return result;
  }

  void setSoldout() async {
    setState(() {
      isDeviceFaulty = true;
    });
  }

  void Devicefaulty() async {
    final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);

    final payloadtoken = {
      "commandcode": "RequestToken",
      "devicecode": deviceCode,
      "result": "false",
      "data": [
        {"key": encryptedKey}
      ]
    };

    final responsetoken = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode(payloadtoken),
    );

    var log = """
                ${communication.AlllogsGetStatus}
                \n\n
                QR request dispense
                OUT >>>:  ${communication.HexQrRequestDispenseOUT}
                IN: <<< ${communication.HexQrRequestDispenseIN}
                Allow dispense : ${communication.isAllowed}
                 \n\n
                 
                QR dispense amount ${selectedAmount}
                OUT >>>: ${communication.HexQrDispenseOUT}
                IN: <<< ${communication.HexQrDispenseIN}
                Allow dispense : ${communication.isAllowed}
                \n\n
                
                ${communication.AlllogsDispensing}
                
                Soldout
                IN: <<< ${communication.HexSoldOutIN}
                OUT >>>: ${communication.HexSoldOutOUT}    
                \n\n
                
                Get Status
                OUT: >>> ${communication.HexGetStatusOUT}
                IN: <<< ${communication.HexGetStatusIN}
                Total Cash UTD: ${communication.TotalCash_}
                Token Dispense UTD: ${communication.TotalToken_}
                """;

    final setDeviceError = {
      "commandcode": "SetDeviceError",
      "devicecode": deviceCode,
      "data": [
        {
          "deviceerrorcode": 3,
          "description": "Soldout! Remaining token: ${remainingTodispenseAm}",
          "errorstart": getFormattedDateTime(),
          "errorend": "1900-JAN-01 00:00:00",
          "rssi": "-99",
          "log": log,
        }
      ]
    };

    final privateKeyPem = await loadPrivateKey();
    String signature = await generateSignature(jsonEncode(setDeviceError), key);

    if (responsetoken.statusCode == 200) {
      final responseData = json.decode(responsetoken.body);
      Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
      String token = parsedJson['data'][0]['token'];

      // print('request token success');
      final responseSetDeviceError = http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json', 'Token': token, 'Signature': signature},
        body: json.encode(setDeviceError),
      );
      print('error sent, success');
      communication.ResetLogDispensing();
    }

    await saveFailedTrx(refId!, selectedAmount, UTDQR);

    setState(() {
      isDeviceFaulty = true;
    });
  }

  void _showDeviceConfigModal(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Fetch latest values from SharedPreferences before opening the modal
    String latestMachineId = prefs.getString('MachineID') ?? 'A001';
    String latestDeviceCode = prefs.getString('DeviceCode') ?? 'TQR000001';
    String latestSecretKey = prefs.getString('SecretKey') ?? r'C0F535771682';
    String latestIVString = prefs.getString('IVString') ?? '0192006944061854';

    // Initialize controllers with updated values
    TextEditingController machineIdController = TextEditingController(text: latestMachineId);
    TextEditingController deviceCodeController = TextEditingController(text: latestDeviceCode);
    TextEditingController secretKeyController = TextEditingController(text: latestSecretKey);
    TextEditingController ivStringController = TextEditingController(text: latestIVString);

    showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing the dialog when clicking outside
      builder: (context) {
        return AlertDialog(
          title: Text('Device Configuration'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: machineIdController,
                  decoration: InputDecoration(labelText: 'Machine ID'),
                  onChanged: (value) {
                    setState(() {
                      machineIdController.text = value;
                    });
                  },
                ),
                SizedBox(height: 10),
                TextField(
                  controller: deviceCodeController,
                  decoration: InputDecoration(labelText: 'Device Code'),
                  onChanged: (value) {
                    setState(() {
                      deviceCodeController.text = value;
                    });
                  },
                ),
                SizedBox(height: 10),
                TextField(
                  controller: secretKeyController,
                  decoration: InputDecoration(labelText: 'Secret Key'),
                  obscureText: true, // Hide key for security
                  onChanged: (value) {
                    setState(() {
                      secretKeyController.text = value;
                    });
                  },
                ),
                SizedBox(height: 10),
                TextField(
                  controller: ivStringController,
                  decoration: InputDecoration(labelText: 'IV String'),
                  onChanged: (value) {
                    setState(() {
                      ivStringController.text = value;
                    });
                  },
                ),
                SizedBox(height: 10),
                Text('MAC address : $_macAddress')
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Save the updated values to SharedPreferences
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setString('MachineID', machineIdController.text);
                await prefs.setString('DeviceCode', deviceCodeController.text);
                await prefs.setString('SecretKey', secretKeyController.text);
                await prefs.setString('IVString', ivStringController.text);
                _loadSavedText();

                // Close the modal
                Navigator.pop(context);

                // Optional: Show confirmation
                _snackBar('Device setting saved successfully');
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Show modal with the list of all entries
  void _showListModal(BuildContext context) {
    List<Map<String, dynamic>> tempCoinPriceList = List.from(coinPriceList);
    List<Map<String, dynamic>> tempCoinPriceListBonus = List.from(coinPriceListBonus);
    List<Map<String, dynamic>> tempCoinPriceListNonQr = List.from(coinPriceListNonQr);

    showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing the dialog when clicking outside
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('Coins & Prices List'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 16, color: Colors.black), // Default text style
                        children: [
                          TextSpan(text: 'The maximum number of coins that can be dispensed at once is '),
                          TextSpan(
                            text: '500',
                            style: TextStyle(fontWeight: FontWeight.bold), // Bold style for "500"
                          ),
                          TextSpan(text: '.'), // Period after "500"
                        ],
                      ),
                    ),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 16, color: Colors.black), // Default text style
                        children: [
                          TextSpan(text: 'Status Soldout : '),
                          TextSpan(
                            text: isLatestSoldout ? 'yes, Remaining token: $remainingTodispenseAm' : 'no',
                            style: TextStyle(fontWeight: FontWeight.bold), // Bold style for "500"
                          ),

                          TextSpan(text: '.'), // Period after "500"
                        ],
                      ),
                    ),
                    SizedBox(height: 15), // Adds spacing
                    _buildListSection(
                      title: 'Regular',
                      list: tempCoinPriceList,
                      setState: setStateDialog,
                      onColorChanged: (color) => setState(() => regularColor = color),
                      sectionColor: regularColor,
                    ),
                    SizedBox(height: 20),
                    _buildListSection(
                      title: 'Bonus',
                      list: tempCoinPriceListBonus,
                      setState: setStateDialog,
                      isBonus: true,
                      onColorChanged: (color) => setState(() => bonusColor = color),
                      sectionColor: bonusColor,
                    ),
                    SizedBox(height: 20),
                    _buildListSection(
                      title: 'Cash',
                      list: tempCoinPriceListNonQr,
                      setState: setStateDialog,
                      isCash: true,
                      isBonus: true,
                      onColorChanged: (color) => setState(() => cashColor = color),
                      sectionColor: cashColor,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      coinPriceList = List.from(tempCoinPriceList);
                      coinPriceListBonus = List.from(tempCoinPriceListBonus);
                      coinPriceListNonQr = List.from(tempCoinPriceListNonQr);
                    });
                    _saveData();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("Coins Setting Saved!"),
                    ));
                  },
                  child: Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildListSection({
    required String title,
    required List<Map<String, dynamic>> list,
    required StateSetter setState,
    bool isBonus = false,
    bool isCash = false,
    required Color sectionColor,
    required Function(Color) onColorChanged,
  }) {
    // Declare controllers and FocusNodes outside the build method to persist their state
    List<TextEditingController> coinsControllers = [];
    List<TextEditingController> priceControllers = [];
    List<TextEditingController?> bonusControllers = [];
    List<TextEditingController?> desControllers = [];
    List<TextEditingController?> promoTitleControllers = [];
    List<TextEditingController?> cashPromoTitleControllers = [];
    List<TextEditingController?> cashPromoTextControllers = [];
    List<FocusNode> coinsFocusNodes = [];
    List<FocusNode> priceFocusNodes = [];
    List<FocusNode?> bonusFocusNodes = [];
    List<FocusNode?> desFocusNodes = [];
    List<FocusNode?> promoTitleFocusNodes = [];
    List<FocusNode?> cashPromoTitleFocusNodes = [];
    List<FocusNode?> cashPromoTextFocusNodes = [];

    return Container(
      margin: EdgeInsets.symmetric(vertical: 0), // space between sections
      padding: EdgeInsets.all(16), // space inside the box
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey, width: 1.5),
        borderRadius: BorderRadius.circular(12), // rounded corners
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.color_lens, color: sectionColor),
                onPressed: () {
                  Color tempColor = sectionColor;
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text('Pick a color for $title'),
                        content: SingleChildScrollView(
                          child: ColorPicker(
                            pickerColor: tempColor,
                            onColorChanged: (Color color) {
                              tempColor = color;
                            },
                          ),
                        ),
                        actions: [
                          TextButton(
                            child: Text('Cancel'),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          TextButton(
                            child: Text('Reset to Default'),
                            onPressed: () {
                              setState(() {
                                if (isBonus && isCash) {
                                  tempColor = const Color(0xFFD32F2F);
                                } else if (!isCash && isBonus) {
                                  tempColor = const Color(0xFF4CAF50);
                                } else if (!isCash && !isBonus) {
                                  tempColor = const Color(0xFFFEE902);
                                }
                                onColorChanged(tempColor);
                              });
                              Navigator.of(context).pop();
                            },
                          ),
                          TextButton(
                            child: Text('Select'),
                            onPressed: () {
                              onColorChanged(tempColor);
                              setState(() {});
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              Text(
                'Change Color',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(list.length, (index) {
              if (coinsControllers.length <= index) {
                coinsControllers.add(TextEditingController(text: list[index]['coins'].toString()));
                priceControllers.add(TextEditingController(text: list[index]['price'].toString()));
                bonusControllers.add(isBonus ? TextEditingController(text: list[index]['bonus'].toString()) : null);
                desControllers.add(TextEditingController(text: list[index]['desc'].toString()));

                promoTitleControllers.add(TextEditingController(text: list[index]['promoTitle'].toString()));

                cashPromoTitleControllers.add(TextEditingController(text: list[index]['cashPromoTitle'].toString()));

                cashPromoTextControllers.add(TextEditingController(text: list[index]['cashPromoText'].toString()));

                coinsFocusNodes.add(FocusNode());
                priceFocusNodes.add(FocusNode());
                bonusFocusNodes.add(isBonus ? FocusNode() : null);
                desFocusNodes.add(FocusNode());
                promoTitleFocusNodes.add(FocusNode());
                cashPromoTitleFocusNodes.add(FocusNode());
                cashPromoTextFocusNodes.add(FocusNode());
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: ValueKey('coins_$index'),
                            controller: coinsControllers[index],
                            focusNode: coinsFocusNodes[index],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(labelText: 'Coins'),
                            onChanged: (value) {
                              int parsedValue = int.tryParse(value) ?? 0;
                              list[index]['coins'] = parsedValue;
                            },
                            onEditingComplete: () {
                              FocusScope.of(context).requestFocus(priceFocusNodes[index]);
                            },
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: ValueKey('price_$index'),
                            controller: priceControllers[index],
                            focusNode: priceFocusNodes[index],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(labelText: 'Price'),
                            onChanged: (value) {
                              int parsedValue = int.tryParse(value) ?? 0;
                              list[index]['price'] = parsedValue;
                            },
                            onEditingComplete: () {
                              FocusScope.of(context).requestFocus(bonusFocusNodes[index] ?? coinsFocusNodes[index]);
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              list.removeAt(index);
                              coinsControllers[index].dispose();
                              priceControllers[index].dispose();
                              bonusControllers[index]?.dispose();
                              desControllers[index]?.dispose();
                              cashPromoTitleControllers[index]?.dispose();
                              cashPromoTextControllers[index]?.dispose();
                              promoTitleControllers[index]?.dispose();
                              coinsControllers.removeAt(index);
                              priceControllers.removeAt(index);
                              bonusControllers.removeAt(index);
                              desControllers.removeAt(index);
                              cashPromoTitleControllers.removeAt(index);
                              cashPromoTextControllers.removeAt(index);
                              promoTitleControllers.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                    if (isBonus && bonusControllers[index] != null) ...[
                      SizedBox(height: 10),
                      TextField(
                        key: ValueKey('bonus_$index'),
                        controller: bonusControllers[index],
                        focusNode: bonusFocusNodes[index],
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(labelText: 'Bonus'),
                        onChanged: (value) {
                          int parsedValue = int.tryParse(value) ?? 0;
                          list[index]['bonus'] = parsedValue;
                        },
                        onEditingComplete: () {
                          FocusScope.of(context).requestFocus(bonusFocusNodes[index]);
                        },
                      )
                    ],
                    if (!isCash && isBonus) ...[
                      SizedBox(height: 10),
                      TextField(
                        key: ValueKey('ptitle_$index'),
                        controller: promoTitleControllers[index],
                        onChanged: (value) {
                          list[index]['promoTitle'] = value;
                        },
                        maxLines: 1,
                        decoration: InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                      )
                    ],
                    if (isCash && isBonus) ...[
                      SizedBox(height: 10),
                      TextField(
                        key: ValueKey('ctitle_$index'),
                        controller: cashPromoTitleControllers[index],
                        onChanged: (value) {
                          list[index]['cashPromoTitle'] = value;
                        },
                        maxLines: 1,
                        decoration: InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 10),
                      TextField(
                        key: ValueKey('cpt_$index'),
                        controller: cashPromoTextControllers[index],
                        onChanged: (value) {
                          list[index]['cashPromoText'] = value;
                        },
                        maxLines: 1,
                        decoration: InputDecoration(
                          labelText: 'First Description',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 10),
                      TextField(
                        key: ValueKey('desc_$index'),
                        controller: desControllers[index],
                        onChanged: (value) {
                          list[index]['desc'] = value;
                        },
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: 'Second Description',
                          border: OutlineInputBorder(),
                        ),
                      )
                    ],
                  ],
                ),
              );
            }),
          ),
          SizedBox(height: 10),
          TextButton(
            onPressed: () {
              setState(() {
                list.add({
                  'coins': 0,
                  'price': 0,
                  if (isBonus) 'bonus': 0,
                });
                coinsControllers.add(TextEditingController(text: '0'));
                priceControllers.add(TextEditingController(text: '0'));
                desControllers.add(TextEditingController(text: ''));
                if (isBonus) {
                  bonusControllers.add(TextEditingController(text: '0'));
                } else {
                  bonusControllers.add(null);
                }
                coinsFocusNodes.add(FocusNode());
                priceFocusNodes.add(FocusNode());
                desFocusNodes.add(FocusNode());
                bonusFocusNodes.add(isBonus ? FocusNode() : null);
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [Icon(Icons.add), Text(" Add $title")],
            ),
          ),
        ],
      ),
    );
  }

  void remainingToDispense(int remaining) async {
    setState(() {
      remainingTodispenseAm = remaining;
    });
  }

  void setLatestFailedTrx() async {
    if (_isSetLatestRunning == false) {
      setState(() {
        _isSetLatestRunning = true;
      });

      List transactions = await getFailedTrx();
      // only run after restarted
      if (isLatestSoldout) {
        print('recently soldout detected');
        if (isLatestQR) {
          if (transactions.isNotEmpty) {
            Map<String, dynamic> firstTransaction = transactions[0]; // Get the first item
            final frefid = firstTransaction['trxid'];
            final famount = firstTransaction['amount'];
            final futdqr = firstTransaction['utdqr'];

            final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);

            final payloadtoken = {
              "commandcode": "RequestToken",
              "devicecode": deviceCode,
              "result": "false",
              "data": [
                {"key": encryptedKey}
              ]
            };

            final responsetoken = await http.post(
              Uri.parse(apiUrl),
              headers: {
                'Content-Type': 'application/json',
              },
              body: json.encode(payloadtoken),
            );

            const int maxRetries = 30; // Maximum retries
            int retries = 0;

            // Retry until isCompleteDispense becomes true or retries exceed maxRetries
            while (retries < maxRetries) {
              print('test : ');
              print(communication.isCompleteDispense);

              if (communication.isCompleteDispense) {
                final SuccessPaymentPayloadtrx = {
                  "commandcode": "DI_SetTransactionEWalletV2",
                  "devicecode": deviceCode,
                  "data": [
                    {
                      "machineid": machineId,
                      "statusstarttime": getFormattedDateTime(),
                      "status": "Success",
                      "eutdcounter": communication.totalUtdQr,
                      "eamount": famount,
                      "eoriginalamount": famount,
                      "qrcode": "",
                      "ewallettransactionid": frefid,
                      "ewallettypecode": "DUITNOW",
                      "numberofinquiry": "0",
                      "duration": "0/175",
                      "errorcode": "0",
                      "errormessage": "",
                      "ewallettestusercode": "",
                      "slot": "55",
                      "responsetime": "1",
                      "rssi": "114"
                    }
                  ]
                };
                // If isCompleteDispense becomes true, return 'Completed'
                communication.isCompleteDispense = false; // Reset the flag for future operations
                communication.isSoldOut = false; // Reset the flag for future operations
                communication.isDispenseCash = false;
                communication.isQr = false;

                // fetch success api
                if (responsetoken.statusCode == 200) {
                  Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
                  String token = parsedJson['data'][0]['token'];

                  final privateKeyPem = await loadPrivateKey();
                  String signature = await generateSignature(jsonEncode(SuccessPaymentPayloadtrx), key);

                  final responseSuccessTRXEW = await http.post(
                    Uri.parse(apiUrl),
                    headers: {'Content-Type': 'application/json', 'Token': token, 'Signature': signature},
                    body: json.encode(SuccessPaymentPayloadtrx),
                  );

                  if (responseSuccessTRXEW.statusCode == 200) {
                    print('Transaction:Success sent successfully');
                  } else {
                    print('Failed to success transaction. Status code: ${responseSuccessTRXEW.statusCode}');
                  }

                  await clearFailedTrx();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('isLatestSoldout');
                  await prefs.remove('isLatestQR');
                  setState(() {
                    remainingTodispenseAm = 0;
                    latestCashValue = 0;
                    isLatestQR = false;
                    isLatestSoldout = false;
                    _isSetLatestRunning = false;
                  });
                  return;
                }
              }
              print('soldout returned');

              // Wait for the specified interval before retrying
              await Future.delayed(Duration(milliseconds: 2000));
              retries++;
            }
          } else {
            await clearFailedTrx();
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('isLatestSoldout');
            await prefs.remove('isLatestQR');

            communication.isCompleteDispense = false; // Reset the flag for future operations
            communication.isSoldOut = false; // Reset the flag for future operations
            communication.isDispenseCash = false;
            communication.isQr = false;

            setState(() {
              remainingTodispenseAm = 0;
              latestCashValue = 0;
              isLatestQR = false;
              isLatestSoldout = false;
              _isSetLatestRunning = false;
            });
            return;
          }
        }

        // latest cash trx
        else {
          if (transactions.isNotEmpty) {
            const int maxRetries = 30; // Maximum retries
            int retries = 0;

            // Retry until isCompleteDispense becomes true or retries exceed maxRetries
            while (retries < maxRetries) {
              if (communication.isCompleteDispense) {
                final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);

                final payloadtoken = {
                  "commandcode": "RequestToken",
                  "devicecode": deviceCode,
                  "result": "false",
                  "data": [
                    {"key": encryptedKey}
                  ]
                };
                // final response = await http.get(Uri.parse(apiUrl));
                final responsetoken = await http.post(
                  Uri.parse(apiUrl),
                  headers: {
                    'Content-Type': 'application/json',
                  },
                  body: json.encode(payloadtoken),
                );

                communication.isSoldOut = false; // Reset the flag for future operations
                communication.isCompleteDispense = false; // Reset the flag for future operations
                communication.isDispenseCash = false;
                communication.isQr = false;

                final setcashpayload = {
                  "commandcode": "SetTransactionCash",
                  "devicecode": deviceCode,
                  "data": [
                    {
                      "statusstarttime": getFormattedDateTime(),
                      "utdcounter": communication.UtdCash.toString(),
                      "cashcounter": communication.CashCounter.toString(),
                      "utdCoinTube": "0.00",
                      "coinTubeCounter": "0.00",
                      "utdCoinBox": "0.00",
                      "coinBoxCounter": "0.00",
                      "amount": latestCashValue == 0 ? communication.CASHDispenseCounter_.toString() : (latestCashValue / 100).toString(),
                      "slot": "5",
                      "rssi": "-99"
                    }
                  ]
                };

                final privateKeyPem = await loadPrivateKey();
                String signature = await generateSignature(jsonEncode(setcashpayload), key);

                if (responsetoken.statusCode == 200) {
                  final responseData = json.decode(responsetoken.body);
                  Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
                  String token = parsedJson['data'][0]['token'];

                  print('request token success');
                  final responseSetCashTrx = http.post(
                    Uri.parse(apiUrl),
                    headers: {'Content-Type': 'application/json', 'Token': token, 'Signature': signature},
                    body: json.encode(setcashpayload),
                  );
                }
                await clearFailedTrx();
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('isLatestSoldout');
                await prefs.remove('isLatestQR');
                await prefs.remove('latestCashValue');

                setState(() {
                  remainingTodispenseAm = 0;
                  latestCashValue = 0;
                  isLatestQR = false;
                  isLatestSoldout = false;
                  _isSetLatestRunning = false;
                });
                print("transactions cash uploaded.");
                return;
              } else {
                print("No failed transactions found.");
              }

              await Future.delayed(Duration(milliseconds: 2000));
              retries++;
            }
          } else {
            await clearFailedTrx();
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('isLatestSoldout');
            await prefs.remove('isLatestQR');

            communication.isCompleteDispense = false; // Reset the flag for future operations
            communication.isSoldOut = false; // Reset the flag for future operations
            communication.isDispenseCash = false;
            communication.isQr = false;

            setState(() {
              remainingTodispenseAm = 0;
              latestCashValue = 0;
              isLatestQR = false;
              isLatestSoldout = false;
              _isSetLatestRunning = false;
            });
            return;
          }
        }
      } else {
        await clearFailedTrx();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('isLatestSoldout');
        await prefs.remove('isLatestQR');
        await prefs.remove('latestCashValue');
        setState(() {
          remainingTodispenseAm = 0;
          latestCashValue = 0;
          isLatestQR = false;
          isLatestSoldout = false;
          _isSetLatestRunning = false;
        });
      }
    }
  }

  void InsertCash(String status, int UtdCash, int CashCounter, int cashValue_, int UTDCASHCounter) async {
    print('insertcash being called');
    if (status == 'Dispensing') {
      setState(() {
        ReceivedPayment = true;
        CompletedDispense = false;
        latestCashValue = 0;
      });
    }

    if (status == 'Completed' && latestCashValue == 0) {
      communication.isDispenseCash = false;
      communication.isCompleteDispense = false;
      final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);

      final payloadtoken = {
        "commandcode": "RequestToken",
        "devicecode": deviceCode,
        "result": "false",
        "data": [
          {"key": encryptedKey}
        ]
      };
      // final response = await http.get(Uri.parse(apiUrl));
      final responsetoken = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(payloadtoken),
      );

      final setcashpayload = {
        "commandcode": "SetTransactionCash",
        "devicecode": deviceCode,
        "data": [
          {
            "statusstarttime": getFormattedDateTime(),
            "utdcounter": UtdCash.toString(),
            "cashcounter": UTDCASHCounter.toString(),
            "utdCoinTube": "0.00",
            "coinTubeCounter": "0.00",
            "utdCoinBox": "0.00",
            "coinBoxCounter": "0.00",
            "amount": cashValue_.toString(),
            "slot": "5",
            "rssi": "-99",
            "EWalletQRCode": communication.hexString
          }
        ]
      };

      final privateKeyPem = await loadPrivateKey();
      String signature = await generateSignature(jsonEncode(setcashpayload), key);

      if (responsetoken.statusCode == 200) {
        final responseData = json.decode(responsetoken.body);
        Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
        String token = parsedJson['data'][0]['token'];

        print('request token success');
        final responseSetCashTrx = http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json', 'Token': token, 'Signature': signature},
          body: json.encode(setcashpayload),
        );
      }

      setState(() {
        CompletedDispense = true;
        FailedDispense == false;
      });
      Future.delayed(Duration(seconds: 2), () {
        setState(() {
          ReceivedPayment = false;
          CompletedDispense = false;
        });
      });
    }

    if (status == 'Failed') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('latestCashValue', communication.cashValue_); // Store cash value

      Devicefaulty();
      saveSoldout(false);
      communication.isDispenseCash = false;
      setState(() {
        ReceivedPayment = true;
        FailedDispense = true;
        Errormsg = 'Token is out of stock.';
      });
    }
  }

  //Completing progress
  // Core of Code for the program to run !!!!!! START
  void closingStatement() async {
    int? amounttodis = 0;
    // Convert selectedAmount to an integer
    int? amount = int.tryParse(selectedAmount.split('.')[0]); // Extract integer part

    // Search in coinPriceList
    for (var item in coinPriceList) {
      if (item['price'] == amount) {
        amounttodis = item['coins']; // Return coins if price matches
        break; // Stop searching
      }
    }

    if (amounttodis == 0) {
      for (var item in coinPriceListBonus) {
        if (item['price'] == amount) {
          amounttodis = (item['coins']! + (item['bonus'] ?? 0)); // Include bonus coins
          break;
        }
      }
    }
    //submit trx payload
    setState(() {
      remainingTodispenseAm = amounttodis!;
      remainingTodispenseLast = amounttodis;
    });
    var log = """
                Get Status
                OUT: >>> aa 04 01 d1 04 d0 dd
                IN: <<< aa 0c 02 d1 04 3a 1c 04 00 8f 21 0a 00 5d dd
                Total Cash UTD: ${communication.TotalCash_}
                Token Dispense UTD: ${communication.TotalToken_}
                \n\n
               
                """;

    final PaymentPayloadtrx = {
      "commandcode": "DI_SetTransactionEWalletV2",
      "devicecode": deviceCode,
      "data": [
        {
          "machineid": machineId,
          "statusstarttime": Datetime,
          "status": "Payment",
          "eutdcounter": communication.TotalToken_,
          "eamount": selectedAmount,
          "eoriginalamount": selectedAmount,
          "qrcode": "",
          "ewallettransactionid": refId,
          "ewallettypecode": "DUITNOW",
          "numberofinquiry": "0",
          "duration": "0/175",
          "errorcode": "0",
          "errormessage": "",
          "ewallettestusercode": "",
          "slot": "55",
          "responsetime": "1",
          "rssi": "114",
          // "log": log
        }
      ]
    };
    final privateKeyPem = await loadPrivateKey();
    String signature = await generateSignature(jsonEncode(PaymentPayloadtrx), key);
    try {
      final responsePaymentTRXEW = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json', 'Token': Token, 'Signature': signature},
        body: json.encode(PaymentPayloadtrx),
      );

      if (responsePaymentTRXEW.statusCode == 200) {
        print('Transaction:Payment sent successfully');
      } else {
        print('Failed to send payment transaction. Status code: ${responsePaymentTRXEW.statusCode}');
      }
    } catch (err) {
      print('Error during fetch payment trx: $err');
    }

    //success trx
    // print('before send trx success $UTDQR');

    bool resultdis = await sendData(amounttodis!, amount!);
    var log2 = """
                Get Status
                OUT: >>> ${communication.HexGetStatusOUTPrev}
                IN: <<< ${communication.HexGetStatusINPrev}
                Total Cash UTD: ${communication.TotalCashPrev_}
                Token Dispense UTD: ${communication.TotalTokenPrev_}
                \n\n
                QR request dispense
                OUT >>>:  ${communication.HexQrRequestDispenseOUT}
                IN: <<< ${communication.HexQrRequestDispenseIN}
                Allow dispense : ${communication.isAllowed}
                 \n\n
                 
                QR dispense amount ${amounttodis}
                OUT >>>: ${communication.HexQrDispenseOUT}
                IN: <<< ${communication.HexQrDispenseIN}
                Allow dispense : ${communication.isAllowed}
                \n\n
                
                ${communication.AlllogsDispensing}
                
                QR dispense telemetry
                OUT >>>: ${communication.HexQrDispenseTelemetryIN}
                IN: <<< ${communication.HexQrDispenseTelemetryOUT}
                Qr Dispense Counter: ${communication.QrDispenseCounterTel}
                UTD qr Dispense Counter: ${communication.totalUtdQr}
                \n\n
                
                Get Status
                OUT: >>> ${communication.HexGetStatusOUT}
                IN: <<< ${communication.HexGetStatusIN}
                Total Cash UTD: ${communication.TotalCash_}
                Token Dispense UTD: ${communication.TotalToken_}
                """;
    final SuccessPaymentPayloadtrx = {
      "commandcode": "DI_SetTransactionEWalletV2",
      "devicecode": deviceCode,
      "data": [
        {
          "machineid": machineId,
          "statusstarttime": Datetime,
          "status": "Success",
          "eutdcounter": communication.TotalToken_,
          "eamount": selectedAmount,
          "eoriginalamount": selectedAmount,
          "qrcode": "",
          "ewallettransactionid": refId,
          "ewallettypecode": "DUITNOW",
          "numberofinquiry": "0",
          "duration": "0/175",
          "errorcode": "0",
          "errormessage": "",
          "ewallettestusercode": "",
          "slot": "55",
          "responsetime": "1",
          "rssi": "114",
          "log": log2
        }
      ]
    };

    if (resultdis || amounttodis == 0) {
      setState(() {
        FailedDispense = false;
        ClosingCall = false;
        CompletedDispense = true;
      });

      Future.delayed(Duration(seconds: 2), () {
        communication.ResetLogDispensing();
        setState(() {
          ReceivedPayment = false;
          CompletedDispense = false;
          FailedDispense = false;
          ClosingCall = false;
        });
      });

      // fetch success api
      String signature = await generateSignature(jsonEncode(SuccessPaymentPayloadtrx), key);
      try {
        final responseSuccessTRXEW = await http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json', 'Token': Token, 'Signature': signature},
          body: json.encode(SuccessPaymentPayloadtrx),
        );

        if (responseSuccessTRXEW.statusCode == 200) {
          print('Transaction:Success sent successfully');
        } else {
          print('Failed to success transaction. Status code: ${responseSuccessTRXEW.statusCode}');
        }
      } catch (err) {
        print('Error during fetch success trx: $err');
      }
    }

    //failed dispense
    else {
      setState(() {
        FailedDispense = true;
        ClosingCall = false;
      });

      Future.delayed(Duration(seconds: 2), () {
        communication.ResetLogDispensing();
        setState(() {
          ReceivedPayment = true;
          CompletedDispense = false;
          ClosingCall = false;
        });
      });
      //fetch refund api / cancel trx
    }

    // print('closingstatement being called');
  }
  // Core of Code for the program to run !!!!!! END

//mqtt

  late MqttService mqttService;

  Future<void> loadSoldoutStatus() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      latestCashValue = prefs.getInt('latestCashValue') ?? 0;
      isLatestSoldout = prefs.getBool('isLatestSoldout') ?? false;
      isLatestQR = prefs.getBool('isLatestQR') ?? false;
      remainingTodispenseAm = prefs.getInt('remainingtoken') ?? 0;
    });

    print('islatestsoldout : $isLatestSoldout');
    print('isLatestQr : $isLatestQR');
  }

  void ReconnectCom(arr) async {
    LoadingOverlay.show(context);
    List<UsbDevice> devices = [];
    UsbDevice? _device;
    setState(() {
      myStringArray.clear(); // Use addAll directly
    });
    devices = await UsbSerial.listDevices();

    setState(() {
      myStringArray.addAll(devices.map((device) => device)); // Use addAll directly
    });
    try {
      // Ensure the Communication initialization is async and handle errors properly
      communication = await Communication(arr); // Ensure async initialization
      await Future.delayed(Duration(seconds: 3), () {
        if (communication!.isConnected == false) {
          print("Error opening port");

          _showErrorDialog();
        } else {
          _snackBar('Port Connected');
        }
      });
    } catch (e) {
      _showErrorDialog();
      setState(() {
        ErrormsgInitConn = e.toString();
      });
      // Catch and handle any error during the initialization of Communication
      print("Error during communication initialization: $e");
    }

    LoadingOverlay.hide();
  }

  void _snackBar(String text) {
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.15, // Position near the top (15% from the top)
        left: (MediaQuery.of(context).size.width - 300) / 2, // Center horizontally with fixed width
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 300,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.greenAccent[700], // Background color
              borderRadius: BorderRadius.circular(12), // Rounded corners
            ),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white, // Text color
                fontSize: 18, // Larger font size
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    overlay?.insert(overlayEntry);

    // Remove the overlay after 3 seconds
    Future.delayed(Duration(seconds: 3), () {
      overlayEntry?.remove();
    });
  }

// Method to show the error dialog
  void _showErrorDialog() {
    if (context.mounted) {
      // Check if the context is still valid
      _reConnectDialog(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to initialize communication")),
      );
    }
  }

  Future<bool> injection(int injectamt) async {
    final result = await communication?.inject(injectamt);

    if (result?.success == true) {
      // print('after result return ${result!.utdQr.toString()}');
      setState(() {
        UTDQR = result!.utdQr.toString();
      });

      final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);

      final payloadtoken = {
        "commandcode": "RequestToken",
        "devicecode": deviceCode,
        "result": "false",
        "data": [
          {"key": encryptedKey}
        ]
      };
      // final response = await http.get(Uri.parse(apiUrl));
      final responsetoken = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(payloadtoken),
      );

      final injectpayloadresponse = {
        "commandcode": "DI_SetTransactionInjectCredit",
        "devicecode": deviceCode,
        "data": [
          {"statusstarttime": getFormattedDateTime(), "utdremotepaycounter": UTDQR, "remotepayamount": injectamt, "transactionid": trxidinject, "responsetime": "1", "rssi": "-50"}
        ]
      };

      // final privateKeyPem = await loadPrivateKey();

      String signature = await generateSignature(jsonEncode(injectpayloadresponse), key);

      if (responsetoken.statusCode == 200) {
        final responseData = json.decode(responsetoken.body);
        Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
        String token = parsedJson['data'][0]['token'];

        print('request token success $token');
        final responseSetinjectTrx = await http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json', 'Token': token, 'Signature': signature},
          body: json.encode(injectpayloadresponse),
        );
        print('payload inject $injectpayloadresponse');
        print('response inject ${responseSetinjectTrx.body}');
      }
    } else {
      setState(() {
        if (result?.message == '1') {
          // Devicefaulty();
          Errormsg = 'Token is out of Stock';
          // isMachineFaulty = true;
        } else {
          Errormsg = 'Timeout';
        }
      });

      return false;
    }

    return true;
  }

  void mqttConn() async {
    await _loadSavedText();

    mqttService = MqttService(deviceCode: deviceCode);
    mqttService.connect(onMessageReceivedCallback: (message) async {
      try {
        // Parse the JSON string into a Dart object (List<dynamic>)
        List<dynamic> parsedMessage = jsonDecode(message);

        // Loop through each item in the parsed list
        for (var item in parsedMessage) {
          if (item is Map<String, dynamic>) {
            // Extract required fields
            final data = item['data'] ?? {};
            // print('mqtt item : $item');

            if (item['commandcode'] == 'SetPing') {
              String trxid = data['transactionid'];

              final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);

              final payloadtoken = {
                "commandcode": "RequestToken",
                "devicecode": deviceCode,
                "result": "false",
                "data": [
                  {"key": encryptedKey}
                ]
              };

              final responsetoken = await http.post(
                Uri.parse(apiUrl),
                headers: {
                  'Content-Type': 'application/json',
                },
                body: json.encode(payloadtoken),
              );
              // Make the POST request
              print('request token');

              final payloadsetdevice = {
                "commandcode": "SetDeviceInfo",
                "devicecode": deviceCode,
                "data": [
                  {
                    "statusstarttime": getFormattedDateTime(),
                    "esp32version": "1.05",
                    "mdbversion": "MDB-2.01",
                    "displayversion": "MDB-2062",
                    "vmcinterface": "",
                    "coinacceptor": "CLA",
                    "transactionid": trxid,
                    "responsetime": "2",
                    "rssi": "-80"
                  }
                ]
              };

              // Handle the response
              if (responsetoken.statusCode == 200) {
                final responseData = json.decode(responsetoken.body);
                Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
                String token = parsedJson['data'][0]['token'];
                final responseSetDevice = await http.post(
                  Uri.parse(apiUrl),
                  headers: {'Content-Type': 'application/json', 'Token': token},
                  body: json.encode(payloadsetdevice),
                );
              }
            }

            if (item['commandcode'] == 'SetInjectCredit') {
              const List<int> validAmounts = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000];
              print('data inject : $data');

              setState(() {
                trxidinject = data['transactionid'];
              });

              int injectamount = int.tryParse(data['amount'].toString()) ?? 0;

              double damount = (injectamount / 100);
              setState(() {
                injectAmountstr = damount.toStringAsFixed(2);
              });
              injection(damount.toInt());

              print('testing amount inj : $injectamount');
            }

            final referenceId = data['referenceid'] ?? 'Unknown';

            if (referenceId == refId) {
              if (ClosingCall == false) {
                setState(() {
                  ClosingCall = true;
                });
                communication.isCompleteDispense = false; // beta
                closingStatement();
                setState(() {
                  latestCashValue = 0;
                  CompletedDispense = false;
                  ReceivedPayment = true; // Save the generated QR code URL
                });
                await clearFailedTrx();
                print('User has successfully paid');
                break;
              }

              break;
            } else {
              // print('Wrong Reference ID!!!');
            }
          }
        }
      } catch (e) {
        print('Error parsing message: $e');
      }
    });
  }

  void mqttdispose() async {
    // MqttService mqttService = MqttService(deviceCode: deviceCode);
    mqttService.disconnect();
  }

  //COM

  String status = 'Initializing...';
  late Communication communication;
  // Connect to the port once

  Future<bool> sendData(int command, int cashValue) async {
    // call helper function in commnucation.dart
    Result? result = await communication.main(command, cashValue);

    if (result.success == true) {
      print('after result return ${result.utdQr.toString()}');
      setState(() {
        UTDQR = result.utdQr.toString();
      });

      // fix 1.1.8 completed/success but no dispense at all, refund at all cost

      return true;
    } else {
      setState(() {
        if (result.message == '1') {
          Devicefaulty();
          Errormsg = 'Token is out of Stock';
          saveSoldout(true);
          // isMachineFaulty = true;
        } else if (result.message == '2') {
          Errormsg = 'Timeout';
          cancelFetchTRX("Timeout");
        } else {
          Errormsg = 'Timeout';
        }
      });

      return false;
    }
  }

  String generateReferenceId() {
    var prefix = secretKey; // Fixed prefix
    String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return "$prefix$timestamp"; // Concatenate prefix and timestamp
  }

  // Helper function to get month as a string (e.g., "Jan", "Feb", etc.)
  String _getMonthString(int month) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return months[month - 1];
  }

  String encryptPlainText(String deviceCode, String secretKey, String ivString) {
    secretKey = '$secretKey!@#\$';
// Get the current UTC time, add 1 minute and format it
    final now = DateTime.now().toUtc().add(Duration(minutes: 1));
    final formattedTime =
        "${now.year}-${_getMonthString(now.month)}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    // Concatenate the device code and formatted time
    final plainText = '$deviceCode,$formattedTime';

    // Create key and IV objects (ensure they are of the correct size)
    final key = encrypt.Key.fromUtf8(secretKey); // 32-byte key for AES-256
    final iv = encrypt.IV.fromUtf8(ivString); // 16-byte IV for AES

    // Configure AES with CBC mode and PKCS7 padding
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));

    // Encrypt the plaintext
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // Return the encrypted text in Base64 format
    return encrypted.base64;
  }

  // Function create failed transaction for refund if 255 (for TB Internal use validation) START
  Future<void> cancelFetchTRX(String errorMsg) async {
    String statustype = "";
    if (errorMsg == "Timeout") {
      statustype = "Payment";
    } else if (errorMsg == "Qr timeout") {
      statustype = "Submit";
    } else if (errorMsg == "User Cancelled") {
      statustype = "Submit";
    } else {
      statustype = "Submit";
    }

    var log = """
                ${communication.AlllogsGetStatus}
                \n\n
                QR request dispense
                OUT >>>:  ${communication.HexQrRequestDispenseOUT}
                IN: <<< ${communication.HexQrRequestDispenseIN}
                Allow dispense : ${communication.isAllowed}
                 \n\n
                 
                QR dispense amount ${selectedAmount}
                OUT >>>: ${communication.HexQrDispenseOUT}
                IN: <<< ${communication.HexQrDispenseIN}
                Allow dispense : ${communication.isAllowed}
                \n\n
                
                ${communication.AlllogsDispensing}
                
                QR dispense telemetry
                OUT >>>: ${communication.HexQrDispenseTelemetryIN}
                IN: <<< ${communication.HexQrDispenseTelemetryOUT}
                Qr Dispense Counter: ${communication.QrDispenseCounterTel}
                UTD qr Dispense Counter: ${communication.totalUtdQr}
                \n\n
                              
                Get Status
                OUT: >>> ${communication.HexGetStatusOUT}
                IN: <<< ${communication.HexGetStatusIN}
                Total Cash UTD: ${communication.TotalCash_}
                Token Dispense UTD: ${communication.TotalToken_}
                """;

    final setDeviceError = {
      "commandcode": "SetDeviceError",
      "devicecode": deviceCode,
      "data": [
        {
          "deviceerrorcode": 3,
          "description": "Timeout! Remaining token: ${remainingTodispenseAm}",
          "errorstart": getFormattedDateTime(),
          "errorend": "1900-JAN-01 00:00:00",
          "rssi": "-99",
          "log": log,
        }
      ]
    };

    final privateKeyPem = await loadPrivateKey();
    final payloadcanceltrx = {
      "commandcode": "DI_SetTransactionEWalletV2",
      "devicecode": deviceCode,
      "data": [
        {
          "statusstarttime": getFormattedDateTime(),
          "machineid": machineId,
          "status": statustype,
          "eutdcounter": selectedAmount,
          "eamount": selectedAmount,
          "eoriginalamount": selectedAmount,
          "discount": "0",
          "discountentitlementamount": "0.00",
          "qrcode": "",
          "ewallettransactionid": refId,
          "ewallettypecode": "DUITNOW",
          "numberofinquiry": "0",
          "duration": "0/175",
          "errorcode": "255",
          "errormessage": errorMsg,
          "ewallettestusercode": "",
          "responsetime": "2",
          "rssi": rssi
        }
      ]
    };
    String signature = await generateSignature(jsonEncode(payloadcanceltrx), key);
    try {
      final responseTRXEW = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json', 'Token': Token, 'Signature': signature},
        body: json.encode(payloadcanceltrx),
      );

      if (responseTRXEW.statusCode == 200) {
        // print('Transaction cancelled successfully');

        if (errorMsg == 'Timeout') {
          final responseSetDeviceError = await http.post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json', 'Token': Token, 'Signature': signature},
            body: json.encode(setDeviceError),
          );
          communication.ResetLogDispensing();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Refund request successfully sent ✅. Processing time may vary—please check your e-wallet within 24 hours."),
              duration: Duration(seconds: 6), // Set duration to 5 minutes
            ),
          );
        }
      } else {
        print('Failed to cancel transaction. Status code: ${responseTRXEW.statusCode}');
      }
    } catch (err) {
      print('Error during fetch cancel trx: $err');
    }
  }
  // Function create failed transaction for refund if 255 (for TB Internal use validation) END

  Future<void> handleButtonPress({
    required BuildContext context,
    required String amount,
    required String currency,
    required Function setLoading,
  }) async {
    String referenceId = generateReferenceId();

    // print('qr started');
    try {
      setLoading(true);

      final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);

      final payloadtoken = {
        "commandcode": "RequestToken",
        "devicecode": deviceCode,
        "result": "false",
        "data": [
          {"key": encryptedKey}
        ]
      };
      // final response = await http.get(Uri.parse(apiUrl));
      final responsetoken = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(payloadtoken),
      );
      // Make the POST request
      print('request token');
      // Handle the response
      if (responsetoken.statusCode == 200) {
        final responseData = json.decode(responsetoken.body);
        Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
        String token = parsedJson['data'][0]['token'];

        print('request token success');
        setState(() {
          Token = token; // Save the generated QR code URL
        });

        final payload = {
          "commandcode": "DI_GetDynamicQR",
          "devicecode": deviceCode,
          "result": "false",
          "data": [
            {"referenceid": referenceId, "eamount": selectedAmount, "validityduration": "120", "rssi": "-39"}
          ]
        };

        final privateKeyPem = await loadPrivateKey();

        String signature = await generateSignature(jsonEncode(payload), key);
        // print('request qr');
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json', 'Token': token, 'Signature': signature},
          body: json.encode(payload),
        );
        //
        final QrResponseData = json.decode(response.body);
        // print('get the data QR : $QrResponseData');
        Map<String, dynamic> qrparsedJson = jsonDecode(response.body);
        String qrcode = qrparsedJson['data'][0]['qrcode'] ?? null;
        String refid = qrparsedJson['data'][0]['referenceid'] ?? null;
        String result = qrparsedJson['result'];
        String errormsg = '';
        errormsg = qrparsedJson['data'][0]['errormessage'];

        setState(() {
          qrCodeImageUrl = qrcode; // Save the generated QR code URL
          qrCompanyname = extractCompanyName(qrcode);
        });

        if (result == false && errormsg.isNotEmpty) {
          setState(() {
            Errormsg = errormsg;
          });
        } else {
          {
            setState(() {
              Errormsg = '';
            });
          }
        }
        setState(() {
          refId = refid; // Save the generated QR code URL
        });

        var log = """
                Get Status
                OUT: >>> aa 04 01 d1 04 d0 dd
                IN: <<< aa 0c 02 d1 04 3a 1c 04 00 8f 21 0a 00 5d dd
                Total Cash UTD: ${communication.TotalCash_}
                Token Dispense UTD: ${communication.TotalToken_}
                """;

        final SetTrxEWpayload = {
          "commandcode": "DI_SetTransactionEWalletV2",
          "devicecode": deviceCode,
          "data": [
            {
              "statusstarttime": getFormattedDateTime(),
              "machineid": "TCN Office",
              "status": "Submit",
              "eutdcounter": communication.TotalToken_,
              "eamount": amount,
              "eoriginalamount": amount,
              "discount": "0",
              "discountentitlementamount": "0.00",
              "qrcode": "",
              "ewallettransactionid": refid,
              "ewallettypecode": "DUITNOW",
              "numberofinquiry": "0",
              "duration": "0/145",
              "errorcode": "0",
              "errormessage": "",
              "ewallettestusercode": "",
              "responsetime": "2",
              "rssi": "-39",
              // "log": log
            }
          ]
        };

        if (qrcode != null) {
          final responseTRXEW = http.post(
            Uri.parse(apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Token': token,
            },
            body: json.encode(SetTrxEWpayload),
          );

          final TRXEWResponseData = json.decode(response.body);
        } else {
          print('TRXEW error: no QR');
          setState(() {
            qrCodeImageUrl = null; // Save the generated QR code URL
          });
        }

        // Show a success message or handle response data
      } else {
        setState(() {
          qrCodeImageUrl = null; // Save the generated QR code URL
        });
        print('Failed: ${responsetoken.statusCode}, ${responsetoken.body}');
        // Show an error message or handle the failure
      }
    } catch (e) {
      print('Error fetch: $e');
      setState(() {
        qrCodeImageUrl = null; // Save the generated QR code URL
      });
      // Show a network error message
    } finally {
      // Hide the loading indicator
      setLoading(false);

      // Show popup after API call
      showPopup(context);
    }
  }

  Future<List<String>> _loadPresetBackgrounds() async {
    final prefs = await SharedPreferences.getInstance();
    return presetKeys.map((key) {
      return prefs.getString(key) ?? 'assets/images/bg${presetKeys.indexOf(key) + 1}.jpg';
    }).toList();
  }

  Future<String?> _uploadImageForSlot(BuildContext context, int slotIndex) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      String filePath = result.files.single.path!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(presetKeys[slotIndex], filePath);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Background ${slotIndex + 1} updated!')));
      return filePath;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No image selected.')));
      return null;
    }
  }

  Future<void> _saveCustomNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('background_custom_names', _customNames);
  }

  void _showBackgroundImageSettingDialog(BuildContext context) async {
    List<String> presetBackgrounds = await _loadPresetBackgrounds();
    await _loadCustomNames();

    double previewScale = _currentScale;
    double previewOffsetY = _backgroundOffsetY;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                  maxWidth: MediaQuery.of(context).size.width * 0.6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title with Close
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Select Background', style: Theme.of(context).textTheme.titleLarge),
                          IconButton(
                            icon: Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Scrollable content (background list and reset)
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            ...List.generate(5, (index) {
                              String bgPath = presetBackgrounds[index];
                              return Column(
                                children: [
                                  ListTile(
                                    leading: bgPath.startsWith('assets/')
                                        ? Image.asset(bgPath, width: 50, height: 50, fit: BoxFit.cover)
                                        : Image.file(File(bgPath), width: 50, height: 50, fit: BoxFit.cover),
                                    title: Text(_customNames[index].isEmpty ? 'Background ${index + 1}' : _customNames[index]),
                                    trailing: IconButton(
                                      icon: Icon(Icons.upload_file),
                                      onPressed: () async {
                                        final path = await _uploadImageForSlot(context, index);
                                        if (path != null) {
                                          setState(() {
                                            presetBackgrounds[index] = path;
                                          });
                                        }
                                      },
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedImagePath = bgPath;
                                        _dragOffset = 0.0;
                                        _backgroundOffsetY = 0.0; // FINAL position
                                        _backgroundOffsetX = 0.0; // FINAL position
                                        _previewOffsetY = 0.0; // Used inside dialog
                                        _currentScale = 1.0; // FINAL scale
                                        _previewScale = 1.0; // Used inside dialog
                                      });
                                    },
                                  ),
                                  if (_selectedImagePath == bgPath)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: TextField(
                                        decoration: InputDecoration(
                                          labelText: 'Rename Background ${index + 1}',
                                          isDense: true,
                                        ),
                                        controller: TextEditingController(
                                          text: _customNames[index],
                                        ),
                                        onChanged: (value) {
                                          _customNames[index] = value;
                                          _saveCustomNames();
                                        },
                                      ),
                                    ),
                                  SizedBox(height: 12),
                                ],
                              );
                            }),
                            Divider(),
                            ListTile(
                              leading: Icon(Icons.restore),
                              title: Text('Reset Current Background to Default'),
                              onTap: () async {
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setString('background_image', 'assets/images/bg.jpg');

                                setState(() {
                                  _backgroundImagePath = 'assets/images/bg.jpg';
                                  _selectedImagePath = 'assets/images/bg.jpg';
                                  _dragOffset = 0.0;
                                  _backgroundOffsetY = 0.0; // FINAL position
                                  _backgroundOffsetX = 0.0; // FINAL position
                                  _previewOffsetY = 0.0; // Used inside dialog
                                  _currentScale = 1.0; // FINAL scale
                                  _previewScale = 1.0; // Used inside dialog
                                  _controllerzoom.value = Matrix4.identity();
                                });
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Background reset to default.')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Animated Preview section (only if image selected)
                    AnimatedSize(
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _selectedImagePath.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Column(
                                children: [
                                  Text("Preview & Adjust", style: Theme.of(context).textTheme.titleMedium),
                                  SizedBox(height: 8),
                                  Container(
                                    height: 500,
                                    width: double.infinity,
                                    color: Colors.black12,
                                    child: InteractiveViewer(
                                      transformationController: _controllerzoom,
                                      panEnabled: true, // allow dragging
                                      scaleEnabled: true, // allow zooming
                                      minScale: 0.5,
                                      maxScale: 3.0,
                                      boundaryMargin: EdgeInsets.all(double.infinity), // allow full movement
                                      child: Container(
                                        height: 500,
                                        width: double.infinity,
                                        alignment: Alignment.topCenter,
                                        clipBehavior: Clip.none,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                        ),
                                        child: _selectedImagePath.startsWith('assets/')
                                            ? Image.asset(
                                                _selectedImagePath,
                                                fit: BoxFit.fitWidth,
                                                alignment: Alignment.topCenter,
                                                width: double.infinity,
                                              )
                                            : Image.file(
                                                File(_selectedImagePath),
                                                fit: BoxFit.fitWidth,
                                                alignment: Alignment.topCenter,
                                                width: double.infinity,
                                              ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      _setBackground(_selectedImagePath);
                                      Navigator.pop(context);
                                    },
                                    icon: Icon(Icons.check),
                                    label: Text("Confirm"),
                                  ),
                                ],
                              ),
                            )
                          : SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPasswordDialog(BuildContext context) {
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing the dialog when clicking outside1
      builder: (context) {
        String contentMessage = "Enter Password";
        bool isPasswordFieldVisible = true; // Controls whether the password field is visible
        bool isShowTextVar = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return Stack(
              children: [
                AlertDialog(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isPasswordFieldVisible ? 'Authentication' : 'Setting'),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () {
                          Navigator.pop(context); // Close the dialog
                        },
                      ),
                    ],
                  ),
                  content: isPasswordFieldVisible
                      ? TextField(
                          controller: passwordController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(hintText: "Password"),
                        )
                      : SizedBox(
                          width: 350, // Set a fixed width
                          height: 500, // Set a fixed height
                          child: Stack(
                            children: [
                              // Port Setting button
                              Positioned(
                                top: 20, // Position it 50 pixels from the top
                                left: 0, // Align to the left
                                right: 0, // Align to the right
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (!isShowTextVar) {
                                      _loadSavedText();
                                      setState(() {
                                        isShowTextVar = true;
                                      });
                                    } else {
                                      setState(() {
                                        isShowTextVar = false;
                                      });
                                    }
                                    // Port setting logic
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent, // Set button background color
                                    minimumSize: Size(120, 50), // Set button size (width, height)
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12), // Rounded corners
                                    ),
                                  ),
                                  child: Text(
                                    'Tips Variable',
                                    style: TextStyle(
                                      color: Colors.white, // Text color
                                      fontSize: 16, // Text size
                                      fontWeight: FontWeight.bold, // Text weight
                                    ),
                                  ),
                                ),
                              ),
                              if (!isShowTextVar)
                                Positioned(
                                  top: 80, // Position it 50 pixels from the top
                                  left: 0, // Align to the left
                                  right: 0, // Align to the right
                                  child: ElevatedButton(
                                    onPressed: () {
                                      // Port setting logic
                                      _showErrorDialog(); //port recon
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent, // Set button background color
                                      minimumSize: Size(120, 50), // Set button size (width, height)
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12), // Rounded corners
                                      ),
                                    ),
                                    child: Text(
                                      'Port Connection (Testing)',
                                      style: TextStyle(
                                        color: Colors.white, // Text color
                                        fontSize: 16, // Text size
                                        fontWeight: FontWeight.bold, // Text weight
                                      ),
                                    ),
                                  ),
                                ),
                              // Port Setting button

                              if (!isShowTextVar)
                                Positioned(
                                  top: 140, // Position it 50 pixels from the top
                                  left: 0, // Align to the left
                                  right: 0, // Align to the right
                                  child: ElevatedButton(
                                    onPressed: () {
                                      // Port setting logic
                                      // _loadSavedText();
                                      _showDeviceConfigModal(context);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent, // Set button background color
                                      minimumSize: Size(120, 50), // Set button size (width, height)
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12), // Rounded corners
                                      ),
                                    ),
                                    child: Text(
                                      'Device Setting',
                                      style: TextStyle(
                                        color: Colors.white, // Text color
                                        fontSize: 16, // Text size
                                        fontWeight: FontWeight.bold, // Text weight
                                      ),
                                    ),
                                  ),
                                ),

                              if (!isShowTextVar)
                                Positioned(
                                  top: 200, // Position it 50 pixels from the top
                                  left: 0, // Align to the left
                                  right: 0, // Align to the right
                                  child: ElevatedButton(
                                    onPressed: () {
                                      // Port setting logic
                                      _showListModal(context);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent, // Set button background color
                                      minimumSize: Size(120, 50), // Set button size (width, height)
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12), // Rounded corners
                                      ),
                                    ),
                                    child: Text(
                                      'Coins Setting',
                                      style: TextStyle(
                                        color: Colors.white, // Text color
                                        fontSize: 16, // Text size
                                        fontWeight: FontWeight.bold, // Text weight
                                      ),
                                    ),
                                  ),
                                ),

                              if (!isShowTextVar)
                                Positioned(
                                  top: 260,
                                  left: 0,
                                  right: 0,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      _showBackgroundImageSettingDialog(context);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent,
                                      minimumSize: Size(120, 50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      'Background Setting',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              if (!isShowTextVar)
                                Positioned(
                                  top: 320, // Position it 50 pixels from the top
                                  left: 0, // Align to the left
                                  right: 0, // Align to the right
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      // Port setting logic
                                      if (_antiSpamButton == false) {
                                        checkForUpdate(context);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent, // Set button background color
                                      minimumSize: Size(120, 50), // Set button size (width, height)
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12), // Rounded corners
                                      ),
                                    ),
                                    child: Text(
                                      'Check Update',
                                      style: TextStyle(
                                        color: Colors.white, // Text color
                                        fontSize: 16, // Text size
                                        fontWeight: FontWeight.bold, // Text weight
                                      ),
                                    ),
                                  ),
                                ),

                              Positioned(
                                top: 115, // Position it 50 pixels from the top
                                left: 0, // Align to the left
                                right: 0, // Align to the right
                                child: Column(
                                  children: [
                                    if (isShowTextVar) ...[
                                      // Display the saved text

                                      // TextField to input new text
                                      TextField(
                                        controller: _controller,
                                        maxLines: 6, // Set to allow 5 lines of text (adjust as needed)
                                        decoration: InputDecoration(
                                          labelText: 'Enter Text',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      SizedBox(height: 20),

                                      // Save Button
                                      ElevatedButton(
                                        onPressed: () {
                                          if (_controller.text.isNotEmpty) {
                                            setState(() {
                                              isShowTextVar = false;
                                            });
                                            _saveText(_controller.text); // Save the entered text
                                            _controller.clear(); // Clear the TextField
                                            _snackBar('Text Saved!');
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          minimumSize: Size(double.infinity, 50), // Full width, fixed height
                                        ),
                                        child: Text(
                                          'Save',
                                          style: TextStyle(color: Colors.white, fontSize: 16),
                                        ),
                                      ),
                                    ] else ...[
                                      // Optional content to show when isShowTextVar is false
                                      Text(
                                        '',
                                        style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              if (!isShowTextVar)
                                Positioned(
                                  top: 375, // Position it 320 pixels from the top
                                  left: 0, // Align to the left
                                  right: 0, // Align to the right
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20.0), // Add horizontal padding
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mqttConnected ? 'MQTT: Connected' : 'MQTT: Disconnected',
                                          style: TextStyle(
                                            fontSize: 14.0,
                                            color: Colors.black.withOpacity(0.6),
                                          ),
                                        ),
                                        SizedBox(height: 4.0), // Space between status texts
                                        Text(
                                          communication.isConnected ? 'Port: Connected' : 'Port: Disconnected',
                                          style: TextStyle(
                                            fontSize: 14.0,
                                            color: Colors.black.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (!isShowTextVar)
                                // Exit App button
                                Positioned(
                                  bottom: 0, // Position it 50 pixels from the bottom
                                  left: 0, // Align to the left
                                  right: 0, // Align to the right
                                  child: SizedBox(
                                    width: double.infinity, // Full width of the parent container
                                    height: 50, // Fixed height
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        SystemNavigator.pop(); // Exit app
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red, // Background color
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12), // Rounded corners
                                        ),
                                      ),
                                      child: Text(
                                        'Exit App',
                                        style: TextStyle(
                                          color: Colors.white, // Text color
                                          fontSize: 16, // Text size
                                          fontWeight: FontWeight.bold, // Text weight
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                  actions: [
                    if (isPasswordFieldVisible)
                      TextButton(
                        onPressed: () {
                          if (passwordController.text == "168168") {
                            // Correct password, update the dialog content
                            setState(() {
                              isPasswordFieldVisible = false;
                              contentMessage = "Access Granted!"; // Update the message
                            });
                          } else {
                            // Incorrect password
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Incorrect password')),
                            );
                            setState(() {
                              contentMessage = "Enter Password"; // Reset the message
                              isPasswordFieldVisible = true;
                            });
                          }
                        },
                        child: Text('Submit'),
                      ),
                    if (!isPasswordFieldVisible)
                      TextButton(
                        onPressed: () {
                          if (isShowTextVar) {
                            setState(() {
                              isShowTextVar = false;
                            });
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        child: Text(isShowTextVar ? 'Back' : 'Exit Setting'),
                      ),
                  ],
                )
              ],
            );
          },
        );
      },
    );
  }

//booting
  void _reConnectDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing the dialog when clicking outside
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Could not connect to the default port. Please choose an available port.',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min, // Ensures the dialog fits content
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Display error messages with better formatting
              Text(
                "Initialize Error: $ErrormsgInitConn\n\nConnection Error: $ErrormsgConn",
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16), // Add spacing between text and dropdown
              // Dropdown for selecting available ports
              DropdownButtonFormField<String>(
                value: selectedPort?.deviceName, // Display the selected device name
                hint: const Text("Select a port"),
                items: myStringArray.map((device) {
                  return DropdownMenuItem<String>(
                    value: device.deviceName,
                    child: Text(device.deviceName ?? "Unknown Device"),
                  );
                }).toList(),
                onChanged: (String? newPort) {
                  setState(() {
                    // Update the selected port
                    selectedPort = myStringArray.firstWhere(
                      (device) => device.deviceName == newPort,
                      orElse: () => null as UsbDevice, // Return null if no matching device is found
                    );
                    print("Selected Port: ${selectedPort?.deviceName}");
                  });
                },
              ),
            ],
          ),
          actions: [
            // "Connect" button
            TextButton(
              onPressed: () {
                if (selectedPort != null) {
                  // Attempt to reconnect with the selected port
                  ReconnectCom(selectedPort!);
                  Navigator.pop(context); // Close the dialog
                } else {
                  // Show a warning if no port is selected
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please select a valid port.")),
                  );
                }
              },
              child: const Text('Connect'),
            ),
            // "Cancel" button
            TextButton(
              onPressed: () => Navigator.pop(context), // Close the dialog
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  // Function to show modal popup
  void showPopup(BuildContext context) {
    int countdown = 60; // Initial countdown value
    Timer? timer;

    // Function to start the countdown
    void startCountdown(StateSetter setState) {
      timer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (countdown > 0) {
          setState(() {
            countdown--; // Update countdown and rebuild UI
          });
        } else {
          timer.cancel();
          Navigator.of(context).pop(); // Close the modal when countdown reaches 0

          cancelFetchTRX("Qr timeout");
        }
      });
    }

    // Show password dialog before exiting

    showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing the dialog when clicking outside
      builder: (BuildContext context) {
        double screenWidth = MediaQuery.of(context).size.width; // Get screen width
        double screenHeight = MediaQuery.of(context).size.height;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            // Start the countdown when the dialog is built
            if (timer == null) {
              startCountdown(setState);
            }

            if (ReceivedPayment) {
              timer?.cancel(); // Cancel the timer if the payment is received
              Navigator.of(context).pop(); // Close the modal
            }

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 130),
              contentPadding: EdgeInsets.zero,
              titlePadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0), // Adjust radius here
              ),
              content: SizedBox(
                width: 650, // Set a fixed width
                height: 1300, // Set a fixed height
                child: Stack(
                  children: [
                    // Positioned title from the top
                    Positioned(
                      top: 50, // Position it from the top
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Payment amount (MYR)',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center, // Center text
                        ),
                      ),
                    ),
                    // Positioned amount below the title
                    Positioned(
                      top: 70, // Adjust the space from the title
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          selectedAmount,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                          textAlign: TextAlign.center, // Center text
                        ),
                      ),
                    ),
                    Positioned(
                      top: 140, // Adjust the space from the title
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Image.asset(
                          'assets/images/duitnowlogo.png', // Replace with your logo path
                          height: 80, // Adjust logo height
                          width: 80, // Adjust logo width
                          fit: BoxFit.contain, // Adjust image fit
                        ),
                      ),
                    ),

                    Positioned(
                      top: 220, // Position it from the top
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'QR',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center, // Center text
                        ),
                      ),
                    ),
                    // Countdown timer at the top-left corner
                    Positioned(
                      top: 14,
                      left: 16,
                      child: Text(
                        'Closing in $countdown s',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    // Close button at the top-right corner
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.black),
                        onPressed: () {
                          timer?.cancel(); // Stop the countdown timer
                          Navigator.of(context).pop(); // Close the modal
                          cancelFetchTRX("User Cancelled");
                        },
                      ),
                    ),

                    // Positioned QR image at the bottom of the dialog
                    Positioned(
                      top: 195, // Position the image at the bottom
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(15.0), // Adjust the margin around the image
                        child: Align(
                          alignment: Alignment.bottomCenter, // Align the image to the bottom and center
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: 30), // You can adjust the height as needed
                              Container(
                                margin: const EdgeInsets.only(bottom: 5.0), // Extra margin from the bottom if needed
                                child: Text(
                                  qrCompanyname,
                                  style: TextStyle(
                                    color: const Color(0xFFE52561),
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              // QR code container
                              Container(
                                margin: const EdgeInsets.only(bottom: 40.0), // Extra margin from the bottom if needed
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE52561), // Border color (same pinkish-red color)
                                    width: 10.0, // Border width
                                  ),
                                  borderRadius: BorderRadius.circular(8.0), // Optional: Rounded corners
                                ),
                                padding: const EdgeInsets.all(8.0), // Optional: Padding inside the border
                                child: qrCodeImageUrl != null
                                    ? QrImageView(
                                        data: qrCodeImageUrl ?? 'default_fallback_value',
                                        version: QrVersions.auto,
                                        size: 530,
                                        gapless: false,
                                        foregroundColor: const Color(0xFFE52561), // QR code color
                                      )
                                    : Column(children: [
                                        Image.asset(
                                          'assets/images/errorpage.png', // Replace with your image path
                                          height: 525, // Adjust dynamically based on screen height
                                          width: 500, // Center the image and set the width
                                        ),
                                        Text(
                                          Errormsg,
                                          style: TextStyle(
                                            color: const Color(0xFFE52561),
                                            fontSize: 16.0,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ]),
                              ),

                              // Rectangle with "Scan code to pay"
                              Transform.translate(
                                offset: const Offset(0, -30), // Move the container 10 units up (negative Y value)
                                child: Container(
                                  width: 575, // Adjust width
                                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 18.0), // Reduce left and right padding to 20
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE52561), // Pinkish red background
                                    borderRadius: BorderRadius.circular(8.0), // Optional: Rounded corners
                                  ),
                                  child: Text(
                                    'Scan code to pay',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 32.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),

                              // Row of 3 small logos

                              Transform.translate(
                                offset: const Offset(0, 10), // Move the Row 10 units up (negative Y value)
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/images/halolomerchantlist.png', // Replace with logo 1 image path
                                      height: 300.0, // Small size for the logos
                                      width: 525.0,
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      timer?.cancel(); // Ensure the timer is canceled when the dialog is closed
    });
  }

  Widget _buildCoinButton({
    required BuildContext context,
    required int coins,
    required String amount,
    String? cashPromoTitle,
    String? cashPromoText,
    String? promoTitle,
    String? description,
    required bool isSpecialOffer,
    required bool isCashOffer,
    int? bonus, // Optional for special offers
  }) {
    return SizedBox(
      width: isSpecialOffer
          ? 620
          : isCashOffer
              ? 725
              : 300, // Special offer takes double width
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            selectedAmount = amount;
            selectedAmountCoin = coins;
          });
          if (isCashOffer == false) {
            handleButtonPress(
              context: context,
              amount: amount,
              currency: 'MYR',
              setLoading: (value) {
                setState(() {
                  isLoading = value;
                });
              },
            );
          }
        },
        style: ElevatedButton.styleFrom(
          minimumSize: Size(275, 200),
          backgroundColor: isSpecialOffer
              ? bonusColor
              : isCashOffer
                  ? cashColor
                  : regularColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.all(isSpecialOffer
              ? 24
              : isCashOffer
                  ? 24
                  : 16), // More padding for special offer
        ),
        child: Text.rich(
          TextSpan(
            children: [
              if (isSpecialOffer) ...[
                TextSpan(
                  text: '$promoTitle\n',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
              if (isCashOffer) ...[
                TextSpan(
                  text: '$cashPromoTitle\n$cashPromoText\n',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
              TextSpan(
                text: '$coins ',
                style: TextStyle(
                  fontSize: 50,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Arial',
                  color: isSpecialOffer
                      ? Colors.white
                      : isCashOffer
                          ? Colors.white
                          : Color(0xFF8F301E),
                ),
              ),
              TextSpan(
                text: 'Coins\nMYR $amount',
                style: TextStyle(
                  fontSize: 45,
                  fontWeight: FontWeight.normal,
                  color: isSpecialOffer
                      ? Colors.white70
                      : isCashOffer
                          ? Colors.white70
                          : Color(0xFF8F301E),
                ),
              ),
              if (isSpecialOffer && bonus != null && bonus > 0) ...[
                TextSpan(
                  text: '\n+ Bonus $bonus Coins 🎁',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.yellowAccent,
                  ),
                ),
              ],
              if (isCashOffer && bonus != null && bonus > 0) ...[
                TextSpan(
                  text: '\n+ Bonus $bonus Coins 🎁',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.yellowAccent,
                  ),
                ),
              ],
              if (isCashOffer) ...[
                TextSpan(
                  text: '\n$description',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.yellowAccent,
                  ),
                ),
              ],
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width; // Get screen width
    double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          // Background Image covering 45% of the screen height
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Transform(
              transform: Matrix4.identity()
                ..translate(_backgroundOffsetX, _backgroundOffsetY) // Apply both X and Y offsets
                ..scale(_currentScale),
              alignment: Alignment.topCenter,
              child: _selectedImagePath.startsWith('assets/') ? Image.asset(_selectedImagePath, fit: BoxFit.cover) : Image.file(File(_selectedImagePath), fit: BoxFit.cover),
            ),
          ),

          // Main Container covering the remaining screen height
          Positioned(
            top: screenHeight * 0.30, // Start 40% from top to avoid overlap
            left: 0,
            right: 0,
            child: Container(
              width: screenWidth,
              height: screenHeight * 0.7, // Adjusted to take the remaining space
              padding: const EdgeInsets.all(10.0), // Padding inside the container
              margin: const EdgeInsets.all(1.0), // Margin around the container
              decoration: BoxDecoration(
                color: Colors.white, // Background color
                borderRadius: BorderRadius.circular(16.0), // Rounded corners
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45, // Shadow color
                    offset: Offset(0, 0), // No offset, so the shadow is centered around the widget
                    blurRadius: 0.5, // Blur radius to make the shadow smooth
                    spreadRadius: 0.5, // Optional: Adds a bit of spread to make the shadow larger
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Description inside the container
                  const Text(
                    'Coin Purchase Package',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8F301E),
                      fontFamily: 'Arial', // Apply Arial-like font
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select the Package or insert cash to pay, the coin will be dispensed once the payment is done.',
                    style: TextStyle(
                      fontSize: 26,
                      color: Color(0xFF8F301E),
                      fontFamily: 'Arial', // Apply Arial-like font
                    ),
                  ),
                  const SizedBox(height: 30), // Add space between description and content below
                  Center(
                      child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      // Regular Coins
                      ...coinPriceList.map((item) {
                        String amount = item['price']!.toStringAsFixed(2);
                        return _buildCoinButton(
                          context: context,
                          coins: item['coins'] ?? 0,
                          amount: amount,
                          isSpecialOffer: false,
                          isCashOffer: false,
                        );
                      }).toList(),

                      // Bonus Coins
                      ...coinPriceListBonus.where((item) => item['coins']! > 0 && item['price']! > 0).map((item) {
                        String amount = item['price']!.toStringAsFixed(2);
                        return _buildCoinButton(
                          context: context,
                          coins: item['coins'] ?? 0,
                          amount: amount,
                          isSpecialOffer: true, // Apply special offer style
                          isCashOffer: false,
                          bonus: item['bonus'], // Pass the bonus value
                          promoTitle: item['promoTitle'],
                        );
                      }).toList(),
                    ],
                  )),
                  const SizedBox(height: 15), // Add space between description and content below
                  Center(
                    child: Column(
                      children: coinPriceListNonQr.where((item) => item['coins']! > 0 && item['price']! > 0).map((item) {
                        String amount = item['price']!.toStringAsFixed(2); // Ensure correct format

                        return _buildCoinButton(
                            context: context,
                            coins: item['coins'] ?? 0,
                            amount: amount,
                            isSpecialOffer: false, // Apply special offer style
                            isCashOffer: true,
                            bonus: item['bonus'], // Pass the bonus value
                            cashPromoTitle: item['cashPromoTitle'],
                            cashPromoText: item['cashPromoText'],
                            description: item['desc']);
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 100),
                  Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Warm Tips',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontFamily: 'Arial',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _savedText.isEmpty ? '' : _savedText,
                          // '1. Once the coins are dispensed, no refund request will be accepted.',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontFamily: 'Arial',
                          ),
                        ),
                        const Text(
                          '',
                          // '2. Any question feel free to contact: 0173990160.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontFamily: 'Arial',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Stack(
            children: [
              Positioned(
                top: 20.0, // Adjust the position as needed
                left: 100.0,
                child: Opacity(
                  opacity: 1, // Fully transparent but still interactive
                  child: TextButton(
                    onPressed: () {
                      handleAdminButtonClick(context);
                    },
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$machineId ',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black), // Bold text
                          ),
                          TextSpan(
                            text: 'V$currentVersion',
                            style: TextStyle(color: Colors.black), // Colored text
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Circle Icon for Internet Connection Status
              Positioned(
                top: 20.0, // Adjust the vertical position as needed
                left: 20.0, // Adjust the horizontal position
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 20.0, // Circle width
                          height: 30.0, // Circle height
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isConnected ? Colors.green : Colors.red).withOpacity(0.6), // Add opacity
                          ),
                        ),
                        SizedBox(width: 8.0), // Add some spacing between the circle and the text
                        Text(
                          isConnected ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 16.0, // Adjust font size for the text
                            fontWeight: FontWeight.bold, // Bold text
                            color: Colors.black.withOpacity(0.6), // Text color
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Loading overlay
          if (ReceivedPayment)
            Container(
              color: Colors.black.withOpacity(0.5), // Semi-transparent background
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20), // Add padding inside the box
                  decoration: BoxDecoration(
                    color: Colors.white, // White background for the box
                    borderRadius: BorderRadius.circular(12), // Rounded corners
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Ensures the content takes minimum space
                    crossAxisAlignment: CrossAxisAlignment.center, // Center the content horizontally
                    children: [
                      // Use AnimatedOpacity to animate the checkmark icon
                      AnimatedOpacity(
                        opacity: ReceivedPayment ? 1.0 : 0,
                        duration: const Duration(milliseconds: 1000), // Animation duration
                        child: Icon(
                          CompletedDispense == false && FailedDispense == true ? Icons.cancel : Icons.check_circle_outline,
                          color: CompletedDispense == false && FailedDispense == true ? Colors.red : Colors.green, // Green color for success
                          size: 50, // Icon size
                        ),
                      ),
                      const SizedBox(height: 32), // Space between the progress indicator and text
                      if (CompletedDispense == false && FailedDispense == false)
                        const Text(
                          'Payment Received',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const SizedBox(height: 16), // Space between the progress indicator and text
                      if (CompletedDispense == false && FailedDispense == false)
                        Text(
                          'Please wait, Dispensing token... \nRemaining Token : $remainingTodispenseAm',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (CompletedDispense == true && FailedDispense == false)
                        const Text(
                          'Completed! Thank You',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (CompletedDispense == false && FailedDispense == true)
                        Text(
                          'Dispense is Failed, ' + Errormsg,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (isLoading)
            Container(
              color: Colors.black.withOpacity(0.5), // Semi-transparent background
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20), // Add padding inside the box
                  decoration: BoxDecoration(
                    color: Colors.white, // White background for the box
                    borderRadius: BorderRadius.circular(12), // Rounded corners
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Ensures the content takes minimum space
                    crossAxisAlignment: CrossAxisAlignment.center, // Center the content horizontally
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue), // You can change the color
                      ),
                      const SizedBox(height: 16), // Space between the progress indicator and text
                      const Text(
                        'Please wait, generating QR code...',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (isLoadingboot)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5), // Semi-transparent background
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20), // Add padding inside the box
                    decoration: BoxDecoration(
                      color: Colors.white, // White background for the box
                      borderRadius: BorderRadius.circular(12), // Rounded corners
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // Ensures the content takes minimum space
                      crossAxisAlignment: CrossAxisAlignment.center, // Center the content horizontally
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue), // You can change the color
                        ),
                        const SizedBox(height: 16), // Space between the progress indicator and text
                        const Text(
                          'Please wait, Connecting port...',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (isLatestSoldout)
            Container(
              color: Colors.black.withOpacity(0.5), // Semi-transparent background
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20), // Padding inside the box
                  decoration: BoxDecoration(
                    color: Colors.white, // White background
                    borderRadius: BorderRadius.circular(12), // Rounded corners
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Minimum space taken
                    crossAxisAlignment: CrossAxisAlignment.center, // Center content
                    children: [
                      Icon(
                        Icons.cancel,
                        color: Colors.red,
                        size: 50, // Icon size
                      ),
                      const SizedBox(height: 16), // Space between icon and text
                      SizedBox(
                        width: 550, // Forces text to take full width
                        child: Text(
                          remainingTodispenseAm == 0 ? 'Please wait,\nEnsure the token is filled!' : 'Please wait,\nEnsure the token is filled!\nRemaining Token: $remainingTodispenseAm',
                          textAlign: TextAlign.center, // Ensure text is centered
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        // The button is centered by default since the Column is centered.
                      ),
                      Text(
                        'If Nothing happens, click the Reset and Exit button',
                        textAlign: TextAlign.center, // Ensure text is centered
                        style: TextStyle(
                          color: Colors.yellow,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16), // Space between icon and text
                      ElevatedButton(
                        onPressed: () => _clearDataAndResetFlags(context),
                        child: const Text('Reset and Exit'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (communication.IsPCBAlive == false)
            Container(
              color: Colors.black.withOpacity(0.5), // Semi-transparent background
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20), // Padding inside the box
                  decoration: BoxDecoration(
                    color: Colors.white, // White background
                    borderRadius: BorderRadius.circular(12), // Rounded corners
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Minimum space taken
                    crossAxisAlignment: CrossAxisAlignment.center, // Center content
                    children: [
                      Icon(
                        Icons.cancel,
                        color: Colors.red,
                        size: 50, // Icon size
                      ),
                      const SizedBox(height: 16), // Space between icon and text
                      SizedBox(
                        width: 375, // Forces text to take full width
                        child: Text(
                          'Port Disconnected!', // If no tokens were dispensed
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (isDeviceFaulty || communication.isSoldOut)
            Container(
              color: Colors.black.withOpacity(0.5), // Semi-transparent background
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20), // Padding inside the box
                  decoration: BoxDecoration(
                    color: Colors.white, // White background
                    borderRadius: BorderRadius.circular(12), // Rounded corners
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Minimum space taken
                    crossAxisAlignment: CrossAxisAlignment.center, // Center content
                    children: [
                      Icon(
                        Icons.cancel,
                        color: Colors.red,
                        size: 50, // Icon size
                      ),
                      const SizedBox(height: 16), // Space between icon and text
                      SizedBox(
                        width: 375, // Forces text to take full width
                        child: Text(
                          remainingTodispenseAm == 0
                              ? 'Soldout!' // If no tokens were dispensed
                              : 'Soldout! \nRemaining Token: $remainingTodispenseAm',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Map<String, String> parseTLV(String data) {
  Map<String, String> result = {};
  int i = 0;

  while (i < data.length) {
    // Extract Tag (2 digits)
    String tag = data.substring(i, i + 2);
    i += 2;

    // Extract Length (2 digits)
    int length = int.parse(data.substring(i, i + 2));
    i += 2;

    // Extract Value (length of 'length')
    String value = data.substring(i, i + length);
    i += length;

    result[tag] = value;
  }

  return result;
}
