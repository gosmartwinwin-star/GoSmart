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
    if (activeCall == null || !_matchesViewerRole(activeCall.role)) {
      return const SizedBox.shrink();
    }

    final presentation = _presentation(activeCall);
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
