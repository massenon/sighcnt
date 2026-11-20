import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/parametres_clinique_poste.dart';
import '../../donnees/tiers_poste.dart';
import '../../impression/apercu.dart';
import '../../impression/identite_poste.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m9/commun.dart' show ecoute;
import 'commun.dart';

/// Le service de la facture à un tiers payeur pour l'agent de la session : les droits sont les GESTES RÉSERVÉS de la fiche RBAC (jamais un nom de rôle).
TiersPoste tiersDe(ContexteEcran c) => TiersPoste(c.magasin,
    auteur: () => acteur(c).nom,
    libelleRole: c.donnees?.matrice.libelle(c.role) ?? c.role,
    droit: (g) => c.donnees?.matrice.droitGeste(c.role, g) ?? false,
    horloge: () => c.aujourdhui);

void _refus(BuildContext ctx, Map<String, Object?> r) =>
    ToastsSigh.afficher(ctx, '${r['code']} : ${r['motif']}', type: TypeToast.erreur, detail: '${r['geste'] ?? ''}', duree: const Duration(seconds: 12));

String _nomTiers(TiersPoste t, String code, String date) => (t.aLaDate(code, date) ?? (t.versions(code).isEmpty ? null : t.versions(code).last))?['nom']?.toString() ?? code;

/// Le BLOC DES CRÉANCES SUR LES TIERS PAYEURS (balance âgée aux tranches des paramètres de clinique) : l'onglet « Créances » de cet écran et le pied de « Créances » de l'assurance.
Widget blocCreancesTiers(ContexteEcran c) {
  final t = tiersDe(c);
  final tr = tranchesCreancesPoste(c.magasin, c.aujourdhui);
  final du = t.creances(isoJour(c.aujourdhui), tr);
  final lib = pcLibellesTranches(tr);
  final lignes = (du['lignes'] as List).cast<Map<String, Object?>>();
  return Column(key: const Key('tiers:creances'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const NoteSigh(
        'Créance sur un tiers payeur = montant dû (base + AIB) moins les lettrages. Les tranches de la balance âgée sont celles des paramètres de clinique. Une échéance sans délai convenu est non calculable (ce n’est pas zéro).',
        icone: LucideIcons.hourglass),
    const SizedBox(height: 12),
    TableauSigh(
      titre: 'Créances sur les tiers payeurs',
      lignes: lignes,
      taillePage: 15,
      nomExport: 'creances-tiers-payeurs',
      messageVide: 'Aucune créance sur un tiers payeur.',
      colonnes: [
        ColonneTableau(cle: 'nom', libelle: 'Tiers payeur', texte: (r) => '${r['nom']}', rendu: (_, r) => Text('${r['nom']}  ${r['code']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        const ColonneTableau(cle: 'factures', libelle: 'Factures', droite: true),
        ColonneTableau(cle: 'facture', libelle: 'Facturé', droite: true, texte: (r) => m(r['facture'])),
        ColonneTableau(cle: 'moins30', libelle: lib.moins30, droite: true, texte: (r) => m(r['moins30'])),
        ColonneTableau(cle: 'de30a90', libelle: lib.de30a90, droite: true, texte: (r) => m(r['de30a90'])),
        ColonneTableau(cle: 'plus90', libelle: lib.plus90, droite: true, texte: (r) => m(r['plus90'])),
        ColonneTableau(cle: 'du', libelle: 'Total dû', droite: true, texte: (r) => m(r['du']), rendu: (_, r) => Text(m(r['du']), style: const TextStyle(fontWeight: FontWeight.w600, color: JetonsShell.warning700))),
        ColonneTableau(
            cle: 'enRetard',
            libelle: 'Échu',
            droite: true,
            texte: (r) => (r['echeanceIncalculable'] as int) > 0 ? '${m(r['enRetard'])} + non calculable ${m(r['echeanceIncalculable'])}' : m(r['enRetard'])),
      ],
    ),
    if ((du['nonLettre'] as int) > 0) ...[
      const SizedBox(height: 12),
      NoteSigh('${m(du['nonLettre'])} de règlements reçus ne sont pas lettrés : ils ne diminuent aucune créance tant qu’ils ne sont pas affectés à une facture.',
          ton: TonSigh.attention, icone: LucideIcons.link),
    ],
  ]);
}

PieceA4 pieceFactureTiers(Fiche f, Fiche? version, {required String utilisateur, required DateTime edite, required String reference, IdentiteImprimee? identite}) {
  final lignes = [for (final l in (f['lignes'] as List)) (l as Map).cast<String, Object?>()];
  final delai = f['delaiPaiementJours'];
  return PieceA4(
    identite: identite,
    titre: 'FACTURE À UN TIERS PAYEUR',
    sousTitre: '${f['numero']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('N° facture', '${f['numero']}'),
      ('Date', dateDe(f['date'])),
      ('Acheteur', '${f['nomAcheteur']}'),
      ('IFU de l’acheteur', '${f['ifuAcheteur']}'),
      ('Adresse', '${version?['adresse'] ?? f['tiersAdresse'] ?? 'Non renseignée'}'),
      ('Patient pris en charge', '${f['patientNom'] ?? 'Non renseigné'}'),
      ('Numéro MECeF', '${f['numeroMecef'] ?? 'Non transmise'}'),
      ('Conditions', '${version?['conditions'] ?? (delai != null ? 'Paiement à $delai jours' : 'Non renseignées')}'),
    ],
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Facture du patient', valeur: (l) => l['factureNumero']),
        ColonneEtat(libelle: 'Prestation', valeur: (l) => l['designation']),
        ColonneEtat(libelle: 'Montant pris en charge', valeur: (l) => m(l['montant']), droite: true, somme: (l) => n(l['montant'])),
      ], lignes: lignes)),
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Décomposition', valeur: (l) => l['libelle']),
        ColonneEtat(libelle: 'Montant', valeur: (l) => m(l['valeur']), droite: true),
      ], lignes: [
        {'libelle': 'Montant hors taxes', 'valeur': f['ht']},
        {'libelle': 'TVA', 'valeur': f['tva']},
        {'libelle': 'Total de la facture', 'valeur': f['base']},
        {'libelle': 'AIB${n(f['aibTaux']) > 0 ? ' (${f['aibTaux']} %)' : ''}', 'valeur': f['aibMontant'] ?? 0},
        {'libelle': 'Net à payer', 'valeur': f['net']},
      ])),
      BlocTexte('La part restante du patient (${m(f['partPatientRestante'] ?? 0)}) est facturée séparément à la caisse.', italique: true),
    ],
    signatures: const [Signature('Le Comptable'), Signature('La Directrice de l’Administration et des Finances')],
  );
}

Future<void> imprimerFactureTiers(BuildContext ctx, Fiche f) {
  final c = ContexteEcran.of(ctx);
  final v = tiersDe(c).colTiers.parId(f['tiersVersionId']);
  return afficherApercu(
      ctx,
      pieceFactureTiers(f, v,
          utilisateur: acteur(c).nom,
          edite: c.aujourdhui,
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          identite: identiteImprimeeDe(c.magasin, datePiece(f, c.aujourdhui))));
}

/// `m8-factures-tiers` — « Factures aux tiers payeurs » : la vente normalisée DISTINCTE de la facture du patient (entreprise, assureur ou convention qui prend un patient en charge).
/// Aucune règle ici : tout vit dans `TiersPoste` et le domaine ; les commandes d'écriture sont ABSENTES sans le geste réservé, et le moteur refuse aussi.
class EcranFacturesTiers extends StatelessWidget with EcranMaquette {
  const EcranFacturesTiers({super.key});

  @override
  String get titre => 'Factures aux tiers payeurs';

  @override
  String get description =>
      'Facture à l’entreprise, à l’assureur ou à la convention qui prend un patient en charge : pièce propre, IFU et nom de l’acheteur, AIB décidé par le comptable, règlements reçus et lettrage.';

  @override
  String get regle =>
      'Cette facture est distincte de la facture du patient : elle se rattache à des lignes de prestations prises en charge, la part restante du patient se facture séparément à la caisse. L’IFU (13 chiffres) et le nom de l’acheteur sont obligatoires et contrôlés avant toute écriture. Le logiciel propose le taux de l’AIB, le comptable décide. Une pièce émise ne se réécrit jamais : elle se corrige par un avoir.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, ['tiersPayeurs', 'facturesTiers', 'avoirsTiers', 'reglementsTiers', 'lettragesTiers']),
      builder: (context, _) {
        final t = tiersDe(c);
        final auj = isoJour(c.aujourdhui);
        final fs = t.colFactures.actives.toList();
        final du = t.creances(auj, tranchesCreancesPoste(c.magasin, c.aujourdhui));
        final regs = t.colReglements.actives.toList()..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
        final lets = t.colLettrages.actives.toList()..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Tiers payeurs', valeur: nombre(t.codes().length), icone: LucideIcons.building2, ton: TonSigh.navy),
            KpiSigh(libelle: 'Factures émises', valeur: nombre(fs.where((f) => f['statut'] == 'emise').length), icone: LucideIcons.receipt, ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Brouillons à décider ou émettre',
                valeur: nombre(fs.where((f) => f['statut'] == 'brouillon').length),
                icone: LucideIcons.filePen,
                ton: fs.any((f) => f['statut'] == 'brouillon') ? TonSigh.attention : TonSigh.neutre),
            KpiSigh(
                libelle: 'Créance sur les tiers',
                valeur: m(du['total']),
                icone: LucideIcons.hourglass,
                ton: (du['total'] as int) > 0 ? TonSigh.attention : TonSigh.neutre,
                indice: (du['nonLettre'] as int) > 0 ? '${m(du['nonLettre'])} de règlements non lettrés' : 'Montant dû moins les lettrages'),
          ]),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(id: 'factures', libelle: 'Factures', construire: (_) => _ongletFactures(context, c, t, fs, auj)),
            OngletDef(id: 'tiers', libelle: 'Tiers payeurs', construire: (_) => _ongletTiers(context, c, t, auj)),
            OngletDef(id: 'reglements', libelle: 'Règlements et lettrage', construire: (_) => _ongletReglements(context, c, t, regs, lets, auj)),
            OngletDef(id: 'creances', libelle: 'Créances', construire: (_) => blocCreancesTiers(c)),
          ]),
        ]);
      },
    );
  }

  // ---------------------------------------------------------------- Factures
  String _libAib(Fiche f) {
    final d = f['aibDecision'];
    if (f['statut'] == 'brouillon') {
      return d is Map ? (d['appliquer'] == true ? 'À émettre : ${d['taux']} %' : 'À émettre : non appliqué') : 'À décider';
    }
    return n(f['aibTaux']) > 0 ? '${f['aibTaux']} %' : 'Non appliqué';
  }

  Widget _badgeMecef(TiersPoste t, Fiche f) {
    if (f['statut'] == 'brouillon') return const BadgeSigh('Brouillon', ton: TonSigh.attention);
    if (t.avoirDe(f['id']) != null) return const BadgeSigh('Annulée par avoir', ton: TonSigh.neutre);
    final s = f['statutMecef'];
    if (s == 'sans_objet') return const BadgeSigh('Sans normalisation (mode désactivé)', ton: TonSigh.neutre);
    final e = etatMecefDe(f);
    return e == null ? const BadgeSigh('Non transmise', ton: TonSigh.attention) : BadgeSigh(e.libelle, ton: TonSigh.attention);
  }

  Widget _ongletFactures(BuildContext ctx, ContexteEcran c, TiersPoste t, List<Fiche> fs, String auj) {
    final lignes = [...fs]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return TableauSigh(
      titre: 'Factures aux tiers payeurs',
      lignes: lignes,
      taillePage: 15,
      nomExport: 'factures-tiers-payeurs',
      messageVide: 'Aucune facture à un tiers payeur.',
      alClicLigne: (f) => _consulter(ctx, c, f),
      colonnes: [
        ColonneTableau(cle: 'numero', libelle: 'N° facture', sansCoupure: true, texte: (f) => '${f['numero'] ?? 'Brouillon'}'),
        ColonneTableau(cle: 'date', libelle: 'Date', texte: (f) => dateDe(f['date'])),
        ColonneTableau(cle: 'tiersNom', libelle: 'Tiers payeur', texte: (f) => '${f['tiersNom']} ${f['ifuAcheteur']}'),
        ColonneTableau(cle: 'patientNom', libelle: 'Patient', texte: (f) => '${f['patientNom'] ?? 'Non renseigné'}'),
        ColonneTableau(cle: 'base', libelle: 'Base', droite: true, texte: (f) => m(f['base'])),
        ColonneTableau(cle: 'aib', libelle: 'AIB', texte: _libAib),
        ColonneTableau(cle: 'net', libelle: 'Net à payer', droite: true, texte: (f) => f['statut'] == 'emise' ? m(f['net']) : 'Non calculable'),
        ColonneTableau(cle: 'creance', libelle: 'Reste dû', droite: true, texte: (f) => f['statut'] == 'emise' ? m(t.creance(f)) : 'Non calculable'),
        ColonneTableau(cle: 'mecef', libelle: 'MECeF', texte: (f) => '${f['statut']}', rendu: (_, f) => _badgeMecef(t, f)),
      ],
      actionsLigne: (x, f) => [
        BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _consulter(x, c, f)),
        if (f['statut'] == 'emise') BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer la facture (A4)', onPressed: () => imprimerFactureTiers(x, f)),
        if (f['statut'] == 'brouillon' && t.peutDeciderAib) BoutonIcone(icone: LucideIcons.scale, libelle: 'Décider de l’AIB', onPressed: () => _decider(x, c, t, f)),
        if (f['statut'] == 'brouillon' && t.peutEmettre) BoutonIcone(icone: LucideIcons.send, libelle: 'Émettre la facture', onPressed: () => _emettre(x, t, f)),
        if (f['statut'] == 'brouillon' && t.peutEmettre) BoutonIcone(icone: LucideIcons.archive, libelle: 'Abandonner le brouillon', onPressed: () => _motif(x, 'Abandonner le brouillon', 'Le brouillon est archivé avec son motif (RG-14) ; les lignes redeviennent facturables.', (mo) => t.abandonner(f['id'], mo))),
        if (f['statut'] == 'emise' && t.avoirDe(f['id']) == null && t.peutCorriger)
          BoutonIcone(icone: LucideIcons.fileMinus2, libelle: 'Émettre un avoir', onPressed: () => _motif(x, 'Avoir total de ${f['numero']}', 'Une pièce émise ne se réécrit jamais : un avoir total annule la facture (${m(f['net'])}).', (mo) => t.avoir(f['id'], mo))),
      ],
      actions: [
        if (t.peutEmettre)
          BoutonSigh(key: const Key('tiers:nouvelle'), libelle: 'Nouvelle facture à un tiers payeur', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _nouvelle(ctx, c, t)),
      ],
    );
  }

  void _consulter(BuildContext ctx, ContexteEcran c, Fiche f) {
    final d = f['aibDecision'];
    afficherTiroir<void>(ctx,
        titre: '${f['numero'] ?? 'Brouillon'} · ${f['tiersNom']}',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MiniTableauSigh(colonnes: [
            ColonneMini('Prestation du patient', (l) => '${l['designation']}'),
            ColonneMini('Facture du patient', (l) => '${l['factureNumero']}'),
            ColonneMini('Pris en charge par le tiers', (l) => m(l['montant']), droite: true),
          ], lignes: [for (final l in (f['lignes'] as List)) (l as Map).cast<String, Object?>()]),
          const SizedBox(height: 12),
          Text('Acheteur : ${f['nomAcheteur']} (IFU ${f['ifuAcheteur']})'),
          Text('Base : ${m(f['base'])}${f['statut'] == 'emise' ? ' · AIB ${m(f['aibMontant'] ?? 0)} · net ${m(f['net'])}' : ''}'),
          Text('Part restante du patient (à facturer séparément à la caisse) : ${m(f['partPatientRestante'] ?? 0)}'),
          Text(d is Map
              ? 'AIB : ${d['appliquer'] == true ? 'appliqué à ${d['taux']} %' : 'non appliqué : ${d['motif']}'}, décidé par ${d['decidePar']} (${d['decideRole']})'
              : 'AIB : à décider par le comptable'),
          Text(f['numeroMecef'] != null ? 'Numéro MECeF : ${f['numeroMecef']}' : 'Aucun numéro MECeF : ${f['motifRefusMecef'] ?? 'la pièce n’est pas transmise'}'),
        ]));
  }

  void _emettre(BuildContext ctx, TiersPoste t, Fiche f) {
    final r = t.emettre(f['id']);
    if (r['ok'] != true) {
      _refus(ctx, r);
      return;
    }
    ToastsSigh.afficher(ctx, 'Facture ${r['numero']} émise${r['statutMecef'] == 'en_attente' ? ' ; certification en attente : ${r['motifMecef'] ?? ''}' : ''}.',
        type: r['statutMecef'] == 'en_attente' ? TypeToast.attention : TypeToast.succes);
  }

  /// Un motif obligatoire (abandon, avoir, délettrage) : formulaire d'une ligne, puis l'action du service.
  void _motif(BuildContext ctx, String titre, String note, Map<String, Object?> Function(String motif) action) {
    final f = ControleurFormulaire(const [ChampDef(nom: 'motif', libelle: 'Motif', requis: true, col: ColChamp.plein)], const {});
    afficherModale<void>(ctx,
        titre: titre,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [NoteSigh(note, icone: LucideIcons.undo2), const SizedBox(height: 12), FormulaireSigh(controleur: f)]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Retour', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('tiers:motif:ok'),
                  libelle: 'Confirmer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final r = action('${v['motif']}');
                    if (r['ok'] != true) {
                      _refus(ctx, r);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Enregistré.', type: TypeToast.succes);
                  }),
            ]);
  }

  void _decider(BuildContext ctx, ContexteEcran c, TiersPoste t, Fiche f) {
    final prop = t.proposerAib(f['id']);
    final sits = aibSituationsActives(AibDonnees(situations: c.magasin.collection('situationsAib').toutes, bareme: c.magasin.collection('baremeAib').toutes));
    final fm = ControleurFormulaire([
      const ChampDef(
          nom: 'appliquer',
          libelle: 'Appliquer l’AIB à cette facture ?',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [OptionChamp('oui', 'Oui, appliquer'), OptionChamp('non', 'Non, ne pas appliquer')]),
      ChampDef(
          nom: 'situation',
          libelle: 'Ligne du barème (situation de l’acheteur)',
          type: TypeChamp.select,
          col: ColChamp.plein,
          condition: (controle: 'appliquer', quand: ['oui']),
          options: [for (final s in sits) OptionChamp('${s['code']}', '${s['libelle']}')]),
      const ChampDef(nom: 'taux', libelle: 'Taux retenu (%)', type: TypeChamp.nombre, col: ColChamp.tiers, condition: (controle: 'appliquer', quand: ['oui'])),
      const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein, aide: 'Obligatoire pour ne pas appliquer, ou si le taux retenu n’est pas celui du barème.'),
    ], const {});
    afficherModale<void>(ctx,
        titre: 'Décider de l’AIB de ${f['tiersNom']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NoteSigh(
              'Le logiciel propose, le comptable décide. Proposition du barème au ${dateDe(f['date'])} pour cet acheteur (IFU ${f['ifuAcheteur']}) : ${prop['ok'] == true ? '${prop['taux']} %${prop['arrete'] == true ? '' : ' (version pas encore arrêtée)'}' : 'aucune (${prop['motif']})'}.',
              icone: LucideIcons.scale),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: fm),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('tiers:decision:ok'),
                  libelle: 'Enregistrer la décision',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = fm.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final r = t.deciderAib(f['id'], {
                      'appliquer': v['appliquer'] == 'oui' ? true : (v['appliquer'] == 'non' ? false : null),
                      'situation': v['situation'],
                      'taux': v['taux'],
                      'motif': v['motif'],
                    });
                    if (r['ok'] != true) {
                      _refus(ctx, r);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Décision de l’AIB enregistrée.', type: TypeToast.succes);
                  }),
            ]);
  }

  void _nouvelle(BuildContext ctx, ContexteEcran c, TiersPoste t) {
    final auj = isoJour(c.aujourdhui);
    final tiers = [for (final code in t.codes()) if (t.aLaDate(code, auj) != null) t.aLaDate(code, auj)!];
    if (tiers.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucun tiers payeur : en créer un d’abord (onglet « Tiers payeurs »).', type: TypeToast.attention);
      return;
    }
    final candidates = trierPar(
            c.magasin.collection('factures').actives.where((f) => f['proforma'] != true && n(f['montantTTC']) > 0 && (f['lignes'] as List? ?? const []).isNotEmpty).toList(), (f) => f['date'],
            descendant: true)
        .take(300)
        .toList();
    afficherModale<void>(ctx,
        titre: 'Nouvelle facture à un tiers payeur',
        taille: TailleModale.lg,
        corps: _ModaleFactureTiers(contexte: c, ecran: ctx, tiers: tiers, candidates: candidates),
        pied: null);
  }

  // ------------------------------------------------------------------- Tiers
  Widget _ongletTiers(BuildContext ctx, ContexteEcran c, TiersPoste t, String auj) {
    final rows = [for (final code in t.codes()) (t.aLaDate(code, auj) ?? t.versions(code).last)];
    return TableauSigh(
      titre: 'Tiers payeurs (version en vigueur)',
      lignes: rows,
      taillePage: 15,
      nomExport: 'tiers-payeurs',
      messageVide: 'Aucun tiers payeur.',
      colonnes: [
        ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (v) => '${v['code']}'),
        const ColonneTableau(cle: 'nom', libelle: 'Nom'),
        ColonneTableau(cle: 'type', libelle: 'Type', texte: (v) => const {'entreprise': 'Entreprise', 'assureur': 'Assureur', 'convention': 'Convention'}['${v['type']}'] ?? '${v['type']}'),
        ColonneTableau(cle: 'ifu', libelle: 'IFU', texte: (v) => '${v['ifu'] ?? 'IFU à renseigner'}', rendu: (_, v) => v['ifu'] == null ? const BadgeSigh('IFU à renseigner', ton: TonSigh.attention) : Text('${v['ifu']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        ColonneTableau(cle: 'adresse', libelle: 'Adresse', texte: (v) => '${v['adresse'] ?? 'Non renseignée'}'),
        ColonneTableau(cle: 'delaiPaiementJours', libelle: 'Délai', droite: true, texte: (v) => v['delaiPaiementJours'] == null ? 'Non convenu' : '${v['delaiPaiementJours']} j'),
        ColonneTableau(cle: 'version', libelle: 'Version', texte: (v) => 'v${v['version']} depuis le ${dateDe(v['dateEffet'])}'),
      ],
      actionsLigne: (x, v) => [if (t.peutEmettre) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Nouvelle version datée', onPressed: () => _formulaireTiers(x, c, t, v))],
      actions: [if (t.peutEmettre) BoutonSigh(key: const Key('tiers:nouveau-tiers'), libelle: 'Nouveau tiers payeur', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _formulaireTiers(ctx, c, t, null))],
    );
  }

  void _formulaireTiers(BuildContext ctx, ContexteEcran c, TiersPoste t, Fiche? v) {
    final fm = ControleurFormulaire([
      const ChampDef(nom: 'nom', libelle: 'Nom', requis: true, col: ColChamp.plein),
      const ChampDef(nom: 'type', libelle: 'Type', type: TypeChamp.select, requis: true, options: [OptionChamp('entreprise', 'Entreprise'), OptionChamp('assureur', 'Assureur'), OptionChamp('convention', 'Convention')]),
      const ChampDef(nom: 'ifu', libelle: 'IFU (13 chiffres)', aide: 'Exigé à la première facture : une vente normalisée à un professionnel porte son IFU.'),
      const ChampDef(nom: 'adresse', libelle: 'Adresse', col: ColChamp.plein),
      const ChampDef(nom: 'delaiPaiementJours', libelle: 'Délai de paiement (jours)', type: TypeChamp.nombre, aide: 'Vide : délai non convenu, l’échéance est non calculable.'),
      const ChampDef(nom: 'conditions', libelle: 'Conditions', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date),
      if (v != null) const ChampDef(nom: 'motif', libelle: 'Motif de la nouvelle version', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
    ], {
      'nom': v?['nom'] ?? '',
      'type': v?['type'] ?? 'entreprise',
      'ifu': v?['ifu'] ?? '',
      'adresse': v?['adresse'] ?? '',
      'delaiPaiementJours': v?['delaiPaiementJours'] ?? '',
      'conditions': v?['conditions'] ?? '',
      'dateEffet': isoJour(c.aujourdhui),
    });
    afficherModale<void>(ctx,
        titre: v == null ? 'Nouveau tiers payeur' : 'Nouvelle version de ${v['code']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: fm),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('tiers:tiers:ok'),
                  libelle: 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final x = fm.valider();
                    if (x == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final r = v == null ? t.creerTiers(x) : t.nouvelleVersion('${v['code']}', x);
                    if (r['ok'] != true) {
                      _refus(ctx, r);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Fiche enregistrée.', type: TypeToast.succes);
                  }),
            ]);
  }

  // ---------------------------------------------------- Règlements et lettrage
  Widget _ongletReglements(BuildContext ctx, ContexteEcran c, TiersPoste t, List<Fiche> regs, List<Fiche> lets, String auj) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TableauSigh(
        titre: 'Règlements reçus des tiers payeurs',
        lignes: regs,
        taillePage: 10,
        nomExport: 'reglements-tiers',
        messageVide: 'Aucun règlement reçu.',
        colonnes: [
          ColonneTableau(cle: 'numero', libelle: 'N°', sansCoupure: true, texte: (r) => '${r['numero']}'),
          ColonneTableau(cle: 'date', libelle: 'Date', texte: (r) => dateDe(r['date'])),
          ColonneTableau(cle: 'tiersCode', libelle: 'Tiers', texte: (r) => _nomTiers(t, '${r['tiersCode']}', auj)),
          const ColonneTableau(cle: 'mode', libelle: 'Mode'),
          const ColonneTableau(cle: 'referencePaiement', libelle: 'Référence'),
          ColonneTableau(cle: 'montant', libelle: 'Montant', droite: true, texte: (r) => m(r['montant'])),
          ColonneTableau(cle: 'reste', libelle: 'Reste à lettrer', droite: true, texte: (r) => t.resteNonLettre(r) > 0 ? m(t.resteNonLettre(r)) : 'Lettré', rendu: (_, r) => t.resteNonLettre(r) > 0 ? BadgeSigh(m(t.resteNonLettre(r)), ton: TonSigh.attention) : const BadgeSigh('Lettré', ton: TonSigh.succes)),
        ],
        actionsLigne: (x, r) => [if (t.peutCorriger && t.resteNonLettre(r) > 0) BoutonIcone(icone: LucideIcons.link, libelle: 'Lettrer sur des factures', onPressed: () => _lettrer(x, c, t, r))],
        actions: [if (t.peutEmettre) BoutonSigh(key: const Key('tiers:reglement'), libelle: 'Enregistrer un règlement reçu', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _reglement(ctx, c, t, auj))],
      ),
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Lettrages',
        lignes: lets,
        taillePage: 10,
        nomExport: 'lettrages-tiers',
        messageVide: 'Aucun lettrage.',
        colonnes: [
          ColonneTableau(cle: 'date', libelle: 'Date', texte: (x) => dateDe(x['date'])),
          const ColonneTableau(cle: 'reglementNumero', libelle: 'Règlement'),
          const ColonneTableau(cle: 'factureNumero', libelle: 'Facture'),
          ColonneTableau(cle: 'montant', libelle: 'Montant lettré', droite: true, texte: (x) => m(x['montant'])),
          const ColonneTableau(cle: 'lettrePar', libelle: 'Par'),
        ],
        actionsLigne: (x, l) => [if (t.peutCorriger) BoutonIcone(icone: LucideIcons.unlink, libelle: 'Délettrer', onPressed: () => _motif(x, 'Défaire le lettrage', 'Le lettrage est archivé avec son motif (RG-14) ; la facture redevient due.', (mo) => t.delettrer(l['id'], mo)))],
      ),
    ]);
  }

  void _reglement(BuildContext ctx, ContexteEcran c, TiersPoste t, String auj) {
    final fm = ControleurFormulaire([
      ChampDef(nom: 'tiersCode', libelle: 'Tiers payeur', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [for (final code in t.codes()) OptionChamp(code, _nomTiers(t, code, auj))]),
      const ChampDef(nom: 'date', libelle: 'Date de réception', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'montant', libelle: 'Montant reçu (FCFA)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'mode', libelle: 'Mode', type: TypeChamp.select, requis: true, options: [OptionChamp('virement', 'Virement'), OptionChamp('cheque', 'Chèque'), OptionChamp('especes', 'Espèces')]),
      const ChampDef(nom: 'referencePaiement', libelle: 'Référence du paiement', requis: true, aide: 'Numéro de chèque, de virement ou de bordereau.'),
    ], {'date': auj, 'mode': 'virement'});
    afficherModale<void>(ctx,
        titre: 'Règlement reçu d’un tiers payeur',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: fm),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('tiers:reglement:ok'),
                  libelle: 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = fm.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final r = t.reglement(v);
                    if (r['ok'] != true) {
                      _refus(ctx, r);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Règlement ${r['numero']} enregistré, à lettrer.', type: TypeToast.succes);
                  }),
            ]);
  }

  void _lettrer(BuildContext ctx, ContexteEcran c, TiersPoste t, Fiche r) {
    final dues = t.facturesEmises().where((f) => f['tiersCode'] == r['tiersCode'] && t.creance(f) > 0).toList();
    if (dues.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucune facture due pour ce tiers.', type: TypeToast.attention);
      return;
    }
    final champs = [for (final _ in dues) TextEditingController()];
    afficherModale<void>(ctx,
        titre: 'Lettrer ${r['numero']}',
        taille: TailleModale.lg,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh('Reste à lettrer sur ${r['numero']} : ${m(t.resteNonLettre(r))}. Un lettrage ne dépasse ni ce reste ni ce qui est dû sur la facture.', icone: LucideIcons.link),
          const SizedBox(height: 8),
          for (final (i, f) in dues.indexed)
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(child: Text('${f['numero']} · reste dû ${m(t.creance(f))}')),
                  SizedBox(width: 130, child: TextField(key: Key('tiers:lettrer:$i'), controller: champs[i], keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true))),
                ])),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('tiers:lettrer:ok'),
                  libelle: 'Lettrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final aff = [
                      for (final (i, f) in dues.indexed)
                        if ((num.tryParse(champs[i].text) ?? 0) > 0) {'factureTiersId': f['id'], 'montant': num.parse(champs[i].text)}
                    ];
                    final x = t.lettrer(r['id'], aff);
                    if (x['ok'] != true) {
                      _refus(ctx, x);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Lettrage enregistré.', type: TypeToast.succes);
                  }),
            ]);
  }
}

/// La modale de « Nouvelle facture à un tiers payeur » : tiers, date, facture du patient, puis les prestations prises en charge (montant par ligne).
class _ModaleFactureTiers extends StatefulWidget {
  const _ModaleFactureTiers({required this.contexte, required this.ecran, required this.tiers, required this.candidates});
  final ContexteEcran contexte;
  final BuildContext ecran;
  final List<Fiche> tiers, candidates;
  @override
  State<_ModaleFactureTiers> createState() => _EtatModaleFactureTiers();
}

class _EtatModaleFactureTiers extends State<_ModaleFactureTiers> {
  late final ControleurFormulaire _form;
  final Map<String, TextEditingController> _montants = {};
  final Set<String> _cochees = {};
  String _vue = '';

  @override
  void initState() {
    super.initState();
    _form = ControleurFormulaire([
      ChampDef(nom: 'tiers', libelle: 'Tiers payeur', type: TypeChamp.select, requis: true, col: ColChamp.plein, recherche: true, options: [for (final t in widget.tiers) OptionChamp('${t['code']}', '${t['nom']}')]),
      const ChampDef(nom: 'date', libelle: 'Date de la facture', type: TypeChamp.date, requis: true),
      ChampDef(nom: 'facture', libelle: 'Facture du patient', type: TypeChamp.select, requis: true, col: ColChamp.plein, recherche: true, options: [for (final f in widget.candidates) OptionChamp('${f['id']}', '${f['numero']} — ${f['patient'] ?? 'Sans dossier'}')]),
    ], {'date': isoJour(widget.contexte.aujourdhui)});
    _form.addListener(() {
      if ('${_form['facture']}' != _vue) {
        _vue = '${_form['facture']}';
        setState(() {
          _cochees.clear();
          for (final c in _montants.values) {
            c.dispose();
          }
          _montants.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    _form.dispose();
    for (final c in _montants.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _creer(VoidCallback fermer) {
    final c = widget.contexte;
    final v = _form.valider();
    if (v == null) return;
    final aff = [
      for (final id in _cochees) {'factureId': '${v['facture']}', 'ligneId': id, 'montant': num.tryParse(_montants[id]?.text ?? '') ?? 0}
    ];
    final r = tiersDe(c).proposer({'tiersCode': v['tiers'], 'date': v['date'], 'lignes': aff});
    if (r['ok'] != true) {
      _refus(widget.ecran, r);
      return;
    }
    fermer();
    ToastsSigh.afficher(widget.ecran, 'Brouillon créé : décider de l’AIB, puis émettre.', type: TypeToast.succes);
  }

  @override
  Widget build(BuildContext context) {
    final t = tiersDe(widget.contexte);
    return ListenableBuilder(
      listenable: _form,
      builder: (context, _) {
        final lf = '${_form['facture']}'.isEmpty ? null : t.lignesFacturables(_form['facture']);
        final lignes = lf != null && lf['ok'] == true ? (lf['lignes'] as List).cast<Map<String, Object?>>() : const <Map<String, Object?>>[];
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'La facture se rattache aux prestations d’un patient. L’IFU et le nom de l’acheteur viennent de la fiche du tiers payeur à la date de la pièce et sont contrôlés avant toute écriture. L’AIB se décide ensuite (le comptable), avant l’émission.',
              icone: LucideIcons.building2),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: _form),
          const SizedBox(height: 12),
          if (lf == null)
            const Text('Choisir la facture du patient pour voir ses prestations.', style: TextStyle(color: JetonsShell.slate400, fontSize: 12))
          else if (lf['ok'] != true)
            NoteSigh('${lf['motif']}', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)
          else ...[
            const LibelleChamp('Prestations prises en charge par le tiers'),
            for (final l in lignes)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: JetonsShell.slate200), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Checkbox(
                      key: Key('tiers:ligne:${l['ligneId']}'),
                      value: _cochees.contains('${l['ligneId']}'),
                      onChanged: l['disponible'] == null || l['disponible'] == 0
                          ? null
                          : (x) => setState(() {
                                final id = '${l['ligneId']}';
                                if (x == true) {
                                  _cochees.add(id);
                                  _montants.putIfAbsent(id, () => TextEditingController(text: '${l['disponible']}'));
                                } else {
                                  _cochees.remove(id);
                                }
                              })),
                  Expanded(child: Text('${l['designation']}', style: const TextStyle(fontSize: 14))),
                  Text(l['disponible'] == null ? 'prix à valoriser' : 'facturable ${m(l['disponible'])}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
                  const SizedBox(width: 8),
                  if (_cochees.contains('${l['ligneId']}'))
                    SizedBox(width: 110, child: TextField(key: Key('tiers:montant:${l['ligneId']}'), controller: _montants['${l['ligneId']}'], keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true))),
                ]),
              ),
          ],
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            BoutonSigh(key: const Key('tiers:creer'), libelle: 'Créer le brouillon', icone: LucideIcons.check, onPressed: () => _creer(() => Navigator.of(context).maybePop())),
          ]),
        ]);
      },
    );
  }
}
