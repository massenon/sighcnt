import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../moteur/moteur_mobile.dart';
import 'commun.dart';

/// Prescription selon droits. Les natures proposées sont celles que la fonction peut prescrire ET que le profil ouvre ; sans aucune, l'écran n'est
/// pas atteignable (la commande est absente du dossier). Le contrôle est refait à l'écriture : un refus s'affiche avec son code, son motif et son geste.
class SaisiePrescription extends StatefulWidget {
  const SaisiePrescription({super.key, required this.service, required this.patientId});
  final ServiceSoignant service;
  final String patientId;

  @override
  State<SaisiePrescription> createState() => _SaisiePrescriptionState();
}

class _SaisiePrescriptionState extends State<SaisiePrescription> {
  String? _produit;
  List<MobProduit> _catalogue = const [];
  final _quantite = TextEditingController();
  final _poso = TextEditingController();
  final _duree = TextEditingController();
  final _coches = <String>{};
  late String _nature = widget.service.naturesPrescriptibles.first;
  String _urgence = mobUrgencesAnalyses.first;
  RefusMobile? _refus;

  @override
  void initState() {
    super.initState();
    widget.service.produits().then((l) {
      if (mounted) setState(() => _catalogue = l);
    });
  }

  Future<void> _envoyer() async {
    try {
      if (_nature == 'medicament') {
        await widget.service.prescrireMedicament(widget.patientId, {'med': _produit ?? '', 'quantite': _quantite.text, 'poso': _poso.text, 'duree': _duree.text});
      } else {
        await widget.service.prescrireAnalyses(widget.patientId, [for (final e in mobExamensAnalyses) if (_coches.contains(e)) e], _urgence);
      }
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
    final natures = widget.service.naturesPrescriptibles;
    final erreurs = _refus?.champs ?? const <String, String>{};
    final medicament = _nature == 'medicament';
    return Scaffold(
      appBar: AppBar(title: Text(mobLibelleEcran(medicament ? 'prescription' : 'demande-analyse'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (natures.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<String>(
              key: const Key('nature'),
              segments: [for (final n in natures) ButtonSegment(value: n, label: Text(mobLibelleNature(n)))],
              selected: {_nature},
              onSelectionChanged: (s) => setState(() {
                _nature = s.first;
                _refus = null;
              }),
            ),
          ),
        // La phrase de la maquette (« Prescrire génère l'ordonnance et la facture de la caisse ») n'est vraie qu'après la transcription par le poste : elle
        // s'affiche au dossier quand le compte rendu est revenu. Ici la prescription PART à la clinique, qui la transcrit.
        NoteInfo(medicament ? mobTexteEnvoiPrescription : mobTexte('analyses')),
        if (medicament) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              key: const Key('champ-med'),
              initialValue: _produit,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Médicament du catalogue *', errorText: erreurs['med'], border: const OutlineInputBorder()),
              items: [for (final p in _catalogue) DropdownMenuItem(value: p.id, child: Text('${p.designation} · stock ${p.stock}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _produit = v),
            ),
          ),
          if (_catalogue.isEmpty) const NoteInfo('Aucun médicament dans le lot de ce téléphone : le catalogue arrive avec le lot du jour.', key: Key('catalogue-vide')),
          champSaisie(cle: 'quantite', libelle: 'Quantité (boîtes, unités)', controleur: _quantite, erreurs: erreurs, requis: true, clavier: TextInputType.number),
          champSaisie(cle: 'poso', libelle: 'Posologie', controleur: _poso, erreurs: erreurs, requis: true),
          champSaisie(cle: 'duree', libelle: 'Durée (jours)', controleur: _duree, erreurs: erreurs, requis: true, clavier: TextInputType.number),
        ] else ...[
          Text('Examens demandés *', style: Theme.of(context).textTheme.titleSmall),
          for (final e in mobExamensAnalyses)
            CheckboxListTile(
              key: Key('examen-$e'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e),
              value: _coches.contains(e),
              onChanged: (v) => setState(() => v == true ? _coches.add(e) : _coches.remove(e)),
            ),
          if (erreurs['examens'] != null) Text(erreurs['examens']!, key: const Key('erreur-examens'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('champ-urgence'),
            initialValue: _urgence,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Urgence', border: OutlineInputBorder()),
            items: [for (final u in mobUrgencesAnalyses) DropdownMenuItem(value: u, child: Text(u))],
            onChanged: (v) => setState(() => _urgence = v ?? _urgence),
          ),
        ],
        if (_refus != null && _refus!.champs.isEmpty) CarteRefus(_refus!),
        const SizedBox(height: 12),
        FilledButton(key: const Key('envoyer-prescription'), onPressed: _envoyer, child: Text(medicament ? 'Enregistrer l’ordonnance' : 'Envoyer la demande')),
      ]),
    );
  }
}
