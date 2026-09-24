import 'package:flutter/material.dart';

import '../../controllers/ride_voice_call_recovery_controller.dart';
import '../../services/ride_voice_call_recovery_service.dart';

enum RideVoiceCallStatusViewerRole { driver, passenger }

class RideVoiceCallStatusPanel extends StatelessWidget {
  const RideVoiceCallStatusPanel({
    super.key,
    required this.controller,
    required this.viewerRole,
  });

  final RideVoiceCallRecoveryController? controller;
  final RideVoiceCallStatusViewerRole viewerRole;

  @override
  Widget build(BuildContext context) {
    final current = controller;
    if (current == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: current,
      builder: (context, _) => _buildStatus(context, current),
    );
  }

  Widget _buildStatus(
    BuildContext context,
    RideVoiceCallRecoveryController current,
  ) {
    final activeCall = current.activeCall;
    if (activeCall == null) {
      return _buildStart(context, current);
    }
    if (!_matchesViewerRole(activeCall.role)) {
      return const SizedBox.shrink();
    }

    final presentation = _presentation(activeCall);
    final actions = _actions(current);
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey('ride-voice-call-status-panel'),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              presentation.icon,
              key: const ValueKey('ride-voice-call-status-icon'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.title,
                    key: const ValueKey('ride-voice-call-status-title'),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    presentation.message,
                    key: const ValueKey('ride-voice-call-status-message'),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (current.rtcErrorCode != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ses bağlantısı şu anda kullanılamıyor.',
                      key: const ValueKey('ride-voice-call-rtc-error'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStart(
    BuildContext context,
    RideVoiceCallRecoveryController current,
  ) {
    if (!current.canStartCall && !current.actionInFlight) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Card(
      key: const ValueKey('ride-voice-call-start-panel'),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.call_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Yolculuk katılımcısını sesli ara',
                key: const ValueKey('ride-voice-call-start-title'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              key: const ValueKey('ride-voice-call-start-button'),
              onPressed: current.actionInFlight || !current.canStartCall
                  ? null
                  : current.startCall,
              child: const Text('Sesli ara'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(RideVoiceCallRecoveryController current) {
    final disabled = current.actionInFlight;

    if (current.canAccept && current.canDecline) {
      return <Widget>[
        FilledButton(
          key: const ValueKey('ride-voice-call-accept-button'),
          onPressed: disabled ? null : current.acceptCall,
          child: const Text('Kabul et'),
        ),
        OutlinedButton(
          key: const ValueKey('ride-voice-call-decline-button'),
          onPressed: disabled ? null : current.declineCall,
          child: const Text('Reddet'),
        ),
      ];
    }

    if (current.canCancel) {
      return <Widget>[
        OutlinedButton(
          key: const ValueKey('ride-voice-call-cancel-button'),
          onPressed: disabled ? null : current.cancelCall,
          child: const Text('İptal et'),
        ),
      ];
    }

    if (current.canEnd) {
      return <Widget>[
        if (current.canControlRtc)
          OutlinedButton.icon(
            key: const ValueKey('ride-voice-call-mute-button'),
            onPressed: disabled ? null : current.toggleMuted,
            icon: Icon(
              current.rtcMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            ),
            label: Text(current.rtcMuted ? 'Mikrofonu aç' : 'Sessize al'),
          ),
        if (current.canControlRtc)
          OutlinedButton.icon(
            key: const ValueKey('ride-voice-call-speaker-button'),
            onPressed: disabled ? null : current.toggleSpeakerphone,
            icon: Icon(
              current.rtcSpeakerphoneEnabled
                  ? Icons.volume_up_rounded
                  : Icons.hearing_rounded,
            ),
            label: Text(current.rtcSpeakerphoneEnabled ? 'Ahize' : 'Hoparlör'),
          ),
        OutlinedButton(
          key: const ValueKey('ride-voice-call-end-button'),
          onPressed: disabled ? null : current.endCall,
          child: const Text('Aramayı bitir'),
        ),
      ];
    }

    return const <Widget>[];
  }

  bool _matchesViewerRole(RideVoiceCallRecoveryRole recoveredRole) =>
      switch (viewerRole) {
        RideVoiceCallStatusViewerRole.driver =>
          recoveredRole == RideVoiceCallRecoveryRole.driver,
        RideVoiceCallStatusViewerRole.passenger =>
          recoveredRole == RideVoiceCallRecoveryRole.passenger,
      };

  _RideVoiceCallPresentation _presentation(
    RideVoiceCallRecoverySnapshot activeCall,
  ) => switch (activeCall.state) {
    RideVoiceCallRecoveryState.ringing
        when activeCall.side == RideVoiceCallRecoverySide.callee =>
      const _RideVoiceCallPresentation(
        title: 'Gelen sesli arama',
        message: 'Karşı taraf sizi arıyor.',
        icon: Icons.call_received_rounded,
      ),
    RideVoiceCallRecoveryState.ringing => const _RideVoiceCallPresentation(
      title: 'Arama isteği gönderildi',
      message: 'Karşı tarafın yanıtı bekleniyor.',
      icon: Icons.call_made_rounded,
    ),
    RideVoiceCallRecoveryState.accepted => const _RideVoiceCallPresentation(
      title: 'Arama kabul edildi',
      message: 'Ses bağlantısı hazırlanıyor.',
      icon: Icons.phone_in_talk_rounded,
    ),
    RideVoiceCallRecoveryState.connecting => const _RideVoiceCallPresentation(
      title: 'Arama bağlanıyor',
      message: 'Ses bağlantısı kuruluyor.',
      icon: Icons.sync_rounded,
    ),
    RideVoiceCallRecoveryState.active => const _RideVoiceCallPresentation(
      title: 'Sesli arama etkin',
      message: 'Arama oturumu etkin durumda.',
      icon: Icons.call_rounded,
    ),
  };
}

class _RideVoiceCallPresentation {
  const _RideVoiceCallPresentation({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;
}
