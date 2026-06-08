import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/call_session.dart';
import '../services/call_manager.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    required this.session,
    super.key,
  });

  final CallSession session;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final CallManager _callManager = CallManager();
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _callManager.activeCallNotifier.addListener(_handleCallUpdate);
    // TODO: add ringtone playback when call audio support is introduced.
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

  void _reject() {
    _callManager.rejectIncomingCall(widget.session);
    _closeScreen();
  }

  void _accept() {
    final connectingSession = widget.session.copyWith(status: 'connecting');
    _callManager.acceptIncomingCall(widget.session);
    setState(() => _isClosing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WebRTC media will be added next')),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(session: connectingSession),
      ),
    );
  }

  String get _initial {
    final name = widget.session.peerName.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  @override
  void dispose() {
    _callManager.activeCallNotifier.removeListener(_handleCallUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = widget.session.isVideo ? 'video' : 'voice';

    return WillPopScope(
      onWillPop: () async {
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.darkGreen,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 72, 24, 44),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 58,
                  backgroundColor: AppColors.mintAvatar,
                  child: Text(
                    _initial,
                    style: const TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
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
                  'Incoming $typeLabel call',
                  style: const TextStyle(
                    color: Color(0xFFB7CBC7),
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallAction(
                      color: const Color(0xFFD94343),
                      icon: Icons.call_end_rounded,
                      label: 'Reject',
                      onPressed: _reject,
                    ),
                    _CallAction(
                      color: AppColors.onlineGreen,
                      icon: widget.session.isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      label: 'Accept',
                      onPressed: _accept,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton.filled(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            fixedSize: const Size(68, 68),
          ),
          iconSize: 31,
          icon: Icon(icon),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}
