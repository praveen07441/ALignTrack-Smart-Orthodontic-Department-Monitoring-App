const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendNotification = onDocumentCreated(
  {
    document: "chat/{messageId}",
    region: "asia-south1", 
  },
  async (event) => {
    try {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No snapshot found");
        return null;
      }

      const data = snapshot.data();
      if (!data) {
        console.log("No data found in snapshot");
        return null;
      }

      // 1. Prepare Notification Content
      const senderName = data.userName || "New Message";
      const messageText = data.text || (data.imageUrl ? "📷 Image" : "New message");
      
      const notificationPayload = {
        title: senderName,
        body: messageText,
      };

      // 2. Enhanced Data Payload (For App Navigation)
      const dataPayload = {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        type: "chat",
        chatType: data.type, 
        senderId: data.userId,
        senderName: data.userName,
      };

      // 3. Platform Specific Sound Config
      const androidConfig = {
        notification: {
          sound: "default",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      };

      const apnsConfig = {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      };

      // ================= 🟢 GROUP CHAT LOGIC =================
      if (data.type === "group") {
        const usersSnapshot = await admin.firestore().collection("users").get();
        const tokensSet = new Set(); // ✅ Fix 1: Prevent duplicate tokens

        usersSnapshot.forEach((doc) => {
          const user = doc.data();
          // Skip sender, collect unique tokens
          if (doc.id !== data.userId && user.fcmToken) {
            tokensSet.add(user.fcmToken);
          }
        });

        const tokens = Array.from(tokensSet);

        if (tokens.length > 0) {
          const response = await admin.messaging().sendEachForMulticast({
            tokens: tokens,
            notification: notificationPayload,
            data: dataPayload,
            android: androidConfig, // ✅ Fix 2: Add Sound
            apns: apnsConfig,       // ✅ Fix 2: Add Sound
          });
          console.log(`Group notification sent to ${response.successCount} unique devices.`);
        } else {
          console.log("No tokens found for group chat.");
        }
      }

      // ================= 🔵 HOD PRIVATE CHAT LOGIC =================
      else if (data.type === "hod") {
        if (!data.targetUserId) {
          console.log("targetUserId is missing.");
          return null;
        }

        if (data.userId === data.targetUserId) return null;

        const userDoc = await admin
          .firestore()
          .collection("users")
          .doc(data.targetUserId)
          .get();

        const destToken = userDoc.data()?.fcmToken;

        if (destToken) {
          await admin.messaging().send({
            token: destToken,
            notification: notificationPayload,
            data: dataPayload,
            android: androidConfig,
            apns: apnsConfig,
          });
          console.log(`Private notification sent to: ${data.targetUserId}`);
        } else {
          console.log("Target user has no token.");
        }
      }

      return null;
    } catch (error) {
      console.error("FCM Error:", error);
      return null;
    }
  }
);