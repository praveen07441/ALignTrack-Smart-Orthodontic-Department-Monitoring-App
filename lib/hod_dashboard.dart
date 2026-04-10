import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import 'chat_screen.dart';

class AppColors {
  static const Color primary = Color(0xFFC8E6C9);
  static const Color accent = Color(0xFF075E54);
  static const Color background = Color(0xFFF1F8E9);
  static const Color submitted = Color(0xFF2E7D32);
  static const Color pending = Color(0xFFF57C00);
  static const Color accentTeal = Color(0xFF00695C);
  static const Color textDark = Color(0xFF2D3436);
}

class HodDashboard extends StatefulWidget {
  final String userId;
  const HodDashboard({super.key, required this.userId});

  @override
  State<HodDashboard> createState() => _HodDashboardState();
}

class _HodDashboardState extends State<HodDashboard> {
  DateTime selectedDate = DateTime.now();
  bool isExporting = false;

  String get formattedDate => DateFormat('yyyy-MM-dd').format(selectedDate);

  @override
  void initState() {
    super.initState();
    // NotificationService init is handled in main.dart
  }

  // ================= CHAT NAVIGATION =================
  void _openCommonChat() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(
                  userId: widget.userId,
                  userName: "HOD",
                  role: "HOD",
                )));
  }

  void _openPrivateChat(String targetId, String targetName) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(
                  userId: widget.userId,
                  userName: "HOD",
                  role: "HOD",
                  targetUserId: targetId,
                  targetUserName: targetName,
                )));
  }

  // ================= MASTER PDF EXPORT =================
  Future<void> exportMonthlyPDF() async {
    setState(() => isExporting = true);
    try {
      final pdf = pw.Document();
      DateTime endDate = selectedDate;
      DateTime startDate = endDate.subtract(const Duration(days: 30));

      final snapshot = await FirebaseFirestore.instance
          .collection('department_entries')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('timestamp', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("No records found for this 30-day period.")));
        }
        return;
      }

      List<List<String>> masterData = [];
      int serialNo = 1;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String name = data['userName'] ?? 'Unknown';
        final String role = data['role'] ?? '-';
        final String dateStr = data['date'] ?? '-';
        final String time = data['timestamp'] != null
            ? DateFormat('hh:mm a')
                .format((data['timestamp'] as Timestamp).toDate())
            : '-';

        if (role == "PG") {
          final patients = data['patients'] as List? ?? [];
          for (var p in patients) {
            masterData.add([
              "${serialNo++}",
              "$dateStr\n$time",
              name,
              "PG Clinical",
              "Pt: ${p['patientName']}\nOP: ${p['opNumber']}",
              "Proc: ${p['procedure']}\nStaff: ${p['staffName']}"
            ]);
          }
        } else if (role == "Faculty") {
          final workEntries = data['workEntries'] as List? ?? [];
          for (var w in workEntries) {
            masterData.add([
              "${serialNo++}",
              "$dateStr\n$time",
              name,
              "Faculty",
              "Cat: ${w['category']}",
              "Work: ${w['details']}"
            ]);
          }
        } else if (role == "OPD Entry") {
          masterData.add([
            "${serialNo++}",
            "$dateStr\n$time",
            name,
            "OPD Unit",
            "Pt: ${data['patientName']}\nOP: ${data['opNumber']}",
            "Diag: ${data['diagnosis']}\nPG: ${data['pgStudentName']}"
          ]);
        }
      }

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(children: [
          pw.Text("DEPARTMENT MONITORING MASTER REPORT",
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 18,
                  color: PdfColors.teal900)),
          pw.Text(
              "Duration: ${DateFormat('dd MMM').format(startDate)} to ${DateFormat('dd MMM yyyy').format(endDate)}",
              style:
                  const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1, color: PdfColors.teal),
        ]),
        build: (context) => [
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              "S.No",
              "Date/Time",
              "User",
              "Log Type",
              "Primary Info",
              "Detailed Findings"
            ],
            data: masterData,
            headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal900),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FixedColumnWidth(70),
              2: const pw.FixedColumnWidth(80),
              3: const pw.FixedColumnWidth(70),
              4: const pw.FixedColumnWidth(150),
              5: const pw.FixedColumnWidth(250),
            },
            cellPadding: const pw.EdgeInsets.all(6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
        ],
      ));

      await Printing.layoutPdf(
          onLayout: (format) async => pdf.save(),
          name: 'Master_Report_$formattedDate');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
  }

  // ================= MONITORING UI =================
  Widget _buildMonitoringCategory(String title, String role) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(top: 15, bottom: 5),
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.accentTeal))),
      _buildUserListForHOD(role),
    ]);
  }

  Widget _buildUserListForHOD(String role) {
    return StreamBuilder<QuerySnapshot>(
      stream: role == "OPD Entry"
          ? FirebaseFirestore.instance
              .collection('department_entries')
              .where('role', isEqualTo: role)
              .where('date', isEqualTo: formattedDate)
              .snapshots()
          : FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: role)
              .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              child: const Text("No logs found.",
                  style: TextStyle(color: Colors.grey, fontSize: 12)));
        }
        return Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: Column(
              children: snap.data!.docs
                  .map((d) => role == "OPD Entry"
                      ? _entryDetailTile(d, role)
                      : _hodUserExpansionTile(d, role))
                  .toList()),
        );
      },
    );
  }

  Widget _hodUserExpansionTile(DocumentSnapshot user, String role) {
    final data = user.data() as Map<String, dynamic>;
    final String name = data['name'] ?? "Unknown";
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('department_entries')
          .where('userId', isEqualTo: user.id)
          .where('date', isEqualTo: formattedDate)
          .snapshots(),
      builder: (context, logSnap) {
        bool hasData = logSnap.hasData && logSnap.data!.docs.isNotEmpty;
        return ExpansionTile(
          leading: Icon(hasData ? Icons.check_circle : Icons.pending_actions,
              color: hasData ? AppColors.submitted : AppColors.pending,
              size: 20),
          title: Text(name,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          trailing: IconButton(
              icon: const Icon(Icons.chat_outlined,
                  color: AppColors.accentTeal, size: 20),
              onPressed: () => _openPrivateChat(user.id, name)),
          children: hasData
              ? logSnap.data!.docs
                  .map((d) => _entryDetailTile(d, role))
                  .toList()
              : [
                  const Text("Pending submission",
                      style: TextStyle(fontSize: 11, color: Colors.grey))
                ],
        );
      },
    );
  }

  Widget _entryDetailTile(DocumentSnapshot doc, String role) {
    final data = doc.data() as Map<String, dynamic>;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: AppColors.background.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        if (role == "PG")
          ...(data['patients'] as List).map((p) => _dataRow(
              "Pt: ${p['patientName']}",
              "Proc: ${p['procedure']}",
              Icons.medical_services))
        else if (role == "Faculty")
          ...(data['workEntries'] as List).map((w) => _dataRow(
              w['category'] ?? 'Work', w['details'] ?? '-', Icons.work))
        else
          _dataRow("OPD Patient", data['patientName'], Icons.assignment),
      ]),
    );
  }

  Widget _dataRow(String label, String value, IconData icon) => Row(children: [
        Icon(icon, size: 14, color: AppColors.accentTeal),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text("$label: $value", style: const TextStyle(fontSize: 12))),
      ]);

  // ================= ADMIN TASKS =================
  void _showHODTaskDialog() {
    final TextEditingController titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New HOD Task"),
        content: TextField(
            controller: titleController,
            decoration: const InputDecoration(labelText: "Task Title")),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () async {
                if (titleController.text.isEmpty) return;
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.userId)
                    .collection('reminders')
                    .add({
                  'title': titleController.text,
                  'status': 'pending',
                  'date': formattedDate,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              },
              child: const Text("Save")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("HOD Management",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          isExporting
              ? const CircularProgressIndicator()
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.black),
                  onPressed: exportMonthlyPDF),
          IconButton(
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.black),
              onPressed: _openCommonChat),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildHeaderDatePicker(),
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("ADMIN TASKS",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black54)),
                IconButton(
                    onPressed: _showHODTaskDialog,
                    icon: const Icon(Icons.add_circle,
                        color: AppColors.accentTeal)),
              ]),
              _buildMonitoringCategory("PG Students", "PG"),
              _buildMonitoringCategory("Faculty", "Faculty"),
              _buildMonitoringCategory("OPD Unit", "OPD Entry"),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeaderDatePicker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30))),
      child: InkWell(
        onTap: () async {
          final d = await showDatePicker(
              context: context,
              initialDate: selectedDate,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030));
          if (d != null) setState(() => selectedDate = d);
        },
        child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('EEEE, dd MMM yyyy').format(selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Icon(Icons.calendar_month, color: AppColors.accent)
                ])),
      ),
    );
  }
}
