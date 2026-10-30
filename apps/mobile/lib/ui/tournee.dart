import 'package:flutter/material.dart';

import '../moteur/moteur_mobile.dart';

/// Liste des dossiers du lot de la tournée ; un dossier s'ouvre sur la saisie des constantes.
class Tournee extends StatefulWidget {
  const Tournee({super.key, required this.moteur});
  final MoteurMobile moteur;

  @override
  State<Tournee> createState() => _TourneeState();
}

class _TourneeState extends State<Tournee> {
  late Future<List<FichePatient>> _liste = widget.moteur.tournee();

  void _rafraichir() => setState(() {
        _liste = widget.moteur.tournee();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FichePatient>>(
      future: _liste,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final l = snap.data!;
        if (l.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Aucun dossier dans votre tournée. La mère dépose le lot du jour à la première synchronisation.', textAlign: TextAlign.center)));
        }
        return ListView(children: [
          for (final p in l)
            ListTile(
              key: Key('patient-${p.id}'),
              title: Text(p.nom.isEmpty ? p.code : p.nom),
              subtitle: Text('${p.code}${p.champs['quartier'] != null ? ' · ${p.champs['quartier']}' : ''}'),
              trailing: const Icon(Icons.monitor_heart_outlined),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SaisieConstantes(moteur: widget.moteur, patient: p)));
                _rafraichir();
              },
            ),
        ]);
      },
    );
  }
}

class SaisieConstantes extends StatefulWidget {
  const SaisieConstantes({super.key, required this.moteur, required this.patient});
  final MoteurMobile moteur;
  final FichePatient patient;

  @override
  State<SaisieConstantes> createState() => _SaisieConstantesState();
}

class _SaisieConstantesState extends State<SaisieConstantes> {
  final _c = {for (final k in ['temperature', 'tension', 'pouls', 'poids']) k: TextEditingController()};
  String? _erreur;

  Future<void> _enregistrer() async {
    final saisie = {for (final e in _c.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim().replaceAll(',', '.')};
    if (saisie.isEmpty) {
      setState(() => _erreur = 'Saisissez au moins une constante.');
      return;
    }
    // Un champ numérique mal saisi est refusé en le NOMMANT : mieux vaut une erreur ici qu'une valeur absurde au dossier.
    for (final k in ['temperature', 'pouls', 'poids']) {
      if (saisie.containsKey(k) && double.tryParse(saisie[k]!) == null) {
        setState(() => _erreur = '« $k » doit être un nombre.');
        return;
      }
    }
    await widget.moteur.enregistrerConstantes(widget.patient.id, {
      for (final e in saisie.entries) e.key: ['temperature', 'pouls', 'poids'].contains(e.key) ? double.parse(e.value) : e.value,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistré sur le téléphone — part dès que le réseau revient.')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const libelles = {'temperature': 'Température (°C)', 'tension': 'Tension (ex. 12/8)', 'pouls': 'Pouls (/min)', 'poids': 'Poids (kg)'};
    return Scaffold(
      appBar: AppBar(title: Text(widget.patient.nom.isEmpty ? widget.patient.code : widget.patient.nom)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final e in _c.entries) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(key: Key('champ-${e.key}'), controller: e.value, decoration: InputDecoration(labelText: libelles[e.key]), keyboardType: TextInputType.text)),
        if (_erreur != null) Text(_erreur!, key: const Key('erreur'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        FilledButton(key: const Key('enregistrer'), onPressed: _enregistrer, child: const Text('Enregistrer')),
      ]),
    );
  }
}
