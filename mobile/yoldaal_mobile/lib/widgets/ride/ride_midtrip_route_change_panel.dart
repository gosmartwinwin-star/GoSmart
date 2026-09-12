import 'package:flutter/material.dart';

import '../../application/ride/ride_midtrip_route_change_gateway.dart';
import '../../controllers/ride_midtrip_route_change_controller.dart';
import '../../domain/ride/canonical_ride.dart';

typedef RideMidtripDropoffPicker = Future<RideLocation?> Function();

class RideMidtripRouteChangePanel extends StatefulWidget {
  const RideMidtripRouteChangePanel({
    super.key,
    required this.rideId,
    required this.controller,
    required this.selectDropoff,
  });

  final String rideId;
  final RideMidtripRouteChangeController controller;
  final RideMidtripDropoffPicker selectDropoff;

  @override
  State<RideMidtripRouteChangePanel> createState() =>
      _RideMidtripRouteChangePanelState();
}

class _RideMidtripRouteChangePanelState
    extends State<RideMidtripRouteChangePanel> {
  bool _pickingDropoff = false;
  String? _feedbackMessage;

  @override
  void didUpdateWidget(covariant RideMidtripRouteChangePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.rideId != widget.rideId ||
        oldWidget.controller != widget.controller) {
      _pickingDropoff = false;
      _feedbackMessage = null;
    }
  }

  bool get _busy => _pickingDropoff || widget.controller.isActionInFlight;

  Future<void> _selectAndPropose() async {
    if (_busy || !widget.controller.isActive) {
      return;
    }

    final operationRideId = widget.rideId;
    final operationController = widget.controller;

    setState(() {
      _pickingDropoff = true;
      _feedbackMessage = null;
    });

    RideLocation? selected;

    try {
      selected = await widget.selectDropoff();
    } catch (_) {
      if (!mounted ||
          widget.rideId != operationRideId ||
          widget.controller != operationController) {
        return;
      }

      setState(() {
        _pickingDropoff = false;
        _feedbackMessage = 'Adres seçimi açılamadı. Lütfen tekrar deneyin.';
      });

      return;
    }

    if (!mounted ||
        widget.rideId != operationRideId ||
        widget.controller != operationController) {
      return;
    }

    setState(() {
      _pickingDropoff = false;
    });

    if (selected == null) {
      return;
    }

    final result = await operationController.proposeDropoffChange(
      newDropoff: selected,
    );

    if (!mounted ||
        widget.rideId != operationRideId ||
        widget.controller != operationController) {
      return;
    }

    if (result == null) {
      if (operationController.actionError != null) {
        setState(() {
          _feedbackMessage =
              'Varış noktası değişikliği tamamlanamadı. '
              'Lütfen tekrar deneyin.';
        });
      }

      return;
    }

    setState(() {
      _feedbackMessage = switch (result.status) {
        RideDropoffChangeProposalStatus.appliedCompatible =>
          'Yeni varış noktası uygulandı.',
        RideDropoffChangeProposalStatus.pendingAcknowledgement =>
          'Değişiklik karşı tarafın onayına gönderildi.',
        RideDropoffChangeProposalStatus.acceptedIncompatible ||
        RideDropoffChangeProposalStatus.rejectedIncompatible =>
          'Varış noktası değişikliği güncellendi.',
      };
    });
  }

  Future<void> _acknowledge(
    RidePendingDropoffChangeProposalResult proposal,
    RideDropoffChangeDecision decision,
  ) async {
    if (_busy || !widget.controller.isActive) {
      return;
    }

    final operationRideId = widget.rideId;
    final operationController = widget.controller;

    setState(() {
      _feedbackMessage = null;
    });

    final result = await operationController.acknowledgeDropoffChange(
      proposalId: proposal.proposalId,
      decision: decision,
    );

    if (!mounted ||
        widget.rideId != operationRideId ||
        widget.controller != operationController) {
      return;
    }

    if (result == null) {
      if (operationController.actionError != null) {
        setState(() {
          _feedbackMessage =
              'Varış noktası değişikliği tamamlanamadı. '
              'Lütfen tekrar deneyin.';
        });
      }

      return;
    }

    setState(() {
      _feedbackMessage = switch (result.status) {
        RideDropoffChangeProposalStatus.acceptedIncompatible =>
          'Varış noktası değişikliği kabul edildi.',
        RideDropoffChangeProposalStatus.rejectedIncompatible =>
          'Varış noktası değişikliği reddedildi.',
        RideDropoffChangeProposalStatus.appliedCompatible ||
        RideDropoffChangeProposalStatus.pendingAcknowledgement =>
          'Varış noktası değişikliği güncellendi.',
      };
    });
  }

  Future<void> _refresh() async {
    if (_busy || !widget.controller.isActive) {
      return;
    }

    await widget.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;

        if (!controller.isActive) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final pending = controller.pendingProposals;
        final busy = _busy;

        return Card(
          key: ValueKey('ride-midtrip-panel-${widget.rideId}'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Varış Noktası Değişikliği',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Yolculuk devam ederken yeni bir varış noktası '
                  'önerebilirsiniz.',
                  style: theme.textTheme.bodySmall,
                ),
                if (controller.isUpdating) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(
                    key: ValueKey('ride-midtrip-discovery-loading'),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: ValueKey('ride-midtrip-select-dropoff-${widget.rideId}'),
                  onPressed: busy ? null : _selectAndPropose,
                  icon: _pickingDropoff
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Varış Noktasını Değiştir'),
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Bekleyen Değişiklikler',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  for (final proposal in pending) ...[
                    _PendingProposalCard(
                      proposal: proposal,
                      busy: busy,
                      onAccept: () {
                        _acknowledge(
                          proposal,
                          RideDropoffChangeDecision.accept,
                        );
                      },
                      onReject: () {
                        _acknowledge(
                          proposal,
                          RideDropoffChangeDecision.reject,
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
                if (controller.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Bekleyen değişiklikler yüklenemedi.',
                    key: ValueKey(
                      'ride-midtrip-discovery-error-${widget.rideId}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: ValueKey('ride-midtrip-refresh-${widget.rideId}'),
                      onPressed: busy ? null : _refresh,
                      child: const Text('Yenile'),
                    ),
                  ),
                ],
                if (_feedbackMessage case final message?) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    key: ValueKey('ride-midtrip-feedback-${widget.rideId}'),
                    style: theme.textTheme.bodySmall,
                  ),
                ] else if (controller.actionError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Varış noktası değişikliği tamamlanamadı. '
                    'Lütfen tekrar deneyin.',
                    key: ValueKey('ride-midtrip-action-error-${widget.rideId}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PendingProposalCard extends StatelessWidget {
  const _PendingProposalCard({
    required this.proposal,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final RidePendingDropoffChangeProposalResult proposal;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: ValueKey('ride-midtrip-proposal-${proposal.proposalId}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            proposal.requestedDropoff.addressLabel,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('ride-midtrip-reject-${proposal.proposalId}'),
                  onPressed: busy ? null : onReject,
                  child: const Text('Reddet'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: ValueKey('ride-midtrip-accept-${proposal.proposalId}'),
                  onPressed: busy ? null : onAccept,
                  child: const Text('Kabul Et'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
