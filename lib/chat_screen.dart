import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // ================= ✅ HELPER: LOADING & ERROR =================

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: ChatColors.primaryTeal)),
    );
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ================= ✅ MESSAGE SENDING =================

  Future<void> _sendMessage(String chatType) async {
    if (_msgController.text.trim().isEmpty) return;
    final text = _msgController.text.trim();

    String? targetId = chatType == "hod" ? widget.targetUserId : null;
    if (chatType == "hod" && targetId == null) {
      _showError("Target user not identified.");
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('chat').add({
        "text": text,
        "userId": widget.userId,
        "userName": widget.userName,
        "role": widget.role,
        "type": chatType,
        "targetUserId": targetId,
        "seenBy": [widget.userId],
        "isDeleted": false,
        "timestamp": FieldValue.serverTimestamp(),
        "clientTimestamp": DateTime.now().millisecondsSinceEpoch,
      });
      _msgController.clear();
    } catch (e) {
      _showError("Failed to send: $e");
    }
  }

  // ================= ✅ IMAGE HANDLING (FIXED PATH & UPLOAD) =================

  Future<void> _handleImage(String chatType) async {
    try {
      if (chatType == "hod" && widget.targetUserId == null) return;

      final XFile? pickedFile = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile == null) return;

      if (!mounted) return;
      _showLoading();

      final bytes = await pickedFile.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) Navigator.pop(context);
        _showError("Could not read image.");
        return;
      }

      final String fileName =
          'chat_media/IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = FirebaseStorage.instance.ref().child(fileName);

      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final String url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('chat').add({
        "imageUrl": url,
        "userId": widget.userId,
        "userName": widget.userName,
        "role": widget.role,
        "type": chatType,
        "targetUserId": chatType == "hod" ? widget.targetUserId : null,
        "seenBy": [widget.userId],
        "isDeleted": false,
        "timestamp": FieldValue.serverTimestamp(),
        "clientTimestamp": DateTime.now().millisecondsSinceEpoch,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError("Upload failed: $e");
      }
    }
  }

  // ================= ✅ FILE HANDLING (FIXED PATH & UPLOAD) =================

  Future<void> _handleFile(String chatType) async {
    try {
      if (chatType == "hod" && widget.targetUserId == null) return;

      final result = await FilePicker.platform
          .pickFiles(type: FileType.any, allowMultiple: false, withData: true);
      if (result == null) return;

      final PlatformFile pickedFile = result.files.single;
      final fileBytes = pickedFile.bytes;
      final filePath = pickedFile.path;

      if (fileBytes == null && filePath == null) {
        _showError("Could not read file.");
        return;
      }

      if (!mounted) return;
      _showLoading();

      final String storagePath =
          'chat_media/FILE_${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
      final Reference ref = FirebaseStorage.instance.ref().child(storagePath);

      if (fileBytes != null) {
        await ref.putData(fileBytes);
      } else {
        await ref.putFile(File(filePath!));
      }

      final String url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('chat').add({
        "fileUrl": url,
        "fileName": pickedFile.name,
        "userId": widget.userId,
        "userName": widget.userName,
        "role": widget.role,
        "type": chatType,
        "targetUserId": chatType == "hod" ? widget.targetUserId : null,
        "seenBy": [widget.userId],
        "isDeleted": false,
        "timestamp": FieldValue.serverTimestamp(),
        "clientTimestamp": DateTime.now().millisecondsSinceEpoch,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError("File failed: $e");
      }
    }
  }

  // ================= ✅ DELETE LOGIC =================

  void _showDeleteDialog(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete message?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('chat')
                  .doc(docId)
                  .update({
                "text": "Deleted",
                "imageUrl": null,
                "fileUrl": null,
                "isDeleted": true,
              });
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ================= ✅ CHAT VIEW (FIXED: Simple Query + Dart Filter) =================

  Widget _buildChatList(String type) {
    // 🔥 FIXED: Remove complex Filter.or to prevent "Exactly one operator" crash
    Query chatQuery = FirebaseFirestore.instance
        .collection('chat')
        .where('type', isEqualTo: type)
        .orderBy('clientTimestamp', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: chatQuery.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        // 🔥 FIXED: Manual filtering in Dart to handle bidirectional HOD chat
        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (type == "hod") {
            final String otherId = widget.targetUserId ?? "";
            return (data['userId'] == widget.userId &&
                    data['targetUserId'] == otherId) ||
                (data['userId'] == otherId &&
                    data['targetUserId'] == widget.userId);
          }
          return true; // Return all for group chat
        }).toList();

        if (docs.isEmpty)
          return const Center(
              child: Text("No messages yet",
                  style: TextStyle(color: Colors.grey)));

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final isMe = data['userId'] == widget.userId;
            return _buildBubble(data, isMe, docs[i].id);
          },
        );
      },
    );
  }

  Widget _buildBubble(Map<String, dynamic> data, bool isMe, String docId) {
    final timestampRaw = data['timestamp'] != null
        ? (data['timestamp'] as Timestamp).toDate()
        : DateTime.fromMillisecondsSinceEpoch(data['clientTimestamp']);
    final timestamp = DateFormat('hh:mm a').format(timestampRaw);
    final bool isDeleted = data['isDeleted'] ?? false;

    return GestureDetector(
      onLongPress: () {
        if (isMe && !isDeleted) _showDeleteDialog(docId);
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: isMe ? ChatColors.myBubble : ChatColors.otherBubble,
            borderRadius: BorderRadius.circular(12),
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
                        fontSize: 10,
                        color: ChatColors.primaryTeal)),
              if (isDeleted)
                const Text("Deleted",
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.black38,
                        fontStyle: FontStyle.italic))
              else ...[
                if (data['imageUrl'] != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(data['imageUrl']))),
                if (data['fileUrl'] != null)
                  InkWell(
                    onTap: () async {
                      final Uri url = Uri.parse(data['fileUrl']);
                      if (await canLaunchUrl(url))
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insert_drive_file,
                              size: 20, color: ChatColors.primaryTeal),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(data['fileName'] ?? "File",
                                  style: const TextStyle(
                                      fontSize: 12,
                                      decoration: TextDecoration.underline,
                                      color: Colors.blue))),
                        ],
                      ),
                    ),
                  ),
                if (data['text'] != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(data['text'],
                          style: const TextStyle(fontSize: 14))),
              ],
              Align(
                  alignment: Alignment.bottomRight,
                  child: Text(timestamp,
                      style:
                          const TextStyle(fontSize: 9, color: Colors.black38))),
            ],
          ),
        ),
      ),
    );
  }

  // ================= ✅ INPUT BAR =================

  Widget _buildInputBar() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final type = _tabController.index == 0 ? "group" : "hod";
        return Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 10,
              left: 10,
              right: 10,
              top: 10),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: const Offset(0, -2))
          ]),
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.attach_file,
                      color: ChatColors.primaryTeal),
                  onPressed: () => _handleFile(type)),
              IconButton(
                  icon: const Icon(Icons.add_photo_alternate,
                      color: ChatColors.primaryTeal),
                  onPressed: () => _handleImage(type)),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(25)),
                  child: TextField(
                    controller: _msgController,
                    maxLines: 4,
                    minLines: 1,
                    decoration: const InputDecoration(
                        hintText: "Type a message...",
                        border: InputBorder.none),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              CircleAvatar(
                backgroundColor: ChatColors.primaryTeal,
                child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: () => _sendMessage(type)),
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
      backgroundColor: ChatColors.background,
      appBar: AppBar(
        backgroundColor: ChatColors.appBarGreen,
        title: Text(
            _isPrivateChat
                ? "Chat with ${widget.targetUserName} Desk"
                : "Department Chat",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ChatColors.primaryTeal,
          tabs: const [Tab(text: "COMMON GROUP"), Tab(text: "HOD DESK")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildChatList("group"), _buildChatList("hod")],
      ),
      bottomNavigationBar: _buildInputBar(),
    );
  }
}
