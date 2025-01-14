import 'package:flutter/material.dart';
import 'package:hacki/models/search_params.dart';
import 'package:hacki/screens/widgets/widgets.dart';
import 'package:intl/intl.dart';

class DateTimeRangeFilterChip extends StatelessWidget {
  const DateTimeRangeFilterChip({
    Key? key,
    required this.filter,
    required this.onDateTimeRangeUpdated,
    required this.onDateTimeRangeRemoved,
  }) : super(key: key);

  final DateTimeRangeFilter? filter;
  final Function(DateTime, DateTime) onDateTimeRangeUpdated;
  final VoidCallback onDateTimeRangeRemoved;

  static final DateFormat _dateTimeFormatter = DateFormat.yMMMd();

  @override
  Widget build(BuildContext context) {
    return CustomChip(
      onSelected: (bool value) {
        showDateRangePicker(
          context: context,
          firstDate: DateTime.now().subtract(const Duration(days: 20 * 365)),
          lastDate: DateTime.now(),
        ).then((DateTimeRange? range) {
          if (range != null) {
            onDateTimeRangeUpdated(range.start, range.end);
          } else {
            onDateTimeRangeRemoved();
          }
        });
      },
      selected: filter != null,
      label:
          '''from ${_formatDateTime(filter?.startTime) ?? 'START DATE'} to ${_formatDateTime(filter?.endTime) ?? 'END DATE'}''',
    );
  }

  static String? _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return null;

    return _dateTimeFormatter.format(dateTime);
  }
}
