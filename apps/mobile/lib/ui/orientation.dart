import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../moteur/moteur_mobile.dart';
import 'commun.dart';

/// Orienter un patient (réception de secours). Les listes sont celles de la page du simulateur ; sans dossier ouvert, l'écran ne propose que le texte
/// « Ouvrez d’abord un dossier. ». L'orientation est une ligne de journal : elle ne se modifie pas, elle ne se supprime pas (RG-14).
class OrienterPatient extends StatefulWidget {
  const OrienterPatient({super.key, required this.service});
  final ServiceSuite service;

  @override
  State<OrienterPatient> createState() => _OrienterPatientState();
}

class _OrienterPatientState extends State<OrienterPatient> {
  late final Future<List<FichePatient>> _dossiers = widget.service.dossiersOuverts();
  String? _dossier;
  String _destination = mobOrientationDestinations.first;
  String _degre = mobOrientationDegres.first;
  RefusMobile? _refus;

  Future<void> _envoyer(List<FichePatient> l) async {
    try {
      await widget.service.orienter(_dossier ?? l.first.id, destination: _destination, degre: _degre);
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
    final champs = {for (final c in mobChampsEcran('orientation')) c.id: c};
    final erreurs = _refus?.champs ?? const <String, String>{};
    return Scaffold(
      appBar: AppBar(title: Text(mobTitreEcranSuite('orientation'))),
      body: FutureBuilder<List<FichePatient>>(
        future: _dossiers,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final l = snap.data!;
          if (l.isEmpty) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(mobOrientationVide, key: const Key('orientation-vide'), textAlign: TextAlign.center)));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  DropdownButtonFormField<String>(
                    key: const Key('champ-pat'),
                    initialValue: _dossier ?? l.first.id,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: champs['pat']!.libelle, border: const OutlineInputBorder()),
                    items: [for (final d in l) DropdownMenuItem(value: d.id, child: Text(mobOrientationChoix(d.champs)))],
                    onChanged: (v) => setState(() => _dossier = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('champ-dest'),
                    initialValue: _destination,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: champs['dest']!.libelle, errorText: erreurs['dest'], border: const OutlineInputBorder()),
                    items: [for (final o in champs['dest']!.options!) DropdownMenuItem(value: o, child: Text(o))],
                    onChanged: (v) => setState(() => _destination = v ?? _destination),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('champ-urg'),
                    initialValue: _degre,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: champs['urg']!.libelle, errorText: erreurs['urg'], border: const OutlineInputBorder()),
                    items: [for (final o in champs['urg']!.options!) DropdownMenuItem(value: o, child: Text(o))],
                    onChanged: (v) => setState(() => _degre = v ?? _degre),
                  ),
                ]),
              ),
            ),
            if (_refus != null && _refus!.champs.isEmpty) CarteRefus(_refus!),
            const SizedBox(height: 8),
            FilledButton(key: const Key('envoyer-orientation'), onPressed: () => _envoyer(l), child: Text(mobBoutonEcran('orientation'))),
          ]);
        },
      ),
    );
  }
}
