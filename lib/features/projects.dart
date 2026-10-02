import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/widgets.dart';

const projectTypes = {
  'RESIDENCIAL': 'Residencial',
  'COMERCIAL': 'Comercial',
  'INDUSTRIAL': 'Industrial',
  'REFORMA': 'Reforma',
  'INFRAESTRUTURA': 'Infraestrutura',
};
const projectStatuses = {
  'PLANEJAMENTO': 'Planejamento',
  'EM_EXECUCAO': 'Em execução',
  'PARALISADA': 'Paralisada',
  'CONCLUIDA': 'Concluída',
  'ENTREGUE': 'Entregue',
};

String _two(int n) => n.toString().padLeft(2, '0');

/// Data na tela, no formato brasileiro: `02/10/2026`.
String formatBrDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// `2026-10-02` (como a API guarda) para `02/10/2026`; vazio ou inválido vira vazio.
String isoToBrDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : formatBrDate(d);
}

/// `02/10/2026` para [DateTime]; recusa dia ou mês que não existem (ex.: `31/02/2026`).
DateTime? parseBrDate(String text) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text.trim());
  if (m == null) return null;
  final day = int.parse(m[1]!),
      month = int.parse(m[2]!),
      year = int.parse(m[3]!);
  final date = DateTime(year, month, day);
  return date.day == day && date.month == month ? date : null;
}

/// `02/10/2026` para `2026-10-02`, que é o que a API recebe; vazio ou inválido vira vazio.
String brDateToIso(String text) {
  final d = parseBrDate(text);
  return d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
}

Future<void> projectDialog(
  BuildContext context,
  AppStore store, {
  Project? existing,
}) async {
  if (!store.canManageProjects) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ProjectDialog(store, existing),
  );
}

/// O diálogo é dono dos controllers: eles só são descartados quando a rota termina de sair da tela.
/// Descartá-los logo depois do `await showDialog` (como era antes) deixava os campos usando um
/// controller já descartado durante a animação de saída, o que derrubava a árvore de widgets.
class _ProjectDialog extends StatefulWidget {
  final AppStore store;
  final Project? existing;
  const _ProjectDialog(this.store, this.existing);
  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  static const _dateKeys = ['plannedStartDate', 'plannedEndDate'];
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  late String type, status;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.existing?.toJson() ?? <String, dynamic>{};
    fields = {
      for (final key in [
        'name',
        'city',
        'state',
        'address',
        'contractor',
        'executor',
        'responsible',
        'registration',
        ..._dateKeys,
        'latitude',
        'longitude',
      ])
        key: TextEditingController(
          text: _dateKeys.contains(key)
              ? isoToBrDate(initial[key]?.toString() ?? '')
              : initial[key]?.toString() ?? '',
        ),
    };
    type = widget.existing?.type ?? 'RESIDENCIAL';
    status = widget.existing?.status ?? 'EM_EXECUCAO';
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String value(String key) => fields[key]!.text.trim();

  Future<void> pickDate(String key) async {
    final current = parseBrDate(fields[key]!.text);
    final start = parseBrDate(fields['plannedStartDate']!.text);
    final date = await showDatePicker(
      context: context,
      initialDate:
          current ?? (key == 'plannedEndDate' ? start : null) ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => fields[key]!.text = formatBrDate(date));
    }
  }

  String? validateDate(String key, String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return null;
    final date = parseBrDate(text);
    if (date == null) return 'Data inválida. Use dia/mês/ano';
    final start = parseBrDate(fields['plannedStartDate']!.text);
    if (key == 'plannedEndDate' && start != null && date.isBefore(start)) {
      return 'O término não pode ser antes do início';
    }
    return null;
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    // Capturado antes do await: o diálogo pode já ter saído da tela quando a resposta chega.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.store.saveProject(
        Project(
          id: widget.existing?.id ?? '',
          name: value('name'),
          code: widget.existing?.code ?? '',
          city: value('city'),
          state: value('state').toUpperCase(),
          address: value('address'),
          contractor: value('contractor'),
          executor: value('executor'),
          responsible: value('responsible'),
          registration: value('registration'),
          type: type,
          status: status,
          plannedStartDate: brDateToIso(value('plannedStartDate')),
          plannedEndDate: brDateToIso(value('plannedEndDate')),
          latitude: double.tryParse(value('latitude').replaceAll(',', '.')),
          longitude: double.tryParse(value('longitude').replaceAll(',', '.')),
        ),
      );
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) setState(() => saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget dateField(String key, String label) => FieldLabel(
    label,
    child: TextFormField(
      controller: fields[key],
      readOnly: true,
      enabled: !saving,
      decoration: InputDecoration(
        hintText: 'dd/mm/aaaa',
        suffixIcon: Icon(Icons.calendar_month),
      ),
      validator: (v) => validateDate(key, v),
      onTap: () => pickDate(key),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Adicionar obra' : 'Dados da obra'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FieldLabel(
                'Nome da obra *',
                child: TextFormField(
                  controller: fields['name'],
                  enabled: !saving,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 200,
                  decoration: InputDecoration(counterText: ''),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Campo obrigatório'
                      : null,
                ),
              ),
              Notice(
                'O identificador da obra é gerado pelo sistema. Executora e responsável técnico usam a organização e o seu usuário quando ficam em branco.',
              ),
              ExpansionTile(
                title: Text('Mais detalhes (opcional)'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                // Mantém os campos montados quando recolhido, para o formulário validar todos.
                maintainState: true,
                children: [
                  for (final field in {
                    'city': 'Cidade',
                    'state': 'UF',
                    'address': 'Endereço',
                    'contractor': 'Contratante',
                    'executor': 'Executora',
                    'responsible': 'Responsável técnico',
                    'registration': 'Registro profissional',
                  }.entries)
                    FieldLabel(
                      field.value,
                      child: TextFormField(
                        controller: fields[field.key],
                        enabled: !saving,
                        textCapitalization: field.key == 'state'
                            ? TextCapitalization.characters
                            : TextCapitalization.sentences,
                        maxLength: switch (field.key) {
                          'state' => 2,
                          'registration' => 60,
                          'city' => 120,
                          'address' => 300,
                          _ => 200,
                        },
                        decoration: InputDecoration(counterText: ''),
                        validator: (v) =>
                            field.key == 'state' &&
                                (v ?? '').trim().isNotEmpty &&
                                !RegExp(r'^[A-Za-z]{2}$').hasMatch(v!.trim())
                            ? 'Use a sigla da UF'
                            : null,
                      ),
                    ),
                  FieldLabel(
                    'Tipo de obra',
                    child: DropdownButtonFormField<String>(
                      initialValue: type,
                      items: projectTypes.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: saving ? null : (v) => type = v!,
                    ),
                  ),
                  FieldLabel(
                    'Situação',
                    child: DropdownButtonFormField<String>(
                      initialValue: status,
                      items: projectStatuses.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: saving ? null : (v) => status = v!,
                    ),
                  ),
                  dateField('plannedStartDate', 'Início previsto'),
                  dateField('plannedEndDate', 'Término previsto'),
                  Notice(
                    'As coordenadas permitem consultar o clima automático da obra.',
                  ),
                  SizedBox(height: 12),
                  for (final field in {
                    'latitude': 'Latitude',
                    'longitude': 'Longitude',
                  }.entries)
                    FieldLabel(
                      field.value,
                      child: TextFormField(
                        controller: fields[field.key],
                        enabled: !saving,
                        keyboardType: TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final value = double.tryParse(v.replaceAll(',', '.'));
                          final max = field.key == 'latitude' ? 90 : 180;
                          return value == null ||
                                  !value.isFinite ||
                                  value.abs() > max
                              ? 'Coordenada inválida'
                              : null;
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text('Cancelar'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'SALVANDO…' : 'SALVAR OBRA'),
      ),
    ],
  );
}
