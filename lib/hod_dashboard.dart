import 'dart:io';
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
  static const Color background = Color(0xFFF8FAF8);
  static const Color submitted = Color(0xFF2E7D32);
  static const Color submittedBg = Color(0xFFE8F5E9);
  static const Color pending = Color(0xFFF57C00);
  static const Color pendingBg = Color(0xFFFFF3E0);
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

  // Helper: Prevents PDF crashes by limiting text length
  String safeText(String? text, {int limit = 100}) {
    if (text == null || text.isEmpty) return "-";
    return text.length > limit ? "${text.substring(0, limit)}..." : text;
  }

  // ✅ Improvement 1: Safe Date Parser to prevent crashes on bad data
  DateTime _parseSafeDate(String dateStr) {
    try {
      return DateFormat('yyyy-MM-dd').parse(dateStr);
    } catch (e) {
      debugPrint("Date Parsing Error: $dateStr - $e");
      return DateTime(2000); // Safe fallback for sorting
    }
  }

  // ================= ✅ STABLE UNREAD RESET LOGIC =================
  Future<void> _markMessagesAsSeen() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('chat')
          .orderBy('clientTimestamp', descending: true)
          .limit(200)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final seenBy = List.from(data['seenBy'] ?? []);

        bool isRelevant = data['type'] == 'group' ||
            data['targetUserId'] == widget.userId ||
            data['userId'] == widget.userId;

        if (isRelevant && !seenBy.contains(widget.userId)) {
          batch.update(doc.reference, {
            'seenBy': FieldValue.arrayUnion([widget.userId])
          });
          hasUpdates = true;
        }
      }
      if (hasUpdates) await batch.commit();
    } catch (e) {
      debugPrint("Seen update error: $e");
    }
  }

  void _openCommonChat() {
    _markMessagesAsSeen();
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
    _markMessagesAsSeen();
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

  // ================= ✅ DYNAMIC PDF EXPORT LOGIC =================
  Future<void> exportPDF(int days) async {
    setState(() => isExporting = true);

    try {
      final pdf = pw.Document();
      DateTime endDate = selectedDate;
      DateTime startDate = endDate.subtract(Duration(days: days));

      final snapshot = await FirebaseFirestore.instance
          .collection('department_entries')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('timestamp', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No records found for this range.")),
          );
        }
        return;
      }

      List<List<String>> masterData = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['userName'] ?? 'Unknown';
        final role = data['role'] ?? '-';
        final date = data['date'] ?? '-';

        if (role == "PG") {
          final patients =
              List<Map<String, dynamic>>.from(data['patients'] ?? []);
          for (var p in patients) {
            masterData.add([
              "", // Serial placeholder
              "$date",
              "$name",
              "PG Clinical",
              "Pt: ${safeText(p['patientName'])} | OP: ${safeText(p['opNumber'])}",
              "Staff: ${safeText(p['staffName'])} | Proc: ${safeText(p['procedure'])}"
            ]);
          }
        } else if (role == "Faculty") {
          final workEntries =
              List<Map<String, dynamic>>.from(data['workEntries'] ?? []);
          for (var w in workEntries) {
            masterData.add([
              "",
              "$date",
              "$name",
              "Faculty",
              "Cat: ${safeText(w['category'])}",
              "Details: ${safeText(w['details'])}"
            ]);
          }
        } else if (role == "OPD Entry") {
          masterData.add([
            "",
            "$date",
            "$name",
            "OPD Unit",
            "Pt: ${safeText(data['patientName'])} | OP: ${safeText(data['opNumber'])}",
            "PG: ${safeText(data['pgStudentName'])} | Diag: ${safeText(data['diagnosis'])}"
          ]);
        }
      }

      // ✅ STEP 5: SORTING (Latest First) with Safe Date Parsing
      masterData.sort((a, b) {
        DateTime dateA = _parseSafeDate(a[1]);
        DateTime dateB = _parseSafeDate(b[1]);
        return dateB.compareTo(dateA);
      });

      // ✅ STEP 6: ADAPTIVE LIMIT (Improvement 2)
      // Tighten limit for 2-month ranges to maintain speed on old hardware
      int adaptiveLimit = days > 30 ? 300 : 500;
      if (masterData.length > adaptiveLimit) {
        masterData = masterData.take(adaptiveLimit).toList();
      }

      // ✅ RE-ASSIGN SERIAL NUMBERS
      for (int i = 0; i < masterData.length; i++) {
        masterData[i][0] = "${i + 1}";
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Column(children: [
            pw.Text("DEPARTMENT ACTIVITY REPORT",
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 16,
                    color: PdfColors.teal900)),
            pw.SizedBox(height: 4),
            pw.Text(
              "${DateFormat('dd MMM yyyy').format(startDate)}  →  ${DateFormat('dd MMM yyyy').format(endDate)}",
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 4),
            if (masterData.length >= adaptiveLimit)
              pw.Text("(Showing latest $adaptiveLimit records for stability)",
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.red)),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 1.5, color: PdfColors.teal900),
            pw.SizedBox(height: 10),
          ]),
          build: (context) => [
            pw.Table.fromTextArray(
              headers: [
                "S.No",
                "Date",
                "User",
                "Log Type",
                "Primary Details",
                "Secondary Details"
              ],
              data: masterData,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.teal900),
              headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellHeight: 22,
              columnWidths: {
                0: const pw.FixedColumnWidth(25),
                1: const pw.FixedColumnWidth(55),
                2: const pw.FixedColumnWidth(65),
                3: const pw.FixedColumnWidth(60),
                4: const pw.FixedColumnWidth(130),
                5: const pw.FixedColumnWidth(160),
              },
            ),
          ],
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
                "Page ${context.pageNumber} of ${context.pagesCount}",
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          ),
        ),
      );

      final pdfBytes = await pdf.save();

      if (Platform.isIOS) {
        await Printing.sharePdf(
            bytes: pdfBytes, filename: 'Dept_Report_${days}days.pdf');
      } else {
        await Printing.layoutPdf(
            onLayout: (format) async => pdfBytes,
            name: 'Dept_Report_${days}days');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("PDF Error: $e")));
      }
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
  }

  // ✅ EXPORT OPTIONS UI
  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Export PDF Report",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 15),
            _exportOptionTile("Past 24 Hours", Icons.today, 1),
            _exportOptionTile("Past 1 Week", Icons.date_range, 7),
            _exportOptionTile("Past 1 Month", Icons.calendar_month, 30),
            _exportOptionTile("Past 2 Months", Icons.history, 60),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _exportOptionTile(String title, IconData icon, int days) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accentTeal),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        exportPDF(days);
      },
    );
  }

  // ================= ✅ MONITORING UI (KEEP FEATURES) =================
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
            final data = doc.data() as Map<String, dynamic>;
            total += (data['patients']?.length ??
                data['workEntries']?.length ??
                1) as int;
          }
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.accentTeal)),
                  Text("Total Entries: $total",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Colors.black54)),
                ]),
          ),
          _buildUserList(role),
        ]);
      },
    );
  }

  Widget _buildUserList(String role) {
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
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: Text("No data found for this date",
                      style: TextStyle(color: Colors.grey, fontSize: 13))));
        }
        return Column(
            children: snap.data!.docs
                .map((d) => role == "OPD Entry"
                    ? _opdDetailCard(d)
                    : _userExpansionCard(d, role))
                .toList());
      },
    );
  }

  Widget _userExpansionCard(DocumentSnapshot user, String role) {
    final name = (user.data() as Map<String, dynamic>)['name'] ?? "Unknown";
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('department_entries')
          .where('userId', isEqualTo: user.id)
          .where('date', isEqualTo: formattedDate)
          .snapshots(),
      builder: (context, logSnap) {
        if (!logSnap.hasData) return const SizedBox();
        bool hasData = logSnap.data!.docs.isNotEmpty;
        int entryCount = 0;
        if (hasData) {
          for (var doc in logSnap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            entryCount += (data['patients']?.length ??
                data['workEntries']?.length ??
                1) as int;
          }
        }
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Colors.grey.shade200)),
          color: hasData ? AppColors.submittedBg : AppColors.pendingBg,
          child: ExpansionTile(
            shape: const Border(),
            leading: CircleAvatar(
              backgroundColor:
                  hasData ? AppColors.submitted : AppColors.pending,
              child: Icon(hasData ? Icons.check : Icons.access_time,
                  color: Colors.white, size: 20),
            ),
            title: Text(name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
                hasData
                    ? "Submitted • $entryCount entries"
                    : "Pending Submission",
                style: TextStyle(
                    fontSize: 12,
                    color: hasData ? AppColors.submitted : AppColors.pending)),
            trailing: IconButton(
                icon: const Icon(Icons.forum_outlined,
                    color: AppColors.accentTeal),
                onPressed: () => _openPrivateChat(user.id, name)),
            children: hasData
                ? logSnap.data!.docs
                    .map((d) => _entryDetailList(d, role))
                    .toList()
                : [],
          ),
        );
      },
    );
  }

  Widget _entryDetailList(DocumentSnapshot doc, String role) {
    final data = doc.data() as Map<String, dynamic>;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (role == "PG")
          ...(data['patients'] as List)
              .map((p) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow("Staff", p['staffName'], Icons.person_search),
                        _infoRow("Patient", p['patientName'], Icons.person),
                        _infoRow("OP No", p['opNumber'], Icons.numbers),
                        _infoRow("Procedure", p['procedure'],
                            Icons.medical_services),
                        const Divider(),
                      ]))
              .toList()
        else if (role == "Faculty")
          ...(data['workEntries'] as List)
              .map((w) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow("Category", w['category'], Icons.category),
                        _infoRow("Details", w['details'], Icons.description),
                        const Divider(),
                      ]))
              .toList()
      ]),
    );
  }

  Widget _opdDetailCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: Colors.black12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          _infoRow("Patient", data['patientName'], Icons.person_outline),
          _infoRow("Diagnosis", data['diagnosis'], Icons.biotech),
          _infoRow("PG Assigned", data['pgStudentName'], Icons.assignment_ind),
        ]),
      ),
    );
  }

  Widget _infoRow(String label, String? value, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 14, color: AppColors.accentTeal),
          const SizedBox(width: 8),
          Text("$label: ",
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Expanded(
              child: Text(value ?? "-", style: const TextStyle(fontSize: 12))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("HOD Management",
            style:
                TextStyle(color: Colors.black87, fontWeight: FontWeight.w900)),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          isExporting
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(15),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))))
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined,
                      color: Colors.black87),
                  onPressed: _showExportOptions),
          _buildChatIcon(),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildHeaderDatePicker(),
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sectionTitle("PRIVATE ADMIN TASKS", Icons.add_circle_outline,
                  _showHODTaskDialog),
              const Divider(),
              _sectionTitle("LIVE SUBMISSION MONITORING", null, null),
              _buildMonitoringCategory("PG Students (Clinical Logs)", "PG"),
              _buildMonitoringCategory("Faculty Work Logs", "Faculty"),
              _buildMonitoringCategory("OPD Registration Unit", "OPD Entry"),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData? icon, VoidCallback? onTap) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black45,
              fontSize: 11,
              letterSpacing: 1.1)),
      if (icon != null)
        IconButton(
            onPressed: onTap, icon: Icon(icon, color: AppColors.accentTeal)),
    ]);
  }

  Widget _buildChatIcon() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat')
          .orderBy('clientTimestamp', descending: true)
          .limit(150)
          .snapshots(),
      builder: (context, snapshot) {
        int unread = 0;
        if (snapshot.hasData) {
          unread = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final seenBy = List.from(data['seenBy'] ?? []);
            bool isRelevant = data['type'] == 'group' ||
                data['targetUserId'] == widget.userId ||
                data['userId'] == widget.userId;
            return isRelevant &&
                !seenBy.contains(widget.userId) &&
                data['userId'] != widget.userId;
          }).length;
        }
        return Stack(alignment: Alignment.center, children: [
          IconButton(
              icon: const Icon(Icons.forum_outlined, color: Colors.black87),
              onPressed: _openCommonChat),
          if (unread > 0)
            Positioned(
                right: 8,
                top: 8,
                child: CircleAvatar(
                    radius: 9,
                    backgroundColor: Colors.red,
                    child: Text(unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)))),
        ]);
      },
    );
  }

  Widget _buildHeaderDatePicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 25),
      decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(35),
              bottomRight: Radius.circular(35)),
          boxShadow: [
            BoxShadow(
                color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
          ]),
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
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE').format(selectedDate),
                  style: const TextStyle(
                      color: Colors.black38,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              Text(DateFormat('dd MMMM, yyyy').format(selectedDate),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.accentTeal)),
            ]),
            const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.calendar_today_rounded,
                    color: AppColors.accent, size: 20)),
          ]),
        ),
      ),
    );
  }

  void _showHODTaskDialog() {
    final ctrl = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("New Admin Task"),
              content: TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(hintText: "Enter task...")),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
                ElevatedButton(
                    onPressed: () async {
                      if (ctrl.text.isEmpty) return;
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.userId)
                          .collection('reminders')
                          .add({
                        'title': ctrl.text,
                        'status': 'pending',
                        'date': formattedDate,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      Navigator.pop(context);
                    },
                    child: const Text("Save")),
              ],
            ));
  }
}
