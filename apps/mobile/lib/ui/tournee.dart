import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../moteur/moteur_mobile.dart';
import 'commun.dart';
import 'dossier.dart';

/// Liste des dossiers du lot de la tournée ; un dossier s'ouvre en LECTURE, d'où partent les gestes que la fonction autorise.
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
              trailing: const Icon(Icons.folder_open_outlined),
              onTap: () async {
                await ouvrirDossier(context, widget.moteur, p.id);
                if (mounted) _rafraichir();
              },
            ),
        ]);
      },
    );
  }
}

/// Saisie des constantes : les bornes et les messages sont ceux de l'écran de la maquette (`mobReglesConstantes`), une valeur improbable est
/// REFUSÉE EN LA NOMMANT. La saisie est visible aussitôt et part à la première occasion.
class SaisieConstantes extends StatefulWidget {
  const SaisieConstantes({super.key, required this.service, required this.patientId, required this.titre});
  final ServiceSoignant service;
  final String patientId;
  final String titre;

  @override
  State<SaisieConstantes> createState() => _SaisieConstantesState();
}

class _SaisieConstantesState extends State<SaisieConstantes> {
  static const _libelles = {
    'temperature': 'Température (°C)',
    'sys': 'Tension, systolique',
    'dia': 'Tension, diastolique',
    'pouls': 'Pouls (/min)',
    'fr': 'FR (/min)',
    'spo2': 'SpO₂ (%)',
    'poids': 'Poids (kg)',
  };
  final _c = {for (final k in _libelles.keys) k: TextEditingController()};
  RefusMobile? _refus;

  Future<void> _enregistrer() async {
    final saisie = {for (final e in _c.entries) e.key: e.value.text};
    try {
      await widget.service.enregistrerConstantes(widget.patientId, saisie);
    } on RefusMobile catch (r) {
      setState(() => _refus = r);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mobFievre(saisie)
            ? 'Fièvre (${saisie['temperature']!.trim()} °C), signalée au médecin avec la saisie. $messageEnregistre'
            : messageEnregistre)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final erreurs = _refus?.champs ?? const <String, String>{};
    return Scaffold(
      appBar: AppBar(title: Text('Constantes, ${widget.titre}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final e in _libelles.entries)
          champSaisie(cle: e.key, libelle: e.value, controleur: _c[e.key]!, erreurs: erreurs, requis: e.key == 'temperature', clavier: const TextInputType.numberWithOptions(decimal: true)),
        if (_refus != null && _refus!.champs.isEmpty) CarteRefus(_refus!),
        const SizedBox(height: 8),
        FilledButton(key: const Key('enregistrer'), onPressed: _enregistrer, child: const Text('Enregistrer')),
      ]),
    );
  }
}
