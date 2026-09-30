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
Future<void> projectDialog(
  BuildContext context,
  AppStore store, {
  Project? existing,
}) async {
  if (!store.canManageProjects) return;
  final form = GlobalKey<FormState>();
  final initial = existing?.toJson() ?? <String, dynamic>{};
  final fields = {
    for (final key in [
      'name',
      'city',
      'state',
      'address',
      'contractor',
      'executor',
      'responsible',
      'registration',
      'plannedStartDate',
      'plannedEndDate',
      'latitude',
      'longitude',
    ])
      key: TextEditingController(text: initial[key]?.toString() ?? ''),
  };
  var type = existing?.type ?? 'RESIDENCIAL',
      status = existing?.status ?? 'EM_EXECUCAO';
  bool saving = false;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(existing == null ? 'Adicionar obra' : 'Dados da obra'),
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
                                    !RegExp(r'^[A-Za-z]{2}$')
                                        .hasMatch(v!.trim())
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
                      for (final field in {
                        'plannedStartDate': 'Início previsto',
                        'plannedEndDate': 'Término previsto',
                      }.entries)
                        FieldLabel(
                          field.value,
                          child: TextFormField(
                            controller: fields[field.key],
                            readOnly: true,
                            enabled: !saving,
                            decoration: InputDecoration(
                              hintText: 'Selecione a data',
                              suffixIcon: Icon(Icons.calendar_month),
                            ),
                            onTap: () async {
                              final date = await showDatePicker(
                                context: c,
                                initialDate:
                                    DateTime.tryParse(
                                      fields[field.key]!.text,
                                    ) ??
                                    DateTime.now(),
                                firstDate: DateTime(1900),
                                lastDate: DateTime(2100),
                              );
                              if (date != null)
                                fields[field.key]!.text = date
                                    .toIso8601String()
                                    .substring(0, 10);
                            },
                          ),
                        ),
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
                              final value = double.tryParse(
                                v.replaceAll(',', '.'),
                              );
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
            onPressed: saving ? null : () => Navigator.pop(c),
            child: Text('Cancelar'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => saving = true);
                    await runAction(c, () async {
                      String value(String key) => fields[key]!.text.trim();
                      await store.saveProject(
                        Project(
                          id: existing?.id ?? '',
                          name: value('name'),
                          code: existing?.code ?? '',
                          city: value('city'),
                          state: value('state').toUpperCase(),
                          address: value('address'),
                          contractor: value('contractor'),
                          executor: value('executor'),
                          responsible: value('responsible'),
                          registration: value('registration'),
                          type: type,
                          status: status,
                          plannedStartDate: value('plannedStartDate'),
                          plannedEndDate: value('plannedEndDate'),
                          latitude: double.tryParse(
                            value('latitude').replaceAll(',', '.'),
                          ),
                          longitude: double.tryParse(
                            value('longitude').replaceAll(',', '.'),
                          ),
                        ),
                      );
                      if (c.mounted) Navigator.pop(c);
                    });
                    if (c.mounted) setState(() => saving = false);
                  },
            child: Text(saving ? 'SALVANDO…' : 'SALVAR OBRA'),
          ),
        ],
      ),
    ),
  );
  for (final field in fields.values) {
    field.dispose();
  }
}
