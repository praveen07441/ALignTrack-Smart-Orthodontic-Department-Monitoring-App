import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ChatColors {
  static const Color primaryTeal = Color(0xFF075E54);
  static const Color background = Color(0xFFE5DDD5);
  static const Color myBubble = Color(0xFFDCF8C6);
  static const Color otherBubble = Colors.white;
  static const Color appBarGreen = Color(0xFFC8E6C9);
}

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String role;
  final String? targetUserId;
  final String? targetUserName;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.role,
    this.targetUserId,
    this.targetUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _msgController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool get _isPrivateChat => widget.targetUserId != null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _isPrivateChat ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  // ================= ✅ FINAL CORRECTED MESSAGE LOGIC =================

  Future<void> _sendMessage(String chatType) async {
    if (_msgController.text.trim().isEmpty) return;
    final text = _msgController.text.trim();
    _msgController.clear();

    // 🔥 CRITICAL FIX: Ensure targetUserId is NOT a placeholder.
    // If students/faculty are in HOD Desk, they must pass the actual HOD UID.
    String ownerId;
    if (widget.role == "HOD") {
      ownerId = widget.targetUserId ?? widget.userId;
    } else {
      // 🚨 Ensure you pass HOD's UID from the Dashboard navigation!
      ownerId = widget.targetUserId!;
    }

    await FirebaseFirestore.instance.collection('chat').add({
      "text": text,
      "userId": widget.userId,
      "userName": widget.userName,
      "role": widget.role,
      "type": chatType,
      "targetUserId": ownerId,
      "seenBy": [widget.userId],
      "timestamp": FieldValue.serverTimestamp(),
      "clientTimestamp": DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _handleImage(String chatType) async {
    try {
      final XFile? image = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;

      if (!mounted) return;
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()));

      final fileName = 'chat/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child(fileName);
      await ref.putFile(File(image.path));
      final url = await ref.getDownloadURL();

      String ownerId = (widget.role == "HOD")
          ? (widget.targetUserId ?? widget.userId)
          : widget.targetUserId!;

      await FirebaseFirestore.instance.collection('chat').add({
        "imageUrl": url,
        "userId": widget.userId,
        "userName": widget.userName,
        "role": widget.role,
        "type": chatType,
        "targetUserId": ownerId,
        "seenBy": [widget.userId],
        "timestamp": FieldValue.serverTimestamp(),
        "clientTimestamp": DateTime.now().millisecondsSinceEpoch,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Upload failed: $e")));
      }
    }
  }

  // ================= ✅ STABLE SEEN_BY UPDATER =================

  Widget _buildChatList(String type) {
    Query chatQuery;
    if (type == "hod") {
      if (widget.role == "HOD" && _isPrivateChat) {
        chatQuery = FirebaseFirestore.instance
            .collection('chat')
            .where('type', isEqualTo: 'hod')
            .where('targetUserId', isEqualTo: widget.targetUserId)
            .orderBy('clientTimestamp', descending: true);
      } else if (widget.role == "HOD") {
        chatQuery = FirebaseFirestore.instance
            .collection('chat')
            .where('type', isEqualTo: 'hod')
            .orderBy('clientTimestamp', descending: true);
      } else {
        chatQuery = FirebaseFirestore.instance
            .collection('chat')
            .where('type', isEqualTo: 'hod')
            .where('targetUserId', isEqualTo: widget.userId)
            .orderBy('clientTimestamp', descending: true);
      }
    } else {
      chatQuery = FirebaseFirestore.instance
          .collection('chat')
          .where('type', isEqualTo: 'group')
          .orderBy('clientTimestamp', descending: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: chatQuery.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (docs.isNotEmpty) {
            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final seenBy = data['seenBy'] ?? [];
              final senderId = data['userId'];
              final msgType = data['type'];
              final targetUserId = data['targetUserId'];

              if (senderId == widget.userId) continue;

              bool isRelevant = false;
              if (msgType == 'group') {
                isRelevant = true;
              } else if (msgType == 'hod') {
                if (widget.role == "HOD") {
                  isRelevant = true;
                } else {
                  isRelevant = targetUserId == widget.userId;
                }
              }

              if (isRelevant && !seenBy.contains(widget.userId)) {
                FirebaseFirestore.instance
                    .collection('chat')
                    .doc(doc.id)
                    .update({
                  "seenBy": FieldValue.arrayUnion([widget.userId])
                });
              }
            }
          }
        });

        if (docs.isEmpty)
          return const Center(
              child: Text("Secure connection active",
                  style: TextStyle(color: Colors.grey)));

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final isMe = data['userId'] == widget.userId;
            return _buildBubble(data, isMe);
          },
        );
      },
    );
  }

  // ================= UI BUILDERS =================

  Widget _buildBubble(Map<String, dynamic> data, bool isMe) {
    final timestamp = data['timestamp'] != null
        ? DateFormat('hh:mm a')
            .format((data['timestamp'] as Timestamp).toDate())
        : DateFormat('hh:mm a').format(
            DateTime.fromMillisecondsSinceEpoch(data['clientTimestamp']));

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? ChatColors.myBubble : ChatColors.otherBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text("${data['userName']} • ${data['role']}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: ChatColors.primaryTeal)),
            if (data['imageUrl'] != null)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(data['imageUrl']))),
            if (data['text'] != null)
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(data['text'],
                      style: const TextStyle(
                          fontSize: 15, color: Colors.black87))),
            Align(
                alignment: Alignment.bottomRight,
                child: Text(timestamp,
                    style:
                        const TextStyle(fontSize: 10, color: Colors.black38))),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final type = _tabController.index == 0 ? "group" : "hod";
        return Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              left: 8,
              right: 8,
              top: 8),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: const Offset(0, -2))
              ]),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Row(
                    children: [
                      IconButton(
                          icon: const Icon(Icons.add_photo_alternate_rounded,
                              color: ChatColors.primaryTeal),
                          onPressed: () => _handleImage(type)),
                      Expanded(
                        child: TextField(
                          controller: _msgController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(type),
                          maxLines: 4,
                          minLines: 1,
                          decoration: const InputDecoration(
                              hintText: "Type a message...",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _sendMessage(type),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [Color(0xFF075E54), Color(0xFF128C7E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight)),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: ChatColors.appBarGreen,
        elevation: 2,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.black, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _isPrivateChat
                    ? "Chat with ${widget.targetUserName}"
                    : "Department Chat",
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            Text(widget.userName,
                style: const TextStyle(color: Colors.black54, fontSize: 11)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ChatColors.primaryTeal,
          indicatorWeight: 3,
          labelColor: ChatColors.primaryTeal,
          unselectedLabelColor: Colors.black54,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [Tab(text: "COMMON GROUP"), Tab(text: "HOD DESK")],
        ),
      ),
      body: Stack(children: [
        Positioned.fill(child: _buildPremiumBackground()),
        TabBarView(
            controller: _tabController,
            children: [_buildChatList("group"), _buildChatList("hod")])
      ]),
      bottomNavigationBar: _buildInputBar(),
    );
  }

  Widget _buildPremiumBackground() {
    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
            Color(0xFFECF3EC),
            Color(0xFFE8F5E9),
            Color(0xFFE0EEF4),
            Color(0xFFEFF6F0)
          ],
              stops: [
            0.0,
            0.35,
            0.65,
            1.0
          ])),
      child: CustomPaint(
          painter: _ChatBackgroundPainter(), child: const SizedBox.expand()),
    );
  }
}

class _ChatBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = const Color(0xFF075E54).withOpacity(0.04);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.08), 120, paint);
    paint.color = const Color(0xFF128C7E).withOpacity(0.05);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), 100, paint);
    final linePaint = Paint()
      ..color = const Color(0xFF075E54).withOpacity(0.025)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (double i = -size.height; i < size.width + size.height; i += 30) {
      canvas.drawLine(
          Offset(i, 0), Offset(i + size.height, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
