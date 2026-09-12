import 'package:flutter/material.dart';

import '../../application/ride/ride_gateway.dart';
import '../../application/ride/ride_history_gateway.dart';
import '../../application/ride/ride_rating_gateway.dart';
import '../../application/ride/ride_support_gateway.dart';
import '../../core/ride/secure_request_id.dart';
import '../../services/ride_rating_service.dart';
import '../../services/ride_support_service.dart';
import '../../domain/ride/canonical_ride.dart';
import '../../domain/ride/ride_history.dart';
import '../../services/ride_history_service.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({
    super.key,
    this.gateway,
    this.ratingGateway,
    this.supportGateway,
    this.requestIdGenerator,
    this.initialScope = RideHistoryScope.passenger,
  });

  final RideHistoryGateway? gateway;
  final RideRatingGateway? ratingGateway;
  final RideSupportGateway? supportGateway;
  final String Function()? requestIdGenerator;
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

          return _RideHistoryCard(
            ride: _rides[index],
            ratingGateway: widget.ratingGateway,
            supportGateway: widget.supportGateway,
            requestIdGenerator:
                widget.requestIdGenerator ?? secureRideRequestId,
          );
        },
      ),
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  const _RideHistoryCard({
    required this.ride,
    required this.ratingGateway,
    required this.supportGateway,
    required this.requestIdGenerator,
  });

  final CanonicalRide ride;
  final RideRatingGateway? ratingGateway;
  final RideSupportGateway? supportGateway;
  final String Function() requestIdGenerator;

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
            if (ride.status == RideStatus.completed) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              _RideRatingPanel(
                key: ValueKey('ride-rating-panel-${ride.rideId}'),
                rideId: ride.rideId,
                gateway: ratingGateway,
                requestIdGenerator: requestIdGenerator,
              ),
            ],
            if (_supportsRideSupport(ride.status)) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              _RideSupportPanel(
                key: ValueKey('ride-support-panel-${ride.rideId}'),
                rideId: ride.rideId,
                gateway: supportGateway,
                requestIdGenerator: requestIdGenerator,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _supportsRideSupport(RideStatus status) =>
      status == RideStatus.completed ||
      status == RideStatus.cancelled ||
      status == RideStatus.expired;
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
class _RideSupportPanel extends StatefulWidget {
  const _RideSupportPanel({
    super.key,
    required this.rideId,
    required this.gateway,
    required this.requestIdGenerator,
  });

  final String rideId;
  final RideSupportGateway? gateway;
  final String Function() requestIdGenerator;

  @override
  State<_RideSupportPanel> createState() => _RideSupportPanelState();
}

class _RideSupportPanelState extends State<_RideSupportPanel> {
  RideSupportGateway? _resolvedGateway;
  String? _selectedCategory;
  String? _requestId;
  String? _requestCategory;
  String? _errorMessage;
  bool _submitting = false;
  bool _success = false;

  RideSupportGateway get _gateway =>
      _resolvedGateway ??= widget.gateway ?? RideSupportService();

  @override
  void didUpdateWidget(covariant _RideSupportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.rideId != widget.rideId ||
        oldWidget.gateway != widget.gateway) {
      _resolvedGateway = null;
      _selectedCategory = null;
      _requestId = null;
      _requestCategory = null;
      _errorMessage = null;
      _submitting = false;
      _success = false;
    }
  }

  void _selectCategory(String? category) {
    if (_submitting || category == null) return;

    setState(() {
      if (_selectedCategory != category) {
        _selectedCategory = category;

        if (_requestCategory != category) {
          _requestId = null;
          _requestCategory = null;
        }
      }

      _errorMessage = null;
      _success = false;
    });
  }

  Future<void> _submit() async {
    final category = _selectedCategory;

    if (_submitting || _success || category == null) {
      return;
    }

    final requestId =
        _requestId ??
        widget.requestIdGenerator();

    setState(() {
      _requestId = requestId;
      _requestCategory = category;
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await _gateway.createCase(
        rideId: widget.rideId,
        category: category,
        requestId: requestId,
      );

      if (!mounted) return;

      setState(() {
        _submitting = false;
        _success = true;
        _errorMessage = null;
      });
    } on RideGatewayException {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _errorMessage =
            'Destek talebi gönderilemedi. Lütfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _errorMessage =
            'Destek talebi gönderilemedi. Lütfen tekrar deneyin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Destek / şikâyet',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          key: ValueKey(
            'ride-support-category-${widget.rideId}',
          ),
          value: _selectedCategory,
          isExpanded: true,
          hint: const Text('Kategori seçin'),
          items: [
            for (final category in rideSupportCategories)
              DropdownMenuItem<String>(
                value: category,
                child: Text(_categoryLabel(category)),
              ),
          ],
          onChanged: _submitting ? null : _selectCategory,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: ValueKey(
            'ride-support-submit-${widget.rideId}',
          ),
          onPressed:
              _selectedCategory == null ||
                  _submitting ||
                  _success
              ? null
              : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.support_agent_outlined),
          label: Text(
            _submitting
                ? 'Gönderiliyor...'
                : 'Destek talebi gönder',
          ),
        ),
        if (_errorMessage case final error?) ...[
          const SizedBox(height: 8),
          Text(
            error,
            key: ValueKey(
              'ride-support-error-${widget.rideId}',
            ),
            style: TextStyle(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (_success) ...[
          const SizedBox(height: 8),
          Text(
            'Destek talebiniz alındı.',
            key: ValueKey(
              'ride-support-success-${widget.rideId}',
            ),
          ),
        ],
      ],
    );
  }

  static String _categoryLabel(String category) => switch (category) {
    'safety' => 'Güvenlik',
    'behavior' => 'Davranış',
    'fare' => 'Ücret',
    'route' => 'Rota',
    'pickup' => 'Alım noktası',
    'no-show' => 'Gelmeme',
    'cancel' => 'İptal',
    'vehicle' => 'Araç',
    'technical' => 'Teknik',
    'lost-item' => 'Kayıp eşya',
    _ => category,
  };
}
class _RideRatingPanel extends StatefulWidget {
  const _RideRatingPanel({
    super.key,
    required this.rideId,
    required this.gateway,
    required this.requestIdGenerator,
  });

  final String rideId;
  final RideRatingGateway? gateway;
  final String Function() requestIdGenerator;

  @override
  State<_RideRatingPanel> createState() => _RideRatingPanelState();
}

class _RideRatingPanelState extends State<_RideRatingPanel> {
  RideRatingGateway? _resolvedGateway;
  RideRatingStatus? _status;

  bool _loading = true;
  bool _submitting = false;

  int? _selectedRating;
  int? _requestRating;
  String? _requestId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadStatus();
      }
    });
  }

  Future<void> _loadStatus() async {
    if (!mounted || _submitting) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final gateway =
          _resolvedGateway ??= widget.gateway ?? RideRatingService();

      final status = await gateway.getMyRatingStatus(
        rideId: widget.rideId,
      );

      if (!mounted) return;

      setState(() {
        _status = status;
        _loading = false;

        if (status.hasSubmitted) {
          _selectedRating = status.rating;
          _requestId = null;
          _requestRating = null;
        }
      });
    } on RideGatewayException {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'Puan durumu alınamadı. Lütfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'Puan durumu alınamadı. Lütfen tekrar deneyin.';
      });
    }
  }

  void _selectRating(int rating) {
    if (_submitting || _status?.hasSubmitted == true) return;

    setState(() {
      if (_selectedRating != rating) {
        _selectedRating = rating;

        if (_requestRating != rating) {
          _requestId = null;
          _requestRating = null;
        }
      }

      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    final rating = _selectedRating;

    if (_submitting ||
        _status?.hasSubmitted == true ||
        rating == null) {
      return;
    }

    final requestId =
        _requestId ??= widget.requestIdGenerator();

    _requestRating ??= rating;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final gateway =
          _resolvedGateway ??= widget.gateway ?? RideRatingService();

      final status = await gateway.submitRating(
        rideId: widget.rideId,
        rating: rating,
        requestId: requestId,
      );

      if (!mounted) return;

      setState(() {
        _status = status;
        _submitting = false;
        _selectedRating = status.rating;
        _requestId = null;
        _requestRating = null;
      });
    } on RideGatewayException {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _errorMessage =
            'Puan gönderilemedi. Lütfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _errorMessage =
            'Puan gönderilemedi. Lütfen tekrar deneyin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    if (_loading) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Puan durumunuz yükleniyor...'),
        ],
      );
    }

    if (status == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _errorMessage ??
                'Puan durumu alınamadı. Lütfen tekrar deneyin.',
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            key: ValueKey(
              'ride-rating-status-retry-${widget.rideId}',
            ),
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar dene'),
          ),
        ],
      );
    }

    if (status.hasSubmitted) {
      return Row(
        key: ValueKey(
          'ride-rating-submitted-${widget.rideId}',
        ),
        children: [
          const Icon(Icons.star),
          const SizedBox(width: 8),
          Text('Puanınız: ${status.rating}/5'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bu yolculuğu puanlayın'),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var value = 1; value <= 5; value++)
              IconButton(
                key: ValueKey(
                  'ride-rating-${widget.rideId}-star-$value',
                ),
                tooltip: '$value yıldız',
                onPressed:
                    _submitting ? null : () => _selectRating(value),
                icon: Icon(
                  (_selectedRating ?? 0) >= value
                      ? Icons.star
                      : Icons.star_border,
                ),
              ),
          ],
        ),
        FilledButton.icon(
          key: ValueKey(
            'ride-rating-submit-${widget.rideId}',
          ),
          onPressed:
              _selectedRating == null || _submitting
                  ? null
                  : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(
            _submitting
                ? 'Gönderiliyor...'
                : 'Puanı gönder',
          ),
        ),
        if (_errorMessage case final error?) ...[
          const SizedBox(height: 8),
          Text(error),
        ],
      ],
    );
  }
}
