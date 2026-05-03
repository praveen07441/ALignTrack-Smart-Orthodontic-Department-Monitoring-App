import 'dart:io'; // ✅ Handles platform-specific logic
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Dashboard Imports
import 'pg_dashboard.dart';
import 'faculty_dashboard.dart';
import 'hod_dashboard.dart';
import 'opd_entry_dashboard.dart';

// ================= PREMIUM COLORS =================
const Color primaryTeal = Color(0xFF075E54);
const Color softGreen = Color(0xFFC8E6C9);
const Color bgColor = Color(0xFFF1F8E9);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool obscurePassword = true;
  bool isLoading = false;
  bool rememberMe = false;
  String selectedRole = "PG";

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool savedRememberMe = prefs.getBool('remember_me') ?? false;

      if (mounted) {
        setState(() {
          rememberMe = savedRememberMe;
          if (rememberMe) {
            emailController.text = prefs.getString('saved_email') ?? '';
            passwordController.text = prefs.getString('saved_password') ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('🔴 Prefs Error: $e');
    }
  }

  Future<void> _handleRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (rememberMe) {
        await prefs.setString('saved_email', emailController.text.trim());
        await prefs.setString('saved_password', passwordController.text.trim());
        await prefs.setBool('remember_me', true);
      } else {
        await prefs.remove('saved_email');
        await prefs.remove('saved_password');
        await prefs.setBool('remember_me', false);
      }
    } catch (e) {
      debugPrint('🔴 Storage Error: $e');
    }
  }

  // ================= LOGIN LOGIC =================
  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter email & password")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // 1. Firebase Auth SignIn
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _handleRememberMe();

      User user = userCredential.user!;

      // 🔔 SAVE FCM TOKEN (Android specific to avoid APNs overhead)
      if (Platform.isAndroid) {
        String? fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'fcmToken': fcmToken}, SetOptions(merge: true));
        }
      }

      // 2. Database Role Fetch
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        await _auth.signOut();
        throw Exception("User profile not found in database.");
      }

      String role = doc['role'].toString().trim();
      String name = doc['name'] ?? "User";

      // 3. Strict Role Verification
      if (role.toLowerCase() != selectedRole.toLowerCase()) {
        await _auth.signOut();
        throw Exception(
            "Access denied: You are not registered as $selectedRole");
      }

      // ✅ 4. SAVE SESSION (CRITICAL FIX)
      // This ensures the app remembers the user upon restart.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', user.uid);
      await prefs.setString('role', role);
      await prefs.setString('userName', name);

      if (!mounted) return;

      // 5. Navigation to Dashboards
      Widget targetPage;
      if (role == "PG") {
        targetPage = PgDashboard(userId: user.uid, userName: name);
      } else if (role == "Faculty") {
        targetPage = FacultyDashboard(userId: user.uid, userName: name);
      } else if (role == "OPD Entry") {
        targetPage = OpdEntryDashboard(userId: user.uid, userName: name);
      } else {
        targetPage = HodDashboard(userId: user.uid);
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => targetPage),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll("Exception: ", ""))),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ================= UI COMPONENTS =================

  Widget roleDropdown() {
    List<String> roles = ["PG", "Faculty", "HOD", "OPD Entry"];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonFormField<String>(
        value: selectedRole,
        decoration: const InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(Icons.badge_outlined, color: primaryTeal),
        ),
        icon: const Icon(Icons.keyboard_arrow_down, color: primaryTeal),
        items: roles.map((String role) {
          return DropdownMenuItem<String>(value: role, child: Text(role));
        }).toList(),
        onChanged: (String? newValue) {
          if (newValue != null) {
            setState(() => selectedRole = newValue);
          }
        },
      ),
    );
  }

  Widget inputField(String hint, TextEditingController c, IconData icon,
      {bool isPassword = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: c,
        obscureText: isPassword ? obscurePassword : false,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: primaryTeal),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () =>
                      setState(() => obscurePassword = !obscurePassword),
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/logo1.png',
                        height: 65,
                        width: 65,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => const Icon(
                            Icons.medical_services,
                            size: 50,
                            color: primaryTeal)),
                    const SizedBox(width: 20),
                    Image.asset('assets/logo2.png',
                        height: 65,
                        width: 65,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => const Icon(
                            Icons.local_hospital,
                            size: 50,
                            color: primaryTeal)),
                  ],
                ),
                const SizedBox(height: 20),
                const Text("Department of Orthodontics",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const Text("and Dentofacial Orthopaedics",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: 10),
                const Text("Login to continue",
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05), blurRadius: 15)
                    ],
                  ),
                  child: Column(
                    children: [
                      inputField("Email Address", emailController,
                          Icons.email_outlined),
                      inputField(
                          "Password", passwordController, Icons.lock_outline,
                          isPassword: true),
                      Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: rememberMe,
                              activeColor: primaryTeal,
                              onChanged: (value) =>
                                  setState(() => rememberMe = value ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text("Remember Password",
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black87)),
                        ],
                      ),
                      const SizedBox(height: 15),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 8),
                          child: Text("Select Role",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.black54)),
                        ),
                      ),
                      roleDropdown(),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryTeal,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                          ),
                          onPressed: isLoading ? null : login,
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text("LOGIN",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.1)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Colors.black12, thickness: 1),
                      const SizedBox(height: 12),
                      const Text("Design: Dr. Ashish Sunny",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54)),
                      const Text("Development: Praveen S",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54)),
                      const Text("Concept: Dr. Laxmikanth S. M.",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54)),
                      const SizedBox(height: 12),
                      const Text("© 2026 All rights reserved.",
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
