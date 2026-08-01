import 'package:flutter/material.dart';

import '../../domain/driver_application/vehicle_catalog.dart';

class SearchableSelectionField extends StatelessWidget {
  final String label;
  final String hint;
  final String? selectedValue;
  final List<String> items;
  final bool enabled;
  final String? specialOption;
  final ValueChanged<String> onSelected;

  const SearchableSelectionField({
    super.key,
    required this.label,
    required this.hint,
    required this.selectedValue,
    required this.items,
    required this.onSelected,
    this.enabled = true,
    this.specialOption,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: selectedValue ?? hint,
    enabled: enabled,
    button: true,
    child: InkWell(
      onTap: enabled ? () => _open(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: enabled ? null : hint,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          enabled: enabled,
        ),
        child: Text(selectedValue ?? hint),
      ),
    ),
  );

  Future<void> _open(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SelectionSheet(
        label: label,
        items: items,
        specialOption: specialOption,
      ),
    );
    if (selected != null) onSelected(selected);
  }
}

class _SelectionSheet extends StatefulWidget {
  final String label;
  final List<String> items;
  final String? specialOption;
  const _SelectionSheet({
    required this.label,
    required this.items,
    this.specialOption,
  });

  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = filterVehicleOptions(widget.items, query);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '${widget.label} ara',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Sonuç bulunamadı.'))
                    : ListView(
                        children: [
                          for (final item in filtered)
                            ListTile(
                              title: Text(item),
                              onTap: () => Navigator.pop(context, item),
                            ),
                        ],
                      ),
              ),
              if (widget.specialOption != null) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(widget.specialOption!),
                  onTap: () => Navigator.pop(context, widget.specialOption),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
