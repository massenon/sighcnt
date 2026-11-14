import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/horssite_poste.dart';
import '../shell/contexte_ecran.dart';
import 'bouton.dart';
import 'carte.dart';
import 'detail.dart';
import 'modale.dart';
import 'toast.dart';
import 'ton.dart';

Widget _noteRefusSauv(RefusSauvegarde r, {Key? key}) => NoteSigh('${r.code} : ${r.motif} ${r.geste}', key: key ?? const Key('horssite:refus'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert);

String _libDest(String d) => switch (d) { 'relais' => 'Relais web', 'dossier' => 'Dossier distant monté', _ => 'Aucune' };

String _quand(Object? ms) => ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal().toString().substring(0, 16) : '—';

/// LA CARTE « SAUVEGARDE HORS SITE » (lot 5, ADR-0007) : l'état de la copie chiffrée du magasin et des fichiers numérisés (relais web ou dossier distant), le réglage, la copie à la demande, le
/// contrôle, la restauration guidée. Les commandes de réglage et de restauration sont ABSENTES sans le droit (administrateur, Directrice Administrative) ; un FILEUL lit le réglage et n'a
/// aucune commande ; l'état et les gestes ne sont montrés que sur le poste mère. La carte dit « non reçu » quand le réglage n'est pas encore arrivé : jamais « désactivée » en silence.
class CarteHorsSite extends StatefulWidget {
  const CarteHorsSite({super.key, required this.role});
  final String role;

  @override
  State<CarteHorsSite> createState() => _EtatCarteHorsSite();
}

class _EtatCarteHorsSite extends State<CarteHorsSite> {
  bool _demande = false;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.maybeOf(context);
    final s = c == null ? null : HorsSitePoste.de(c.magasin);
    if (s == null) return const SizedBox.shrink();
    if (!_demande) {
      _demande = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => s.rafraichir());
    }
    return ListenableBuilder(listenable: s, builder: (context, _) => _corps(context, s));
  }

  (String, Object?) _ligneType(HorsSitePoste s, String type, String libelle) {
    final r = s.reglage.de(type);
    final t = s.etatMere == null ? null : ((s.etatMere!['types'] as Map?)?[type] as Map?);
    final dernier = (t?['dernier'] as Map?);
    final erreur = (t?['erreur'] as Map?);
    final String etat;
    if (r.destination == 'aucune') {
      etat = 'Aucune destination';
    } else if (t == null) {
      etat = _libDest(r.destination);
    } else if (erreur != null) {
      etat = '${_libDest(r.destination)} : EN ERREUR ${erreur['code']}';
    } else if (dernier == null) {
      etat = '${_libDest(r.destination)} : aucune copie faite';
    } else {
      etat = '${_libDest(r.destination)} : dernière copie le ${_quand(dernier['quand'])}, ${dernier['deposes']} bloc(s) déposé(s)${t['enRetard'] == true ? ', EN RETARD' : ''}';
    }
    return (libelle, etat);
  }

  Widget _corps(BuildContext context, HorsSitePoste s) {
    final r = s.reglage;
    final regle = s.peutRegler(widget.role) && !s.estFileul();
    final mere = s.source != null;
    final etat = s.etatMere;
    final controle = (etat?['controle'] as Map?);
    final lignes = <(String, Object?)>[
      ('État', s.reglageRecu ? (r.actif ? 'ACTIVE' : 'Désactivée') : 'Réglage non encore reçu de la poste mère'),
      _ligneType(s, 'magasin', 'Magasin (base de la mère)'),
      _ligneType(s, 'fichiers', 'Fichiers numérisés'),
      ('Fréquence des fichiers', 'toutes les ${r.frequenceMinutes} minutes ; copie et contrôle de nuit après ${r.heureControle} h'),
      if (controle != null && controle['quand'] != null) ('Dernier contrôle', _quand(controle['quand'])),
      ('Conservation', 'Les anciennes copies sont ARCHIVÉES (restaurables) ; elles ne sont purgées que si l\'espace manque, jamais l\'une des copies courantes.'),
    ];
    return CarteSigh(
        key: const Key('horssite:carte'),
        titre: 'Sauvegarde hors site',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh(lignes),
          const SizedBox(height: 8),
          const NoteSigh('Copie chiffrée par la clé de la clinique AVANT de quitter ce poste : le relais ou le dossier distant ne reçoit que des blocs opaques. La clé n\'y est jamais envoyée : sans elle, une copie est irrécupérable (export de la clé, copie papier sous scellé).',
              key: Key('horssite:cle'), ton: TonSigh.info, icone: LucideIcons.keyRound),
          if (s.estFileul()) const Padding(padding: EdgeInsets.only(top: 8), child: NoteSigh('Ce poste lit le réglage de la clinique : il se règle sur le poste mère.', key: Key('horssite:fileul'), icone: LucideIcons.lock)),
          if (!mere && !s.estFileul()) const Padding(padding: EdgeInsets.only(top: 8), child: NoteSigh('L\'état de la copie et ses gestes se lisent sur le poste mère.', key: Key('horssite:sans-mere'), icone: LucideIcons.server)),
          if (s.erreurEtat != null) Padding(padding: const EdgeInsets.only(top: 8), child: _noteRefusSauv(s.erreurEtat!, key: const Key('horssite:erreur-etat'))),
          for (final t in shTypes)
            if (((etat?['types'] as Map?)?[t] as Map?)?['erreur'] != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _noteRefusSauv(RefusSauvegarde('${(((etat!['types'] as Map)[t] as Map)['erreur'] as Map)['code']}', '${(((etat['types'] as Map)[t] as Map)['erreur'] as Map)['motif']}', '${(((etat['types'] as Map)[t] as Map)['erreur'] as Map)['geste']}'),
                      key: Key('horssite:erreur-$t'))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (regle) BoutonSigh(key: const Key('horssite:regler'), libelle: 'Régler la copie hors site', icone: LucideIcons.cloudCog, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _regler(context, s)),
            if (mere && regle && r.actif) ...[
              for (final t in shTypes)
                if (r.de(t).actifPossible)
                  BoutonSigh(
                      key: Key('horssite:copier-$t'),
                      libelle: s.enCours ? 'En cours…' : (t == 'magasin' ? 'Copier le magasin maintenant' : 'Copier les fichiers maintenant'),
                      icone: LucideIcons.cloudUpload,
                      taille: TailleBouton.sm,
                      onPressed: s.enCours ? null : () => _geste(context, s, 'Copie $t', () => s.copierMaintenant(role: widget.role, type: t))),
              BoutonSigh(key: const Key('horssite:controler'), libelle: 'Contrôler les copies', icone: LucideIcons.shieldCheck, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: s.enCours ? null : () => _geste(context, s, 'Contrôle', () => s.controlerMaintenant(role: widget.role))),
            ],
            if (mere && regle) BoutonSigh(key: const Key('horssite:restaurer'), libelle: 'Restaurer une copie', icone: LucideIcons.cloudDownload, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _restaurer(context, s)),
          ]),
        ]));
  }

  Future<void> _geste(BuildContext context, HorsSitePoste s, String nom, Future<RefusSauvegarde?> Function() f) async {
    final refus = await f();
    if (!context.mounted) return;
    if (refus != null) {
      ToastsSigh.afficher(context, '$nom impossible : ${refus.code}', type: TypeToast.erreur, detail: '${refus.motif} ${refus.geste}');
    } else {
      ToastsSigh.afficher(context, '$nom faite.', type: TypeToast.succes);
    }
  }

  Future<void> _regler(BuildContext context, HorsSitePoste s) async {
    final r = s.reglage;
    var actif = r.actif;
    var destM = r.magasin.destination, destF = r.fichiers.destination;
    final dossierM = TextEditingController(text: r.magasin.dossier), dossierF = TextEditingController(text: r.fichiers.dossier);
    final copiesM = TextEditingController(text: '${r.magasin.copies}'), copiesF = TextEditingController(text: '${r.fichiers.copies}');
    final freq = TextEditingController(text: '${r.frequenceMinutes}'), heure = TextEditingController(text: '${r.heureControle}');
    final taille = TextEditingController(text: '${r.tailleBloc}'), blocs = TextEditingController(text: '${r.blocsControles}');
    final motif = TextEditingController();
    final refus = ValueNotifier<RefusSauvegarde?>(null);
    Widget champ(String lib, TextEditingController c, String cle) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(lib, style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)), TextField(key: Key(cle), controller: c)]));
    Widget dest(String lib, String valeur, void Function(String) surChoix, String cle) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(lib, style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)),
          DropdownButton<String>(key: Key(cle), value: valeur, isExpanded: true, items: [for (final d in const ['aucune', 'relais', 'dossier']) DropdownMenuItem(value: d, child: Text(_libDest(d)))], onChanged: (v) => surChoix(v ?? valeur)),
        ]));
    await afficherModale<void>(context,
        titre: 'Régler la sauvegarde hors site',
        taille: TailleModale.md,
        corps: StatefulBuilder(
            builder: (ctx, maj) => ValueListenableBuilder<RefusSauvegarde?>(
                valueListenable: refus,
                builder: (_, x, __) => SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const NoteSigh('Désactivée par défaut. La copie est chiffrée au poste mère ; le relais ne voit que des blocs opaques. SFTP n\'est pas pris en charge : un dossier distant se monte (partage réseau).'),
                  SwitchListTile(key: const Key('horssite:actif'), title: const Text('Copie hors site active'), value: actif, onChanged: (v) => maj(() => actif = v)),
                  dest('Destination du magasin', destM, (v) => maj(() => destM = v), 'horssite:dest-magasin'),
                  if (destM == 'dossier') champ('Dossier distant du magasin (chemin complet)', dossierM, 'horssite:dossier-magasin'),
                  dest('Destination des fichiers numérisés', destF, (v) => maj(() => destF = v), 'horssite:dest-fichiers'),
                  if (destF == 'dossier') champ('Dossier distant des fichiers (chemin complet)', dossierF, 'horssite:dossier-fichiers'),
                  champ('Copies du magasin gardées (2 à 60)', copiesM, 'horssite:copies-magasin'),
                  champ('Copies des fichiers gardées (2 à 60)', copiesF, 'horssite:copies-fichiers'),
                  champ('Fréquence des fichiers (minutes, 15 à 1440)', freq, 'horssite:frequence'),
                  champ('Heure du contrôle de nuit (0 à 23)', heure, 'horssite:heure'),
                  champ('Taille d\'un bloc (octets, 65 536 à 4 194 304)', taille, 'horssite:taille'),
                  champ('Blocs vérifiés chaque nuit (0 à 200)', blocs, 'horssite:blocs'),
                  champ('Motif (consigné dans le journal)', motif, 'horssite:motif'),
                  if (x != null) Padding(padding: const EdgeInsets.only(top: 8), child: _noteRefusSauv(x)),
                ])))),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('horssite:enregistrer'),
                  libelle: 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    int? n(TextEditingController c) => int.tryParse(c.text.trim());
                    final nouveau = ReglageHorsSite(
                        actif: actif,
                        magasin: ReglageType(destination: destM, dossier: dossierM.text.trim(), copies: n(copiesM) ?? -1),
                        fichiers: ReglageType(destination: destF, dossier: dossierF.text.trim(), copies: n(copiesF) ?? -1),
                        frequenceMinutes: n(freq) ?? -1,
                        heureControle: n(heure) ?? -1,
                        tailleBloc: n(taille) ?? -1,
                        blocsControles: n(blocs) ?? -1);
                    final x = s.definirReglage(role: widget.role, nouveau: nouveau, motif: motif.text);
                    if (x != null) {
                      refus.value = x;
                      return;
                    }
                    fermer();
                    if (context.mounted) ToastsSigh.afficher(context, 'Réglage enregistré.', type: TypeToast.succes, detail: 'La mère l\'applique à sa prochaine passe (une minute).');
                  }),
            ]);
  }

  Future<void> _restaurer(BuildContext context, HorsSitePoste s) async {
    var type = 'magasin';
    List<Map<String, Object?>> copies = [];
    String? choisie;
    final cible = TextEditingController();
    final confirmation = TextEditingController();
    final refus = ValueNotifier<RefusSauvegarde?>(null);
    Future<void> charger(void Function(void Function()) maj) async {
      final (liste, x) = await s.copies(role: widget.role, type: type);
      maj(() {
        copies = [for (final c in (liste ?? const <Map<String, Object?>>[])) if (c['etat'] == 'complete' || c['etat'] == 'archivee') c];
        choisie = copies.isEmpty ? null : '${copies.first['id']}';
        refus.value = x;
      });
    }

    await afficherModale<void>(context,
        titre: 'Restaurer une copie hors site',
        taille: TailleModale.md,
        corps: StatefulBuilder(builder: (ctx, maj) {
          if (copies.isEmpty && refus.value == null) charger(maj);
          return ValueListenableBuilder<RefusSauvegarde?>(
              valueListenable: refus,
              builder: (_, x, __) => SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const NoteSigh('La restauration est écrite dans un dossier NEUF, après vérification de CHAQUE bloc (empreinte, authentification, longueur). Un bloc altéré ou manquant est refusé et nommé : rien n\'est restauré à moitié. La base et les fichiers en service ne sont jamais touchés ; le remplacement se fait ensuite, par la procédure de reprise, après votre contrôle.'),
                DropdownButton<String>(
                    key: const Key('horssite:type'), value: type, isExpanded: true, items: const [DropdownMenuItem(value: 'magasin', child: Text('Magasin (base de la mère)')), DropdownMenuItem(value: 'fichiers', child: Text('Fichiers numérisés'))],
                    onChanged: (v) {
                      type = v ?? type;
                      copies = [];
                      refus.value = null;
                      maj(() {});
                    }),
                DropdownButton<String>(
                    key: const Key('horssite:copie'),
                    value: choisie,
                    isExpanded: true,
                    hint: const Text('Aucune copie restaurable'),
                    items: [for (final c in copies) DropdownMenuItem(value: '${c['id']}', child: Text('${_quand(c['date'])} · ${c['etat'] == 'archivee' ? 'archivée' : 'courante'} · ${c['nbBlocs'] ?? c['nb_blocs'] ?? '?'} blocs'))],
                    onChanged: (v) => maj(() => choisie = v)),
                const SizedBox(height: 8),
                const Text('Dossier NEUF de destination (chemin complet)', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                TextField(key: const Key('horssite:cible'), controller: cible),
                const SizedBox(height: 8),
                Text('Pour confirmer, tapez « $type »', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                TextField(key: const Key('horssite:confirmation'), controller: confirmation),
                if (x != null) Padding(padding: const EdgeInsets.only(top: 8), child: _noteRefusSauv(x)),
              ])));
        }),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('horssite:lancer-restauration'),
                  libelle: 'Restaurer',
                  icone: LucideIcons.cloudDownload,
                  onPressed: () async {
                    final (res, x) = await s.restaurer(role: widget.role, type: type, copie: choisie ?? '', cible: cible.text, confirmation: confirmation.text);
                    if (x != null) {
                      refus.value = x;
                      return;
                    }
                    fermer();
                    if (context.mounted) ToastsSigh.afficher(context, 'Copie restaurée et vérifiée.', type: TypeToast.succes, detail: '${res!['elements']} élément(s), ${res['octets']} octet(s) dans ${res['cible']}.');
                  }),
            ]);
  }
}
