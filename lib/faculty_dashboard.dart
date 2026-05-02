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
  static const Color accentTeal = Color(0xFF00695C);
  static const Color submitted = Color(0xFF2E7D32);
  static const Color textDark = Color(0xFF2D3436);
}

class FacultyDashboard extends StatefulWidget {
  final String userId;
  final String userName;

  const FacultyDashboard({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends State<FacultyDashboard> {
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
  }

  // ================= ✅ SMART CHAT & BADGE RESET LOGIC =================
  Future<void> _markMessagesAsSeen() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('chat').get();
      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final seenBy = List.from(data['seenBy'] ?? []);

        bool isRelevant = data['type'] == 'group' ||
            (data['type'] == 'hod' && data['targetUserId'] == widget.userId);

        if (isRelevant && !seenBy.contains(widget.userId)) {
          batch.update(doc.reference, {
            'seenBy': FieldValue.arrayUnion([widget.userId])
          });
          hasUpdates = true;
        }
      }
      if (hasUpdates) await batch.commit();
    } catch (e) {
      debugPrint("Faculty Badge reset error: $e");
    }
  }

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
            role: "Faculty",
            targetUserId: hodUid,
            targetUserName: "HOD Desk",
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error syncing with HOD: $e")),
        );
      }
    }
  }

  Widget _buildChatIcon() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chat').snapshots(),
      builder: (context, snapshot) {
        int unreadCount = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final seenBy = List.from(data['seenBy'] ?? []);
            if (data['userId'] == widget.userId) continue;

            bool isRelevant = data['type'] == 'group' ||
                (data['type'] == 'hod' &&
                    data['targetUserId'] == widget.userId);

            if (isRelevant && !seenBy.contains(widget.userId)) {
              unreadCount++;
            }
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

  // ================= ✅ PDF EXPORT LOGIC (iOS FIXED) =================
  Future<void> _exportMonthlyFacultyPDF() async {
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
              content: Text("No work logs found for this 30-day period.")));
        }
        return;
      }

      List<List<String>> rows = [];
      int serialNo = 1;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final workEntries = data['workEntries'] as List? ?? [];
        final dateLabel = data['date'] ?? '-';
        final String time = data['timestamp'] != null
            ? DateFormat('hh:mm a')
                .format((data['timestamp'] as Timestamp).toDate())
            : '-';

        for (var entry in workEntries) {
          rows.add([
            "${serialNo++}",
            "$dateLabel\n$time",
            data['timeSlot'] ?? '-',
            entry['category'] ?? '-',
            entry['details'] ?? '-'
          ]);
        }
      }

      pdf.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(children: [
                pw.Text("FACULTY PERFORMANCE LOG REPORT",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 18,
                        color: PdfColors.teal900)),
                pw.Text("Faculty: ${widget.userName}",
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
                    "Time Slot",
                    "Category",
                    "Work Details"
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
                    4: const pw.FixedColumnWidth(280),
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

      // ✅ FIXED: Pre-save bytes to variable for iOS compatibility
      final pdfBytes = await pdf.save();

      await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes, name: 'Faculty_Monthly_Log');
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
        title: const Text("Faculty Dashboard",
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
                  onPressed: _exportMonthlyFacultyPDF),
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
            subtitle: Text(isDone ? "Logs Submitted" : "No logs recorded",
                style: TextStyle(
                    color: isDone ? AppColors.submitted : Colors.grey)),
            trailing: Icon(
                isDone ? Icons.check_circle : Icons.arrow_forward_ios,
                color: isDone ? AppColors.submitted : Colors.grey,
                size: 20),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => FacultyEntryScreen(
                        userId: widget.userId,
                        userName: widget.userName,
                        slot: slot,
                        date: formattedDate))),
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
          title: const Text("New Faculty Task",
              style: TextStyle(
                  color: AppColors.accentTeal, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ],
          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("MY REMINDERS",
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
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
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
              return const Center(
                  child: Text("No reminders for today",
                      style: TextStyle(color: Colors.grey, fontSize: 12)));
            return ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: snapshot.data!.docs.map((doc) {
                var data = doc.data() as Map<String, dynamic>;
                bool isDone = data['status'] == 'completed';
                return CheckboxListTile(
                  value: isDone,
                  title: Text(data['title'],
                      style: TextStyle(
                          decoration:
                              isDone ? TextDecoration.lineThrough : null)),
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

// ================= FACULTY ENTRY SCREEN (Features Preserved) =================
class FacultyEntryScreen extends StatefulWidget {
  final String userId, userName, slot, date;
  const FacultyEntryScreen(
      {super.key,
      required this.userId,
      required this.userName,
      required this.slot,
      required this.date});
  @override
  State<FacultyEntryScreen> createState() => _FacultyEntryScreenState();
}

class _FacultyEntryScreenState extends State<FacultyEntryScreen> {
  final List<Map<String, dynamic>> _entries = [];
  final List<String> categories = [
    "Teaching",
    "Clinical supervision",
    "NAAC work",
    "Admin work",
    "Records",
    "Other"
  ];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _addEntry();
  }

  @override
  void dispose() {
    for (var entry in _entries) {
      (entry['controller'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _addEntry() {
    setState(() => _entries
        .add({"category": null, "controller": TextEditingController()}));
  }

  Future<void> _submit() async {
    setState(() => isLoading = true);
    try {
      List workData = _entries
          .map((e) => {
                "category": e['category'],
                "details":
                    (e['controller'] as TextEditingController).text.trim()
              })
          .toList();

      await FirebaseFirestore.instance.collection('department_entries').add({
        "userId": widget.userId,
        "userName": widget.userName,
        "role": "Faculty",
        "date": widget.date,
        "timeSlot": widget.slot,
        "workEntries": workData,
        "submitted": true,
        "timestamp": FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          title: Text("Work Log: ${widget.slot}"),
          backgroundColor: AppColors.primary,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context))),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _entries.length,
              itemBuilder: (context, index) =>
                  _buildWorkCard(index, _entries[index]),
            ),
          ),
          _buildSubmitBar(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        backgroundColor: AppColors.accentTeal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildWorkCard(int index, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Text("Entry #${index + 1}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_entries.length > 1)
              IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () => setState(() => _entries.removeAt(index))),
          ]),
          DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Category"),
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (val) => data['category'] = val),
          const SizedBox(height: 12),
          TextField(
              controller: data['controller'],
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: "Details",
                  filled: true,
                  border: OutlineInputBorder())),
        ]),
      ),
    );
  }

  Widget _buildSubmitBar() {
    return Container(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
                onPressed: isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentTeal),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("SUBMIT WORK LOG",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)))));
  }
}
