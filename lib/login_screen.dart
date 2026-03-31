import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  String selectedRole = "PG"; // Initial value for dropdown

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ================= LOGIN LOGIC =================
  Future<void> login() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter email & password")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      User user = userCredential.user!;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) throw Exception("User profile not found in database");

      String role = doc['role'].toString().trim();
      String name = doc['name'] ?? "User";

      // Role Verification: Ensures chosen dropdown role matches DB role
      if (role != selectedRole) {
        await _auth.signOut(); // Log them out if roles don't match
        throw Exception(
          "Access denied: You are not registered as $selectedRole",
        );
      }

      // Navigation Logic based on Verified Role
      if (role == "PG") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PgDashboard(userId: user.uid, userName: name),
          ),
        );
      } else if (role == "Faculty") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FacultyDashboard(userId: user.uid, userName: name),
          ),
        );
      } else if (role == "OPD Entry") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OpdEntryDashboard(userId: user.uid, userName: name),
          ),
        );
      } else if (role == "HOD") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HodDashboard(userId: user.uid),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ================= UI COMPONENTS =================

  Widget roleDropdown() {
    List<String> roles = ["PG", "Faculty", "HOD", "OPD Entry"];
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          value: selectedRole,
          decoration: const InputDecoration(
            border: InputBorder.none,
            prefixIcon: Icon(Icons.badge_outlined, color: primaryTeal),
          ),
          icon: const Icon(Icons.keyboard_arrow_down, color: primaryTeal),
          style: const TextStyle(color: Colors.black87, fontSize: 16),
          items: roles.map((String role) {
            return DropdownMenuItem<String>(value: role, child: Text(role));
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              selectedRole = newValue!;
            });
          },
        ),
      ),
    );
  }

  Widget inputField(
    String hint,
    TextEditingController c,
    IconData icon, {
    bool isPassword = false,
  }) {
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
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
                // LOGOS
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 65,
                      width: 65,
                      child: Image.asset(
                        'assets/logo1.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.medical_services,
                                size: 50, color: primaryTeal),
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      height: 65,
                      width: 65,
                      child: Image.asset(
                        'assets/logo2.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.local_hospital,
                                size: 50, color: primaryTeal),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  "Department of Orthodontics",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Text(
                  "and Dentofacial Orthopaedics",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Login to continue",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 25),

                // LOGIN CARD
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      inputField(
                        "Email Address",
                        emailController,
                        Icons.email_outlined,
                      ),
                      inputField(
                        "Password",
                        passwordController,
                        Icons.lock_outline,
                        isPassword: true,
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            "Select Role",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ),
                      roleDropdown(),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryTeal,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: isLoading ? null : login,
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  "LOGIN",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Colors.black12, thickness: 1),
                      const SizedBox(height: 12),
                      const Text(
                        "Design: Dr. Ashish Sunny",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54),
                      ),
                      const Text(
                        "Development: Praveen S",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54),
                      ),
                      const Text(
                        "Concept: Dr. Laxmikanth S. M.",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "© 2026 All rights reserved.",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            letterSpacing: 0.5),
                      ),
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
