import 'package:flutter/material.dart';

import '../../application/ride/ride_gateway.dart';
import '../../application/ride/ride_support_gateway.dart';
import '../../services/ride_support_service.dart';

class RideActiveSupportPanel extends StatefulWidget {
  const RideActiveSupportPanel({
    super.key,
    required this.rideId,
    required this.gateway,
    required this.requestIdGenerator,
  });

  final String rideId;
  final RideActiveSupportGateway? gateway;
  final String Function() requestIdGenerator;

  @override
  State<RideActiveSupportPanel> createState() =>
      _RideActiveSupportPanelState();
}

class _RideActiveSupportPanelState
    extends State<RideActiveSupportPanel> {
  RideActiveSupportGateway? _resolvedGateway;
  String? _selectedCategory;
  String? _requestId;
  String? _requestCategory;
  String? _errorMessage;
  bool _submitting = false;
  bool _success = false;

  RideActiveSupportGateway get _gateway =>
      _resolvedGateway ??=
          widget.gateway ?? RideSupportService();

  @override
  void didUpdateWidget(
    covariant RideActiveSupportPanel oldWidget,
  ) {
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

        _success = false;
        _errorMessage = null;
      }
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
      await _gateway.createActiveCase(
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

    return Card(
      key: ValueKey(
        'ride-active-support-panel-${widget.rideId}',
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Destek',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    key: ValueKey(
                      'ride-active-support-category-${widget.rideId}',
                    ),
                    value: _selectedCategory,
                    hint: const Text('Kategori'),
                    isExpanded: true,
                    onChanged:
                        _submitting || _success
                            ? null
                            : _selectCategory,
                    items: [
                      for (final category in rideSupportCategories)
                        DropdownMenuItem<String>(
                          value: category,
                          child: Text(category),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: ValueKey(
                    'ride-active-support-submit-${widget.rideId}',
                  ),
                  onPressed:
                      _submitting ||
                          _success ||
                          _selectedCategory == null
                      ? null
                      : _submit,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Gönder'),
                ),
              ],
            ),
            if (_success) ...[
              const SizedBox(height: 6),
              Text(
                'Destek talebiniz alındı.',
                key: ValueKey(
                  'ride-active-support-success-${widget.rideId}',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_errorMessage case final message?) ...[
              const SizedBox(height: 6),
              Text(
                message,
                key: ValueKey(
                  'ride-active-support-error-${widget.rideId}',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
