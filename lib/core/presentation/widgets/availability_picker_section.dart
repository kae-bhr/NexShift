import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Section verte "Votre disponibilité" avec sélection Du/Au.
///
/// Widget autonome réutilisable dans :
/// - replacement_request_dialog.dart (acceptation d'un remplacement)
/// - replacement_requests_list_page.dart (acceptation d'une recherche AgentQuery)
class AvailabilityPickerSection extends StatefulWidget {
  /// Borne inférieure minimale pour le Du
  final DateTime rangeStart;

  /// Borne supérieure maximale pour le Au
  final DateTime rangeEnd;

  /// Valeur initiale du Du (défaut = rangeStart)
  final DateTime? initialStart;

  /// Valeur initiale du Au (défaut = rangeEnd)
  final DateTime? initialEnd;

  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;

  const AvailabilityPickerSection({
    super.key,
    required this.rangeStart,
    required this.rangeEnd,
    this.initialStart,
    this.initialEnd,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  @override
  State<AvailabilityPickerSection> createState() =>
      _AvailabilityPickerSectionState();
}

class _AvailabilityPickerSectionState
    extends State<AvailabilityPickerSection> {
  late DateTime _selectedStart;
  late DateTime _selectedEnd;

  @override
  void initState() {
    super.initState();
    _selectedStart = widget.initialStart ?? widget.rangeStart;
    _selectedEnd = widget.initialEnd ?? widget.rangeEnd;
  }

  String _fmt(DateTime dt) => DateFormat('dd/MM HH:mm').format(dt);

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedStart,
      firstDate: widget.rangeStart,
      lastDate: widget.rangeEnd,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedStart),
    );
    if (time == null || !mounted) return;

    final newStart = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (newStart.isBefore(widget.rangeStart) ||
        !newStart.isBefore(widget.rangeEnd)) {
      return;
    }

    setState(() {
      _selectedStart = newStart;
      if (_selectedEnd.isBefore(_selectedStart)) {
        _selectedEnd = widget.rangeEnd;
      }
    });
    widget.onStartChanged(_selectedStart);
    widget.onEndChanged(_selectedEnd);
  }

  Future<void> _pickEnd() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedEnd,
      firstDate: _selectedStart,
      lastDate: widget.rangeEnd,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedEnd),
    );
    if (time == null || !mounted) return;

    final newEnd = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (newEnd.isAfter(widget.rangeEnd) || !newEnd.isAfter(_selectedStart)) {
      return;
    }

    setState(() => _selectedEnd = newEnd);
    widget.onEndChanged(_selectedEnd);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Votre disponibilité',
            style: TextStyle(
              fontSize: 12,
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickStart,
            child: _TimePickerRow(
              label: 'Du',
              value: _fmt(_selectedStart),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickEnd,
            child: _TimePickerRow(
              label: 'Au',
              value: _fmt(_selectedEnd),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tapez pour modifier les horaires',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimePickerRow extends StatelessWidget {
  final String label;
  final String value;

  const _TimePickerRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label  $value',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          Icon(
            Icons.edit,
            size: 15,
            color: Colors.green.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}
