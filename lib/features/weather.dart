import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class DiaryWeather extends StatefulWidget {
  final AppStore store;
  final DiaryEntry entry;
  const DiaryWeather(this.store, this.entry, {super.key});
  @override
  State<DiaryWeather> createState() => _DiaryWeatherState();
}

class _DiaryWeatherState extends State<DiaryWeather> {
  bool busy = false;
  static const labels = {
    'condicao': 'Condição',
    'temperaturaC': 'Temperatura (°C)',
    'umidadePercent': 'Umidade (%)',
    'ventoKmh': 'Vento (km/h)',
    'precipitacaoMm': 'Chuva (mm)',
  };

  /// [suggestion] é o clima consultado automaticamente: o usuário confirma ou corrige antes de salvar.
  Future<void> edit({Map<String, dynamic>? suggestion}) async {
    // Os controllers pertencem a este diálogo: ficam locais e são descartados só depois da animação de
    // saída, e não mais pela página (que podia sair da tela com o diálogo ainda aberto).
    final inputs = <String, TextEditingController>{
      for (final k in labels.keys)
        k: TextEditingController(
          text: '${(suggestion ?? widget.entry.weather)[k] ?? ''}',
        ),
    };
    String? error;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text('Clima observado'),
          content: SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in labels.entries)
                    FieldLabel(
                      e.value,
                      child: TextField(
                        controller: inputs[e.key],
                        keyboardType: e.key == 'condicao'
                            ? TextInputType.text
                            : TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                      ),
                    ),
                  if (error != null) Notice(error!, color: Palette.warning),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final result = <String, dynamic>{};
                for (final k in labels.keys) {
                  final v = inputs[k]!.text.trim();
                  if (v.isEmpty) continue;
                  if (k == 'condicao') {
                    if (v.length > 100) {
                      set(() => error = 'Condição: até 100 caracteres.');
                      return;
                    }
                    result[k] = v;
                  } else {
                    final n = double.tryParse(v.replaceAll(',', '.'));
                    final min = k == 'temperaturaC' ? -90 : 0;
                    final max = switch (k) {
                      'temperaturaC' => 60,
                      'umidadePercent' => 100,
                      'ventoKmh' => 500,
                      _ => 1000,
                    };
                    if (n == null ||
                        !n.isFinite ||
                        n < min ||
                        n > max ||
                        k == 'umidadePercent' && n != n.roundToDouble()) {
                      set(
                        () => error =
                            '${labels[k]}: informe um valor entre $min e $max${k == 'umidadePercent' ? ', inteiro' : ''}.',
                      );
                      return;
                    }
                    result[k] = k == 'umidadePercent' ? n.toInt() : n;
                  }
                }
                if (result.isEmpty) {
                  set(() => error = 'Preencha ao menos um campo.');
                  return;
                }
                if (suggestion != null) {
                  final corrected = labels.keys.any((k) {
                    final a = suggestion[k], b = result[k];
                    if (a is num && b is num)
                      return a.toDouble() != b.toDouble();
                    return a != b;
                  });
                  result['corrigidoPeloUsuario'] = corrected;
                  if (!corrected)
                    result['tokenConsulta'] = suggestion['tokenConsulta'];
                } else {
                  result['corrigidoPeloUsuario'] = true;
                }
                Navigator.pop(context, result);
              },
              child: Text('Salvar clima'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      for (final c in inputs.values) {
        c.dispose();
      }
    });
    if (values == null || !mounted) return;
    setState(() => busy = true);
    await runAction(
      context,
      () => widget.store.updateWeather(widget.entry, values),
      success: 'Clima atualizado.',
    );
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Eyebrow('CLIMA DO DIÁRIO'),
          SizedBox(height: 18),
          if (e.weather.isEmpty)
            Text(
              'O clima ainda não está disponível.',
              style: TextStyle(color: Palette.muted),
            )
          else ...[
            Text(
              '${e.weather['condicao'] ?? 'Condição não informada'}',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 14),
            for (final field in labels.entries.where(
              (e) => e.key != 'condicao',
            ))
              if (e.weather[field.key] != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${field.value}: ${e.weather[field.key]}',
                    style: mono(size: 12),
                  ),
                ),
            if (e.weather['fonte'] != null) ...[
              SizedBox(height: 6),
              StatusPill('${e.weather['fonte']}'),
            ],
          ],
          SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: busy || e.closed || !widget.store.canDiary ? null : edit,
            icon: Icon(Icons.edit_outlined, size: 16),
            label: Text('INFORMAR CLIMA'),
          ),
          if (e.remoteId != null) ...[
            SizedBox(height: 8),
            TextButton(
              onPressed: busy || e.closed
                  ? null
                  : () async {
                      setState(() => busy = true);
                      Map<String, dynamic>? suggestion;
                      await runAction(
                        context,
                        () async =>
                            suggestion = await widget.store.fetchWeather(e),
                      );
                      if (mounted) setState(() => busy = false);
                      if (suggestion != null && mounted)
                        await edit(suggestion: suggestion);
                    },
              child: Text('CONSULTAR CLIMA AUTOMÁTICO'),
            ),
            TextButton(
              onPressed: busy || widget.store.tasks.containsKey(e.id)
                  ? null
                  : () =>
                        runAction(context, () => widget.store.refreshDiary(e)),
              child: Text('ATUALIZAR REGISTRO'),
            ),
          ],
          SizedBox(height: 8),
          Text(
            'O clima automático usa as coordenadas da obra cadastradas no servidor.',
            style: TextStyle(fontSize: 12, height: 1.5, color: Palette.muted),
          ),
        ],
      ),
    );
  }
}
