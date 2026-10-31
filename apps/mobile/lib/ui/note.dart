import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../moteur/moteur_mobile.dart';
import 'commun.dart';

/// Note de consultation à domicile. Dossier, fiche, prescription : la prescription ne s'ouvre qu'après l'enregistrement de cette note.
/// Les constantes relevées ce jour sont reprises dans la note (copie datée), jamais ressaisies. L'orientation est celle de la fiche de consultation.
class SaisieNote extends StatefulWidget {
  const SaisieNote({super.key, required this.service, required this.patientId, this.motif = ''});
  final ServiceSoignant service;
  final String patientId;
  final String motif;

  @override
  State<SaisieNote> createState() => _SaisieNoteState();
}

class _SaisieNoteState extends State<SaisieNote> {
  late final _motif = TextEditingController(text: widget.motif);
  final _anamnese = TextEditingController();
  final _precision = TextEditingController();
  late final Map<String, TextEditingController> _temps = {for (final t in mobTempsExamen) t.code: TextEditingController()};
  String _diagnostic = mobDiagnostics.first;
  String _orientation = '';
  RefusMobile? _refus;

  Future<void> _enregistrer() async {
    final saisie = <String, String>{
      'motif': _motif.text,
      'anamnese': _anamnese.text,
      for (final e in _temps.entries) e.key: e.value.text,
      'diagnostic': _diagnostic,
      'precision': _precision.text,
      'orientation': _orientation,
    };
    try {
      await widget.service.enregistrerNote(widget.patientId, saisie);
    } on RefusMobile catch (r) {
      setState(() => _refus = r);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(messageEnregistre)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final erreurs = _refus?.champs ?? const <String, String>{};
    return Scaffold(
      appBar: AppBar(title: Text(mobLibelleEcran('consultation'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        NoteInfo(mobTexte('consultation')),
        champSaisie(cle: 'motif', libelle: 'Motif', controleur: _motif, erreurs: erreurs, requis: true),
        champSaisie(cle: 'anamnese', libelle: 'Anamnèse', controleur: _anamnese, erreurs: erreurs, lignes: 3),
        for (final t in mobTempsExamen) champSaisie(cle: t.code, libelle: t.libelle, controleur: _temps[t.code]!, erreurs: erreurs, lignes: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            key: const Key('champ-diagnostic'),
            initialValue: _diagnostic,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Diagnostic *', errorText: erreurs['diagnostic'], border: const OutlineInputBorder()),
            items: [for (final d in mobDiagnostics) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() => _diagnostic = v ?? _diagnostic),
          ),
        ),
        if (_diagnostic == mobDiagnosticAutre) champSaisie(cle: 'precision', libelle: 'Diagnostic à préciser', controleur: _precision, erreurs: erreurs, requis: true),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            key: const Key('champ-orientation'),
            initialValue: _orientation,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Orientation', errorText: erreurs['orientation'], border: const OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: '', child: Text('Aucune')),
              for (final o in mobOrientations) DropdownMenuItem(value: o.valeur, child: Text(o.libelle)),
            ],
            onChanged: (v) => setState(() => _orientation = v ?? ''),
          ),
        ),
        if (_refus != null && _refus!.champs.isEmpty) CarteRefus(_refus!),
        const SizedBox(height: 8),
        FilledButton(key: const Key('enregistrer-note'), onPressed: _enregistrer, child: const Text('Enregistrer la fiche')),
      ]),
    );
  }
}
