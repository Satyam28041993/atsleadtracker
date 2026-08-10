import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/flexible_date_parse.dart';

/// Date picker for when the lead/tender was received (defaults to today).
class LeadDateField extends StatelessWidget {
  const LeadDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.label = 'Lead date',
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                helpText: label,
              );
              if (picked != null) {
                onChanged(dateOnly(picked));
              }
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(DateFormat('dd.MM.yyyy').format(value)),
      ),
    );
  }
}
