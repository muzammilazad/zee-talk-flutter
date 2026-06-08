import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/call_session.dart';
import '../services/call_manager.dart';

class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({
    required this.session,
    super.key,
  });

  final CallSession session;

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  final CallManager _callManager = CallManager();
  late CallSession _session;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _callManager.activeCallNotifier.addListener(_handleCallUpdate);
    // TODO: add ringback audio when call audio support is introduced.
  }

  void _handleCallUpdate() {
    final activeCall = _callManager.activeCall;
    if (activeCall == null || activeCall.callId != widget.session.callId) {
      _closeScreen();
      return;
    }
    if (mounted) {
      setState(() => _session = activeCall);
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

  String get _statusText {
    switch (_session.status) {
      case 'declined':
        return 'Call declined';
      case 'timeout':
        return 'No answer';
      case 'unavailable':
        return 'User offline';
      case 'ended':
        return 'Call ended';
      case 'missed':
        return 'Missed call';
      default:
        return _session.isVideo ? 'Video calling...' : 'Calling...';
    }
  }

  String get _initial {
    final name = _session.peerName.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
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
                  _session.peerName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _statusText,
                  style: const TextStyle(
                    color: Color(0xFFB7CBC7),
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
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
                const SizedBox(height: 10),
                const Text(
                  'End call',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
