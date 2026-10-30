import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show bandeauLectureSeule, convertirSaisie;
import '../m2/cs_commun.dart' show sessionDe, stockDe;
import 'bloc_commun.dart';

/// `m3-bons-pansements` — « Bons de pansement » : la prescription des pansements, réglés à la caisse SÉANCE PAR SÉANCE et exécutés en salle de soins.
///
/// Le bon RÉUTILISE la chaîne existante (le moteur `csPrescrire` = `PR.prescrire`) : la prescription porte UNE LIGNE PAYABLE PAR SÉANCE — la caisse
/// encaisse des séances NOMMÉES, et un règlement partiel libère exactement celles qu'il couvre. L'exécution passe par la file de la salle de soins,
/// débloquée par l'encaissement.
///
/// LE PANSEMENT VAUT 9 000 NON ASSURÉ / 6 000 ASSURÉ : les colonnes de la grille sont INVERSÉES (décision du 26/08) — ne pas « corriger ». Écart E414 :
/// ce sont les actes du catalogue (9 000, tarif non assuré) qui tarifient la ligne ; le 6 000 assuré n'est qu'annoncé par l'indicateur, il ne s'applique
/// que par la répartition de la garantie. Écart E413 : « Séances en attente de règlement » compte des BONS, non des séances.
class EcranBonsPansements extends StatelessWidget with EcranMaquette {
  const EcranBonsPansements({super.key});

  @override
  String get titre => 'Bons de pansement';

  @override
  String get description =>
      'Prescription des pansements, réglés à la caisse séance par séance et exécutés en salle de soins.';

  @override
  String get regle =>
      'Le bon réutilise la chaîne existante : la prescription porte une ligne payable par séance — la caisse encaisse des séances NOMMÉES, et un règlement partiel libère exactement celles qu’il couvre. L’exécution passe par la file de la salle de soins, débloquée par l’encaissement.';

  static List<Fiche> actesPansement(Magasin m) => [
        for (final a in m.collection('actes').actives)
          if (blocCodesPansement.contains(a['code'])) a
      ];

  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: optionsPatientsBloc(m)),
        ChampDef(nom: 'medecin', libelle: 'Prescripteur', type: TypeChamp.select, requis: true, options: [
          for (final x in m.collection('soignants').actives)
            if (x['prescrit'] == true) OptionChamp('${x['nomComplet']}', '${x['nomComplet']} — ${x['poste']}'),
        ]),
        ChampDef(nom: 'acteCode', libelle: 'Type de pansement', type: TypeChamp.select, requis: true, options: [
          for (final a in actesPansement(m)) OptionChamp('${a['code']}', '${a['libelle']}'),
        ]),
        const ChampDef(
            nom: 'seances',
            libelle: 'Nombre de séances',
            type: TypeChamp.nombre,
            requis: true,
            aide: 'Une ligne payable PAR SÉANCE : la caisse peut encaisser séance par séance.'),
        const ChampDef(
            nom: 'indication',
            libelle: 'Indication',
            type: TypeChamp.textarea,
            lignes: 2,
            requis: true,
            col: ColChamp.plein),
      ];

  /// L'émission : UNE prescription (`csPrescrire`) dont les actes sont le pansement répété autant de fois que de séances.
  static ResultatPrescription emettre(ContexteEcran c, Map<String, Object?> v, int n) => csPrescrire(
      stockDe(c),
      {
        'patientCode': v['patientCode'],
        'medecin': v['medecin'],
        'diagnostic': v['indication'],
        'actes': [for (var i = 0; i < n; i++) v['acteCode']],
      },
      sessionDe(c));

  static void nouveauBon(BuildContext ctx, Magasin m) {
    final c = ContexteEcran.of(ctx);
    final defs = champs(m);
    final ctl = ControleurFormulaire(defs, const {'seances': '1'});
    afficherModale<void>(ctx,
        titre: 'Nouveau bon de pansement',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Émettre le bon',
                  icone: LucideIcons.plus,
                  onPressed: () {
                    final brut = ctl.valider();
                    if (brut == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final v = convertirSaisie(defs, brut);
                    final n = blocNombreSeances(v['seances']);
                    final ResultatPrescription res;
                    try {
                      res = emettre(c, v, n);
                    } on RefusCs catch (e) {
                      ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Bon ${res.ordonnance['numero']} émis — $n séance(s).',
                        type: TypeToast.succes,
                        duree: const Duration(seconds: 8),
                        detail:
                            'Facture ${res.facture['numero']} à la caisse ; la salle de soins est informée, exécutable après encaissement.');
                    imprimerBon(ctx, res.ordonnance);
                  }),
            ]);
  }

  static void imprimerBon(BuildContext ctx, Fiche o) {
    final c = ContexteEcran.of(ctx);
    final s = blocSeancesDe(o, c.magasin.collection('factures').actives);
    final actes = [
      for (final (i, a) in ((o['actes'] as List?) ?? const []).indexed)
        {'rang': 'Séance ${i + 1}', ...(a as Map).cast<String, Object?>()}
    ];
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'BON DE PANSEMENT',
          sousTitre: '${o['numero']} — ${o['patient']}',
          cartouche: [
            ('Patient', '${o['patient']}'),
            ('Dossier', '${o['patientCode'] ?? ''}'.isEmpty ? '—' : '${o['patientCode']}'),
            ('Date', dateBloc(o['date'])),
            ('Prescripteur', '${o['medecin']}'),
            ('Facture', s.facture == null ? '—' : '${s.facture!['numero']}'),
          ],
          blocs: [
            if ('${o['diagnostic'] ?? ''}'.isNotEmpty) BlocTexte('Indication : ${o['diagnostic']}'),
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Séance', valeur: (x) => x['rang']),
              ColonneEtat(libelle: 'Acte', valeur: (x) => x['libelle']),
              ColonneEtat(
                  libelle: 'Tarif',
                  droite: true,
                  valeur: (x) => money(x['prix'], avecDevise: false),
                  somme: (x) => nombreOuZero(x['prix'])),
            ], lignes: actes)),
            const BlocTexte(
                'Chaque séance se règle à la caisse ; la salle de soins n’exécute que les séances réglées, sur présentation du présent bon.',
                italique: true),
          ],
          signatures: [
            Signature('Le prescripteur', nom: '${o['medecin']}'),
            const Signature('L’exécutant', mention: 'Salle de soins'),
          ],
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
        ));
  }

  static void detail(BuildContext ctx, Fiche o) {
    final c = ContexteEcran.of(ctx);
    final s = blocSeancesDe(o, c.magasin.collection('factures').actives);
    afficherTiroir<void>(ctx,
        titre: 'Bon ${o['numero']}',
        sousTitre: '${o['patient']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Patient', o['patient']),
            ('Prescripteur', o['medecin']),
            ('Date', dateBloc(o['date'])),
            ('Séances', '${s.reglees} réglée(s) sur ${s.total}'),
            ('Facture', s.facture == null ? '—' : s.facture!['numero']),
            ('Montant', money(o['montant'])),
          ]),
          const SizedBox(height: 16),
          NoteSigh(
              s.reglees < s.total
                  ? 'La salle de soins n’exécute que les séances RÉGLÉES : ${s.total - s.reglees} séance(s) attendent la caisse.'
                  : 'Toutes les séances sont réglées : la file de la salle de soins les porte.',
              ton: s.reglees < s.total ? TonSigh.attention : TonSigh.info,
              icone: LucideIcons.wallet),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final ords = c.magasin.collection('ordonnances');
    final facs = c.magasin.collection('factures');
    return ListenableBuilder(
      listenable: Listenable.merge([ords, facs, c.magasin.collection('actes')]),
      builder: (context, _) {
        final rows = blocBonsPansement(ords.actives);
        final k = blocKpisPansements(rows, facs.actives);
        final types = actesPansement(c.magasin);
        final so09 = types.where((a) => a['code'] == 'SO09').firstOrNull;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bandeauLectureSeule(c),
          kpisBloc([
            KpiSigh(libelle: 'Bons émis', valeur: nombre(k.bons), icone: LucideIcons.bandage),
            KpiSigh(
                libelle: 'Séances en attente de règlement',
                valeur: nombre(k.attente),
                icone: LucideIcons.wallet,
                ton: k.attente > 0 ? TonSigh.attention : TonSigh.neutre),
            KpiSigh(
                libelle: 'Types au catalogue',
                valeur: nombre(types.length),
                icone: LucideIcons.list,
                ton: TonSigh.neutre,
                indice: 'Pansement (SO09) et pansement chirurgical (CH04)'),
            KpiSigh(
                libelle: 'Tarif du pansement',
                valeur: so09 != null && so09['prix'] != null ? money(so09['prix']) : '—',
                icone: LucideIcons.receipt,
                ton: TonSigh.info,
                indice: 'Grille (colonnes inversées, 26/08) : 9 000 non assuré · 6 000 assuré'),
          ]),
          TableauSigh(
            titre: 'Registre des bons',
            lignes: rows,
            nomExport: 'bons-pansements',
            triInitial: 'date',
            sensInitial: 'desc',
            messageVide: 'Aucun bon de pansement émis.',
            alClicLigne: (o) => detail(context, o),
            actions: [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Nouveau bon de pansement',
                    icone: LucideIcons.plus,
                    taille: TailleBouton.sm,
                    onPressed: () => nouveauBon(context, c.magasin)),
            ],
            actionsLigne: (ctx, o) => [
              BoutonIcone(
                  icone: LucideIcons.printer, libelle: 'Imprimer le bon', onPressed: () => imprimerBon(ctx, o)),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'numero',
                  libelle: 'N°',
                  texte: (o) => '${o['numero'] ?? ''}',
                  rendu: (_, o) => Text('${o['numero'] ?? ''}',
                      style: const TextStyle(
                          fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, color: JetonsShell.slate700))),
              ColonneTableau(
                  cle: 'date',
                  libelle: 'Date',
                  valeur: (o) => DateTime.tryParse('${o['date'] ?? ''}')?.millisecondsSinceEpoch ?? 0,
                  texte: (o) => dateBloc(o['date'])),
              ColonneTableau(
                  cle: 'patient',
                  libelle: 'Patient',
                  texte: (o) => '${o['patient']} — ${'${o['patientCode'] ?? ''}'.isEmpty ? '—' : o['patientCode']}'),
              const ColonneTableau(cle: 'medecin', libelle: 'Prescripteur'),
              ColonneTableau(
                  cle: 'seances',
                  libelle: 'Séances réglées',
                  droite: true,
                  valeur: (o) {
                    final s = blocSeancesDe(o, facs.actives);
                    return '${s.reglees}/${s.total}';
                  },
                  texte: (o) {
                    final s = blocSeancesDe(o, facs.actives);
                    return '${s.reglees} / ${s.total}';
                  },
                  rendu: (_, o) {
                    final s = blocSeancesDe(o, facs.actives);
                    return BadgeSigh('${s.reglees} / ${s.total}',
                        ton: s.reglees == s.total
                            ? TonSigh.succes
                            : (s.reglees > 0 ? TonSigh.attention : TonSigh.danger));
                  }),
              ColonneTableau(
                  cle: 'montant',
                  libelle: 'Montant',
                  droite: true,
                  texte: (o) => money(o['montant'], avecDevise: false)),
            ],
          ),
        ]);
      },
    );
  }
}
