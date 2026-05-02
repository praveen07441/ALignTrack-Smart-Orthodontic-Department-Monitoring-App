import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'chat_screen.dart';

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

  // ================= ✅ OPTIMIZED MARK AS SEEN =================
  Future<void> _markMessagesAsSeen() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      final groupSnapshot = await FirebaseFirestore.instance
          .collection('chat')
          .where('type', isEqualTo: 'group')
          .get();

      for (var doc in groupSnapshot.docs) {
        final data = doc.data();
        if (data['userId'] == widget.userId) continue;
        final seenBy = List.from(data['seenBy'] ?? []);
        if (!seenBy.contains(widget.userId)) {
          batch.update(doc.reference, {
            'seenBy': FieldValue.arrayUnion([widget.userId])
          });
          hasUpdates = true;
        }
      }

      final hodSnapshot = await FirebaseFirestore.instance
          .collection('chat')
          .where('type', isEqualTo: 'hod')
          .where('targetUserId', isEqualTo: widget.userId)
          .get();

      for (var doc in hodSnapshot.docs) {
        final data = doc.data();
        if (data['userId'] == widget.userId) continue;
        final seenBy = List.from(data['seenBy'] ?? []);
        if (!seenBy.contains(widget.userId)) {
          batch.update(doc.reference, {
            'seenBy': FieldValue.arrayUnion([widget.userId])
          });
          hasUpdates = true;
        }
      }

      if (hasUpdates) await batch.commit();
    } catch (e) {
      debugPrint("Badge reset error: $e");
    }
  }

  // ================= ✅ NAVIGATE TO CHAT =================
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
      final String hodName = hodQuery.docs.first.data()['name'] ?? 'HOD';

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            userId: widget.userId,
            userName: widget.userName,
            role: "PG",
            targetUserId: hodUid,
            targetUserName: hodName,
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

  // ================= ✅ OPTIMIZED CHAT BADGE COUNTER =================
  Widget _buildChatIcon() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat')
          .where('type', isEqualTo: 'group')
          .snapshots(),
      builder: (context, groupSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chat')
              .where('type', isEqualTo: 'hod')
              .where('targetUserId', isEqualTo: widget.userId)
              .snapshots(),
          builder: (context, hodSnap) {
            int unreadCount = 0;

            if (groupSnap.hasData) {
              for (var doc in groupSnap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['userId'] == widget.userId) continue;
                final seenBy = List.from(data['seenBy'] ?? []);
                if (!seenBy.contains(widget.userId)) unreadCount++;
              }
            }

            if (hodSnap.hasData) {
              for (var doc in hodSnap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['userId'] == widget.userId) continue;
                final seenBy = List.from(data['seenBy'] ?? []);
                if (!seenBy.contains(widget.userId)) unreadCount++;
              }
            }

            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                    icon: const Icon(Icons.chat_bubble_outline,
                        color: Colors.black, size: 26),
                    onPressed: () async {
                      await _markMessagesAsSeen();
                      _getHodAndNavigate();
                    }),
                if (unreadCount > 0)
                  Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.primary, width: 1.5)),
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
      },
    );
  }

  // ================= ✅ PDF EXPORT LOGIC (FIXED FOR iOS) =================
  Future<void> _exportMonthlyPGPDF() async {
    setState(() => isExporting = true);
    try {
      final pdf = pw.Document();
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
              content: Text("No clinical records found for this period.")));
        }
        return;
      }

      List<List<String>> rows = [];
      int serialNo = 1;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final patients = data['patients'] as List? ?? [];
        final dateLabel = data['date'] ?? '-';
        final String time = data['timestamp'] != null
            ? DateFormat('hh:mm a')
                .format((data['timestamp'] as Timestamp).toDate())
            : '-';

        for (var p in patients) {
          rows.add([
            "${serialNo++}",
            "$dateLabel\n$time",
            data['timeSlot'] ?? '-',
            p['staffName'] ?? '-',
            "Pt: ${p['patientName']}\nOP: ${p['opNumber']}",
            p['procedure'] ?? '-'
          ]);
        }
      }

      pdf.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(children: [
                pw.Text("PG CLINICAL LOG PERFORMANCE REPORT",
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
                    "S.No",
                    "Date/Time",
                    "Slot",
                    "Staff",
                    "Patient Info",
                    "Procedure Detail"
                  ],
                  data: rows,
                  headerStyle: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.teal900),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(35),
                    1: const pw.FixedColumnWidth(85),
                    2: const pw.FixedColumnWidth(100),
                    3: const pw.FixedColumnWidth(100),
                    4: const pw.FixedColumnWidth(150),
                    5: const pw.FixedColumnWidth(250),
                  },
                  cellPadding: const pw.EdgeInsets.all(6),
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                ),
              ],
          footer: (context) => pw.Container(
                alignment: pw.Alignment.centerRight,
                padding: const pw.EdgeInsets.only(top: 20),
                child: pw.Text(
                    "Page ${context.pageNumber} | Clinical Monitoring App",
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey600)),
              )));

      // ✅ FIX: Save bytes first to prevent iOS Layout errors
      final pdfBytes = await pdf.save();

      await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes, name: 'PG_Clinical_Log_Report');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("PDF Error: $e")));
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
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
                  child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black)))
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined,
                      color: Colors.black),
                  onPressed: _exportMonthlyPGPDF),
          _buildChatIcon(),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeaderDatePicker(),
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
              lastDate: DateTime(2030),
              builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                          primary: AppColors.accentTeal)),
                  child: child!));
          if (d != null) setState(() => selectedDate = d);
        },
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('EEEE, dd MMM yyyy').format(selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Icon(Icons.calendar_month, color: AppColors.accentTeal)
                ])),
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
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: "Task Title*")),
            TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: "Description")),
            ListTile(
              title: Text(selectedTime == null
                  ? "Pick Time"
                  : "Time: ${selectedTime!.format(context)}"),
              onTap: () async {
                final t = await showTimePicker(
                    context: context, initialTime: TimeOfDay.now());
                if (t != null) setDialogState(() => selectedTime = t);
              },
            )
          ]),
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
                    'description': descController.text,
                    'status': 'pending',
                    'date': formattedDate,
                    'time': selectedTime?.format(context) ?? "No Time",
                  });
                  Navigator.pop(context);
                },
                child: const Text("Save"))
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("MY REMINDERS",
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.black54)),
            IconButton(
                onPressed: _showAddReminderDialog,
                icon:
                    const Icon(Icons.add_circle, color: AppColors.accentTeal)),
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
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
              return const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(
                    child: Text("No clinical tasks for today",
                        style: TextStyle(color: Colors.grey, fontSize: 12))),
              );
            return ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: snapshot.data!.docs.map((doc) {
                var data = doc.data() as Map<String, dynamic>;
                return CheckboxListTile(
                  value: data['status'] == 'completed',
                  title: Text(data['title'],
                      style: TextStyle(
                          decoration: data['status'] == 'completed'
                              ? TextDecoration.lineThrough
                              : null)),
                  subtitle: Text(
                      "${data['time'] ?? ''} ${data['description'] ?? ''}"),
                  onChanged: (val) => doc.reference
                      .update({'status': val! ? 'completed' : 'pending'}),
                );
              }).toList(),
            );
          },
        )
      ],
    );
  }
}

// ================= ENTRY SCREEN (Features Preserved) =================
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

  @override
  void dispose() {
    for (var cMap in _controllers) {
      cMap.values.forEach((controller) => controller.dispose());
    }
    super.dispose();
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
          title: Text("Log Entry: ${widget.slot}"),
          backgroundColor: AppColors.primary),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _controllers.length,
              itemBuilder: (context, index) =>
                  _buildPatientFormCard(index, _controllers[index]),
            ),
          ),
          _buildSubmitButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewPatient,
        backgroundColor: AppColors.accentTeal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
          style:
              ElevatedButton.styleFrom(backgroundColor: AppColors.accentTeal),
          onPressed: isLoading ? null : _submitLogs,
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text("SUBMIT LOGS",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Future<void> _submitLogs() async {
    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('department_entries').add({
        "userId": widget.userId,
        "userName": widget.userName,
        "date": widget.selectedDate,
        "timeSlot": widget.slot,
        "role": widget.role,
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
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Submission Failed: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildPatientFormCard(
      int index, Map<String, TextEditingController> c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Text("Patient #${index + 1}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_controllers.length > 1)
              IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () =>
                      setState(() => _controllers.removeAt(index))),
          ]),
          TextField(
              controller: c['staff'],
              decoration: const InputDecoration(labelText: "Staff Name")),
          TextField(
              controller: c['patient'],
              decoration: const InputDecoration(labelText: "Patient Name")),
          TextField(
              controller: c['op'],
              decoration: const InputDecoration(labelText: "OP Number")),
          TextField(
              controller: c['proc'],
              decoration: const InputDecoration(labelText: "Procedure")),
        ]),
      ),
    );
  }
}
