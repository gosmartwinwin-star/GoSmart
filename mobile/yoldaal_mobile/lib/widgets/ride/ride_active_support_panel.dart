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
  State<RideActiveSupportPanel> createState() => _RideActiveSupportPanelState();
}

class _RideActiveSupportPanelState extends State<RideActiveSupportPanel> {
  final TextEditingController _noteController = TextEditingController();

  RideActiveSupportGateway? _resolvedGateway;
  String? _selectedCategory;
  String? _requestId;
  String? _requestCategory;
  String? _requestNote;
  String? _errorMessage;
  bool _submitting = false;
  bool _success = false;

  RideActiveSupportGateway get _gateway =>
      _resolvedGateway ??= widget.gateway ?? RideSupportService();

  String? get _currentNote {
    final value = _noteController.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  void didUpdateWidget(covariant RideActiveSupportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.rideId != widget.rideId ||
        oldWidget.gateway != widget.gateway) {
      _resolvedGateway = null;
      _selectedCategory = null;
      _requestId = null;
      _requestCategory = null;
      _requestNote = null;
      _errorMessage = null;
      _submitting = false;
      _success = false;
      _noteController.clear();
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _selectCategory(String? category) {
    if (_submitting || _success || category == null) return;

    setState(() {
      _selectedCategory = category;
      _errorMessage = null;
    });
  }

  void _noteChanged(String _) {
    if (_submitting || _success) return;

    setState(() {
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    final category = _selectedCategory;

    if (_submitting || _success || category == null) {
      return;
    }

    final note = _currentNote;
    final canReuseRequest =
        _requestId != null &&
        _requestCategory == category &&
        _requestNote == note;

    final requestId = canReuseRequest
        ? _requestId!
        : widget.requestIdGenerator();

    setState(() {
      _requestId = requestId;
      _requestCategory = category;
      _requestNote = note;
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await _gateway.createActiveCase(
        rideId: widget.rideId,
        category: category,
        requestId: requestId,
        note: note,
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
            'Bildiriminiz g\u00F6nderilemedi. '
            'L\u00FCtfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _errorMessage =
            'Bildiriminiz g\u00F6nderilemedi. '
            'L\u00FCtfen tekrar deneyin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _selectedCategory;
    final controlsEnabled = !_submitting && !_success;

    return Card(
      key: ValueKey('ride-active-support-panel-${widget.rideId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("YoldaAl'a Bildir", style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              "Yolculukla ilgili bir sorun veya geri bildirim varsa "
              "YoldaAl'a bildirebilirsiniz.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              key: ValueKey('ride-active-support-category-${widget.rideId}'),
              value: category,
              hint: const Text('Kategori se\u00E7in'),
              isExpanded: true,
              onChanged: controlsEnabled ? _selectCategory : null,
              items: [
                for (final item in rideSupportUiCategories)
                  DropdownMenuItem<String>(
                    value: item,
                    child: Text(rideSupportCategoryLabel(item)),
                  ),
              ],
            ),
            if (category == 'safety') ...[
              const SizedBox(height: 4),
              Text(
                "Bu alan acil yard\u0131m hizmeti de\u011Fildir. "
                "Acil bir tehlike varsa 112'yi aray\u0131n.",
                key: ValueKey(
                  'ride-active-support-safety-warning-${widget.rideId}',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (category == 'lost-item') ...[
              const SizedBox(height: 4),
              Text(
                'E\u015Fyay\u0131 tan\u0131mlaman\u0131z '
                'bulmam\u0131za yard\u0131mc\u0131 olur.',
                key: ValueKey(
                  'ride-active-support-lost-item-help-${widget.rideId}',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (category != null) ...[
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('ride-active-support-note-${widget.rideId}'),
                controller: _noteController,
                enabled: controlsEnabled,
                maxLength: rideSupportNoteMaxCodePoints,
                minLines: 2,
                maxLines: 4,
                onChanged: _noteChanged,
                decoration: const InputDecoration(
                  labelText:
                      'K\u0131sa a\u00E7\u0131klama '
                      '(iste\u011Fe ba\u011Fl\u0131)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              key: ValueKey('ride-active-support-submit-${widget.rideId}'),
              onPressed: category == null || !controlsEnabled ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.flag_outlined),
              label: Text(
                _submitting ? 'G\u00F6nderiliyor...' : "YoldaAl'a Bildir",
              ),
            ),
            if (_success) ...[
              const SizedBox(height: 6),
              Text(
                "Bildiriminiz YoldaAl'a iletildi.",
                key: ValueKey('ride-active-support-success-${widget.rideId}'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_errorMessage case final message?) ...[
              const SizedBox(height: 6),
              Text(
                message,
                key: ValueKey('ride-active-support-error-${widget.rideId}'),
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
