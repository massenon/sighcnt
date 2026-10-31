import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rha_commun.dart';
import 'rhb_commun.dart';
import 'rhc_commun.dart';

/// L'événement dont on vient « voir les participations » : la maquette passe `{evenement: id}` dans l'adresse (`app.go('m10-participations', {evenement})`), la
/// coque du poste ne porte pas de paramètre de navigation (E746) — l'écran des participations consomme ce message UNE fois, à son ouverture.
String? rhcEvenementCible;

/// `m10-evenements` — « Événements du personnel » : mariages, naissances, décès… Créer un événement ENGENDRE une participation par agent (au montant retenu, 1 000 FCFA par
/// défaut, modifiable) ; le BÉNÉFICIAIRE NE COTISE PAS à son propre événement. Ces sommes TRANSITENT : ni recette de la clinique ni charge. Modifier ne touche que les participations
/// NON RÉGLÉES (ce qui a été encaissé l'a été au montant annoncé sur le reçu). Annuler archive (RG-14), avec un avertissement réglé sur ce qu'il y a réellement à perdre.
class EcranEvenements extends StatelessWidget with EcranMaquette {
  const EcranEvenements({super.key});

  @override
  String get titre => 'Événements du personnel';
  @override
  String get description => 'Mariages, naissances, décès et autres événements donnant lieu à une participation du personnel.';
  @override
  String get regle =>
      'Créer un événement engendre une participation par agent, au montant retenu pour cet événement — 1 000 FCFA par défaut, modifiable. Le bénéficiaire ne cotise pas à son propre événement. Ces sommes transitent : elles ne sont ni une recette de la clinique ni une charge.';

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['evenements', 'participations', 'personnel'], construire: _corps);

  static List<Fiche> participationsDe(ContexteEcran c, Object? evenementId) => [for (final x in rhbActives(c, 'participations')) if (x['evenementId'] == evenementId) x];

  Widget _corps(BuildContext context, ContexteEcran c) {
    final evts = rhbActives(c, 'evenements');
    final bilans = [for (final e in evts) rhcBilanEvenement(participationsDe(c, e['id']))];
    final attendu = bilans.fold<num>(0, (s, b) => s + b.attendu), collecte = bilans.fold<num>(0, (s, b) => s + b.collecte);
    final nouvel = c.droit.editer ? BoutonSigh(libelle: 'Nouvel événement', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _creer(context, c)) : null;
    return rhbEspace([
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Événements enregistrés', valeur: nombre(evts.length), icone: LucideIcons.calendarHeart, ton: TonSigh.navy),
        KpiSigh(libelle: 'Participations attendues', valeur: nombre(bilans.fold<int>(0, (s, b) => s + b.attendus)), icone: LucideIcons.users, ton: TonSigh.info),
        KpiSigh(libelle: 'Montant collecté', valeur: money(collecte), icone: LucideIcons.handCoins, ton: TonSigh.succes, indice: 'sur ${money(attendu)} attendus'),
        KpiSigh(libelle: 'Reste à collecter', valeur: money(attendu - collecte), icone: LucideIcons.clock, ton: attendu > collecte ? TonSigh.attention : TonSigh.succes),
      ]),
      if (evts.isEmpty)
        CarteSigh(
            titre: 'Événements du personnel',
            actions: [if (nouvel != null) nouvel],
            child: const VideSigh('Aucun événement enregistré.', icone: LucideIcons.calendarHeart, indice: 'Créer un événement engendre automatiquement une participation par agent.'))
      else ...[
        TableauSigh(
          titre: 'Événements',
          lignes: [
            for (final (i, e) in evts.indexed)
              {
                ...e,
                'natureLabel': rhcNatureEvenement(e['nature']),
                'attendu': bilans[i].attendu,
                'collecte': bilans[i].collecte,
                'taux': bilans[i].taux,
                'regles': bilans[i].regles,
                'attendus': bilans[i].attendus,
              }
          ],
          taillePage: 15,
          triInitial: 'date',
          sensInitial: 'desc',
          nomExport: 'evenements-personnel',
          actions: [if (nouvel != null) nouvel],
          filtres: [FiltreTableau(nom: 'nature', libelle: 'Nature', options: [for (final n in rhcNaturesEvenement) OptionChamp(n.id, n.label)])],
          colonnes: [
            ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (e) => rhcDate(e['date'])),
            ColonneTableau(
                cle: 'libelle',
                libelle: 'Événement',
                texte: (e) => '${e['libelle']}',
                rendu: (_, e) => rhcDeuxLignes('${e['libelle']}', '${e['beneficiaire'] ?? '—'}')),
            ColonneTableau(
                cle: 'nature',
                libelle: 'Nature',
                texte: (e) => '${e['natureLabel']}',
                rendu: (_, e) => rhcBadge('${e['natureLabel']}', rhcNaturesEvenement.where((n) => n.id == e['nature']).map((n) => n.ton).firstOrNull ?? 'neutral')),
            ColonneTableau(cle: 'montantParAgent', libelle: 'Par agent', droite: true, texte: (e) => rhcMontant(e['montantParAgent'])),
            ColonneTableau(
                cle: 'periodePaiement',
                libelle: 'Période de paiement',
                sansCoupure: true,
                texte: (e) => rhcMois(e['periodePaiement'])),
            ColonneTableau(
                cle: 'taux',
                libelle: 'Collecte',
                droite: true,
                texte: (e) => '${e['taux']}',
                rendu: (_, e) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                      Text('${e['taux']} %',
                          style: TextStyle(color: (e['taux'] as num) >= 100 ? JetonsShell.success700 : JetonsShell.warning700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                      Text('${rhcMontant(e['collecte'])} / ${rhcMontant(e['attendu'])}', style: rhbPetit),
                    ])),
          ],
          actionsLigne: (ctx, e) => [
            BoutonIcone(
                icone: LucideIcons.users,
                libelle: 'Voir les participations',
                onPressed: () {
                  rhcEvenementCible = '${e['id']}';
                  c.aller('m10-participations');
                }),
            BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer la liste de collecte', onPressed: () => _imprimerCollecte(context, c, e)),
            if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier l’événement', onPressed: () => _modifier(context, c, e)),
            if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Annuler l’événement', onPressed: () => _annuler(context, c, e)),
          ],
        ),
        _lectureGraphique(evts, bilans),
      ],
      rhcSource('$rhcSourceEvenements — montant standard ${rhcMontant(rhcMontantStandard)} par agent.'),
    ]);
  }

  Widget _lectureGraphique(List<Fiche> evts, List<RhcBilan> bilans) {
    final parNature = rhcGrouper(evts, (e) => rhcNatureEvenement(e['nature']));
    final parMois = rhcGrouper(evts, (e) => '${e['date']}'.substring(0, 7));
    final mois = parMois.keys.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      rhbDeuxCartes([
        CarteSigh(titre: 'Événements par nature', child: GraphiqueAnneau(trou: 0, etiquettes: parNature.keys.toList(), valeurs: [for (final l in parNature.values) l.length])),
        CarteSigh(
            titre: 'Montant collecté par événement',
            child: GraphiqueBarres(horizontal: true, empile: true, etiquettes: [
              for (final e in evts) '${e['libelle']}'
            ], series: [
              SerieGraphique('Collecté', [for (final b in bilans) b.collecte], couleur: rhbTonVert),
              SerieGraphique('Reste dû', [for (final b in bilans) b.reste], couleur: rhbTonOrange),
            ])),
      ]),
      if (mois.length > 1) ...[
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Événements au fil des mois',
            child: GraphiqueLigne(
                hauteur: 240,
                etiquettes: [for (final m in mois) rhcMois(m)],
                series: [SerieGraphique('Événements', [for (final m in mois) parMois[m]!.length], couleur: rhbTonNavy)])),
      ],
    ]);
  }

  // ---- Saisie -------------------------------------------------------------------------------------------------------------------------------------

  List<ChampDef> _champs(Magasin m) => [
        ChampDef(nom: 'nature', libelle: 'Nature de l’événement', type: TypeChamp.select, requis: true, options: [for (final n in rhcNaturesEvenement) OptionChamp(n.id, n.label)]),
        const ChampDef(nom: 'libelle', libelle: 'Intitulé de l’événement', requis: true, col: ColChamp.plein, aide: 'Par exemple « Mariage de KORA Salifou » ou « Décès du père de TEPA Séraphine »'),
        ChampDef(
            nom: 'beneficiaireId',
            libelle: 'Agent bénéficiaire',
            type: TypeChamp.select,
            requis: true,
            options: rhaOptionsEmployes(m),
            col: ColChamp.plein,
            aide: 'Celui que l’événement concerne. Il ne cotise pas à son propre événement.'),
        const ChampDef(
            nom: 'portee',
            libelle: 'Qui participe ?',
            type: TypeChamp.select,
            requis: true,
            options: [OptionChamp('tous', 'Tout le personnel, hors bénéficiaire'), OptionChamp('selection', 'Une sélection d’agents')],
            aide: 'Par défaut tout le personnel cotise ; la sélection sert aux événements de service.'),
        ChampDef(
            nom: 'participants',
            libelle: 'Agents participants',
            type: TypeChamp.multiselect,
            col: ColChamp.plein,
            options: rhaOptionsEmployes(m),
            aide: 'À renseigner seulement si la participation ne concerne pas tout le personnel.'),
        const ChampDef(nom: 'date', libelle: 'Date de l’événement', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'montantParAgent', libelle: 'Participation par agent (FCFA)', type: TypeChamp.nombre, requis: true, aide: 'Standard : 1 000 FCFA. Modifiable pour cet événement.'),
        ChampDef(
            nom: 'periodePaiement',
            libelle: 'Période de paiement',
            indicatif: 'AAAA-MM',
            requis: true,
            aide: 'Mois sur lequel la retenue est portée, pour les agents qui choisissent l’imputation sur salaire.',
            valider: (v, _) => RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch('$v'.trim()) ? null : 'Mois attendu au format AAAA-MM.'),
        ChampDef(
            nom: 'modeParDefaut',
            libelle: 'Mode de règlement par défaut',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in rhcModesReglement) OptionChamp(x.id, x.label)],
            aide: 'Chaque agent pourra en changer individuellement.'),
        const ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ];

  void _creer(BuildContext ctx, ContexteEcran c) {
    final ctl = ControleurFormulaire(_champs(c.magasin), {
      'montantParAgent': '$rhcMontantStandard',
      'date': iso(c.aujourdhui),
      'periodePaiement': iso(c.aujourdhui).substring(0, 7),
      'modeParDefaut': 'salaire',
      'portee': 'tous',
    });
    afficherModale<void>(ctx,
        titre: 'Nouvel événement du personnel',
        sousTitre: 'Une participation sera engendrée pour chaque agent, hors bénéficiaire.',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NoteSigh(
              'À l’enregistrement, une participation est créée pour chacun des ${nombre(rhcPersonnel(c).length - 1)} autres agents. Chacun pourra ensuite régler au comptant ou par imputation sur son salaire. Ces sommes transitent par la clinique : elles ne sont ni une recette ni une charge.',
              icone: LucideIcons.users),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Créer et engendrer les participations',
                  icone: LucideIcons.plus,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final evts = c.magasin.collection('evenements'), parts = c.magasin.collection('participations');
                    final ben = rhaAgentPar(c.magasin, v['beneficiaireId']);
                    final montant = rhcMontantParAgent(v['montantParAgent']);
                    final res = evts.inserer({
                      'statut': 'actif',
                      'nature': v['nature'],
                      'libelle': v['libelle'],
                      'beneficiaireId': v['beneficiaireId'],
                      'portee': v['portee'],
                      'participants': v['participants'] ?? const [],
                      'date': v['date'],
                      'montantParAgent': montant,
                      'periodePaiement': v['periodePaiement'],
                      'modeParDefaut': v['modeParDefaut'],
                      'observation': v['observation'] ?? '',
                      if (ben != null) 'beneficiaire': ben['nomComplet'],
                      // La série SUIT le registre (E743 — `C.nextRef` repartait de 1 à chaque session : EVT-0001 existait déjà).
                      'reference': rhbReferenceSuivante('EVT-', 4, evts.toutes),
                      '_creePar': c.utilisateur,
                      '_creeLe': c.aujourdhui.toIso8601String(),
                    }, prefixe: 'EVT');
                    final engendrees = [
                      for (final p in rhcParticipationsAEngendrer(res.fiche, rhcPersonnel(c))) parts.inserer({'statut': 'actif', ...p}, prefixe: 'PAR').fiche['id']
                    ];
                    c.magasin.journaliser('Création d’un événement du personnel', 'M10', 'Événement', '${res.fiche['id']}', null, {'libelle': v['libelle'], 'participations': engendrees.length});
                    fermer();
                    ToastsSigh.afficher(ctx, 'Événement créé.',
                        type: TypeToast.succes,
                        detail: '${nombre(engendrees.length)} participation(s) engendrée(s) — ${money(montant * engendrees.length)} attendus.',
                        annuler: () {
                          for (final id in engendrees) {
                            parts.archiver(id);
                          }
                          res.annuler();
                        },
                        messageAnnulation: 'Événement annulé — les participations sont archivées.');
                  }),
            ]);
  }

  void _modifier(BuildContext ctx, ContexteEcran c, Fiche evt) {
    final b = rhcBilanEvenement(participationsDe(c, evt['id']));
    final ctl = ControleurFormulaire(_champs(c.magasin), rhcEnTexte(evt));
    afficherModale<void>(ctx,
        titre: 'Modifier « ${evt['libelle']} »',
        sousTitre: '${evt['reference']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (b.regles > 0) ...[
            NoteSigh(
                '${nombre(b.regles)} participation(s) sont déjà réglées pour cet événement. Changer le montant ne modifiera que les participations encore dues : ce qui a été encaissé l’a été au montant annoncé, et le réécrire fausserait les reçus déjà remis.',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert),
            const SizedBox(height: 12),
          ],
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
                    final ben = rhaAgentPar(c.magasin, v['beneficiaireId']);
                    final montant = rhcMontantParAgent(v['montantParAgent'], evt['montantParAgent']);
                    final fiche = <String, Object?>{
                      'nature': v['nature'],
                      'libelle': v['libelle'],
                      'beneficiaireId': v['beneficiaireId'],
                      'portee': v['portee'],
                      'participants': v['participants'] ?? const [],
                      'date': v['date'],
                      'montantParAgent': montant,
                      'periodePaiement': v['periodePaiement'],
                      'modeParDefaut': v['modeParDefaut'],
                      'observation': v['observation'] ?? '',
                      if (ben != null) 'beneficiaire': ben['nomComplet'],
                    };
                    c.magasin.collection('evenements').mettreAJour(evt['id'], fiche);
                    // SEULES les participations non réglées suivent le nouveau montant.
                    final correctifs = rhcCorrectifsParticipations(participationsDe(c, evt['id']), fiche);
                    for (final e in correctifs.entries) {
                      c.magasin.collection('participations').mettreAJour(e.key, e.value);
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Événement modifié.',
                        type: TypeToast.succes,
                        detail: '${nombre(correctifs.length)} participation(s) non réglée(s) mise(s) à jour ; ${nombre(b.regles)} déjà encaissée(s) laissée(s) intacte(s).');
                  }),
            ]);
  }

  Future<void> _annuler(BuildContext ctx, ContexteEcran c, Fiche evt) async {
    final b = rhcBilanEvenement(participationsDe(c, evt['id']));
    // Le message se règle sur ce qu'il y a réellement à perdre : trois situations, trois avertissements — et aucune alarme pour rien.
    final String message;
    if (b.attendus == 0) {
      message =
          'Aucune participation n’a encore été engendrée pour cet événement : l’annulation n’a donc aucune conséquence financière. Conformément à RG-14, l’événement est archivé et non supprimé — il reste consultable et restaurable.';
    } else if (b.regles == 0) {
      message =
          '${nombre(b.attendus)} participation(s) ont été engendrées, aucune n’a encore été réglée. L’annulation les archive toutes : rien n’a été encaissé, rien n’est à restituer. Conformément à RG-14, rien n’est supprimé : tout reste consultable et restaurable.';
    } else {
      message =
          'Attention. ${nombre(b.regles)} participation(s) sur ${nombre(b.attendus)} ont déjà été réglées, pour ${money(b.collecte)}. L’annulation archive l’événement et ses participations non réglées ; les sommes déjà encaissées restent tracées et devront être restituées hors application. Conformément à RG-14, rien n’est supprimé : tout reste consultable et restaurable.';
    }
    final motif = await confirmerAvecMotif(ctx, titre: 'Annuler l’événement « ${evt['libelle']} » ?', message: message, libelleOk: 'Annuler l’événement', dangereux: b.regles > 0);
    if (motif == null || !ctx.mounted) return;
    final parts = c.magasin.collection('participations');
    final annulations = <VoidCallback>[];
    for (final x in participationsDe(c, evt['id'])) {
      if (x['statutPaiement'] == 'paye') continue;
      annulations.add(parts.archiver(x['id']));
      rhcMotifArchivage(c, 'Participation', '${x['id']}', motif);
    }
    annulations.add(c.magasin.collection('evenements').archiver(evt['id']));
    rhcMotifArchivage(c, 'Événement', '${evt['reference'] ?? evt['id']}', motif);
    ToastsSigh.afficher(ctx, 'Événement annulé.',
        type: TypeToast.succes,
        detail: '${nombre(annulations.length - 1)} participation(s) non réglée(s) archivée(s).',
        // L'annulation restitue l'événement ET ses participations (E743 : la maquette ne restaurait que l'événement).
        annuler: () {
          for (final u in annulations) {
            u();
          }
        });
  }

  void _imprimerCollecte(BuildContext ctx, ContexteEcran c, Fiche evt) {
    final parts = trierPar(participationsDe(c, evt['id']), (x) => x['agent']);
    final b = rhcBilanEvenement(parts);
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Liste de collecte — participation du personnel',
            sousTitre: '${evt['libelle']}',
            cartouche: [
              ('Événement', '${evt['libelle']}'),
              ('Nature', rhcNatureEvenement(evt['nature'])),
              ('Date', rhcDate(evt['date'])),
              ('Bénéficiaire', '${evt['beneficiaire'] ?? '—'}'),
              ('Participation par agent', money(evt['montantParAgent'])),
              ('Total attendu', money(b.attendu)),
              ('Déjà collecté', money(b.collecte)),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Matricule', valeur: (x) => x['matricule']),
                ColonneEtat(libelle: 'Agent', valeur: (x) => x['agent']),
                ColonneEtat(libelle: 'Montant', valeur: (x) => rhcMontant(x['montant']), droite: true, somme: (x) => nombreOuZero(x['montant'])),
                ColonneEtat(libelle: 'Mode', valeur: (x) => rhcModeCourt(x['mode'])),
                // Le pied de cette colonne porte ce qui est DÉJÀ COLLECTÉ, refait depuis les lignes imprimées : la liste de collecte sert à retrouver qui reste à voir.
                ColonneEtat(
                    libelle: 'Réglé',
                    valeur: (x) => x['statutPaiement'] == 'paye' ? 'Oui — ${'${x['datePaiement'] ?? ''}'.isEmpty ? '' : rhcDate(x['datePaiement'])}' : 'Non',
                    somme: (x) => x['statutPaiement'] == 'paye' ? nombreOuZero(x['montant']) : 0),
                ColonneEtat(libelle: 'Émargement', valeur: (_) => ''),
              ], lignes: parts)),
              const BlocTexte(
                  'Les participations aux événements du personnel transitent par la clinique pour le compte du collectif. Elles ne constituent ni une recette de l’établissement ni une charge, et ne figurent à ce titre ni au chiffre d’affaires ni en comptabilité.',
                  italique: true),
            ],
            signatures: const [Signature('Le Caissier'), rhbSignDaf]));
  }
}
