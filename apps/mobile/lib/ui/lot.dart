import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/theme.dart';
import '../moteur/moteur_mobile.dart';
import 'commun.dart';
import 'dossier.dart';
import 'formulaire_suite.dart';

/// Le lot de tournée : combien de dossiers, jusqu'à quand il est valide, et ce qui arrive quand il expire. Le compteur « Validité restante » et la note
/// sont ceux de la page du simulateur ; l'état (aucun, valide, expiré), la date d'expiration et « Rafraîchir » s'y ajoutent (E1653) parce qu'un vrai
/// lot expire et s'efface. La date de DÉPÔT n'est pas communiquée par la mère : l'écran le dit.
class EcranLot extends StatefulWidget {
  const EcranLot({super.key, required this.moteur, required this.service});
  final MoteurMobile moteur;
  final ServiceSuite service;

  @override
  State<EcranLot> createState() => _EcranLotState();
}

class _EcranLotState extends State<EcranLot> {
  late Future<(MobLotVue, List<FichePatient>)> _lot = _lire();
  RefusMobile? _refus;

  Future<(MobLotVue, List<FichePatient>)> _lire() async => (await widget.service.lot(), await widget.moteur.tournee());

  Future<void> _rafraichir() async {
    final ext = widget.moteur;
    if (ext is ExtensionsMobile) await (ext as ExtensionsMobile).actualiser();
    if (mounted) {
      setState(() {
        _lot = _lire();
      });
    }
  }

  Widget _compteur(String libelle, String valeur) => Expanded(
        child: Column(children: [
          Text(valeur, key: Key('lot-${libelle.toLowerCase().replaceAll(' ', '-')}'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(libelle),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.service.peut('lot')) return EcranFerme(ecran: 'lot', profil: widget.service.profil);
    return Scaffold(
      appBar: AppBar(title: Text(mobLibelleEcran('lot'))),
      body: FutureBuilder<(MobLotVue, List<FichePatient>)>(
        future: _lot,
        builder: (context, snap) {
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (vue, dossiers) = snap.data!;
          final c = mobLotCompteurs;
          final etat = switch (vue.etat) {
            MobEtatLot.aucun => 'Aucun lot reçu : la mère dépose le lot du jour à la première synchronisation.',
            MobEtatLot.valide => 'Lot valide',
            MobEtatLot.expire => 'Lot expiré : les dossiers vont s’effacer de ce téléphone, sauf ce qui n’est pas encore parti.',
          };
          return ListView(padding: const EdgeInsets.all(16), children: [
            CarteTitre(titre: mobLotCarte, enfants: [
              Row(children: [_compteur(c[0], '${vue.dossiers}'), _compteur(c[1], vue.validite)]),
              const SizedBox(height: 8),
              Text(etat, key: const Key('lot-etat'), style: TextStyle(fontWeight: FontWeight.w600, color: vue.etat == MobEtatLot.valide ? ThemeSigh.succes : ThemeSigh.danger)),
              if (vue.texteExpiration != null) Text(vue.texteExpiration!, key: const Key('lot-expiration')),
              const Text('Date de dépôt : non communiquée par la mère.', key: Key('lot-depot')),
            ]),
            NoteInfo(mobLotNote, ton: ThemeSigh.attentionFond),
            if (_refus != null) CarteRefus(_refus!),
            OutlinedButton.icon(key: const Key('rafraichir-lot'), icon: const Icon(Icons.refresh), label: const Text('Rafraîchir'), onPressed: _rafraichir),
            const SizedBox(height: 12),
            for (final p in dossiers)
              ListTile(
                key: Key('lot-dossier-${p.id}'),
                leading: const Icon(Icons.person_outline),
                title: Text(p.nom.isEmpty ? p.code : p.nom),
                subtitle: Text(p.code),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  try {
                    await ouvrirDossier(context, widget.moteur, p.id);
                  } on RefusMobile catch (r) {
                    setState(() => _refus = r);
                  }
                },
              ),
          ]);
        },
      ),
    );
  }
}
