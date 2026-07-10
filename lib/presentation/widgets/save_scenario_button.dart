import 'package:flutter/material.dart';
import '../../core/freemium/freemium_service.dart';
import '../../core/language/language_notifier.dart';

/// A "Save Scenario" button that pins the current calculator result.
///
/// Shows a name-entry dialog before saving (all users).
/// Bilingual EN/ES via [isSpanishNotifier].
class SaveScenarioButton extends StatefulWidget {
  /// Called when the user confirms the save. [label] is null if the user left the name blank.
  final Future<void> Function(String? label) onSave;

  const SaveScenarioButton({super.key, required this.onSave});

  @override
  State<SaveScenarioButton> createState() => _SaveScenarioButtonState();
}

class _SaveScenarioButtonState extends State<SaveScenarioButton> {
  bool _saving = false;

  Future<void> _handleTap() async {
    final isEs = isSpanishNotifier.value;
    String? label;

    label = await _showNameDialog(isEs);
    if (label == null) return;
    if (label.trim().isEmpty) label = null;

    setState(() => _saving = true);
    try {
      await widget.onSave(label);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            label != null && label.isNotEmpty
                ? (isEs ? 'Escenario "$label" guardado' : 'Scenario "$label" saved')
                : (isEs ? 'Escenario guardado' : 'Scenario saved'),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _showNameDialog(bool isEs) {
    return showDialog<String>(
      context: context,
      builder: (_) => _SaveScenarioNameDialog(isEs: isEs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _saving ? null : _handleTap,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.bookmark_add_outlined, size: 18),
        label: Text(
          _saving
              ? (isEs ? 'Guardando…' : 'Saving…')
              : (isEs ? 'Guardar escenario' : 'Save Scenario'),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}

class _SaveScenarioNameDialog extends StatefulWidget {
  final bool isEs;

  const _SaveScenarioNameDialog({required this.isEs});

  @override
  State<_SaveScenarioNameDialog> createState() =>
      _SaveScenarioNameDialogState();
}

class _SaveScenarioNameDialogState extends State<_SaveScenarioNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEs = widget.isEs;
    return AlertDialog(
      title: Text(isEs ? 'Guardar escenario' : 'Save Scenario'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          hintText: isEs
              ? 'Nombre del escenario (opcional)'
              : 'Scenario name (optional)',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(isEs ? 'Cancelar' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(isEs ? 'Guardar' : 'Save'),
        ),
      ],
    );
  }
}
