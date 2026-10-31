import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';

/// `m10-evaluations` — « Évaluations mensuelles (NS 131) » : l'évaluation du rendement selon les QUATRE critères de la note de service, avec le prélèvement
/// calculé sur le salaire BRUT. Le barème est administrable, mais DERRIÈRE une porte : fermée par défaut, elle s'ouvre depuis « Paramètres système » ; fermée,
/// la modification est ABSENTE (jamais grisée). Une modification demande sa portée : une évaluation déjà prononcée garde le barème sous lequel elle l'a été.
class EcranEvaluations extends StatelessWidget with EcranMaquette {
  const EcranEvaluations({super.key});

  @override
  String? get titre => 'Évaluations mensuelles (NS 131)';

  @override
  String get description =>
      'Évaluation du rendement selon les quatre critères de la note de service, avec calcul automatique du prélèvement sur salaire brut.';

  @override
  String get regle =>
      'Barème de la note $rhbNs131Reference, en vigueur depuis le ${dateFR(DateTime.parse(rhbNs131DateEffet))}. Le prélèvement total s’applique au salaire brut de l’agent.';

  @override
  Widget build(BuildContext context) => RhbEcoute(
      collections: const ['evaluations', 'baremeNS131', 'historiqueBareme', 'personnel', 'planning', 'reglages'], construire: _corps);

  static Widget _corps(BuildContext context, ContexteEcran c) {
    final col = c.magasin.collection('evaluations');
    final evs = col.actives;
    return rhbEspace([
      BlocBareme(contexte: context),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Évaluations enregistrées', valeur: nombre(evs.length), icone: LucideIcons.clipboardCheck, ton: TonSigh.navy),
        KpiSigh(libelle: 'Agents à évaluer', valeur: nombre(rhbActives(c, 'personnel').length), icone: LucideIcons.usersRound, ton: TonSigh.info),
        KpiSigh(
            libelle: 'Avec prélèvement',
            valeur: nombre(evs.where((e) => (e['prelevementPct'] as num? ?? 0) > 0).length),
            icone: LucideIcons.trendingDown,
            ton: TonSigh.danger),
        KpiSigh(
            libelle: 'Montant prélevé',
            valeur: money(evs.fold<num>(0, (s, e) => s + (e['prelevementMontant'] as num? ?? 0))),
            icone: LucideIcons.wallet,
            ton: TonSigh.attention),
      ]),
      _TableEvaluations(contexte: context),
    ]);
  }
}

const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Les périodes proposées : les douze mois de l'année en cours (l'année était écrite en dur dans la maquette, écart E661, levé).
List<String> rhbPeriodesEvaluation(int annee) => [for (final m in _mois) '${_cap(m)} $annee'];

String _periodeDe(DateTime d) => '${_cap(_mois[d.month - 1])} ${d.year}';

/// Le barème en vigueur à [date] (E650 levé) : les critères de la collection versionnée, à défaut la note d'origine.
List<RhbCritere> rhbCriteresDe(ContexteEcran c, String date) =>
    rhbCriteresALaDate(rhbActives(c, 'baremeNS131'), rhbActives(c, 'historiqueBareme'), date);

(String, TonSigh) _niveau(Object? n) => switch (n) {
      'bonne' => ('Bonne', TonSigh.succes),
      'moyenne' => ('Moyenne', TonSigh.attention),
      'faible' => ('Faible', TonSigh.danger),
      _ => ('—', TonSigh.neutre),
    };

// ---------------------------------------------------------------------------------------------------------------------
// Le tableau des évaluations
// ---------------------------------------------------------------------------------------------------------------------

class _TableEvaluations extends StatelessWidget {
  const _TableEvaluations({required this.contexte});
  final BuildContext contexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('evaluations');
    final lignes = [
      for (final e in col.actives) {...e, for (final k in rhbCriteresDe(c, iso(c.aujourdhui))) 'crit_${k.id}': (e['criteres'] as Map?)?[k.id]}
    ];
    return TableauSigh(
      titre: 'Évaluations mensuelles',
      lignes: lignes,
      taillePage: 12,
      triInitial: 'periode',
      sensInitial: 'desc',
      nomExport: 'evaluations',
      selectionnable: true,
      messageVide: 'Aucune évaluation enregistrée.',
      indiceVide: 'Établir une fiche d’évaluation mensuelle pour un agent.',
      actions: [
        if (c.droit.editer)
          BoutonSigh(libelle: 'Nouvelle évaluation', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => ouvrirEvaluation(context, c)),
      ],
      alClicLigne: (e) => _consulter(context, c, e),
      actionsLigne: (ctx, e) => [
        BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer la fiche', onPressed: () => imprimerFiche(ctx, c, e)),
        // « Modifier » : la maquette l'offre à tout profil qui ouvre l'écran ; une commande interdite est ABSENTE (écart E662).
        if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => ouvrirEvaluation(context, c, existante: e)),
      ],
      colonnes: [
        const ColonneTableau(cle: 'periode', libelle: 'Période', sansCoupure: true),
        const ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true),
        const ColonneTableau(cle: 'employe', libelle: 'Agent'),
        const ColonneTableau(cle: 'service', libelle: 'Service'),
        for (final k in rhbCriteresDe(c, iso(c.aujourdhui)))
          ColonneTableau(
              cle: 'crit_${k.id}',
              libelle: k.label.split(' ').first,
              texte: (e) => '${e['crit_${k.id}'] ?? ''}',
              rendu: (_, e) {
                final n = _niveau(e['crit_${k.id}']);
                return BadgeSigh(n.$1, ton: n.$2);
              }),
        ColonneTableau(
            cle: 'prelevementPct',
            libelle: 'Prélèvement',
            droite: true,
            texte: (e) => '${e['prelevementPct']}',
            rendu: (_, e) => (e['prelevementPct'] as num? ?? 0) > 0
                ? Text('− ${e['prelevementPct']} %', style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, fontWeight: FontWeight.w600))
                : const BadgeSigh('Aucun', ton: TonSigh.succes)),
        ColonneTableau(cle: 'prelevementMontant', libelle: 'Montant', droite: true, texte: (e) => money(e['prelevementMontant'] ?? 0, avecDevise: false), rendu: (_, e) => Text(money(e['prelevementMontant'] ?? 0, avecDevise: false))),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Saisie d'une évaluation (modale)
// ---------------------------------------------------------------------------------------------------------------------

void ouvrirEvaluation(BuildContext ctx, ContexteEcran c, {Fiche? existante}) {
  final col = c.magasin.collection('evaluations');
  // Le barème en vigueur à la date de l'évaluation (E650 levé) : celle de la fiche existante, ou le jour de la saisie.
  final dateB = existante != null ? rhbDateBaremeDe(existante) : iso(c.aujourdhui);
  final critsB = rhbCriteresDe(c, dateB);
  final champs = <ChampDef>[
    ChampDef(nom: 'employeId', libelle: 'Agent', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [
      for (final e in rhbPersonnelTrie(c)) OptionChamp('${e['id']}', '${e['matricule']} — ${e['nomComplet']} (${e['poste']})')
    ]),
    ChampDef(nom: 'periode', libelle: 'Période évaluée', type: TypeChamp.select, requis: true, options: [for (final p in rhbPeriodesEvaluation(c.aujourdhui.year)) OptionChamp(p)]),
    const ChampDef.section('Éléments d’évaluation — barème $rhbNs131Reference'),
    for (final k in critsB)
      ChampDef(
          nom: 'crit_${k.id}',
          libelle: '${k.num} — ${k.label}',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          aide: k.criteres.join(' · '),
          options: [
            for (final n in rhbNiveaux) OptionChamp(n.id, '${n.label}${k.sanction(n.id) > 0 ? ' (− ${k.sanction(n.id)} %)' : ' (aucune sanction)'}')
          ]),
    const ChampDef(nom: 'observations', libelle: 'Observations de l’évaluateur', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
  ];
  final initial = <String, Object?>{
    if (existante != null) ...existante else 'periode': _periodeDe(c.aujourdhui),
    for (final k in critsB) 'crit_${k.id}': (existante?['criteres'] as Map?)?[k.id] ?? 'bonne',
  };
  final ctl = ControleurFormulaire(champs, initial);

  Map<String, Object?> criteresDe() => {for (final k in critsB) k.id: '${ctl['crit_${k.id}']}'};
  int prelevementDe(Map<String, Object?> cr) => rhbPrelevementALaDate(cr, rhbActives(c, 'baremeNS131'), rhbActives(c, 'historiqueBareme'), dateB);

  Widget apercu() => ListenableBuilder(
      listenable: ctl,
      builder: (_, __) {
        final emp = rhbActives(c, 'personnel').where((x) => x['id'] == ctl['employeId']).firstOrNull;
        final brut = (emp?['salaireBase'] as num?) ?? 0;
        final pct = prelevementDe(criteresDe());
        final m = rhbMontantPrelevement(brut, pct);
        return KpiGrilleSigh(colonnes: 4, kpis: [
          KpiSigh(libelle: 'Salaire brut de référence', valeur: money(brut), icone: LucideIcons.banknote, ton: TonSigh.navy),
          KpiSigh(libelle: 'Prélèvement total', valeur: '$pct %', icone: LucideIcons.trendingDown, ton: pct > 0 ? TonSigh.danger : TonSigh.succes),
          KpiSigh(libelle: 'Montant prélevé', valeur: money(m), icone: LucideIcons.wallet, ton: pct > 0 ? TonSigh.danger : TonSigh.succes),
          KpiSigh(libelle: 'Salaire brut restant', valeur: money(brut - m), icone: LucideIcons.circleCheck, ton: TonSigh.succes),
        ]);
      });

  afficherModale<void>(ctx,
      titre: existante != null ? 'Modifier l’évaluation' : 'Nouvelle fiche d’évaluation',
      sousTitre: '$rhbNs131Reference — prélèvement calculé automatiquement sur le salaire brut',
      taille: TailleModale.lg,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        FormulaireSigh(controleur: ctl),
        const SizedBox(height: 12),
        apercu(),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: existante != null ? 'Enregistrer' : 'Valider l’évaluation',
                icone: LucideIcons.save,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                    return;
                  }
                  final emp = rhbActives(c, 'personnel').where((x) => x['id'] == v['employeId']).firstOrNull;
                  final criteres = criteresDe();
                  final pct = prelevementDe(criteres);
                  final enr = <String, Object?>{
                    'employeId': v['employeId'],
                    'employe': emp?['nomComplet'] ?? '',
                    'matricule': emp?['matricule'] ?? '',
                    'service': emp?['service'] ?? '',
                    'fonction': emp?['fonction'] ?? '',
                    'categorie': emp?['categorie'] ?? '',
                    'periode': v['periode'],
                    'criteres': criteres,
                    'prelevementPct': pct,
                    'prelevementMontant': emp != null ? rhbMontantPrelevement(emp['salaireBase'], pct) : 0,
                    'salaireBrut': emp?['salaireBase'] ?? 0,
                    'observations': v['observations'] ?? '',
                    'dateBareme': dateB,
                    // `C.nextRef('EV-', 4)` de la maquette repartait de 1 à chaque chargement : « EV-0001 » doublonnait la série « EV-AAAA-NNNN » du jeu.
                    // Corrigé dans la maquette (E663) : la série de l'année, lue sur les fiches EXISTANTES.
                    'reference': existante?['reference'] ?? rhbReferenceSuivante('EV-${c.aujourdhui.year}-', 4, col.toutes),
                    'evaluateur': c.utilisateur,
                  };
                  fermer();
                  VoidCallback annuler;
                  if (existante != null) {
                    annuler = col.mettreAJour(existante['id'], enr);
                  } else {
                    annuler = col.inserer({'statut': 'actif', ...enr}, prefixe: 'EVA').annuler;
                  }
                  ToastsSigh.afficher(ctx, 'Évaluation enregistrée — prélèvement de $pct %.',
                      type: pct > 0 ? TypeToast.attention : TypeToast.succes,
                      detail: pct > 0 ? '${money(enr['prelevementMontant'])} seront retenus sur le salaire brut.' : 'Aucune sanction.',
                      annuler: annuler);
                }),
          ]);
}

// ---------------------------------------------------------------------------------------------------------------------
// Consulter (tiroir) et impressions
// ---------------------------------------------------------------------------------------------------------------------

void _consulter(BuildContext ctx, ContexteEcran c, Fiche e) {
  final pct = (e['prelevementPct'] as num?) ?? 0;
  afficherTiroir<void>(ctx,
      titre: 'Évaluation — ${e['employe']}',
      sousTitre: '${e['periode']} — ${e['reference']}',
      largeurMax: 672,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KpiGrilleSigh(colonnes: 2, kpis: [
          KpiSigh(libelle: 'Prélèvement', valeur: '$pct %', icone: LucideIcons.trendingDown, ton: pct > 0 ? TonSigh.danger : TonSigh.succes),
          KpiSigh(libelle: 'Montant retenu', valeur: money(e['prelevementMontant'] ?? 0), icone: LucideIcons.wallet, ton: pct > 0 ? TonSigh.danger : TonSigh.succes),
        ]),
        const SizedBox(height: 16),
        DescListeSigh([
          ('Agent', e['employe']),
          ('Matricule', e['matricule']),
          ('Service', e['service']),
          ('Catégorie', e['categorie']),
          ('Période', e['periode']),
          ('Évaluateur', e['evaluateur']),
          ('Salaire brut', money(e['salaireBrut'] ?? 0)),
        ]),
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Détail par critère',
            sansRemplissage: true,
            child: MiniTableauSigh(colonnes: [
              ColonneMini('N°', (k) => '${k['num']}'),
              ColonneMini('Élément d’évaluation', (k) => '${k['label']}'),
              ColonneMini('Résultat', (k) => '', rendu: (k) {
                final n = (e['criteres'] as Map?)?[k['id']];
                final t = switch (n) { 'bonne' => ('Bonne', TonSigh.succes), 'moyenne' => ('Moyenne', TonSigh.attention), 'faible' => ('Faible à mauvaise', TonSigh.danger), _ => ('—', TonSigh.neutre) };
                return BadgeSigh(t.$1, ton: t.$2);
              }),
              ColonneMini('Prélèvement', (k) => '', droite: true, rendu: (k) {
                final p = rhbCriteresDe(c, rhbDateBaremeDe(e)).firstWhere((x) => x.id == k['id']).sanction((e['criteres'] as Map?)?[k['id']]);
                return p > 0
                    ? Text('− $p %', style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, fontWeight: FontWeight.w600))
                    : const Text('—');
              }),
            ], lignes: [
              for (final k in rhbCriteresDe(c, rhbDateBaremeDe(e))) {'num': k.num, 'label': k.label, 'id': k.id}
            ])),
        if ('${e['observations'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 16),
          CarteSigh(titre: 'Observations', child: Text('${e['observations']}', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
        ],
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Imprimer la fiche', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => imprimerFiche(ctx, c, e)),
            if (c.droit.editer)
              BoutonSigh(
                  libelle: 'Modifier l’évaluation',
                  icone: LucideIcons.pencil,
                  onPressed: () {
                    fermer();
                    ouvrirEvaluation(ctx, c, existante: e);
                  }),
          ]);
}

/// Reproduction fidèle de la fiche d'évaluation et de solde de la clinique : éléments d'évaluation à gauche, éléments de solde à droite (la pièce A4 les
/// superpose : écart E664).
void imprimerFiche(BuildContext ctx, ContexteEcran c, Fiche e) {
  final emp = rhbActives(c, 'personnel').where((x) => x['id'] == e['employeId']).firstOrNull;
  final a = emp != null ? rhbAnciennete(emp['dateEmbauche'], c.aujourdhui) : (ans: 0, mois: 0);
  final grille = rhbActives(c, 'grillePrimes'), hist = rhbActives(c, 'historiquePrimes'), pl = rhbActives(c, 'planning');
  final f = emp != null ? '${emp['fonction']}' : '';
  final s = rhbSolde(
      salaireBrut: e['salaireBrut'],
      prelevementPct: e['prelevementPct'],
      gardes: emp != null ? rhbCompter(pl, emp['id'], c.aujourdhui.year, c.aujourdhui.month, 'garde') : 0,
      permanences: emp != null ? rhbCompter(pl, emp['id'], c.aujourdhui.year, c.aujourdhui.month, 'permanence') : 0,
      montantGarde: emp != null ? rhbMontantPrime(grille, hist, 'garde', f) : 0,
      montantPermanence: emp != null ? rhbMontantPrime(grille, hist, 'permanence', f) : 0,
      montantAccueil: emp != null ? rhbMontantPrime(grille, hist, 'accueil', f) : 0,
      ans: a.ans);
  String m(num x) => money(x, avecDevise: false);
  final cr = (e['criteres'] as Map?) ?? const {};
  String lib(Object? n) => switch (n) { 'bonne' => 'Bonne', 'moyenne' => 'Moyenne', 'faible' => 'Faible à mauvaise', _ => '' };
  final gauche = [
    for (final k in rhbCriteresDe(c, rhbDateBaremeDe(e)))
      {
        'num': k.num,
        'label': k.label,
        'res': '1) ${lib(cr[k.id])}   2) ${k.sanction(cr[k.id]) > 0 ? '${k.sanction(cr[k.id])} %' : 'Aucune'}   3) ${k.sanction(cr[k.id]) > 0 ? m(arrondiJs(s.brut * k.sanction(cr[k.id]) / 100)) : '0'}',
      }
  ];
  final droite = <Fiche>[
    {'n': '01', 'l': 'SALAIRE DE BASE', 'm': m((e['salaireBrut'] as num?) ?? 0)},
    {'n': '02', 'l': 'PRIME D’ANCIENNETÉ', 'm': a.ans >= 2 ? m(s.primeAnciennete) : ''},
    {'n': '03', 'l': 'PRIME DE GARDE', 'm': s.primeGarde > 0 ? m(s.primeGarde) : ''},
    {'n': '04', 'l': 'PRIME DE PERMANENCE', 'm': s.primePermanence > 0 ? m(s.primePermanence) : ''},
    {'n': '05', 'l': 'PRIME D’ACCUEIL', 'm': s.primeAccueil > 0 ? m(s.primeAccueil) : ''},
    {'n': '', 'l': 'AUTRE PRIME', 'm': ''},
    {'n': '', 'l': 'SALAIRE BRUT', 'm': m(s.brut)},
    {'n': '', 'l': 'SALAIRE BRUT RESTANT', 'm': m(s.brut - s.prelevement)},
  ];
  afficherApercu(
      ctx,
      rhbPiece(c,
          titre: 'Fiche d’évaluation du mois de ${'${e['periode']}'.toUpperCase()}',
          cartouche: [
            ('Nom et prénoms', '${e['employe']}'),
            ('Numéro matricule', '${e['matricule']}'),
            ('Ancienneté', '${a.ans} ans ${a.mois} mois'),
            ('Catégorie / Échelon', '${e['categorie']}'),
            ('Service', '${e['service']}'),
            ('Référence barème', rhbNs131Reference),
          ],
          tableaux: [
            TableauEtat(colonnes: [
              ColonneEtat(libelle: 'N°', valeur: (r) => r['num']),
              ColonneEtat(libelle: 'Éléments d’évaluation', valeur: (r) => r['label']),
              ColonneEtat(libelle: '1) Résultat  2) Sanction  3) Prélèvement', valeur: (r) => r['res']),
            ], lignes: gauche),
          ],
          blocs: [
            BlocTexte('TOTAL À PRÉLEVER : ${m(s.prelevement)}', gras: true),
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'N°', valeur: (r) => r['n']),
              ColonneEtat(libelle: 'Éléments de solde', valeur: (r) => r['l']),
              ColonneEtat(libelle: 'Montant', valeur: (r) => r['m'], droite: true),
            ], lignes: droite)),
          ],
          signatures: [
            Signature('L’Évaluateur', nom: '${e['evaluateur']}'),
            Signature('L’Agent', nom: '${e['employe']}'),
            const Signature('La Directrice Administrative', nom: 'TAKI Alimatou épse BASSONGUI'),
          ]));
}

void imprimerNoteNs131(BuildContext ctx, ContexteEcran c) {
  afficherApercu(
      ctx,
      rhbPiece(c,
          titre: 'Note de service',
          sousTitre: 'N/Réf. : $rhbNs131Reference',
          cartouche: [
            ('Référence', rhbNs131Reference),
            ('Objet', 'Évaluation du rendement'),
            ('Date de signature', dateFR(DateTime.parse(rhbNs131DateSignature))),
            ('Date d’effet', dateFR(DateTime.parse(rhbNs131DateEffet))),
            ('Version', 'v$rhbNs131Version'),
            ('Statut', rhbNs131Statut),
          ],
          blocs: [
            const BlocTexte(
                'Le Directeur Médical de la Clinique NASSIERA TOO informe tous ses Agents qu’il est procédé à la modification de l’évaluation du rendement entrant dans le compte de la rémunération salariale. La nouvelle formule d’évaluation est présentée dans le tableau ci-dessous.'),
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'N°', valeur: (r) => r['num']),
              ColonneEtat(libelle: 'Éléments d’évaluation', valeur: (r) => r['label']),
              ColonneEtat(libelle: 'Critères', valeur: (r) => r['criteres']),
              ColonneEtat(libelle: 'Bonne', valeur: (r) => 'Aucune'),
              ColonneEtat(libelle: 'Moyenne (1er niveau)', valeur: (r) => '1 à 2 — moins ${r['moyenne']} % du salaire brut'),
              ColonneEtat(libelle: 'Faible à mauvaise (2e niveau)', valeur: (r) => '3 et plus — ${r['faible']} % du salaire brut'),
            ], lignes: [
              for (final k in rhbCriteres) {'num': k.num, 'label': k.label, 'criteres': k.criteres.join(' ; '), 'moyenne': k.moyenne, 'faible': k.faible}
            ])),
            const BlocTexte('$rhbNs131Mention Entre en vigueur à compter de sa date de signature.'),
            const BlocTexte('Ampliation : $rhbNs131Ampliation', italique: true),
          ],
          signatures: const [Signature('Le Directeur Médical', nom: rhbNs131Signataire)]));
}

// ---------------------------------------------------------------------------------------------------------------------
// Le barème (administrable derrière la porte)
// ---------------------------------------------------------------------------------------------------------------------

class BlocBareme extends StatelessWidget {
  const BlocBareme({super.key, required this.contexte});
  final BuildContext contexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final ouvert = rhbPorteBaremeOuverte(c);
    final colB = c.magasin.collection('baremeNS131');
    final colH = c.magasin.collection('historiqueBareme');
    final anciennes = colH.actives;
    final modifiable = ouvert && c.droit.editer;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          ouvert
              ? 'Modification autorisée. La porte a été ouverte depuis « Paramètres système ». Chaque changement demandera sa portée — évaluations à venir seulement, ou évaluations déjà prononcées comprises. Penser à refermer la porte après usage.'
              : 'Le barème est consultable. Pour le modifier, ouvrir la porte depuis « Paramètres système », onglet Barème NS 131. Un barème de sanctions ne se retouche pas au détour d’un écran d’évaluation.',
          ton: ouvert ? TonSigh.attention : TonSigh.info,
          icone: ouvert ? LucideIcons.lockOpen : LucideIcons.lock),
      const SizedBox(height: 12),
      TableauSigh(
        titre: 'Barème d’évaluation — $rhbNs131Reference',
        lignes: colB.actives,
        taillePage: 10,
        triInitial: 'num',
        nomExport: 'bareme-ns131',
        selectionnable: true,
        actions: [
          if (modifiable)
            BoutonSigh(libelle: 'Nouveau critère', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _editer(context, c, null)),
          BoutonSigh(libelle: 'Paramètres système', icone: LucideIcons.settings, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => c.aller('cfg-systeme')),
        ],
        actionsLigne: (ctx, b) => [
          if (modifiable) ...[
            BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier ce critère', onPressed: () => _editer(context, c, b)),
            BoutonIcone(icone: LucideIcons.archive, libelle: 'Retirer ce critère', onPressed: () => _retirer(context, c, b)),
          ]
        ],
        colonnes: [
          ColonneTableau(cle: 'num', libelle: 'N°', sansCoupure: true, rendu: (_, b) => Text('${b['num']}', style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12))),
          ColonneTableau(
              cle: 'label',
              libelle: 'Critère',
              texte: (b) => '${b['label']} ${((b['criteres'] as List?) ?? const []).join(' · ')}',
              rendu: (_, b) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('${b['label']}', style: rhbCorps),
                    Text(((b['criteres'] as List?) ?? const []).join(' · '), style: rhbPetit),
                  ])),
          ColonneTableau(cle: 'bonne', libelle: 'Bonne', droite: true, valeur: (b) => (b['sanctions'] as Map?)?['bonne'], texte: (b) => '${(b['sanctions'] as Map?)?['bonne'] ?? 0} %'),
          ColonneTableau(
              cle: 'moyenne',
              libelle: 'Moyenne',
              droite: true,
              valeur: (b) => (b['sanctions'] as Map?)?['moyenne'],
              texte: (b) => '${(b['sanctions'] as Map?)?['moyenne'] ?? 0} %',
              rendu: (_, b) => Text('${(b['sanctions'] as Map?)?['moyenne'] ?? 0} %', style: const TextStyle(color: JetonsShell.warning700, fontSize: 14))),
          ColonneTableau(
              cle: 'faible',
              libelle: 'Faible à mauvaise',
              droite: true,
              valeur: (b) => (b['sanctions'] as Map?)?['faible'],
              texte: (b) => '${(b['sanctions'] as Map?)?['faible'] ?? 0} %',
              rendu: (_, b) => Text('${(b['sanctions'] as Map?)?['faible'] ?? 0} %', style: const TextStyle(color: JetonsShell.danger700, fontSize: 14, fontWeight: FontWeight.w600))),
          ColonneTableau(cle: 'dateEffet', libelle: 'En vigueur depuis', droite: true, sansCoupure: true, texte: (b) => dateFR(DateTime.parse('${b['dateEffet']}')), rendu: (_, b) => Text(dateFR(DateTime.parse('${b['dateEffet']}')), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12))),
        ],
      ),
      if (anciennes.isNotEmpty) ...[
        const SizedBox(height: 12),
        CarteSigh(
            titre: 'Versions antérieures du barème',
            sansRemplissage: true,
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Critère', (v) => '${v['label']}'),
              ColonneMini('En vigueur du', (v) => dateFR(DateTime.parse('${v['dateEffet']}'))),
              ColonneMini('au', (v) => v['dateFin'] != null ? dateFR(DateTime.parse('${v['dateFin']}')) : 'en cours'),
              ColonneMini('Taux', (v) {
                final s = (v['sanctions'] as Map?) ?? const {};
                return 'bonne ${s['bonne'] ?? 0} % · moyenne ${s['moyenne'] ?? 0} % · faible ${s['faible'] ?? 0} %';
              }),
            ], lignes: trierPar(anciennes, (v) => v['dateFin'], descendant: true))),
        const SizedBox(height: 12),
        const NoteSigh(
            'Ces versions ne sont pas décoratives : c’est en elles qu’une évaluation prononcée sous l’ancien barème retrouve le taux qui lui a été appliqué.',
            icone: LucideIcons.history),
      ],
      Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
              alignment: Alignment.centerRight,
              child: BoutonSigh(libelle: 'Imprimer la note', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => imprimerNoteNs131(context, c)))),
    ]);
  }

  static List<String> _criteres(String texte) => [for (final x in texte.split('\n')) if (x.trim().isNotEmpty) x.trim()];

  void _editer(BuildContext ctx, ContexteEcran c, Fiche? b) {
    final colB = c.magasin.collection('baremeNS131');
    final creation = b == null;
    ChampDef pct(String nom, String lib) => ChampDef(
        nom: nom,
        libelle: lib,
        type: TypeChamp.nombre,
        requis: true,
        valider: (v, _) {
          final n = num.tryParse('$v'.replaceAll(',', '.'));
          return n == null || n < 0 || n > 100 ? 'Une valeur entre 0 et 100 est attendue.' : null;
        });
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'num', libelle: 'Numéro', requis: true),
      const ChampDef(nom: 'label', libelle: 'Intitulé du critère', requis: true, col: ColChamp.plein),
      const ChampDef(
          nom: 'criteresTexte',
          libelle: 'Manquements retenus',
          type: TypeChamp.textarea,
          lignes: 3,
          col: ColChamp.plein,
          aide: 'Un manquement par ligne — ils s’affichent sous l’intitulé.'),
      pct('bonne', 'Retenue — Bonne (%)'),
      pct('moyenne', 'Retenue — Moyenne (%)'),
      pct('faible', 'Retenue — Faible à mauvaise (%)'),
    ], creation
        ? {'bonne': '0', 'moyenne': '5', 'faible': '10', 'num': '${colB.actives.length + 1}'.padLeft(2, '0')}
        : {
            'num': b['num'],
            'label': b['label'],
            'criteresTexte': ((b['criteres'] as List?) ?? const []).join('\n'),
            'bonne': '${(b['sanctions'] as Map)['bonne']}',
            'moyenne': '${(b['sanctions'] as Map)['moyenne']}',
            'faible': '${(b['sanctions'] as Map)['faible']}',
          });
    afficherModale<void>(ctx,
        titre: creation ? 'Nouveau critère d’évaluation' : 'Modifier « ${b['label']} »',
        sousTitre: rhbNs131Reference,
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NoteSigh(
              'Ces taux s’appliquent au salaire brut de l’agent. ${creation ? 'Un critère créé hors note de service devra être couvert par un avenant.' : 'La portée de la modification vous sera demandée à l’enregistrement.'}',
              ton: TonSigh.attention,
              icone: LucideIcons.shieldAlert),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: creation ? 'Créer le critère' : 'Enregistrer',
                  icone: creation ? LucideIcons.plus : LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final sanctions = {
                      'bonne': (num.tryParse('${v['bonne']}') ?? 0).toInt(),
                      'moyenne': (num.tryParse('${v['moyenne']}') ?? 0).toInt(),
                      'faible': (num.tryParse('${v['faible']}') ?? 0).toInt(),
                    };
                    final criteres = _criteres('${v['criteresTexte'] ?? ''}');
                    fermer();
                    if (creation) {
                      final id = '${v['label']}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
                      colB.inserer({
                        'statut': 'actif',
                        'critereId': id.length > 20 ? id.substring(0, 20) : id,
                        'num': v['num'],
                        'label': v['label'],
                        'criteres': criteres,
                        'sanctions': sanctions,
                        'dateEffet': iso(c.aujourdhui),
                        'version': 1,
                        'source': 'Créé dans l’application le ${dateFR(c.aujourdhui)} — à couvrir par un avenant',
                      }, prefixe: 'BAR');
                      ToastsSigh.afficher(ctx, 'Critère créé.', type: TypeToast.succes, detail: '${v['label']}');
                      return;
                    }
                    _portee(ctx, c, b, {'num': v['num'], 'label': v['label'], 'criteres': criteres, 'sanctions': sanctions});
                  }),
            ]);
  }

  /// LA PORTÉE — reprise du mécanisme NS 132, non réinventée : deux mécanismes auraient divergé au premier correctif.
  void _portee(BuildContext ctx, ContexteEcran c, Fiche critere, Map<String, Object?> valeurs) {
    final colB = c.magasin.collection('baremeNS131');
    final colH = c.magasin.collection('historiqueBareme');
    final prononcees = c.magasin.collection('evaluations').actives.where((e) => (e['prelevementPct'] as num? ?? 0) > 0).length;
    final avant = (critere['sanctions'] as Map).cast<String, Object?>();
    final apres = (valeurs['sanctions'] as Map).cast<String, Object?>();
    final ecarts = [
      for (final k in ['bonne', 'moyenne', 'faible'])
        if ((avant[k] ?? 0) != (apres[k] ?? 0)) (k, (avant[k] as num? ?? 0).toInt(), (apres[k] as num? ?? 0).toInt())
    ];
    rhbDemanderPortee(ctx,
        sousTitre: '${critere['label']}',
        alerteTitre: 'Cette modification touche des salaires.',
        alerteTexte: '${nombre(prononcees)} évaluation(s) ont déjà donné lieu à une retenue. Les réévaluer changerait des sommes déjà prélevées.',
        tonAlerte: TonSigh.danger,
        tableau: ecarts.isEmpty
            ? null
            : CarteSigh(
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Résultat', (x) => rhbNiveaux.firstWhere((n) => n.id == x['niveau']).label),
                  ColonneMini('Avant', (x) => '${x['avant']} %', droite: true),
                  ColonneMini('Après', (x) => '${x['apres']} %', droite: true),
                  ColonneMini('Écart', (x) => '', droite: true, rendu: (x) {
                    final d = (x['apres'] as int) - (x['avant'] as int);
                    return Text('${d > 0 ? '+' : ''}$d pt', style: TextStyle(color: d > 0 ? JetonsShell.danger700 : JetonsShell.success700, fontSize: 14, fontWeight: FontWeight.w600));
                  }),
                ], lignes: [
                  for (final e in ecarts) {'niveau': e.$1, 'avant': e.$2, 'apres': e.$3}
                ])),
        futur: (
          'Évaluations à venir seulement',
          'La version actuelle est archivée avec sa période de validité ; la nouvelle prend effet le ${dateFR(c.aujourdhui)}. Les retenues déjà prélevées restent justifiables par le barème d’alors.'
        ),
        tout: (
          'Y compris les évaluations déjà prononcées',
          'Le barème est réécrit depuis sa date d’effet d’origine. Les ${nombre(prononcees)} évaluation(s) déjà prononcées seront recalculées à un taux différent de celui qui a été notifié aux agents. À réserver à la correction d’une erreur de saisie.'
        ),
        appliquer: (portee) {
          if (portee == 'futur') {
            colH.inserer({
              'statut': 'actif',
              'critereId': critere['critereId'],
              'num': critere['num'],
              'label': critere['label'],
              'criteres': [...((critere['criteres'] as List?) ?? const [])],
              'sanctions': {...avant},
              'dateEffet': critere['dateEffet'],
              'dateFin': iso(ajouterJours(c.aujourdhui, -1)),
              'remplacePar': 'Version du ${dateFR(c.aujourdhui)}',
              'archivePar': c.utilisateur,
            }, prefixe: 'HBA');
          }
          final annuler = colB.mettreAJour(critere['id'], {
            ...valeurs,
            'dateEffet': portee == 'futur' ? iso(c.aujourdhui) : critere['dateEffet'],
            'version': ((critere['version'] as num?) ?? 1).toInt() + 1,
            'portee': portee,
            'modifieLe': iso(c.aujourdhui),
            'modifiePar': c.utilisateur,
          });
          c.magasin.journaliser('Modification du barème NS 131', 'M10', 'Barème', '${critere['critereId']}', {'sanctions': avant}, {'sanctions': apres, 'portee': portee});
          ToastsSigh.afficher(ctx, 'Barème modifié.',
              type: portee == 'tout' ? TypeToast.attention : TypeToast.succes,
              duree: const Duration(seconds: 8),
              detail: portee == 'tout'
                  ? 'Application RÉTROACTIVE — les évaluations prononcées changeront de retenue.'
                  : 'Applicable à compter du ${dateFR(c.aujourdhui)} ; l’historique est préservé.',
              annuler: annuler);
        });
  }

  void _retirer(BuildContext ctx, ContexteEcran c, Fiche b) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Retirer le critère « ${b['label']} » ?',
        message:
            'Ce critère cesse d’être évalué. Les évaluations déjà prononcées ne changent pas — les versions antérieures du barème restent consultables.\n\nConformément à RG-14, le critère est archivé et non supprimé. Un critère institué par note de service ne peut être retiré que par une note qui l’abroge.',
        libelleOk: 'Retirer le critère',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    c.magasin.collection('historiqueBareme').inserer({
      'statut': 'actif',
      'critereId': b['critereId'],
      'num': b['num'],
      'label': b['label'],
      'criteres': [...((b['criteres'] as List?) ?? const [])],
      'sanctions': {...(b['sanctions'] as Map).cast<String, Object?>()},
      'dateEffet': b['dateEffet'],
      'dateFin': iso(ajouterJours(c.aujourdhui, -1)),
      'remplacePar': 'Critère retiré — $motif',
      'archivePar': c.utilisateur,
    }, prefixe: 'HBA');
    final annuler = c.magasin.collection('baremeNS131').archiver(b['id']);
    ToastsSigh.afficher(ctx, 'Critère retiré du barème.', type: TypeToast.succes, detail: 'Archivage logique (RG-14) — restaurable depuis la corbeille.', annuler: annuler);
  }
}
