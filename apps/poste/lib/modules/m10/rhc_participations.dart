import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';
import 'rhc_commun.dart';
import 'rhc_evenements.dart';

/// `m10-participations` — « Frais de participation » : le registre agent par agent. Deux modes de règlement, au choix de l'agent : IMPUTATION SUR SALAIRE (la retenue figure
/// au bulletin du mois de paiement) ou PAIEMENT AU COMPTANT (avec reçu). Une participation déjà réglée ne se modifie plus : elle s'ANNULE, et l'annulation est tracée (RG-12) et
/// exige son motif. Ces sommes TRANSITENT : ni recette ni charge.
///
/// E742 — le jeu de démonstration de la maquette sème les participations sous une AUTRE forme (`agentId`, `regle`, `dateReglement`) que celle que l'écran lit (`employeId`,
/// `statutPaiement`, `datePaiement`) : 387 participations « Dues », zéro réglée, sans fonction ni service. Porté fidèlement, signalé ; l'écran fonctionne dès que les fiches
/// sont écrites sous sa forme (c'est celle que l'écran des événements engendre).
class EcranParticipations extends StatefulWidget with EcranMaquette {
  const EcranParticipations({super.key});

  @override
  String get titre => 'Frais de participation';
  @override
  String get description => 'Participations dues par chaque agent : mode de règlement, encaissement au comptant et retenue sur salaire.';
  @override
  String get regle =>
      'Deux modes de règlement, au choix de l’agent : imputation sur salaire — la retenue figure au bulletin du mois de paiement — ou paiement au comptant, avec reçu. Une participation déjà réglée ne se modifie plus : elle s’annule, et l’annulation est tracée (RG-12).';

  @override
  State<EcranParticipations> createState() => _EtatParticipations();
}

class _EtatParticipations extends State<EcranParticipations> {
  RhbFiltre? _evenement, _mode, _etat;
  List<RhbFiltre> get _tous => [_evenement!, _mode!, _etat!];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_evenement != null) return;
    final c = ContexteEcran.of(context);
    _evenement = RhbFiltre(ChampDef(nom: 'evenement', libelle: 'Événement', type: TypeChamp.select, options: [
      const OptionChamp('', 'Tous les événements'),
      for (final e in rhbActives(c, 'evenements')) OptionChamp('${e['id']}', '${e['libelle']} — ${rhcDate(e['date'])}'),
    ]));
    _mode = RhbFiltre(ChampDef(nom: 'mode', libelle: 'Mode de règlement', type: TypeChamp.select, options: [
      const OptionChamp('', 'Tous les modes'),
      for (final m in rhcModesReglement) OptionChamp(m.id, m.label),
    ]));
    _etat = RhbFiltre(const ChampDef(nom: 'etat', libelle: 'État', type: TypeChamp.select, options: [
      OptionChamp('', 'Tous les états'),
      OptionChamp('du', 'Non réglée'),
      OptionChamp('paye', 'Réglée'),
    ]));
    // Lien profond depuis l'écran des événements : la sélection se lit à l'ouverture, UNE fois.
    final cible = rhcEvenementCible;
    rhcEvenementCible = null;
    if (cible != null && _evenement!.def.options.any((o) => o.valeur == cible)) _evenement!.poser(cible);
    for (final f in _tous) {
      f.controleur.addListener(_maj);
    }
  }

  @override
  void dispose() {
    for (final f in _tous) {
      f.controleur.removeListener(_maj);
    }
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  List<Fiche> _lignes(ContexteEcran c) => [
        for (final x in rhbActives(c, 'participations'))
          if ((_evenement!.valeur.isEmpty || x['evenementId'] == _evenement!.valeur) &&
              (_mode!.valeur.isEmpty || x['mode'] == _mode!.valeur) &&
              (_etat!.valeur.isEmpty || x['statutPaiement'] == _etat!.valeur))
            x
      ];

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['participations', 'evenements', 'personnel'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final rows = _lignes(c);
    final payees = [for (final x in rows) if (x['statutPaiement'] == 'paye') x];
    final surSalaire = [for (final x in rows) if (x['mode'] == 'salaire' && x['statutPaiement'] != 'paye') x];
    final total = rhcSomme(rows, 'montant'), encaisse = rhcSomme(payees, 'montant');
    return rhbEspace([
      rhbBarre(_tous, colonnes: 4, boutons: [
        BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _imprimer(context, c)),
      ]),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Participations', valeur: nombre(rows.length), icone: LucideIcons.handCoins, ton: TonSigh.navy, indice: '${money(total)} attendus'),
        KpiSigh(libelle: 'Réglées', valeur: nombre(payees.length), icone: LucideIcons.circleCheckBig, ton: TonSigh.succes, indice: '${money(encaisse)} encaissés'),
        KpiSigh(libelle: 'À retenir sur salaire', valeur: nombre(surSalaire.length), icone: LucideIcons.wallet, ton: TonSigh.attention, indice: '${money(rhcSomme(surSalaire, 'montant'))} portés aux bulletins'),
        KpiSigh(libelle: 'Reste dû', valeur: money(total - encaisse), icone: LucideIcons.clock, ton: rows.length == payees.length ? TonSigh.succes : TonSigh.danger),
      ]),
      if (rows.isEmpty)
        const CarteSigh(
            titre: 'Participations',
            child: VideSigh('Aucune participation pour ces critères.',
                icone: LucideIcons.handCoins, indice: 'Les participations naissent de la création d’un événement, à l’écran « Événements du personnel ».'))
      else ...[
        TableauSigh(
          titre: 'Registre des participations',
          lignes: rows,
          taillePage: 20,
          triInitial: 'agent',
          nomExport: 'participations',
          colonnes: [
            ColonneTableau(
                cle: 'agent',
                libelle: 'Agent',
                texte: (x) => '${x['agent']}',
                rendu: (_, x) => rhcDeuxLignes('${x['agent']}', '${'${x['matricule'] ?? ''}'.isEmpty ? '—' : x['matricule']} · ${_vrai(x['fonction']) ? rhbFonctionLabel(x['fonction']) : '—'}')),
            const ColonneTableau(cle: 'evenementLibelle', libelle: 'Événement'),
            ColonneTableau(cle: 'montant', libelle: 'Montant', droite: true, texte: (x) => rhcMontant(x['montant'])),
            ColonneTableau(
                cle: 'mode',
                libelle: 'Mode de règlement',
                texte: (x) => rhcModeCourt(x['mode']),
                rendu: (_, x) => x['mode'] == 'salaire'
                    ? BadgeSigh('Sur salaire — ${'${x['periodeRetenue'] ?? ''}'.isNotEmpty ? rhcMois(x['periodeRetenue']) : '?'}', ton: TonSigh.navy)
                    : const BadgeSigh('Au comptant', ton: TonSigh.info)),
            ColonneTableau(
                cle: 'statutPaiement',
                libelle: 'État',
                droite: true,
                texte: (x) => x['statutPaiement'] == 'paye' ? 'réglée' : 'due',
                rendu: (_, x) {
                  if (x['statutPaiement'] != 'paye') return const BadgeSigh('Due', ton: TonSigh.attention);
                  final detail = '${'${x['datePaiement'] ?? ''}'.isEmpty ? '' : rhcDate(x['datePaiement'])}${_vrai(x['recu']) ? ' · ${x['recu']}' : ''}';
                  return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    const BadgeSigh('Réglée', ton: TonSigh.succes),
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, style: rhbPetit)),
                  ]);
                }),
          ],
          actionsLigne: (ctx, x) {
            if (x['statutPaiement'] == 'paye') {
              return [
                BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer le reçu', onPressed: () => _imprimerRecu(context, c, x)),
                if (c.droit.annuler) BoutonIcone(icone: LucideIcons.rotateCcw, libelle: 'Annuler le règlement', onPressed: () => _annulerReglement(context, c, x)),
              ];
            }
            return [
              if (c.droit.editer) ...[
                BoutonIcone(icone: LucideIcons.repeat, libelle: 'Changer de mode de règlement', onPressed: () => _changerMode(context, c, x)),
                if (x['mode'] == 'comptant')
                  BoutonIcone(icone: LucideIcons.banknote, libelle: 'Encaisser au comptant', onPressed: () => _encaisser(context, c, x))
                else
                  BoutonIcone(icone: LucideIcons.check, libelle: 'Confirmer la retenue sur salaire', onPressed: () => _confirmerRetenue(context, c, x)),
              ],
            ];
          },
        ),
        _graphiques(rows, payees),
      ],
    ]);
  }

  static bool _vrai(Object? v) => v != null && v != '' && v != false && v != 0;

  Widget _graphiques(List<Fiche> rows, List<Fiche> payees) {
    final parMode = rhcGrouper(rows, (x) => '${x['mode']}');
    final parService = rhcGrouper(rows, (x) => _vrai(x['service']) ? '${x['service']}' : 'Non renseigné');
    return rhbTroisCartes([
      CarteSigh(
          titre: 'Modes de règlement',
          child: GraphiqueAnneau(
              etiquettes: [for (final k in parMode.keys) k == 'salaire' ? 'Sur salaire' : 'Au comptant'],
              valeurs: [for (final l in parMode.values) l.length],
              couleurs: const [rhbTonNavy, Color(0xFF6C9ED4)])),
      CarteSigh(
          titre: 'État du recouvrement',
          child: GraphiqueAnneau(etiquettes: const ['Réglées', 'Dues'], valeurs: [payees.length, rows.length - payees.length], couleurs: const [rhbTonVert, rhbTonOrange])),
      CarteSigh(
          titre: 'Participations par service',
          child: GraphiqueBarres(
              horizontal: true,
              hauteur: 260,
              etiquettes: parService.keys.toList(),
              series: [SerieGraphique('Agents', [for (final l in parService.values) l.length], couleur: rhbTonNavy)])),
    ]);
  }

  // ---- Gestes ------------------------------------------------------------------------------------------------------------------------------------

  void _changerMode(BuildContext ctx, ContexteEcran c, Fiche x) {
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'mode', libelle: 'Mode de règlement', type: TypeChamp.select, requis: true, options: [for (final m in rhcModesReglement) OptionChamp(m.id, m.label)]),
      ChampDef(
          nom: 'periodeRetenue',
          libelle: 'Mois de retenue',
          indicatif: 'AAAA-MM',
          aide: 'Utile seulement pour l’imputation sur salaire.',
          valider: (v, _) => '$v'.trim().isEmpty || RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch('$v'.trim()) ? null : 'Mois attendu au format AAAA-MM.'),
    ], {'mode': x['mode'], 'periodeRetenue': x['periodeRetenue'] ?? ''});
    afficherModale<void>(ctx,
        titre: 'Mode de règlement',
        sousTitre: '${x['agent']} — ${x['evenementLibelle']}',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NoteSigh(
              'L’imputation sur salaire porte ${rhcMontant(x['montant'])} en retenue au bulletin du mois choisi. Le paiement au comptant attend un versement à la caisse et donne lieu à un reçu.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final mois = '${v['periodeRetenue'] ?? ''}'.trim();
                    final salaire = v['mode'] == 'salaire';
                    // Au comptant, la période de retenue n'a plus de sens ; sur salaire sans mois saisi, l'ancienne est gardée.
                    c.magasin.collection('participations').mettreAJour(x['id'], {
                      'mode': v['mode'],
                      'periodeRetenue': salaire ? (mois.isNotEmpty ? mois : x['periodeRetenue']) : null,
                    });
                    fermer();
                    ToastsSigh.afficher(ctx, 'Mode de règlement modifié.',
                        type: TypeToast.succes,
                        detail: salaire ? 'Retenue portée au bulletin de ${mois.isNotEmpty ? rhcMois(mois) : 'la période choisie'}.' : 'Versement attendu à la caisse.');
                  }),
            ]);
  }

  void _encaisser(BuildContext ctx, ContexteEcran c, Fiche x) {
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'montantVerse', libelle: 'Montant versé (FCFA)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'datePaiement', libelle: 'Date du versement', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'observation', libelle: 'Observation', col: ColChamp.plein),
    ], {'montantVerse': '${x['montant']}', 'datePaiement': iso(c.aujourdhui)});
    afficherModale<void>(ctx,
        titre: 'Encaisser la participation',
        sousTitre: '${x['agent']} — ${x['evenementLibelle']}',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          DescListeSigh([('Agent', x['agent']), ('Matricule', x['matricule'] ?? '—'), ('Événement', x['evenementLibelle']), ('Montant dû', money(x['montant']))]),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Valider l’encaissement',
                  icone: LucideIcons.banknote,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final col = c.magasin.collection('participations');
                    // Le reçu SUIT la série du registre (E743 — `C.nextRef` repartait de 1 à chaque session : REC-PART-0001 pouvait déjà exister).
                    final recu = rhbReferenceSuivante('REC-PART-', 4, [for (final p in col.toutes) {'reference': p['recu']}]);
                    final verse = nombreOuZero(v['montantVerse']);
                    final obs = '${v['observation'] ?? ''}';
                    final annuler = col.mettreAJour(x['id'], {
                      'statutPaiement': 'paye',
                      'mode': 'comptant',
                      'montantVerse': verse == verse.roundToDouble() ? verse.toInt() : verse,
                      'datePaiement': v['datePaiement'],
                      'recu': recu,
                      'encaissePar': c.utilisateur,
                      if (obs.isNotEmpty) 'observation': obs,
                    });
                    c.magasin.journaliser('Encaissement d’une participation', 'M10', 'Participation', '${x['id']}', {'statut': 'du'}, {'statut': 'paye', 'recu': recu});
                    fermer();
                    ToastsSigh.afficher(ctx, 'Participation encaissée.', type: TypeToast.succes, detail: 'Reçu $recu — ${money(verse)}', annuler: annuler);
                  }),
            ]);
  }

  Future<void> _confirmerRetenue(BuildContext ctx, ContexteEcran c, Fiche x) async {
    final mois = '${x['periodeRetenue'] ?? ''}'.isNotEmpty ? rhcMois(x['periodeRetenue']) : 'la période retenue';
    final ok = await confirmerSigh(ctx,
        titre: 'Confirmer la retenue sur salaire ?',
        message:
            'La participation de ${money(x['montant'])} due par ${x['agent']} est portée en retenue sur le bulletin de $mois. Confirmer signifie que la retenue a bien été opérée sur la paie du mois. L’opération reste annulable et journalisée (RG-12).',
        libelleOk: 'Confirmer la retenue');
    if (!ok || !ctx.mounted) return;
    final annuler = c.magasin.collection('participations').mettreAJour(x['id'], {
      'statutPaiement': 'paye',
      'datePaiement': iso(c.aujourdhui),
      'recu': 'Retenue sur salaire — ${x['periodeRetenue'] ?? ''}',
      'encaissePar': c.utilisateur,
    });
    ToastsSigh.afficher(ctx, 'Retenue confirmée.', type: TypeToast.succes, detail: '${x['agent']} — ${money(x['montant'])}', annuler: annuler);
  }

  Future<void> _annulerReglement(BuildContext ctx, ContexteEcran c, Fiche x) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Annuler le règlement ?',
        message:
            'Le règlement de ${money(x['montant'])} par ${x['agent']}${_vrai(x['recu']) ? ' (reçu ${x['recu']})' : ''} est annulé et la participation redevient due. Si des espèces ont été encaissées, leur restitution se fait hors application. L’annulation est journalisée (RG-12).',
        libelleOk: 'Annuler le règlement',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    // Le règlement annulé ne laisse AUCUNE trace de paiement sur la fiche, hormis le motif et l'auteur de l'annulation.
    c.magasin.collection('participations').mettreAJour(x['id'], {
      'statutPaiement': 'du',
      'datePaiement': null,
      'recu': null,
      'montantVerse': null,
      'motifAnnulation': motif,
      'annulePar': c.utilisateur,
    });
    c.magasin.journaliser('Annulation d’un règlement de participation', 'M10', 'Participation', '${x['id']}', {'statut': 'paye'}, {'statut': 'du', 'motif': motif});
    ToastsSigh.afficher(ctx, 'Règlement annulé.', type: TypeToast.attention, detail: 'La participation redevient due.');
  }

  // ---- Pièces imprimées ------------------------------------------------------------------------------------------------------------------------

  void _imprimerRecu(BuildContext ctx, ContexteEcran c, Fiche x) {
    final verse = _vrai(x['montantVerse']) ? x['montantVerse'] : x['montant'];
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Reçu de participation',
            sousTitre: '${x['evenementLibelle']}',
            cartouche: [
              ('Reçu n°', '${_vrai(x['recu']) ? x['recu'] : '—'}'),
              ('Agent', '${x['agent']}'),
              ('Matricule', '${x['matricule'] ?? '—'}'),
              ('Événement', '${x['evenementLibelle']}'),
              ('Date du versement', '${x['datePaiement'] ?? ''}'.isNotEmpty ? rhcDate(x['datePaiement']) : '—'),
              ('Encaissé par', '${_vrai(x['encaissePar']) ? x['encaissePar'] : '—'}'),
            ],
            blocs: [
              rhcBlocRubriques([('Participation due', rhcMontant(x['montant'])), ('MONTANT VERSÉ', rhcMontant(verse))], col2: 'Montant'),
              BlocTexte('Arrêté le présent reçu à la somme de ${montantEnLettres(verse)}.'),
              const BlocTexte(
                  'Participation du personnel à un événement. Cette somme transite par la clinique pour le compte du collectif : elle ne constitue ni une recette de l’établissement ni une charge.',
                  italique: true),
            ],
            signatures: [Signature('L’Agent', nom: '${x['agent']}', mention: 'Versé'), Signature('Le Caissier', nom: _vrai(x['encaissePar']) ? '${x['encaissePar']}' : null)]));
  }

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final rows = trierPar(_lignes(c), (x) => x['agent']);
    final payees = [for (final x in rows) if (x['statutPaiement'] == 'paye') x];
    final libEvt = _evenement!.valeur.isEmpty ? 'Tous les événements' : _evenement!.def.options.firstWhere((o) => o.valeur == _evenement!.valeur).libelle;
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'État des participations du personnel',
            sousTitre: libEvt,
            cartouche: [
              ('Participations', nombre(rows.length)),
              ('Réglées', nombre(payees.length)),
              ('Montant attendu', money(rhcSomme(rows, 'montant'))),
              ('Montant encaissé', money(rhcSomme(payees, 'montant'))),
              ('Établi par', c.utilisateur),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Matricule', valeur: (x) => x['matricule']),
                ColonneEtat(libelle: 'Agent', valeur: (x) => x['agent']),
                ColonneEtat(libelle: 'Événement', valeur: (x) => x['evenementLibelle']),
                ColonneEtat(libelle: 'Montant', valeur: (x) => rhcMontant(x['montant']), droite: true, somme: (x) => nombreOuZero(x['montant'])),
                ColonneEtat(libelle: 'Mode', valeur: (x) => rhcModeCourt(x['mode'])),
                // Le pied porte le montant ENCAISSÉ, refait depuis les lignes.
                ColonneEtat(libelle: 'État', valeur: (x) => x['statutPaiement'] == 'paye' ? 'Réglée' : 'Due', somme: (x) => x['statutPaiement'] == 'paye' ? nombreOuZero(x['montant']) : 0),
                ColonneEtat(libelle: 'Reçu', valeur: (x) => x['recu'] ?? ''),
              ], lignes: rows)),
            ],
            signatures: const [Signature('Le Caissier'), rhbSignDaf]));
  }
}

/// Un état « Rubrique / valeur » à deux colonnes, valeurs alignées à droite.
BlocPiece rhcBlocRubriques(List<(String, String)> l, {String col2 = 'Valeur'}) => BlocTableau(TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
      ColonneEtat(libelle: col2, valeur: (x) => x['v'], droite: true),
    ], lignes: [
      for (final x in l) {'k': x.$1, 'v': x.$2}
    ]));
