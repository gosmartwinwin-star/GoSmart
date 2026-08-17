import 'package:flutter/material.dart';

import '../../application/ride/ride_gateway.dart';
import '../../application/ride/ride_history_gateway.dart';
import '../../domain/ride/canonical_ride.dart';
import '../../domain/ride/ride_history.dart';
import '../../services/ride_history_service.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({
    super.key,
    this.gateway,
    this.initialScope = RideHistoryScope.passenger,
  });

  final RideHistoryGateway? gateway;
  final RideHistoryScope initialScope;

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  late final RideHistoryGateway _gateway;
  late RideHistoryScope _scope;

  final List<CanonicalRide> _rides = [];

  RideHistoryCursor? _nextCursor;
  bool _loading = false;
  bool _loadingMore = false;
  String? _errorMessage;

  bool get _hasMore => _nextCursor != null;
  bool get _busy => _loading || _loadingMore;

  @override
  void initState() {
    super.initState();

    _gateway = widget.gateway ?? RideHistoryService();
    _scope = widget.initialScope;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load(reset: true);
      }
    });
  }

  Future<void> _load({required bool reset}) async {
    if (!mounted || _busy) return;

    setState(() {
      if (reset) {
        _loading = true;
        _rides.clear();
        _nextCursor = null;
      } else {
        _loadingMore = true;
      }

      _errorMessage = null;
    });

    try {
      final page = await _gateway.loadPage(
        scope: _scope,
        pageSize: 20,
        cursor: reset ? null : _nextCursor,
      );

      if (!mounted) return;

      setState(() {
        if (reset) {
          _rides
            ..clear()
            ..addAll(page.rides);
        } else {
          _rides.addAll(page.rides);
        }

        _nextCursor = page.nextCursor;
      });
    } on RideGatewayException {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Yolculuk ge\u00e7mi\u015fi y\u00fcklenemedi. '
            'L\u00fctfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Yolculuk ge\u00e7mi\u015fi y\u00fcklenemedi. '
            'L\u00fctfen tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _changeScope(RideHistoryScope scope) async {
    if (_busy || scope == _scope) return;

    setState(() {
      _scope = scope;
    });

    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yolculuk ge\u00e7mi\u015fi')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      key: const ValueKey('ride-history-passenger-scope'),
                      label: const Text('Yolcu olarak'),
                      selected: _scope == RideHistoryScope.passenger,
                      onSelected: _busy
                          ? null
                          : (_) => _changeScope(RideHistoryScope.passenger),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      key: const ValueKey('ride-history-driver-scope'),
                      label: const Text('S\u00fcr\u00fcc\u00fc olarak'),
                      selected: _scope == RideHistoryScope.driver,
                      onSelected: _busy
                          ? null
                          : (_) => _changeScope(RideHistoryScope.driver),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage case final error?) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 96),
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Center(
              child: FilledButton(
                key: const ValueKey('ride-history-retry'),
                onPressed: () => _load(reset: true),
                child: const Text('Tekrar dene'),
              ),
            ),
          ],
        ),
      );
    }

    if (_rides.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 96),
            Icon(Icons.history_outlined, size: 48),
            SizedBox(height: 16),
            Text(
              'Bu kapsamda hen\u00fcz tamamlanm\u0131\u015f '
              'bir yolculuk bulunmuyor.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _rides.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _rides.length) {
            return Center(
              child: TextButton.icon(
                key: const ValueKey('ride-history-load-more'),
                onPressed: _loadingMore ? null : () => _load(reset: false),
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: const Text('Daha fazla y\u00fckle'),
              ),
            );
          }

          return _RideHistoryCard(ride: _rides[index]);
        },
      ),
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  const _RideHistoryCard({required this.ride});

  final CanonicalRide ride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final terminalAt =
        ride.completedAt ??
        ride.cancelledAt ??
        ride.expiredAt ??
        ride.updatedAt ??
        ride.createdAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(ride.status)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusLabel(ride.status),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (terminalAt != null)
                  Text(
                    _formatDate(terminalAt),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              ride.pickup.addressLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.south, size: 18),
            ),
            Text(
              ride.dropoff.addressLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Text(
              '${_distance(ride.route.distanceMeters)}'
              ' \u2022 '
              '${_duration(ride.route.durationSeconds)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(RideStatus status) => switch (status) {
    RideStatus.completed => 'Tamamland\u0131',
    RideStatus.cancelled => '\u0130ptal edildi',
    RideStatus.expired => 'S\u00fcr\u00fcc\u00fc bulunamad\u0131',
    _ => 'Yolculuk',
  };

  static IconData _statusIcon(RideStatus status) => switch (status) {
    RideStatus.completed => Icons.check_circle_outline,
    RideStatus.cancelled => Icons.cancel_outlined,
    RideStatus.expired => Icons.timer_off_outlined,
    _ => Icons.local_taxi_outlined,
  };

  static String _distance(int meters) {
    if (meters < 1000) {
      return '$meters m';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String _duration(int seconds) {
    final minutes = (seconds / 60).ceil();
    return '$minutes dk';
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(local.day)}.'
        '${two(local.month)}.'
        '${local.year} '
        '${two(local.hour)}:'
        '${two(local.minute)}';
  }
}
