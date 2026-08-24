import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/driver_ride_match_offer_controller.dart';
import '../../domain/ride/ride_match_offer.dart';

class RideMatchOfferPanel extends StatelessWidget {
  const RideMatchOfferPanel({
    required this.controller,
    required this.onAccept,
    required this.onRefresh,
    super.key,
  });

  final DriverRideMatchOfferController controller;
  final Future<void> Function(RideMatchOffer offer) onAccept;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.loading &&
            !controller.hasLoaded &&
            controller.errorMessage == null &&
            controller.offers.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          key: const ValueKey('ride-match-offer-panel'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _content(context),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    if (controller.loading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Uygun Yolculuklar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12),
          LinearProgressIndicator(key: ValueKey('ride-match-offer-loading')),
          SizedBox(height: 8),
          Text(
            'Dönüş rotanıza uygun '
            'yolculuklar aranıyor.',
          ),
        ],
      );
    }

    if (controller.errorMessage case final message?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Yolculuk Teklifleri',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('ride-match-offer-refresh'),
              onPressed: controller.busy
                  ? null
                  : () {
                      unawaited(onRefresh());
                    },
              child: const Text('Tekrar Dene'),
            ),
          ),
        ],
      );
    }

    if (controller.offers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Uygun Yolculuklar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Şu anda dönüş rotanıza '
            'uygun yolculuk yok.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('ride-match-offer-refresh'),
              onPressed: controller.busy
                  ? null
                  : () {
                      unawaited(onRefresh());
                    },
              child: const Text('Yenile'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Uygun Yolculuklar '
          '(${controller.offers.length})',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final offer in controller.offers) ...[
          _OfferItem(
            offer: offer,
            accepting: controller.acceptingRideId == offer.rideId,
            busy: controller.busy,
            onAccept: () {
              unawaited(onAccept(offer));
            },
          ),
          if (offer != controller.offers.last) const Divider(),
        ],
      ],
    );
  }
}

class _OfferItem extends StatelessWidget {
  const _OfferItem({
    required this.offer,
    required this.accepting,
    required this.busy,
    required this.onAccept,
  });

  final RideMatchOffer offer;
  final bool accepting;
  final bool busy;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('ride-match-offer-${offer.rideId}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Alış: ${offer.pickup.addressLabel}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Varış: ${offer.dropoff.addressLabel}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: ValueKey(
                'ride-match-offer-accept-'
                '${offer.rideId}',
              ),
              onPressed: busy ? null : onAccept,
              child: accepting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Yolculuğu Kabul Et'),
            ),
          ),
        ],
      ),
    );
  }
}
