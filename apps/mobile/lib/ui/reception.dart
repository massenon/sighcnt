import 'package:flutter/material.dart';

import '../moteur/moteur_mobile.dart';

/// Réception de secours : l'accueil continue quand les postes fileuls n'ont plus de courant. On enregistre le dossier ici ;
/// le code CNT vient de la plage réservée à CE téléphone, jamais inventé à la main (RG-01). Un homonyme n'est pas refusé :
/// il est SIGNALÉ « doublon possible » à la mère, qui arbitre — on ne bloque pas un patient devant le guichet.
class Reception extends StatefulWidget {
  const Reception({super.key, required this.moteur});
  final MoteurMobile moteur;

  @override
  State<Reception> createState() => _ReceptionState();
}

class _ReceptionState extends State<Reception> {
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _age = TextEditingController();
  final _telephone = TextEditingController();
  final _quartier = TextEditingController();
  String? _erreur;
  late Future<List<FichePatient>> _crees = widget.moteur.dossiersCrees();

  Future<void> _creer() async {
    final age = int.tryParse(_age.text.trim());
    if (_nom.text.trim().isEmpty || _prenom.text.trim().isEmpty) {
      setState(() => _erreur = 'Le nom et le prénom sont obligatoires.');
      return;
    }
    if (age == null || age < 0 || age > 120) {
      setState(() => _erreur = 'L’âge déclaré est obligatoire (0 à 120 ans).');
      return;
    }
    await widget.moteur.creerPatient({
      'nom': _nom.text.trim(),
      'prenom': _prenom.text.trim(),
      'ageDeclare': age,
      if (_telephone.text.trim().isNotEmpty) 'telephone': _telephone.text.trim(),
      if (_quartier.text.trim().isNotEmpty) 'quartier': _quartier.text.trim(),
      'origine': 'reception_secours',
    });
    for (final c in [_nom, _prenom, _age, _telephone, _quartier]) {
      c.clear();
    }
    setState(() {
      _erreur = null;
      _crees = widget.moteur.dossiersCrees();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(key: const Key('nom'), controller: _nom, decoration: const InputDecoration(labelText: 'Nom')),
      TextField(key: const Key('prenom'), controller: _prenom, decoration: const InputDecoration(labelText: 'Prénom')),
      TextField(key: const Key('age'), controller: _age, decoration: const InputDecoration(labelText: 'Âge déclaré'), keyboardType: TextInputType.number),
      TextField(key: const Key('telephone'), controller: _telephone, decoration: const InputDecoration(labelText: 'Téléphone'), keyboardType: TextInputType.phone),
      TextField(key: const Key('quartier'), controller: _quartier, decoration: const InputDecoration(labelText: 'Quartier')),
      if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erreur!, key: const Key('erreur'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 12),
      FilledButton(key: const Key('creer'), onPressed: _creer, child: const Text('Ouvrir le dossier')),
      const Divider(height: 32),
      Text('Dossiers ouverts depuis ce téléphone', style: Theme.of(context).textTheme.titleMedium),
      FutureBuilder<List<FichePatient>>(
        future: _crees,
        builder: (context, snap) {
          final l = snap.data ?? const <FichePatient>[];
          if (l.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('Aucun pour l’instant.'));
          return Column(children: [for (final p in l) ListTile(key: Key('cree-${p.id}'), dense: true, title: Text(p.nom), subtitle: Text(p.code))]);
        },
      ),
    ]);
  }
}
