import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/ride/ride_chat_gateway.dart';
import '../../application/ride/ride_gateway.dart';
import '../../controllers/ride_chat_controller.dart';
import '../../domain/ride/canonical_ride.dart';
import '../../services/ride_chat_service.dart';
import '../../services/ride_chat_push_hint_service.dart';

class RideChatPanel extends StatefulWidget {
  const RideChatPanel({
    super.key,
    required this.rideId,
    required this.status,
    required this.viewerRole,
    required this.gateway,
    required this.requestIdGenerator,
    this.periodicTimerFactory,
    this.pushHintSource,
  });

  final String rideId;
  final RideStatus status;
  final RideChatSenderRole viewerRole;
  final RideChatGateway? gateway;
  final String Function() requestIdGenerator;
  final RideChatPeriodicTimerFactory? periodicTimerFactory;
  final RideChatPushHintSource? pushHintSource;

  @override
  State<RideChatPanel> createState() => _RideChatPanelState();
}

class _RideChatPanelState extends State<RideChatPanel> {
  final TextEditingController _textController = TextEditingController();

  late RideChatController _controller;
  StreamSubscription<int>? _pushHintSubscription;
  RideChatPushHintSource? _pushHintSource;
  int _handledPushHintRevision = 0;

  String? _requestId;
  String? _requestText;
  String? _localSendError;

  @override
  void initState() {
    super.initState();

    _textController.addListener(_handleDraftChanged);
    _createController();
    _bindPushHintSource();
  }

  void _createController() {
    _controller = RideChatController(
      gateway: widget.gateway ?? RideChatService(),
      periodicTimerFactory: widget.periodicTimerFactory,
    );

    _controller.addListener(_refresh);

    _controller.updateContext(rideId: widget.rideId, status: widget.status);
  }

  void _bindPushHintSource() {
    final source = widget.pushHintSource ?? rideChatPushHintBus;

    _pushHintSource = source;
    _handledPushHintRevision = 0;

    _pushHintSubscription = source.revisions.listen(
      _handlePushHintRevision,
      onError: (_, _) {},
    );

    final revision = source.revision;

    if (revision > 0) {
      scheduleMicrotask(() {
        _handlePushHintRevision(revision);
      });
    }
  }

  void _unbindPushHintSource() {
    final subscription = _pushHintSubscription;

    _pushHintSubscription = null;
    _pushHintSource = null;
    _handledPushHintRevision = 0;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  void _handlePushHintRevision(int revision) {
    if (!mounted ||
        revision <= _handledPushHintRevision ||
        _pushHintSource == null) {
      return;
    }

    _handledPushHintRevision = revision;
    unawaited(_controller.refresh());
  }

  @override
  void didUpdateWidget(covariant RideChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pushHintSource != widget.pushHintSource) {
      _unbindPushHintSource();
      _bindPushHintSource();
    }

    if (oldWidget.gateway != widget.gateway ||
        oldWidget.periodicTimerFactory != widget.periodicTimerFactory) {
      _controller.removeListener(_refresh);
      _controller.dispose();

      _requestId = null;
      _requestText = null;
      _localSendError = null;

      _createController();
      return;
    }

    if (oldWidget.rideId != widget.rideId) {
      _requestId = null;
      _requestText = null;
      _localSendError = null;
      _textController.clear();
    }

    _controller.updateContext(rideId: widget.rideId, status: widget.status);
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleDraftChanged() {
    final normalized = _textController.text.trim();

    if (_requestText != normalized) {
      _requestId = null;
      _requestText = null;
    }

    if (_localSendError != null && mounted) {
      setState(() {
        _localSendError = null;
      });
    }
  }

  Future<void> _send() async {
    if (_controller.sending || !_controller.canSend) {
      return;
    }

    final normalized = _textController.text.trim();

    if (normalized.isEmpty ||
        normalized.runes.length > rideChatTextMaxCharacters) {
      setState(() {
        _localSendError = 'Mesaj 1-1000 karakter arasında olmalıdır.';
      });
      return;
    }

    final requestId = _requestId ?? widget.requestIdGenerator();

    _requestId = requestId;
    _requestText = normalized;

    setState(() {
      _localSendError = null;
    });

    try {
      await _controller.send(requestId: requestId, text: normalized);

      if (!mounted) {
        return;
      }

      _requestId = null;
      _requestText = null;
      _textController.clear();

      setState(() {
        _localSendError = null;
      });
    } on RideGatewayException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _localSendError = switch (error.code) {
          'resource-exhausted' =>
            'Çok hızlı mesaj gönderiyorsunuz. Lütfen kısa bir süre bekleyin.',
          'permission-denied' || 'failed-precondition' =>
            'Bu yolculuk için mesaj gönderme erişimi sona erdi.',
          _ => 'Mesaj gönderilemedi. Lütfen tekrar deneyin.',
        };
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _localSendError = 'Mesaj gönderilemedi. Lütfen tekrar deneyin.';
      });
    }
  }

  @override
  void dispose() {
    _unbindPushHintSource();

    _textController.removeListener(_handleDraftChanged);
    _textController.dispose();

    _controller.removeListener(_refresh);
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!RideChatController.isReadableStatus(widget.status)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final messages = _controller.messages;

    return Card(
      key: ValueKey('ride-chat-panel-${widget.rideId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Yolculuk Sohbeti',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (_controller.loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    key: ValueKey('ride-chat-refresh-${widget.rideId}'),
                    tooltip: 'Sohbeti yenile',
                    visualDensity: VisualDensity.compact,
                    onPressed: _controller.accessClosed
                        ? null
                        : () {
                            unawaited(_controller.refresh());
                          },
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
              ],
            ),
            if (_controller.accessClosed) ...[
              const SizedBox(height: 6),
              Text(
                'Bu sohbet için erişim sona erdi.',
                key: ValueKey('ride-chat-access-closed-${widget.rideId}'),
                style: theme.textTheme.bodySmall,
              ),
            ] else ...[
              if (_controller.readErrorCode != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Sohbet şu anda yenilenemiyor.',
                  key: ValueKey('ride-chat-read-error-${widget.rideId}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              if (messages.isEmpty && !_controller.loading)
                Text(
                  'Henüz mesaj yok.',
                  key: ValueKey('ride-chat-empty-${widget.rideId}'),
                  style: theme.textTheme.bodySmall,
                )
              else if (messages.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    key: ValueKey('ride-chat-messages-${widget.rideId}'),
                    shrinkWrap: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final mine = message.senderRole == widget.viewerRole;

                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          key: ValueKey(
                            'ride-chat-message-${message.messageId}',
                          ),
                          constraints: const BoxConstraints(maxWidth: 300),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                mine
                                    ? 'Siz'
                                    : message.senderRole ==
                                          RideChatSenderRole.driver
                                    ? 'Sürücü'
                                    : 'Yolcu',
                                style: theme.textTheme.labelSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(message.text),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              if (_controller.canSend) ...[
                TextField(
                  key: ValueKey('ride-chat-input-${widget.rideId}'),
                  controller: _textController,
                  enabled: !_controller.sending,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Mesaj yazın',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_textController.text.trim().runes.length}/$rideChatTextMaxCharacters',
                        key: ValueKey('ride-chat-counter-${widget.rideId}'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    FilledButton.icon(
                      key: ValueKey('ride-chat-send-${widget.rideId}'),
                      onPressed: _controller.sending ? null : _send,
                      icon: _controller.sending
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send, size: 18),
                      label: const Text('Gönder'),
                    ),
                  ],
                ),
              ] else if (!_controller.accessClosed) ...[
                Text(
                  'Bu sohbet artık yalnızca okunabilir.',
                  key: ValueKey('ride-chat-read-only-${widget.rideId}'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_localSendError case final error?) ...[
                const SizedBox(height: 6),
                Text(
                  error,
                  key: ValueKey('ride-chat-send-error-${widget.rideId}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
