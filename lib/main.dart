import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For JSON encoding/decoding
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'utils//RSA.dart'; // Import the signature utility file
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:io';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  runApp(const MyApp());
}

bool isLoading = false;


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}



class _MyHomePageState extends State<MyHomePage> {
  String selectedAmount = ''; // Store the selected amount as state
  String? qrCodeImageUrl;
  String? Token;
  String Signature = '';

  String readPrivateKey(String filePath) {
    return File(filePath).readAsStringSync();
  }
  //load privatekey
  Future<String> loadPrivateKey() async {
    try {
      // Load the private key from assets

      final privateKey = await rootBundle.loadString('assets/private_key.txt');
      return privateKey;
    } catch (e) {
      throw Exception("Error loading private key: $e");
    }
  }
//api

  String generateReferenceId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  // Helper function to get month as a string (e.g., "Jan", "Feb", etc.)
  String _getMonthString(int month) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return months[month - 1];
  }


  String encryptPlainText(String deviceCode, String secretKey, String ivString) {
// Get the current UTC time, add 1 minute and format it
    final now = DateTime.now().toUtc().add(Duration(minutes: 1));
    final formattedTime = "${now.year}-${_getMonthString(now.month)}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

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


  Future<void> handleButtonPress({
    required BuildContext context,
    required String amount,
    required String currency,
    required Function setLoading,
  }) async {
    String referenceId = generateReferenceId();
    String apiUrl = 'https://tqrdnqr-api.transpire.com.my/API/Exchange';


 try{
      setLoading(true);

      String deviceCode = "TQR000001";  // Replace with the actual device code
      //set encryption obj
      const secretKey = r'24D7EB69ACD0!@#$'; // Must be 32 characters
      const ivString = '0192006944061854'; // Must be 16 characters


      final encryptedKey = encryptPlainText(deviceCode, secretKey, ivString);

      print('encrypted key : $encryptedKey');
      final payloadtoken = {
        "commandcode":"RequestToken",
        "devicecode":deviceCode,
        "result":"false",
        "data":[{ "key":encryptedKey }]
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


      // Handle the response
      if (responsetoken.statusCode == 200) {
        final responseData = json.decode(responsetoken.body);
        Map<String, dynamic> parsedJson = jsonDecode(responsetoken.body);
        String token = parsedJson['data'][0]['token'];
        print('success token : $responseData');

        final payload = {
          "commandcode":"DI_GetDynamicQR",
          "devicecode":deviceCode,
          "result":"false",
          "data":[{
            "referenceid": referenceId,
            "eamount":amount,
            "validityduration":"120",
            "rssi":"-39"
          }]

        };

        final privateKeyPem = await loadPrivateKey();
        String pemKey = readPrivateKey('assets/private_key.txt');
        String cleanPem(String pem) {
          return pem.replaceAll(RegExp(r'\s+'), ''); // Removing all whitespace characters
        }

        final cleanPrivateKeyPem = cleanPem(pemKey);

        print("Private Key: $pemKey");
        final privateKeyPem1 = '''-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAweRWO8AKeU3h6tJ/DUe7kzRNV2i/O8EalKVdDPQACZJ+6g0L
3JIz00J5lrQ/hpO1V539CF5kbeElot8Pd8fzBWINMWyr1xMltNpE+XwOzUA1/lXH
9jaeKTqushXfSfKlS4xYUAcZQXO9dDOtYUebjz23Tl+Hud5l7yaneDgIFY+I/8h3
EeDwWnDFnBRzy+iq04LNNykG6OA/qS1BW0dL4V0X4ZyzloFeu8Vpq6gE+qbhxUE3
qZZU8V8MD7E1EQQnsbiHjbndZ4BYS+VCr8zcLtn+GoueWb4m0OSlGb2k2YRrFP+M
4pXfQeWvUbniXALoUZBTZ0VwG435q8UmfASlYwIDAQABAoIBAFAvnggs5kf/kSh7
sGauHWGGFlxJahkMxfDmqKJkQKW0y78A8UBhyIQcsEtGtSTzbmJTaONuoisdG2MN
zAhWDWfTArDHiBO1C/mM8UyaZUa2QP4zvLRTJzrW1Yu55vPeoUSqwJUsMmIyuw3V
F2WtZySouef0Mx4H33E1s7nQtmsvjeDk/aXCBJenIH8enQDHqgzqv7U5ZUqTzdYd
TuizKlkryw/1ZHd2+O34BtOb1Re5rBpTk7sTMHnarxyANCMgHzm/QoCNjcV/+ND0
1u5lHaVruYNfoRKER2p7QCdKXAcOFJngwvybnbxhB8MyaOVkuxTPt2bGRTIJxq42
hFmQ7sUCgYEA8npMwHJFNxPKb/BANoztmttYdqRvMnlMsG+opKimgU4eAhplGBDv
VlhZnD3WyuWdjlR673W0t5vfbii0Ri3HlHnbfRW5z1ZRr5BgaEvN+7c+x8PXYsFo
0kve/PXw1U5Ol9XD3T1b7l1x2AegVL25ax4WQ9rYarb1XBmyJ6DAt/UCgYEAzLRo
mu11m9aR7nNvXNApljDR7eHJXf4LFeQ2LtvMoY+E2H16d3Jm3m2kLH1ab71/9dBy
4TW/XF50sZRshLD50m6Ufn3WPNbwvgqtpyvgRhRB5MXpTmnTgWfkLAm56stRrFBg
q50PVuzN6OcaLjCZD58PdZhqPpOSjxwoU7xViPcCgYBVqqPHMhgGF3XkCmuFWlDv
7yLX98xZdsWDaE+arQL2mBS+BXlGAWWtidVPAAIM+QarLGmqhFlurSFJGBRo3u+u
I0dKcAyPlh2R+140OuPxVJJXnXdRKqfP9II5uOJ3Wg0mU525Yl5CXr1D553bkpQZ
pi2Tl5PyT+VrvqBUo9SyqQKBgQCO6mmZuK2CloSd4NPgDajrJbx7A0buK14b849s
maI9LZEHAFvPJvzwz8VuFjpchwXeXaDG4Rpv57Y7AK/e2BwisXdU9I/tO/cqBxSE
ARr8ckoq6Y3gY/v5fcoMgOHfLgIgdqF3TxkVjBCaSTa7Bszl3hwR8s5CUA9jgLoa
9AMXswKBgQCwnJMTflpDNP0XwETNY8Y15raULMveqvCIipTg1TkzeS4luaI82uhY
vI3HnI8PWGEGSTMCAnXz8cq78eLUErjD9XGG7sobBDcOe7nlf4WpuhwN2GS6syxF
iSJ2IiW4pVP2IyRWDcIv1v3ugt0sr3Jw62tcTgYNaH3Fc+xx3xDJAw==
-----END RSA PRIVATE KEY-----''';
        String signature = await generateSignature(jsonEncode(payload), privateKeyPem1);
        print('Signature: $signature');
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Token': token,
            'Signature' : signature

          },
          body: json.encode(payload),
        );
        //
        final QrResponseData = json.decode(response.body);
        Map<String, dynamic> qrparsedJson = jsonDecode(response.body);
        String qrcode = qrparsedJson ['data'][0]['qrcode'] ?? null;
        print('qr res : $QrResponseData');
        print('qr code : $qrcode');
        setState(() {
          qrCodeImageUrl = qrcode; // Save the generated QR code URL
        });

        // Show a success message or handle response data
      } else {
        print('Failed: ${responsetoken.statusCode}, ${responsetoken.body}');
        // Show an error message or handle the failure
      }
    } catch (e) {
      print('Error fetch: $e');
      // Show a network error message
    } finally {
      // Hide the loading indicator
      setLoading(false);

      // Show popup after API call
      showPopup(context);
    }

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
        }
      });
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        double screenWidth = MediaQuery.of(context).size.width; // Get screen width
        double screenHeight = MediaQuery.of(context).size.height;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            // Start the countdown when the dialog is built
            if (timer == null) {
              startCountdown(setState);
            }
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 130),
              contentPadding: EdgeInsets.zero,
              titlePadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0), // Adjust radius here
              ),
              content: SizedBox(
                width: 400, // Set a fixed width
                height: 600, // Set a fixed height
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
                  top: 85, // Adjust the space from the title
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child:
                    Image.asset(
                    'assets/images/duitnowlogo.png', // Replace with your logo path
                    height: 50, // Adjust logo height
                    width: 50, // Adjust logo width
                    fit: BoxFit.contain, // Adjust image fit
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
                      },
                    ),
                  ),
                  // Positioned QR image at the bottom of the dialog
                  Positioned(
                    bottom: 0, // Position the image at the bottom
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(5.0), // Adjust the margin around the image
                      child: Align(
                        alignment: Alignment.bottomCenter, // Align the image to the bottom and center
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10.0), // Extra margin from the bottom if needed
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFFE52561), // Border color (same pinkish-red color)
                              width: 4.0, // Border width
                            ),
                            borderRadius: BorderRadius.circular(8.0), // Optional: Rounded corners
                          ),
                          padding: const EdgeInsets.all(8.0), // Optional: Padding inside the border
                          child: qrCodeImageUrl != null
                              ?
                              QrImageView(
                                data: qrCodeImageUrl ?? 'default_fallback_value',
                                version: QrVersions.auto,
                                size: 320,
                                gapless: false,
                                foregroundColor: const Color(0xFFE52561), // QR code color
                              )


                              : Image.asset(
                            'assets/images/errorpage.png', // Replace with your image path
                            height: screenHeight * 0.45, // Adjust dynamically based on screen height
                            width: screenWidth * 0.4, // Center the image and set the width
                          ),
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
            child: Container(
              height: screenHeight * 0.45, // 45% of screen height
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                      'assets/images/bg.jpg'), // Add your image path here
                  fit: BoxFit.cover, // Cover the entire container
                ),
              ),
            ),
          ),
          // Main Container covering the remaining screen height
          Positioned(
            top: screenHeight * 0.4, // Start 40% from top to avoid overlap
            left: 0,
            right: 0,
            child: Container(
              width: screenWidth,
              height:
              screenHeight * 0.6, // Adjusted to take the remaining space
              padding:
              const EdgeInsets.all(15.0), // Padding inside the container
              margin: const EdgeInsets.all(1.0), // Margin around the container
              decoration: BoxDecoration(
                color: Colors.white, // Background color
                borderRadius: BorderRadius.circular(16.0), // Rounded corners
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45, // Shadow color
                    offset: Offset(0,
                        0), // No offset, so the shadow is centered around the widget
                    blurRadius: 0.5, // Blur radius to make the shadow smooth
                    spreadRadius:
                    0.5, // Optional: Adds a bit of spread to make the shadow larger
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
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.lightBlue,
                      fontFamily: 'Arial', // Apply Arial-like font
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select the Package or insert cash to pay, the coin will be dispensed once the payment is done.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.lightBlueAccent,
                      fontFamily: 'Arial', // Apply Arial-like font
                    ),
                  ),
                  const SizedBox(
                      height:
                      30), // Add space between description and content below
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: ()  {
                          setState(() {
                            selectedAmount = '10.00'; // Set the selected amount
                          });
                          handleButtonPress(
                            context: context,
                            amount: '10.00',
                            currency: 'MYR',
                            setLoading: (value) {
                              setState(() {
                                isLoading = value;
                              });
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(200, 150), // Set both width and height to make it square
                          backgroundColor: Colors.blue.shade50, // Change background color here
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12), // Optional: rounded corners
                          ),
                        ),
                        child: const Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '10 ',
                                style: TextStyle(
                                  fontSize: 24, // Larger size for "10"
                                  fontWeight: FontWeight.bold, // Bold text
                                  fontFamily: 'Arial', // Apply Arial-like font
                                  color: Colors.lightBlue,
                                ),
                              ),
                              TextSpan(
                                text: 'Coins\nMYR 10.00', // Line break and the rest of the text
                                style: TextStyle(
                                  fontSize: 18, // Smaller size for "MYR 10"
                                  fontWeight: FontWeight.normal, // Regular weight for the rest
                                  color: Colors.lightBlue,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center, // This centers the whole text
                        ),
                      ), //1
                      ElevatedButton(
                        onPressed: ()  {
                          setState(() {
                            selectedAmount = '20.00'; // Set the selected amount
                          });
                          handleButtonPress(
                            context: context,
                            amount: '20.00',
                            currency: 'MYR',
                            setLoading: (value) {
                              setState(() {
                                isLoading = value;
                              });
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(200, 150),
                          backgroundColor: Colors.blue.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '20 ',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Arial',
                                  color: Colors.lightBlue,
                                ),
                              ),
                              TextSpan(
                                text: 'Coins\nMYR 20.00',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.lightBlue,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ), //2
                      ElevatedButton(
                        onPressed: ()  {
                          setState(() {
                            selectedAmount = '50.00'; // Set the selected amount
                          });
                          handleButtonPress(
                            context: context,
                            amount: '50.00',
                            currency: 'MYR',
                            setLoading: (value) {
                              setState(() {
                                isLoading = value;
                              });
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(200, 150),
                          backgroundColor: Colors.blue.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '50 ',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Arial',
                                  color: Colors.lightBlue,
                                ),
                              ),
                              TextSpan(
                                text: 'Coins\nMYR 50.00',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.lightBlue,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ), //3
                      ElevatedButton(
                        onPressed: ()  {
                          setState(() {
                            selectedAmount = '100.00'; // Set the selected amount
                          });
                          handleButtonPress(
                            context: context,
                            amount: '100.00',
                            currency: 'MYR',
                            setLoading: (value) {
                              setState(() {
                                isLoading = value;
                              });
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(200, 150),
                          backgroundColor: Colors.blue.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '100 ',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Arial',
                                  color: Colors.lightBlue,
                                ),
                              ),
                              TextSpan(
                                text: 'Coins\nMYR 100',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.lightBlue,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ), //4
                    ],
                  ),
                  const SizedBox(height: 100),
                  Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Warm Tips',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontFamily: 'Arial',
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          '1. Once the coins are dispensed, no refund request will be accepted.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontFamily: 'Arial',
                          ),
                        ),
                        Text(
                          '2. Any question feel free to contact: 0173990160.',
                          style: TextStyle(
                            fontSize: 12,
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
        // Loading overlay
        if (isLoading)
    Container(
      color: Colors.black.withOpacity(0.5), // Semi-transparent background
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    ),
        ],
      ),
    );
  }
}
