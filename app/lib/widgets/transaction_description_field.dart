import 'package:flutter/material.dart';

class TransactionDescriptionField extends StatelessWidget {
  const TransactionDescriptionField({
    required this.controller,
    required this.label,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.notes),
        alignLabelWithHint: true,
      ),
    );
  }
}
