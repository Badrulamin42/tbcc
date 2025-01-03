import 'package:flutter/material.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

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
              content: Stack(
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
                      padding: const EdgeInsets.all(16.0), // Adjust the margin around the image
                      child: Align(
                        alignment: Alignment.bottomCenter, // Align the image to the bottom and center
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10.0), // Extra margin from the bottom if needed
                          child: Image.asset(
                            'assets/images/qr.jpg', // Replace with your image path
                            height: screenHeight * 0.45, // Adjust dynamically based on screen height
                            width: screenWidth * 0.9, // Center the image and set the width
                            fit: BoxFit.cover, // Make sure image covers the space
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
                        onPressed: () {
                          setState(() {
                            selectedAmount = '10'; // Set the selected amount
                          });
                          showPopup(context); // Pass the BuildContext to the showPopup function
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
                                text: 'Coins\nMYR 10', // Line break and the rest of the text
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
                        onPressed: () {
                          setState(() {
                            selectedAmount = '20'; // Set the selected amount
                          });
                          showPopup(context); // Show the popup for selected amount
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
                                text: 'Coins\nMYR 20',
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
                        onPressed: () {
                          setState(() {
                            selectedAmount = '50'; // Set the selected amount
                          });
                          showPopup(context); // Show the popup for selected amount
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
                                text: 'Coins\nMYR 50',
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
                        onPressed: () {
                          setState(() {
                            selectedAmount = '100'; // Set the selected amount
                          });
                          showPopup(context); // Show the popup for selected amount
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
                  const SizedBox(height: 50),
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
        ],
      ),
    );
  }
}
