import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/qual_qr.dart';
import 'rha_commun.dart';
import 'rhb_commun.dart';
import 'rhc_badge_carte.dart';
import 'rhc_commun.dart';

/// `m10-badges` — « Badges du personnel » : UN badge par agent, sa validité, sa remise, son retrait. Le badge est une PIÈCE IMPRIMÉE rattachée à un agent : sa place est
/// M10, jamais un module nouveau (un module séparé aurait créé une seconde vérité sur l'identité du personnel). Un badge SE RETIRE, il ne se supprime pas (RG-14) : la
/// fiche d'un badge perdu est celle qu'on ressort le jour où quelqu'un se présente avec. Un seul badge valide par agent — l'émission d'une seconde est REFUSÉE en
/// nommant la première. Le QR ne porte que le matricule et le numéro de série. Quatre points restent à arbitrer par la Direction : ils sont MARQUÉS.
class EcranBadges extends StatefulWidget with EcranMaquette {
  const EcranBadges({super.key});

  @override
  String get titre => 'Badges du personnel';
  @override
  String get description => 'Un badge par agent : émission, remise, validité, retrait — et le code de contrôle qui permet de le vérifier.';
  @override
  String get regle =>
      'Un badge se RETIRE, il ne se supprime jamais : la fiche d’un badge perdu est précisément celle qu’on ressort le jour où quelqu’un se présente avec. Le code QR ne porte que le matricule et le numéro de série — ni nom, ni fonction : un badge se photographie dans un couloir, et la vérification doit passer par le logiciel, seul à savoir si le badge est encore valide.';

  @override
  State<EcranBadges> createState() => _EtatBadges();
}

class _EtatBadges extends State<EcranBadges> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    rhcAmorcerModele(ContexteEcran.of(context));
  }

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['badges', 'modelesBadge', 'personnel'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final tous = rhbActives(c, 'badges');
    final actifs = [for (final b in tous) if (rhcEtatBadge(b['etat']).actif) b];
    final retires = [for (final b in tous) if (!rhcEtatBadge(b['etat']).actif) b];
    final expirant = rhcBadgesExpirant(actifs, c.aujourdhui);
    final sansBadge = rhcAgentsSansBadge(rhcPersonnel(c), actifs);
    final aEditer = actifs.where((b) => b['etat'] != 'remis').length;
    return rhbEspace([
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Badges en cours', valeur: nombre(actifs.length), icone: LucideIcons.idCard, ton: TonSigh.navy),
        KpiSigh(libelle: 'Remis à l’agent', valeur: nombre(actifs.where((b) => b['etat'] == 'remis').length), icone: LucideIcons.handCoins, ton: TonSigh.succes),
        KpiSigh(libelle: 'À éditer ou à remettre', valeur: nombre(aEditer), icone: LucideIcons.printer, ton: TonSigh.attention),
        KpiSigh(libelle: 'Expirent sous 60 jours', valeur: nombre(expirant.length), icone: LucideIcons.calendarClock, ton: expirant.isNotEmpty ? TonSigh.attention : TonSigh.neutre),
        KpiSigh(libelle: 'Retirés (perte, départ)', valeur: nombre(retires.length), icone: LucideIcons.archive, ton: TonSigh.neutre),
        KpiSigh(
            libelle: 'Agents sans badge',
            valeur: nombre(sansBadge.length),
            icone: LucideIcons.userX,
            ton: sansBadge.isNotEmpty ? TonSigh.danger : TonSigh.succes,
            indice: 'Effectif rapproché du registre'),
      ]),
      OngletsSigh(onglets: [
        OngletDef(id: 'badges', libelle: 'Badges en cours (${actifs.length})', construire: (ctx) => _tableau(ctx, c, actifs, false)),
        OngletDef(id: 'retires', libelle: 'Retirés (${retires.length})', construire: (ctx) => _tableau(ctx, c, retires, true)),
        OngletDef(id: 'sans', libelle: 'Agents sans badge (${sansBadge.length})', construire: (ctx) => _sansBadge(ctx, c, sansBadge)),
        OngletDef(id: 'decisions', libelle: 'À décider par la Direction', construire: (ctx) => _decisions()),
      ]),
    ]);
  }

  // ------------------------------------------------------------------------------------------------------------------------------------------------------

  Widget _tableau(BuildContext ctx, ContexteEcran c, List<Fiche> rows, bool retire) {
    final lignes = trierPar(rows, (b) => b['numero']).reversed.toList();
    return TableauSigh(
      titre: retire ? 'Badges retirés — conservés, jamais effacés' : 'Badges en cours de validité',
      lignes: lignes,
      taillePage: 12,
      nomExport: 'badges',
      messageVide: retire ? 'Aucun badge retiré.' : 'Aucun badge émis.',
      filtres: [
        FiltreTableau(nom: 'etat', libelle: 'État', options: [for (final e in rhcEtatsBadge) if (e.actif != retire) OptionChamp(e.id, e.label)]),
      ],
      // « Émettre un badge » n'est PAS offert sans le droit d'écrire (commande ABSENTE, jamais grisée).
      actions: [
        if (!retire && c.droit.editer)
          BoutonSigh(libelle: 'Émettre un badge', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _emettre(ctx, c, null)),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'numero',
            libelle: 'N° de série',
            texte: (b) => '${b['numero']}',
            rendu: (_, b) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${b['numero']}', style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
                  Text('Émis le ${rhcDate(b['emisLe'])}', style: rhbPetit),
                ])),
        ColonneTableau(
            cle: 'agent',
            libelle: 'Agent',
            texte: (b) => '${b['agent']}',
            rendu: (_, b) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${b['agent']}', overflow: TextOverflow.ellipsis, style: rhbCorps),
                  Text('${b['poste'] ?? ''} · ${b['service'] ?? ''}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
                ])),
        ColonneTableau(cle: 'matricule', libelle: 'Matricule', texte: (b) => '${b['matricule'] ?? ''}'),
        ColonneTableau(
            cle: 'expireLe',
            libelle: 'Validité',
            texte: (b) => '${b['expireLe'] ?? ''}',
            rendu: (_, b) {
              final e = b['expireLe'];
              if (e == null || e == '') return const BadgeSigh('non fixée', ton: TonSigh.neutre);
              if (rhcExpire(b, c.aujourdhui)) return BadgeSigh('Expiré le ${rhcDate(e)}', ton: TonSigh.danger);
              return Text('jusqu’au ${rhcDate(e)}', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14));
            }),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            texte: (b) => rhcEtatBadge(b['etat']).label,
            rendu: (_, b) {
              final e = rhcEtatBadge(b['etat']);
              final motif = '${b['motifRetrait'] ?? ''}';
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                rhcBadge(e.label, e.ton),
                if (motif.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(motif, style: rhbPetit)),
              ]);
            }),
      ],
      actionsLigne: (ctx2, b) => [
        BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter le badge', onPressed: () => _fiche(ctx, c, b)),
        if (!retire) ...[
          BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer la carte', onPressed: () => _imprimer(ctx, c, b)),
          if (c.droit.editer && b['etat'] != 'remis') BoutonIcone(icone: LucideIcons.handCoins, libelle: 'Marquer remis à l’agent', onPressed: () => _marquerRemis(ctx, c, b)),
          if (c.droit.annuler) BoutonIcone(icone: LucideIcons.ban, libelle: 'Retirer le badge', onPressed: () => _retirer(ctx, c, b)),
        ] else if (c.droit.editer)
          BoutonIcone(icone: LucideIcons.rotateCcw, libelle: 'Émettre un remplacement', onPressed: () => _emettre(ctx, c, '${b['personnelId']}')),
      ],
    );
  }

  Widget _sansBadge(BuildContext ctx, ContexteEcran c, List<Fiche> agents) => TableauSigh(
        titre: 'Agents sans badge en cours',
        lignes: agents,
        taillePage: 10,
        nomExport: 'agents-sans-badge',
        messageVide: 'Tout l’effectif porte un badge.',
        colonnes: const [
          ColonneTableau(cle: 'matricule', libelle: 'Matricule'),
          ColonneTableau(cle: 'nomComplet', libelle: 'Agent'),
          ColonneTableau(cle: 'poste', libelle: 'Poste'),
          ColonneTableau(cle: 'service', libelle: 'Service'),
        ],
        actionsLigne: (_, a) => [
          if (c.droit.editer) BoutonSigh(libelle: 'Émettre', icone: LucideIcons.idCard, taille: TailleBouton.sm, onPressed: () => _emettre(ctx, c, '${a['id']}')),
        ],
      );

  Widget _decisions() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'Quatre points ne sont fixés par aucun document de cadrage. Les écrans fonctionnent avec des valeurs d’attente marquées comme telles : les inventer sans le dire aurait produit des badges dont personne ne saurait justifier la durée.',
            ton: TonSigh.attention,
            icone: LucideIcons.circleHelp),
        const SizedBox(height: 12),
        CarteSigh(
            titre: 'En attente d’un arbitrage de la Direction',
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Point', (d) => '${d['libelle']}'),
              ColonneMini('Valeur d’attente', (d) => '${d['valeur']}'),
              ColonneMini('Pourquoi elle n’est pas arrêtée', (d) => '${d['motif']}'),
            ], lignes: [
              for (final d in rhcDecisionsBadge) {'libelle': d.libelle, 'valeur': d.valeurAffichee, 'motif': d.motif}
            ])),
      ]);

  // ---- Émission ------------------------------------------------------------------------------------------------------------------------------------

  void _emettre(BuildContext ctx, ContexteEcran c, String? personnelId) {
    final modeles = rhbActives(c, 'modelesBadge');
    if (modeles.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucun modèle de badge — en créer un aux « Modèles de badge ».', type: TypeToast.erreur);
      return;
    }
    final col = c.magasin.collection('badges');
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'personnelId', libelle: 'Agent', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: rhaOptionsEmployes(c.magasin)),
      ChampDef(nom: 'modeleId', libelle: 'Modèle de badge', type: TypeChamp.select, requis: true, options: [for (final m in modeles) OptionChamp('${m['id']}', '${m['libelle']}')]),
      const ChampDef(nom: 'emisLe', libelle: 'Date d’émission', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'expireLe', libelle: 'Valable jusqu’au', type: TypeChamp.date, requis: true, aide: 'Proposé à 24 mois — durée d’attente, à arrêter par la Direction.'),
      ChampDef(nom: 'etat', libelle: 'État à l’émission', type: TypeChamp.select, requis: true, options: [for (final e in rhcEtatsBadge) if (e.actif) OptionChamp(e.id, e.label)]),
    ], {
      'personnelId': personnelId ?? '',
      'modeleId': rhcModeleParDefaut(modeles)?['id'],
      'emisLe': iso(c.aujourdhui),
      'expireLe': rhcExpirationDepuis(c.aujourdhui),
      'etat': 'a_editer',
    });
    afficherModale<void>(ctx,
        titre: 'Émettre un badge',
        sousTitre: 'Le numéro de série est attribué automatiquement et ne se modifie pas.',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          // E744 : le poste n'a pas de sélecteur de fichier (E726) — la photographie se COLLE sur la carte imprimée, et la carte le dit (« PHOTO À COLLER »).
          const NoteSigh('La photographie de l’agent n’est pas chargée à l’écran : la carte imprimée porte le cadre « PHOTO À COLLER » (le poste n’a pas encore de sélecteur de fichier).',
              ton: TonSigh.neutre, icone: LucideIcons.image),
          const SizedBox(height: 12),
          const NoteSigh('Le code QR portera le matricule et le numéro de série, rien d’autre. Un QR qui porterait le nom en clair remplacerait un contrôle par une simple lecture.',
              icone: LucideIcons.qrCode),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Émettre le badge',
                  icone: LucideIcons.idCard,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final a = rhaAgentPar(c.magasin, v['personnelId']);
                    if (a == null) {
                      ToastsSigh.afficher(ctx, 'Agent introuvable.', type: TypeToast.erreur);
                      return;
                    }
                    // UN SEUL BADGE EN COURS PAR AGENT : deux cartes valides pour la même personne, c'est une carte qui circule sans que personne ne la réclame.
                    // Le refus NOMME le premier badge.
                    final deja = rhcBadgeEnCours(rhbActives(c, 'badges'), a['id']);
                    if (deja != null) {
                      ToastsSigh.afficher(ctx, 'L’agent porte déjà le badge ${deja['numero']} — le retirer d’abord.',
                          type: TypeToast.erreur, detail: 'Deux badges valides pour un même agent laisseraient une carte circuler sans titulaire.');
                      return;
                    }
                    final etat = '${v['etat']}';
                    final r = col.inserer({
                      'statut': 'actif',
                      'numero': rhcNumeroBadge(col.toutes, v['emisLe'], c.aujourdhui),
                      'personnelId': a['id'],
                      'matricule': a['matricule'],
                      'agent': a['nomComplet'],
                      'poste': a['poste'],
                      'service': a['service'],
                      'modeleId': v['modeleId'],
                      'emisLe': v['emisLe'],
                      'expireLe': v['expireLe'],
                      'etat': etat,
                      if (etat == 'remis') 'remisLe': v['emisLe'],
                      'emisPar': c.utilisateur,
                      '_creePar': c.utilisateur,
                      '_creeLe': c.aujourdhui.toIso8601String(),
                    }, prefixe: 'BDG');
                    fermer();
                    ToastsSigh.afficher(ctx, 'Badge ${r.fiche['numero']} émis.', type: TypeToast.succes, detail: '${a['nomComplet']}', annuler: r.annuler, messageAnnulation: 'Émission annulée.');
                  }),
            ]);
  }

  // ---- Remise, retrait, fiche, impression -----------------------------------------------------------------------------------------------------------

  Future<void> _marquerRemis(BuildContext ctx, ContexteEcran c, Fiche b) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Marquer le badge remis à l’agent ?',
        message: 'Le badge ${b['numero']} sera enregistré comme remis à ${b['agent']} le ${dateFR(c.aujourdhui)}.',
        libelleOk: 'Remis');
    if (!ok || !ctx.mounted) return;
    final annuler = c.magasin.collection('badges').mettreAJour(b['id'], {'etat': 'remis', 'remisLe': iso(c.aujourdhui)});
    ToastsSigh.afficher(ctx, 'Badge remis.', type: TypeToast.succes, annuler: annuler);
  }

  void _retirer(BuildContext ctx, ContexteEcran c, Fiche b) {
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'motifRetrait', libelle: 'Motif du retrait', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: rhaOptions(rhcMotifsRetrait)),
      const ChampDef(nom: 'retireLe', libelle: 'Date', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ], {'retireLe': iso(c.aujourdhui)});
    afficherModale<void>(ctx,
        titre: 'Retirer le badge ${b['numero']}',
        sousTitre: 'Le badge reste au registre : c’est la fiche qu’on ressort si quelqu’un se présente avec.',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          const NoteSigh('Un badge se retire, il ne se supprime pas (RG-14). Il basculera à l’onglet « Retirés » et sera refusé à la vérification, en nommant le motif.',
              ton: TonSigh.attention, icone: LucideIcons.ban),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Retirer le badge',
                  icone: LucideIcons.ban,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final obs = '${v['observation'] ?? ''}';
                    final annuler = c.magasin.collection('badges').mettreAJour(b['id'], {
                      'etat': rhcEtatDeRetrait(v['motifRetrait']),
                      'motifRetrait': v['motifRetrait'],
                      'retireLe': v['retireLe'],
                      if (obs.isNotEmpty) 'observationRetrait': obs,
                      'retirePar': c.utilisateur,
                    });
                    fermer();
                    ToastsSigh.afficher(ctx, 'Badge ${b['numero']} retiré.',
                        type: TypeToast.succes, detail: '${v['motifRetrait']}', annuler: annuler, messageAnnulation: 'Retrait annulé — le badge redevient valide.');
                  }),
            ]);
  }

  void _fiche(BuildContext ctx, ContexteEcran c, Fiche b) {
    final mod = rhcModeleDe(c, b);
    final v = rhcVerdictBadge(b, c.aujourdhui);
    final charge = rhcBadgeQR(b);
    afficherTiroir<void>(ctx,
        titre: '${b['numero']}',
        sousTitre: '${b['agent']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('N° de série', b['numero']),
            ('Agent', b['agent']),
            ('Matricule', b['matricule']),
            ('Poste', b['poste'] ?? '—'),
            ('Service', b['service'] ?? '—'),
            ('Émis le', '${rhcDate(b['emisLe'])} par ${b['emisPar'] ?? '—'}'),
            ('Valable jusqu’au', b['expireLe'] != null && b['expireLe'] != '' ? rhcDate(b['expireLe']) : '—'),
            ('Remis le', b['remisLe'] != null && b['remisLe'] != '' ? rhcDate(b['remisLe']) : 'non remis'),
            ('Modèle', mod.libelle ?? '—'),
            ('État', rhcEtatBadge(b['etat']).label),
            ('Motif du retrait', b['motifRetrait'] ?? '—'),
          ]),
          const SizedBox(height: 12),
          CarteSigh(
              titre: 'Contrôle',
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (rhcQrAcceptable(charge)) QrSigh(charge, taille: 120, marge: 2, libelle: 'Code du badge') else const SizedBox(width: 120, child: Text('Code trop long')),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  rhcBadge(v.label, v.ton),
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(v.message, style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14))),
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(charge, style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, color: JetonsShell.slate400))),
                  const Text('Le code ne porte que le matricule et le numéro de série.', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                ])),
              ])),
        ]),
        pied: (fermer) => [BoutonSigh(libelle: 'Imprimer la carte', icone: LucideIcons.printer, onPressed: () => _imprimer(ctx, c, b))]);
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, Fiche b) =>
      afficherApercuBadge(ctx, c, badge: b, modele: rhcModeleDe(c, b), agent: rhaAgentPar(c.magasin, b['personnelId']));
}

/// `modeleDe(badge)` : le modèle du badge, à défaut le modèle par défaut.
RhcModele rhcModeleDe(ContexteEcran c, Fiche badge) {
  final modeles = rhbActives(c, 'modelesBadge');
  final m = c.magasin.collection('modelesBadge').parId(badge['modeleId']);
  return rhcModeleNormalise(m ?? rhcModeleParDefaut(modeles), modeles);
}

/// `amorcerBadges` (la part qui compte hors jeu de démonstration) : sans modèle, la maquette sème le modèle PROPOSÉ — marqué à valider, jamais présenté
/// comme arrêté. Le jeu de badges de démonstration, lui, vient du jeu du poste.
void rhcAmorcerModele(ContexteEcran c) {
  final col = c.magasin.collection('modelesBadge');
  if (col.toutes.isNotEmpty) return;
  Future.microtask(() {
    if (col.toutes.isNotEmpty) return;
    col.inserer({
      'id': 'MDB001',
      'statut': 'actif',
      'defaut': true,
      'libelle': 'Badge agent — CR80 paysage',
      'format': 'CR80 (85,6 × 54 mm)',
      'orientation': 'paysage',
      'zones': ['photo', 'nom', 'fonction', 'service', 'qr'],
      'mentionsVerso':
          'Ce badge est la propriété de la Clinique NASSIERA TOO SARL.\nIl doit être porté visiblement pendant le service.\nEn cas de perte, prévenir immédiatement la Direction Administrative.\nToute perte est à signaler dans les 24 heures.\nÀ restituer au départ de l’agent.',
      'aValider': true,
      'source': 'Proposition — aucun document de cadrage ne décrit le badge de la clinique. Format CR80 retenu : c’est celui des imprimantes à cartes et des porte-badges du commerce.',
    });
  });
}
