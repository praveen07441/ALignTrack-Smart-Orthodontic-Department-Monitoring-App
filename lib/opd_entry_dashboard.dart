import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

// Import local services
import 'chat_screen.dart';

// ================= PREMIUM THEME CONFIG =================
class AppColors {
  static const Color primary = Color(0xFFC8E6C9);
  static const Color accent = Color(0xFFA5D6A7);
  static const Color background = Color(0xFFF1F8E9);
  static const Color accentTeal = Color(0xFF00695C);
}

class OpdEntryDashboard extends StatefulWidget {
  final String userId;
  final String userName;

  const OpdEntryDashboard({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<OpdEntryDashboard> createState() => _OpdEntryDashboardState();
}

class _OpdEntryDashboardState extends State<OpdEntryDashboard> {
  final List<Map<String, TextEditingController>> _controllers = [];
  bool isLoading = false;
  bool isExporting = false;
  DateTime selectedDate = DateTime.now();

  String get formattedDate => DateFormat('yyyy-MM-dd').format(selectedDate);

  @override
  void initState() {
    super.initState();
    _addNewEntry();
  }

  @override
  void dispose() {
    // CLEANUP: Dispose all dynamic controllers to prevent memory leaks
    for (var group in _controllers) {
      group.values.forEach((controller) => controller.dispose());
    }
    super.dispose();
  }

  void _addNewEntry() {
    setState(() => _controllers.add({
          "pgName": TextEditingController(),
          "patient": TextEditingController(),
          "op": TextEditingController(),
          "diagnosis": TextEditingController(),
          "allottedTo": TextEditingController(),
        }));
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
            role: "OPD Entry",
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

  // ================= ✅ PREMIUM 1 MONTH PDF EXPORT =================
  Future<void> _exportMonthlyOPDPDF() async {
    setState(() => isExporting = true);
    try {
      final pdf = pw.Document();
      DateTime endDate = selectedDate;
      DateTime startDate = endDate.subtract(const Duration(days: 30));

      final snapshot = await FirebaseFirestore.instance
          .collection('department_entries')
          .where('role', isEqualTo: 'OPD Entry')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('timestamp', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No records for this period.")));
        }
        return;
      }

      List<List<String>> rows = [];
      int serialNo = 1;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String time = data['timestamp'] != null
            ? DateFormat('hh:mm a')
                .format((data['timestamp'] as Timestamp).toDate())
            : '-';

        rows.add([
          "${serialNo++}",
          "${data['date'] ?? '-'}\n$time",
          data['opNumber'] ?? '-',
          data['patientName'] ?? '-',
          data['pgStudentName'] ?? '-',
          "Diag: ${data['diagnosis'] ?? '-'}\nAllot: ${data['caseAllottedTo'] ?? '-'}",
        ]);
      }

      pdf.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(children: [
                pw.Text("OPD REGISTRATION REPORT",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 18,
                        color: PdfColors.teal900)),
                pw.Text("Registrar: ${widget.userName}",
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
                    "OP No",
                    "Patient Name",
                    "Assigned PG",
                    "Clinical Details"
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
                    0: const pw.FixedColumnWidth(35),
                    1: const pw.FixedColumnWidth(80),
                    2: const pw.FixedColumnWidth(60),
                    3: const pw.FixedColumnWidth(100),
                    4: const pw.FixedColumnWidth(100),
                    5: const pw.FixedColumnWidth(250),
                  },
                  cellPadding: const pw.EdgeInsets.all(6),
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                ),
              ]));

      await Printing.layoutPdf(
          onLayout: (format) async => pdf.save(), name: 'OPD_Report');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("PDF Error: $e")));
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
  }

  // ================= ✅ SMART CHAT ICON =================
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
        return Stack(alignment: Alignment.center, children: [
          IconButton(
              icon: const Icon(Icons.chat_bubble_outline,
                  color: Colors.black, size: 26),
              onPressed: _getHodAndNavigate),
          if (unreadCount > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            ),
        ]);
      },
    );
  }

  Future<void> _validateAndSubmit() async {
    // Validation check
    for (int i = 0; i < _controllers.length; i++) {
      if (_controllers[i].values.any((c) => c.text.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text("Fill all fields for Patient #${i + 1}")),
        );
        return;
      }
    }

    setState(() => isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (var group in _controllers) {
        DocumentReference doc =
            FirebaseFirestore.instance.collection('department_entries').doc();
        batch.set(doc, {
          "userId": widget.userId,
          "userName": widget.userName,
          "pgStudentName": group['pgName']!.text.trim(),
          "patientName": group['patient']!.text.trim(),
          "opNumber": group['op']!.text.trim(),
          "diagnosis": group['diagnosis']!.text.trim(),
          "caseAllottedTo": group['allottedTo']!.text.trim(),
          "role": "OPD Entry",
          "date": formattedDate,
          "submitted": true,
          "timestamp": FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Logs submitted successfully!")));
        Navigator.pop(context);
      }
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
        title: const Text("OPD Entry",
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
                  onPressed: _exportMonthlyOPDPDF),
          _buildChatIcon(),
        ],
      ),
      body: Column(
        children: [
          _buildHeaderDatePicker(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _controllers.length,
              itemBuilder: (context, index) =>
                  _buildPatientCard(index, _controllers[index]),
            ),
          ),
          _buildBottomActionArea(),
        ],
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(DateFormat('EEEE, dd MMM yyyy').format(selectedDate),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Icon(Icons.calendar_month,
                color: AppColors.accentTeal, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildPatientCard(
      int index, Map<String, TextEditingController> controllers) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Patient #${index + 1}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_controllers.length > 1)
              IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () =>
                      setState(() => _controllers.removeAt(index))),
          ]),
          const Divider(),
          _buildField(
              controllers['pgName']!, "PG Student Name", Icons.account_circle),
          _buildField(controllers['patient']!, "Patient Name", Icons.person),
          _buildField(controllers['op']!, "OP Number", Icons.tag),
          _buildField(controllers['diagnosis']!, "Diagnosis", Icons.analytics),
          _buildField(controllers['allottedTo']!, "Case Allotted To",
              Icons.assignment_ind),
        ]),
      ),
    );
  }

  Widget _buildField(
      TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.accentTeal),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
        ),
      ),
    );
  }

  Widget _buildBottomActionArea() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton.icon(
          onPressed: _addNewEntry,
          icon: const Icon(Icons.add),
          label: const Text("Add Another Patient"),
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentTeal,
              minimumSize: const Size(double.infinity, 45)),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: isLoading ? null : _validateAndSubmit,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentTeal,
              minimumSize: const Size(double.infinity, 55)),
          child: isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text("SUBMIT TO DEPARTMENT",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
