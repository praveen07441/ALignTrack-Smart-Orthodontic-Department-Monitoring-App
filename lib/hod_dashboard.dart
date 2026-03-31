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

  // ================= SMART CHAT ICON =================
  Widget _buildChatIcon() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chat').snapshots(),
      builder: (context, snapshot) {
        int unreadCount = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final seenBy = data['seenBy'] ?? [];
            if (data['userId'] == widget.userId) continue;
            if (!seenBy.contains(widget.userId)) unreadCount++;
          }
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
                icon: const Icon(Icons.chat_bubble_outline,
                    color: Colors.black, size: 26),
                onPressed: _openCommonChat),
            if (unreadCount > 0)
              Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center))),
          ],
        );
      },
    );
  }

  // ================= ✅ MASTER PDF EXPORT (1 MONTH DURATION) =================
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("No records found for this 30-day period.")));
        return;
      }

      List<List<String>> masterData = [];

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
          for (var p in data['patients']) {
            masterData.add([
              "$dateStr\n$time",
              name,
              "PG Clinical",
              "Pt: ${p['patientName']}\nOP: ${p['opNumber']}",
              "Proc: ${p['procedure']}\nStaff: ${p['staffName']}"
            ]);
          }
        } else if (role == "Faculty") {
          for (var w in data['workEntries']) {
            masterData.add([
              "$dateStr\n$time",
              name,
              "Faculty",
              "Cat: ${w['category']}",
              "Work: ${w['details']}"
            ]);
          }
        } else if (role == "OPD Entry") {
          masterData.add([
            "$dateStr\n$time",
            name,
            "OPD Unit",
            "Pt: ${data['patientName']}\nOP: ${data['opNumber']}",
            "Diag: ${data['diagnosis']}\nPG: ${data['pgStudentName']}\nAllot: ${data['caseAllottedTo']}"
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
              "Period: ${DateFormat('dd MMM').format(startDate)} to ${DateFormat('dd MMM yyyy').format(endDate)}",
              style:
                  const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1, color: PdfColors.teal),
        ]),
        build: (context) => [
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              "Date/Time",
              "User",
              "Type",
              "Primary Info",
              "Detailed Clinical/Work/Diagnosis Findings"
            ],
            data: masterData,
            headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal900),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(70),
              1: const pw.FixedColumnWidth(80),
              2: const pw.FixedColumnWidth(70),
              3: const pw.FixedColumnWidth(150),
              4: const pw.FixedColumnWidth(280)
            },
            cellPadding: const pw.EdgeInsets.all(6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
        ],
        footer: (context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.only(top: 20),
            child: pw.Text(
                "Page ${context.pageNumber} of ${context.pagesCount}",
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('department_entries')
          .where('date', isEqualTo: formattedDate)
          .where('role', isEqualTo: role)
          .snapshots(),
      builder: (context, snapshot) {
        int total = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            total +=
                (d['patients']?.length ?? d['workEntries']?.length ?? 1) as int;
          }
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 15, bottom: 5),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.accentTeal)),
                    Text("Total logs today: $total",
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ])),
          _buildUserListForHOD(role),
        ]);
      },
    );
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
        if (!snap.hasData || snap.data!.docs.isEmpty)
          return _emptySmallCard("No records for $formattedDate");
        return Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: Column(
              children: snap.data!.docs.map((d) {
            if (role == "OPD Entry") {
              final data = d.data() as Map<String, dynamic>;
              int count = data['patients'] != null
                  ? (data['patients'] as List).length
                  : 1;
              return _entryDetailTile(d, role,
                  customTitle: "OPD Registration ($count)");
            }
            return _hodUserExpansionTile(d, role);
          }).toList()),
        );
      },
    );
  }

  Widget _hodUserExpansionTile(DocumentSnapshot user, String role) {
    final String displayName =
        (user.data() as Map<String, dynamic>)['name'] ?? "Unknown";
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('department_entries')
            .where('userId', isEqualTo: user.id)
            .where('date', isEqualTo: formattedDate)
            .snapshots(),
        builder: (context, logSnap) {
          int count = 0;
          bool hasData = logSnap.hasData && logSnap.data!.docs.isNotEmpty;
          if (hasData) {
            for (var doc in logSnap.data!.docs) {
              final d = doc.data() as Map<String, dynamic>;
              count += (d['patients']?.length ?? d['workEntries']?.length ?? 1)
                  as int;
            }
          }
          return ExpansionTile(
            leading: Icon(hasData ? Icons.check_circle : Icons.pending_actions,
                color: hasData ? AppColors.submitted : AppColors.pending,
                size: 20),
            title: Text(count > 0 ? "$displayName ($count)" : displayName,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            trailing: IconButton(
                icon: const Icon(Icons.chat_outlined,
                    color: AppColors.accentTeal, size: 20),
                onPressed: () => _openPrivateChat(user.id, displayName)),
            children: hasData
                ? logSnap.data!.docs
                    .map((d) => _entryDetailTile(d, role))
                    .toList()
                : [
                    const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text("Pending submission",
                            style: TextStyle(fontSize: 11, color: Colors.grey)))
                  ],
          );
        });
  }

  Widget _entryDetailTile(DocumentSnapshot doc, String role,
      {String? customTitle}) {
    final data = doc.data() as Map<String, dynamic>;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (customTitle != null)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(customTitle,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentTeal,
                    fontSize: 13))),
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: AppColors.background.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade100)),
        child: Column(children: [
          if (role == "PG")
            ...(data['patients'] as List)
                .map((p) => _dataRow(
                    "Pt: ${p['patientName']}",
                    "OP: ${p['opNumber']} | Proc: ${p['procedure']} | Staff: ${p['staffName']}",
                    Icons.medical_services))
                .toList()
          else if (role == "Faculty")
            ...(data['workEntries'] as List)
                .map((w) => _dataRow(w['category'] ?? 'Work',
                    w['details'] ?? '-', Icons.work_history_outlined))
                .toList()
          else // OPD
            _dataRow(
                "Pt: ${data['patientName']}",
                "OP: ${data['opNumber']}\nDiag: ${data['diagnosis']}\nPG: ${data['pgStudentName']}\nAllot: ${data['caseAllottedTo']}",
                Icons.assignment_turned_in_outlined),
        ]),
      ),
    ]);
  }

  Widget _dataRow(String label, String value, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: AppColors.accentTeal),
        const SizedBox(width: 8),
        Expanded(
            child: RichText(
                text: TextSpan(
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87, height: 1.4),
                    children: [
              TextSpan(
                  text: "$label: ",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: value),
            ]))),
      ]));

  Widget _emptySmallCard(String m) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Center(
          child: Text(m,
              style: const TextStyle(color: Colors.grey, fontSize: 11))));

  // ================= PRIVATE ADMIN TASKS =================
  void _showHODTaskDialog() async {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    TimeOfDay? selectedTime;
    showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: const Text("New HOD Admin Task",
                      style: TextStyle(
                          color: AppColors.accentTeal,
                          fontWeight: FontWeight.bold)),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: titleController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration:
                            const InputDecoration(labelText: "Task Title*")),
                    const SizedBox(height: 10),
                    TextField(
                        controller: descController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            labelText: "Description (Optional)")),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.access_time,
                            color: AppColors.accentTeal),
                        title: Text(selectedTime == null
                            ? "Pick Time"
                            : "Time: ${selectedTime!.format(context)}"),
                        onTap: () async {
                          final TimeOfDay? picked = await showTimePicker(
                              context: context, initialTime: TimeOfDay.now());
                          if (picked != null)
                            setDialogState(() => selectedTime = picked);
                        }),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel")),
                    ElevatedButton(
                        onPressed: () async {
                          if (titleController.text.trim().isEmpty) return;
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(widget.userId)
                              .collection('reminders')
                              .add({
                            'title': titleController.text.trim(),
                            'description': descController.text.trim(),
                            'status': 'pending',
                            'date': formattedDate,
                            'time': selectedTime != null
                                ? selectedTime!.format(context)
                                : "No Time",
                            'role': 'HOD',
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          if (mounted) Navigator.pop(context);
                        },
                        child: const Text("Save Task")),
                  ],
                )));
  }

  Widget _buildHODReminderSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("MY PRIVATE ADMIN TASKS",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Colors.black54)),
            IconButton(
                onPressed: _showHODTaskDialog,
                icon: const Icon(Icons.add_circle,
                    color: AppColors.accentTeal, size: 28)),
          ])),
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('reminders')
            .where('date', isEqualTo: formattedDate)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
            return _emptySmallCard("No admin tasks for this date");
          final docs = snapshot.data!.docs.toList();
          return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                bool isDone = data['status'] == 'completed';
                return Card(
                  elevation: 0.5,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: isDone
                              ? Colors.transparent
                              : Colors.teal.shade50)),
                  child: ListTile(
                    leading: Checkbox(
                        value: isDone,
                        activeColor: AppColors.accentTeal,
                        onChanged: (v) => docs[index]
                            .reference
                            .update({'status': v! ? 'completed' : 'pending'})),
                    title: Text(data['title'],
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration:
                                isDone ? TextDecoration.lineThrough : null)),
                    subtitle: Text("${data['time']} - ${data['description']}",
                        style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: Colors.redAccent),
                        onPressed: () => docs[index].reference.delete()),
                  ),
                );
              });
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst)),
        title: const Text("HOD Management",
            style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        actions: [
          isExporting
              ? const SizedBox(
                  width: 40,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined,
                      color: Colors.black),
                  onPressed: exportMonthlyPDF),
          _buildChatIcon(),
        ],
      ),
      body: Column(
        children: [
          Container(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15)),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            DateFormat('EEEE, dd MMM yyyy')
                                .format(selectedDate),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const Icon(Icons.calendar_month,
                            color: AppColors.accent, size: 20)
                      ])),
            ),
          ),
          Expanded(
              child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  children: [
                _buildHODReminderSection(),
                const Divider(height: 40),
                const Text("LIVE SUBMISSION MONITORING",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54)),
                _buildMonitoringCategory("PG Students (Clinical Logs)", "PG"),
                _buildMonitoringCategory(
                    "Faculty members (Work Logs)", "Faculty"),
                _buildMonitoringCategory("OPD Registration Unit", "OPD Entry"),
                const SizedBox(height: 50),
              ])),
        ],
      ),
    );
  }
}
