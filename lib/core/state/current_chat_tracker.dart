class CurrentChatTracker {
  CurrentChatTracker._();

  static final CurrentChatTracker _instance = CurrentChatTracker._();

  factory CurrentChatTracker() => _instance;

  String? currentOpenChatUserId;

  void openChat(String userId) {
    currentOpenChatUserId = userId;
  }

  void closeChat(String userId) {
    if (currentOpenChatUserId == userId) {
      currentOpenChatUserId = null;
    }
  }

  bool isChatOpen(String userId) => currentOpenChatUserId == userId;
}
