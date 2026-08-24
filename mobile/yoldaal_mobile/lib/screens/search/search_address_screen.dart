import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/place/place_search_gateway.dart';
import '../../controllers/address_controller.dart';
import '../../core/place/place_session_token.dart';
import '../../models/address_model.dart';
import '../../services/place_search_service.dart';
import '../../widgets/search/search_result_tile.dart';

class SearchAddressScreen extends StatefulWidget {
  const SearchAddressScreen({
    super.key,
    this.gateway,
    this.sessionTokenFactory,
    this.debounceDuration = const Duration(milliseconds: 350),
  });

  final PlaceSearchGateway? gateway;
  final String Function()? sessionTokenFactory;
  final Duration debounceDuration;

  @override
  State<SearchAddressScreen> createState() => _SearchAddressScreenState();
}

class _SearchAddressScreenState extends State<SearchAddressScreen> {
  final TextEditingController searchController = TextEditingController();

  final AddressController addressController = AddressController();

  late final PlaceSearchGateway _gateway;
  late String _sessionToken;

  Timer? _debounce;

  List<PlaceSearchSuggestion> _suggestions = const [];

  String? _errorMessage;
  String? _resolvingPlaceId;

  bool _loading = false;
  bool _hasCompletedSearch = false;

  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();

    addressController.load();

    _gateway = widget.gateway ?? PlaceSearchService();

    _sessionToken = _createSessionToken();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  String _createSessionToken() =>
      widget.sessionTokenFactory?.call() ?? createPlaceSessionToken();

  void _onSearchChanged(String value) {
    _debounce?.cancel();

    final generation = ++_searchGeneration;

    final query = value.trim();

    setState(() {
      _suggestions = const [];
      _errorMessage = null;
      _resolvingPlaceId = null;
      _hasCompletedSearch = false;
      _loading = query.length >= PlaceSearchService.minInputLength;
    });

    if (query.length < PlaceSearchService.minInputLength) {
      return;
    }

    _debounce = Timer(widget.debounceDuration, () {
      unawaited(_runSearch(query, generation));
    });
  }

  Future<void> _runSearch(String query, int generation) async {
    try {
      final result = await _gateway.search(
        input: query,
        sessionToken: _sessionToken,
      );

      if (!mounted || generation != _searchGeneration) {
        return;
      }

      setState(() {
        _suggestions = result;
        _loading = false;
        _hasCompletedSearch = true;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) {
        return;
      }

      setState(() {
        _suggestions = const [];
        _loading = false;
        _hasCompletedSearch = true;
        _errorMessage =
            'Adres araması şu anda kullanılamıyor. '
            'Tekrar deneyin.';
      });
    }
  }

  void _retry() {
    final query = searchController.text.trim();

    if (query.length < PlaceSearchService.minInputLength) {
      return;
    }

    _debounce?.cancel();

    final generation = ++_searchGeneration;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _hasCompletedSearch = false;
      _suggestions = const [];
    });

    unawaited(_runSearch(query, generation));
  }

  Future<void> _selectSuggestion(PlaceSearchSuggestion suggestion) async {
    if (_resolvingPlaceId != null) {
      return;
    }

    _debounce?.cancel();

    ++_searchGeneration;

    setState(() {
      _resolvingPlaceId = suggestion.placeId;

      _errorMessage = null;
    });

    try {
      final address = await _gateway.resolve(
        placeId: suggestion.placeId,
        sessionToken: _sessionToken,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, address);
    } catch (_) {
      if (!mounted) {
        return;
      }

      // A Place Details attempt can conclude the
      // autocomplete session. Fail closed and use
      // a fresh token for the next retry.
      _sessionToken = _createSessionToken();

      setState(() {
        _resolvingPlaceId = null;
        _suggestions = const [];
        _loading = false;
        _hasCompletedSearch = true;
        _errorMessage =
            'Adres ayrıntıları alınamadı. '
            'Tekrar arayın.';
      });
    }
  }

  Widget _favoriteTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .15),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        debugPrint(title);
      },
    );
  }

  Widget _buildIdleContent() {
    return ListView(
      children: [
        const SizedBox(height: 8),
        _favoriteTile(
          icon: Icons.home,
          color: Colors.blue,
          title: 'Ev',
          subtitle: 'Henüz kayıtlı değil',
        ),
        _favoriteTile(
          icon: Icons.work,
          color: Colors.orange,
          title: 'İş',
          subtitle: 'Henüz kayıtlı değil',
        ),
        _favoriteTile(
          icon: Icons.favorite,
          color: Colors.red,
          title: 'Favoriler',
          subtitle: 'Kayıtlı adresler',
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Önerilen Yerler',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ),
        ...addressController.filtered.map((AddressModel address) {
          return SearchResultTile(
            address: address,
            onTap: () {
              Navigator.pop(context, address);
            },
          );
        }),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('place_search_retry'),
              onPressed: _retry,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _googleMapsAttribution() {
    return const Padding(
      key: ValueKey('google_maps_attribution'),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          'Google Maps',
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Color(0xFF5E5E5E),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchContent() {
    final query = searchController.text.trim();

    if (query.length < PlaceSearchService.minInputLength) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aramak için en az 3 karakter girin.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildError();
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: ValueKey('place_search_loading')),
      );
    }

    if (_hasCompletedSearch && _suggestions.isEmpty) {
      return const Center(child: Text('Sonuç bulunamadı.'));
    }

    return ListView(
      children: [
        ..._suggestions.map((suggestion) {
          final resolving = _resolvingPlaceId == suggestion.placeId;

          return ListTile(
            key: ValueKey(
              'place_suggestion_'
              '${suggestion.placeId}',
            ),
            leading: const CircleAvatar(child: Icon(Icons.location_on)),
            title: Text(suggestion.title),
            subtitle: suggestion.description.isEmpty
                ? null
                : Text(suggestion.description),
            trailing: resolving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _resolvingPlaceId != null
                ? null
                : () {
                    unawaited(_selectSuggestion(suggestion));
                  },
          );
        }),
        if (_suggestions.isNotEmpty) _googleMapsAttribution(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final idle = searchController.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Adres Ara'), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Adres veya yer ara',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: idle ? _buildIdleContent() : _buildSearchContent()),
          ],
        ),
      ),
    );
  }
}
