import 'package:flutter/material.dart';
import '../core/design/app_tokens.dart';

/// Horizontal scrollable filter chip bar.
class AppFilterChipBar extends StatelessWidget {
  final List<String> labels;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool showAll;
  final String allLabel;

  const AppFilterChipBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.showAll = true,
    this.allLabel = 'All',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
        children: [
          if (showAll)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppTokens.s8),
              child: FilterChip(
                label: Text(allLabel),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
              ),
            ),
          ...labels.map(
            (label) => Padding(
              padding: const EdgeInsetsDirectional.only(end: AppTokens.s8),
              child: FilterChip(
                label: Text(label),
                selected: selected == label,
                onSelected: (sel) => onSelected(sel ? label : null),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
