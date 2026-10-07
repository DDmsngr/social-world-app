import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/widgets/user_avatar.dart';
import 'call_controller.dart';
import 'call_models.dart';

/// Экран звонка. Всё состояние — в [CallController]; экран только рисует и
/// закрывается сам, когда звонок кончился.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late final CallController _call = ref.read(callControllerProvider);
  bool _closing = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  CallPhase? _lastPhase;

  @override
  void initState() {
    super.initState();
    _call.addListener(_onChange);
  }

  @override
  void dispose() {
    _call.removeListener(_onChange);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (_call.phase == CallPhase.idle && !_closing) {
      _closing = true;
      Navigator.of(context).maybePop();
      return;
    }
    // Разговор пошёл — через 3 секунды кнопки уходят, остаётся картинка.
    if (_call.phase == CallPhase.active && _lastPhase != CallPhase.active) _scheduleHide();
    if (_call.phase != CallPhase.active) {
      _hideTimer?.cancel();
      _controlsVisible = true;
    }
    _lastPhase = _call.phase;
    setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _call.phase == CallPhase.active) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (_call.phase != CallPhase.active) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final call = _call.call;
    final phase = _call.phase;
    final video = call?.video ?? false;
    final showRemote = video && _call.hasRemoteVideo && _call.peerCameraOn && phase == CallPhase.active;
    final showLocal = video && _call.cameraOn && phase != CallPhase.ended;
    final status = callPhaseLabel(phase, video: video, talked: _call.talked, reason: _call.endReason);

    return PopScope(
      // Пока идёт звонок, «назад» его не бросает: положить трубку — красной кнопкой.
      canPop: !_call.busy,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
        backgroundColor: const Color(0xFF120E11),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleControls,
          child: Stack(
          fit: StackFit.expand,
          children: [
            if (showRemote)
              RTCVideoView(
                _call.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF3A1C2C), Color(0xFF120E11)],
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  if (!showRemote) ...[
                    const SizedBox(height: 40),
                    UserAvatar(name: call?.peerName ?? '', url: call?.peerAvatarUrl, radius: 64),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    call?.peerName ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: showRemote ? 20 : 28,
                      fontWeight: FontWeight.w600,
                      shadows: showRemote ? const [Shadow(blurRadius: 8)] : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 15,
                      shadows: showRemote ? const [Shadow(blurRadius: 8)] : null,
                    ),
                  ),
                  if (video && phase == CallPhase.active && !_call.peerCameraOn) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Камера собеседника выключена',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                    ),
                  ],
                  const Spacer(),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _controlsVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: _Controls(call: _call, video: video, onTouch: _scheduleHide),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
            if (showLocal)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 16,
                right: 16,
                width: 108,
                height: 152,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: Colors.black,
                    child: RTCVideoView(
                      _call.localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.call, required this.video, required this.onTouch});

  final CallController call;
  final bool video;
  final VoidCallback onTouch;

  @override
  Widget build(BuildContext context) {
    final ended = call.phase == CallPhase.ended;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 16,
            children: [
              _RoundButton(
                icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: call.muted ? 'Микрофон выкл.' : 'Микрофон',
                active: call.muted,
                onTap: ended ? null : () { call.toggleMute(); onTouch(); },
              ),
              _RoundButton(
                icon: call.speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
                label: call.speaker ? 'Динамик' : 'У уха',
                active: call.speaker,
                onTap: ended ? null : () { call.toggleSpeaker(); onTouch(); },
              ),
              if (video) ...[
                _RoundButton(
                  icon: call.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  label: call.cameraOn ? 'Камера' : 'Камера выкл.',
                  active: !call.cameraOn,
                  onTap: ended ? null : () { call.toggleCamera(); onTouch(); },
                ),
                _RoundButton(
                  icon: Icons.cameraswitch_rounded,
                  label: 'Сменить',
                  onTap: ended || !call.cameraOn ? null : () { call.switchCamera(); onTouch(); },
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          Semantics(
            button: true,
            label: 'Завершить звонок',
            child: GestureDetector(
              onTap: ended ? null : call.hangUp,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: ended ? 0.4 : 1,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 34),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, this.active = false, this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: active ? const Color(0xFF120E11) : Colors.white, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
