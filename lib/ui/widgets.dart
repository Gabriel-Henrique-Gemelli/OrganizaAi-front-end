import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import 'theme.dart';

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.color,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Palette.surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: Palette.border),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class Eyebrow extends StatelessWidget {
  final String text;
  final bool accent;
  const Eyebrow(this.text, {super.key, this.accent = false});
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: mono(color: accent ? Palette.accent : Palette.muted),
  );
}

class PageHeading extends StatelessWidget {
  final String number, title, description;
  final List<Widget> actions;
  const PageHeading({
    super.key,
    required this.number,
    required this.title,
    required this.description,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow('$number / ESPAÇO DE TRABALHO', accent: true),
        SizedBox(height: 14),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: c.maxWidth < 600 ? 32 : 46,
            fontWeight: FontWeight.w800,
            height: 1.02,
            letterSpacing: -1.5,
          ),
        ),
        SizedBox(height: 14),
        Text(
          description,
          style: TextStyle(color: Palette.muted, fontSize: 15, height: 1.5),
        ),
        if (actions.isNotEmpty) ...[
          SizedBox(height: 22),
          Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
        SizedBox(height: 30),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill(this.text, {super.key, this.color = Palette.muted});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Text(text.toUpperCase(), style: mono(size: 9, color: color)),
  );
}

class EmptyState extends StatelessWidget {
  final String title, description;
  final Widget? action;
  final IconData icon;
  const EmptyState({
    super.key,
    required this.title,
    required this.description,
    this.action,
    this.icon = Icons.folder_open_outlined,
  });
  @override
  Widget build(BuildContext context) => Panel(
    child: Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(icon, size: 36, color: Palette.accent),
            SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 440),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.muted, height: 1.5),
              ),
            ),
            if (action != null) ...[SizedBox(height: 22), action!],
          ],
        ),
      ),
    ),
  );
}

class Notice extends StatelessWidget {
  final String text;
  final Color color;
  const Notice(this.text, {super.key, this.color = Palette.muted});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .06),
      border: Border(left: BorderSide(color: color, width: 2)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, height: 1.5),
    ),
  );
}

class AdaptiveColumns extends StatelessWidget {
  final Widget left, right;
  final double breakpoint;
  final int leftFlex, rightFlex;
  const AdaptiveColumns({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = 850,
    this.leftFlex = 3,
    this.rightFlex = 2,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth >= breakpoint
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: leftFlex, child: left),
              SizedBox(width: 22),
              Expanded(flex: rightFlex, child: right),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, SizedBox(height: 22), right],
          ),
  );
}

class Metric extends StatelessWidget {
  final String value, label, detail;
  final VoidCallback? onTap;
  final bool accent;
  const Metric(
    this.value,
    this.label,
    this.detail, {
    super.key,
    this.onTap,
    this.accent = false,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Palette.surface,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(22),
        decoration: BoxDecoration(border: Border.all(color: Palette.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: mono(
                size: 36,
                color: accent ? Palette.accent : Palette.text,
                weight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Eyebrow(label),
            SizedBox(height: 8),
            Text(detail, style: TextStyle(color: Palette.muted, fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

Color documentColor(DocumentRecord d) => {'FAILED', 'FALHOU'}.contains(d.status)
    ? Palette.danger
    : d.reviewed
    ? Palette.success
    : d.ready
    ? Palette.warning
    : Palette.muted;
String fileSize(int n) => n == 0
    ? '—'
    : n < 1024 * 1024
    ? '${(n / 1024).toStringAsFixed(0)} KB'
    : '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
String dateLabel(DateTime d) => DateFormat('dd/MM/yyyy', 'pt_BR').format(d);
String timeLabel(DateTime d) => DateFormat('HH:mm', 'pt_BR').format(d);
void toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> runAction(
  BuildContext context,
  Future<void> Function() work, {
  String? success,
}) async {
  try {
    await work();
    if (success != null && context.mounted) toast(context, success);
  } catch (e) {
    if (context.mounted) toast(context, e.toString());
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String text, {
  String button = 'Confirmar',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 430),
          child: Text(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(button),
          ),
        ],
      ),
    ) ??
    false;

class FieldLabel extends StatelessWidget {
  final String text;
  final Widget child;
  const FieldLabel(this.text, {super.key, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Eyebrow(text), SizedBox(height: 8), child],
    ),
  );
}
