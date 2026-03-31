import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'chat_screen.dart';
import 'notification_service.dart';

class AppColors {
  static const Color primary = Color(0xFFC8E6C9);
  static const Color accent = Color(0xFFA5D6A7);
  static const Color background = Color(0xFFF1F8E9);
  static const Color cardBg = Colors.white;
  static const Color accentTeal = Color(0xFF00695C);
  static const Color textDark = Color(0xFF2D3436);
  static const Color submitted = Color(0xFF2E7D32);
}

class PgDashboard extends StatefulWidget {
  final String userId;
  final String userName;
  const PgDashboard({super.key, required this.userId, required this.userName});

  @override
  State<PgDashboard> createState() => _PgDashboardState();
}

class _PgDashboardState extends State<PgDashboard> {
  DateTime selectedDate = DateTime.now();
  bool isExporting = false;

  final List<String> slots = [
    "09:00 AM - 10:00 AM",
    "10:00 AM - 11:00 AM",
    "11:00 AM - 12:00 PM",
    "12:00 PM - 01:00 PM",
    "01:00 PM - 02:00 PM",
    "02:00 PM - 03:00 PM",
  ];

  String get formattedDate => DateFormat('yyyy-MM-dd').format(selectedDate);

  @override
  void initState() {
    super.initState();
    NotificationService().init();
  }

  // ================= ✅ DYNAMIC HOD FETCH & NAVIGATION =================
  Future<void> _getHodAndNavigate() async {
    try {
      final hodQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'HOD')
          .limit(1)
          .get();

      if (hodQuery.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("HOD account not found.")),
          );
        }
        return;
      }

      final String hodUid = hodQuery.docs.first.id;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            userId: widget.userId,
            userName: widget.userName,
            role: "PG",
            targetUserId: hodUid,
            targetUserName: "HOD Desk",
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error opening chat: $e")),
        );
      }
    }
  }

  // ================= ✅ 1 MONTH PDF EXPORT LOGIC =================
  Future<void> _exportMonthlyPGPDF() async {
    setState(() => isExporting = true);
    try {
      final pdf = pw.Document();

      // Calculate 1 month range (30 days back from selected date)
      DateTime endDate = selectedDate;
      DateTime startDate = endDate.subtract(const Duration(days: 30));

      final snapshot = await FirebaseFirestore.instance
          .collection('department_entries')
          .where('userId', isEqualTo: widget.userId)
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

      List<List<String>> rows = [];
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final patients = data['patients'] as List? ?? [];
        final dateLabel = data['date'] ?? '-';
        for (var p in patients) {
          rows.add([
            dateLabel,
            data['timeSlot'] ?? '-',
            p['staffName'] ?? '-',
            p['patientName'] ?? '-',
            p['opNumber'] ?? '-',
            p['procedure'] ?? '-'
          ]);
        }
      }

      pdf.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape, // ✅ FIXED Landscape syntax
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(children: [
                pw.Text("PG MONTHLY CLINICAL LOG REPORT",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 18,
                        color: PdfColors.teal900)),
                pw.Text("Student: ${widget.userName}",
                    style: const pw.TextStyle(fontSize: 12)),
                pw.Text(
                    "Period: ${DateFormat('dd MMM').format(startDate)} to ${DateFormat('dd MMM yyyy').format(endDate)}",
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey700)),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 1, color: PdfColors.teal),
              ]),
          build: (context) => [
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  headers: [
                    "Date",
                    "Slot",
                    "Staff",
                    "Patient",
                    "OP No",
                    "Procedure"
                  ],
                  data: rows,
                  headerStyle: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 9),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.teal900),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(60),
                    1: const pw.FixedColumnWidth(80),
                    2: const pw.FixedColumnWidth(80),
                    3: const pw.FixedColumnWidth(100),
                    4: const pw.FixedColumnWidth(60),
                    5: const pw.FixedColumnWidth(150),
                  },
                  cellPadding: const pw.EdgeInsets.all(5),
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                ),
              ],
          footer: (context) => pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("Page ${context.pageNumber}",
                    style: const pw.TextStyle(fontSize: 8)),
              )));

      await Printing.layoutPdf(
          onLayout: (format) async => pdf.save(),
          name: 'PG_Monthly_Clinical_Report');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("PDF Error: $e")));
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
  }

  // ================= CHAT ICON WITH COUNT BADGE =================
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
            bool isRelevant = data['type'] == 'group' ||
                (data['type'] == 'hod' &&
                    data['targetUserId'] == widget.userId);
            if (isRelevant && !seenBy.contains(widget.userId)) unreadCount++;
          }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
                icon: const Icon(Icons.chat_bubble_outline,
                    color: Colors.black, size: 26),
                onPressed: _getHodAndNavigate),
            if (unreadCount > 0)
              Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.primary, width: 1.5)),
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

  // ================= REMINDER LOGIC =================
  void _showAddReminderDialog() {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    TimeOfDay? selectedTime;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("New Clinical Task",
              style: TextStyle(
                  color: AppColors.accentTeal, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: "Task Title*", hintText: "e.g., Ward Rounds")),
              const SizedBox(height: 10),
              TextField(
                  controller: descController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: "Description (Optional)")),
              const SizedBox(height: 15),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.access_time, color: AppColors.accentTeal),
                title: Text(selectedTime == null
                    ? "Pick Schedule Time"
                    : "Scheduled: ${selectedTime!.format(context)}"),
                onTap: () async {
                  final TimeOfDay? picked = await showTimePicker(
                      context: context, initialTime: TimeOfDay.now());
                  if (picked != null)
                    setDialogState(() => selectedTime = picked);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentTeal),
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
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) Navigator.pop(context);
              },
              child: const Text("Save Task",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("MY REMINDERS",
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Colors.black54)),
            IconButton(
                onPressed: _showAddReminderDialog,
                icon: const Icon(Icons.add_circle,
                    color: AppColors.accentTeal, size: 28)),
          ]),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .collection('reminders')
              .where('date', isEqualTo: formattedDate)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                      child: Text("No reminders for this date",
                          style: TextStyle(color: Colors.grey))));
            }
            final docs = snapshot.data!.docs.toList();
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                var doc = docs[index];
                var data = doc.data() as Map<String, dynamic>;
                bool isDone = data['status'] == 'completed';
                return Card(
                  elevation: 0.5,
                  color: isDone ? Colors.grey[50] : Colors.white,
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
                        onChanged: (val) => doc.reference.update(
                            {'status': val! ? 'completed' : 'pending'})),
                    title: Text(data['title'],
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration:
                                isDone ? TextDecoration.lineThrough : null,
                            color: isDone ? Colors.grey : AppColors.textDark)),
                    subtitle: Text("${data['time']} - ${data['description']}",
                        style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent, size: 20),
                        onPressed: () => doc.reference.delete()),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
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
        title: const Text("PG Dashboard",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          isExporting
              ? const SizedBox(
                  width: 40,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.black),
                  onPressed: _exportMonthlyPGPDF),
          _buildChatIcon(),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
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
                      lastDate: DateTime(2030),
                      builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.light(
                                  primary: AppColors.accentTeal)),
                          child: child!));
                  if (d != null) setState(() => selectedDate = d);
                },
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
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
                              color: AppColors.accentTeal)
                        ])),
              ),
            ),
            ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: slots.length,
                itemBuilder: (context, i) => _buildSlotCard(slots[i])),
            const Divider(height: 20, thickness: 1, indent: 20, endIndent: 20),
            _buildReminderSection(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotCard(String slot) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('department_entries')
          .where('userId', isEqualTo: widget.userId)
          .where('date', isEqualTo: formattedDate)
          .where('timeSlot', isEqualTo: slot)
          .snapshots(),
      builder: (context, snapshot) {
        bool isDone = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 1,
          child: ListTile(
            title:
                Text(slot, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(isDone ? "Entries Recorded" : "No records yet",
                style: TextStyle(color: isDone ? Colors.green : Colors.grey)),
            trailing: Icon(
                isDone ? Icons.check_circle : Icons.arrow_forward_ios,
                color: isDone ? Colors.green : Colors.grey,
                size: 20),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EntryScreen(
                        userId: widget.userId,
                        userName: widget.userName,
                        slot: slot,
                        role: "PG",
                        selectedDate: formattedDate))),
          ),
        );
      },
    );
  }
}

// ================= ENTRY SCREEN =================
class EntryScreen extends StatefulWidget {
  final String userId, userName, slot, role, selectedDate;
  const EntryScreen(
      {super.key,
      required this.userId,
      required this.userName,
      required this.slot,
      required this.role,
      required this.selectedDate});
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final List<Map<String, TextEditingController>> _controllers = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _addNewPatient();
  }

  void _addNewPatient() {
    setState(() => _controllers.add({
          "staff": TextEditingController(),
          "patient": TextEditingController(),
          "op": TextEditingController(),
          "proc": TextEditingController()
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          title: Text("Log Entry: ${widget.slot.split(' ')[0]}"),
          backgroundColor: AppColors.primary),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                ..._controllers
                    .asMap()
                    .entries
                    .map((e) => _buildPatientFormCard(e.key, e.value)),
                OutlinedButton.icon(
                    onPressed: _addNewPatient,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Another Patient"),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentTeal)),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentTeal),
                    onPressed: isLoading
                        ? null
                        : () async {
                            setState(() => isLoading = true);
                            await FirebaseFirestore.instance
                                .collection('department_entries')
                                .add({
                              "userId": widget.userId,
                              "userName": widget.userName,
                              "date": widget.selectedDate,
                              "timeSlot": widget.slot,
                              "role": widget.role,
                              "submitted": true,
                              "timestamp": FieldValue.serverTimestamp(),
                              "patients": _controllers
                                  .map((c) => {
                                        "staffName": c['staff']!.text,
                                        "patientName": c['patient']!.text,
                                        "opNumber": c['op']!.text,
                                        "procedure": c['proc']!.text
                                      })
                                  .toList(),
                            });
                            Navigator.pop(context);
                          },
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("SUBMIT LOGS",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)))),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientFormCard(
      int index, Map<String, TextEditingController> c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.teal.shade50)),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: AppColors.accent,
                  radius: 12,
                  child: Text("${index + 1}",
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white))),
              const SizedBox(width: 10),
              const Text("Patient Details",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_controllers.length > 1)
                IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.redAccent),
                    onPressed: () =>
                        setState(() => _controllers.removeAt(index)))
            ]),
            const Divider(height: 25),
            _buildField(c['staff']!, "Staff Name", Icons.person_outline),
            _buildField(
                c['patient']!, "Patient Name", Icons.medical_services_outlined),
            _buildField(c['op']!, "OP Number", Icons.tag),
            _buildField(c['proc']!, "Procedure", Icons.edit_note),
          ])),
    );
  }

  Widget _buildField(
      TextEditingController controller, String label, IconData icon) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: controller,
            decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon, color: AppColors.accentTeal, size: 20),
                filled: true,
                fillColor: AppColors.background.withOpacity(0.5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none))));
  }
}
