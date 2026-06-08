import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/call_session.dart';
import '../services/call_manager.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    required this.session,
    super.key,
  });

  final CallSession session;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallManager _callManager = CallManager();
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _callManager.activeCallNotifier.addListener(_handleCallUpdate);
  }

  void _handleCallUpdate() {
    final activeCall = _callManager.activeCall;
    if (activeCall == null || activeCall.callId != widget.session.callId) {
      _closeScreen();
    }
  }

  void _closeScreen() {
    if (_isClosing || !mounted) {
      return;
    }
    setState(() => _isClosing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _endCall() {
    _callManager.endCurrentCall();
    _closeScreen();
  }

  @override
  void dispose() {
    _callManager.activeCallNotifier.removeListener(_handleCallUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.darkGreen,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.session.isVideo
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                  color: AppColors.mintAvatar,
                  size: 64,
                ),
                const SizedBox(height: 24),
                Text(
                  widget.session.peerName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.session.isVideo ? 'Video call' : 'Voice call',
                  style: const TextStyle(
                    color: Color(0xFFB7CBC7),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'WebRTC media will be added next',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 56),
                IconButton.filled(
                  onPressed: _endCall,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFD94343),
                    foregroundColor: Colors.white,
                    fixedSize: const Size(72, 72),
                  ),
                  iconSize: 32,
                  icon: const Icon(Icons.call_end_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
