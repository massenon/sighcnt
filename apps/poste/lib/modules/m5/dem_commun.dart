import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Ce que partagent les quatre écrans des demandes d'analyses (M5) : les lectures du répertoire, les colonnes du registre, la fiche en tiroir et les
/// pièces imprimées. Les règles (code d'analyse, circuit du prélèvement, vues par service) sont dans `packages/domaine` (`dem_regles.dart`).

DateTime? dateDe(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
String dateCourte(Object? v) {
  final d = dateDe(v);
  return d == null ? '' : dateFR(d);
}

String dateHeureDe(Object? v) {
  final d = dateDe(v);
  return d == null ? '' : dateHeure(d);
}

bool vrai(Object? v) => v != null && v != false && v != 0 && v != '';

const _mono = 'LiberationMono';

Widget monoTexte(String t,
        {double taille = 12, Color couleur = JetonsShell.slate900}) =>
    Text(t,
        style: TextStyle(fontFamily: _mono, fontSize: taille, color: couleur));

/// Laborantins (`fonction: tsl`) et médecins du personnel, comme `laborantins()` / `medecins()` de la maquette.
List<OptionChamp> laborantins(Magasin m) => [
      for (final e in m.collection('personnel').actives)
        if (e['fonction'] == 'tsl')
          OptionChamp('${e['nomComplet']}', '${e['nomComplet']}')
    ];

List<OptionChamp> medecins(Magasin m) => [
      for (final e in m.collection('personnel').actives)
        if (e['fonction'] == 'medecin')
          OptionChamp('${e['nomComplet']}', '${e['nomComplet']}')
    ];

/// `optionsPatients()` : le répertoire trié par code, « code — nom prénom ».
List<OptionChamp> optionsPatients(Magasin m) => [
      for (final p
          in trierPar(m.collection('patients').actives, (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

Widget _deuxLignes(String haut, String bas,
        {FontWeight? poids, Color hautCouleur = JetonsShell.slate700}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(haut,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: hautCouleur,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: poids)),
      Text(bas,
          style: const TextStyle(
              color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
    ]);

/// `colonnesDemande` : les neuf colonnes du registre des demandes (et des vues par service).
List<ColonneTableau> colonnesDemande() => [
      ColonneTableau(
          cle: 'reference',
          libelle: 'N°',
          sansCoupure: true,
          texte: (r) => '${r['reference'] ?? ''}',
          rendu: (_, r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    monoTexte('${r['reference'] ?? ''}'),
                    // Le code d'analyse NNNNN-AAAA : l'identifiant du registre annuel, distinct de la référence interne.
                    if (vrai(r['codeAnalyse']))
                      monoTexte('${r['codeAnalyse']}',
                          taille: 10, couleur: JetonsShell.navy700),
                    Text(
                        r['origine'] == 'ordonnance'
                            ? '${r['ordonnanceNumero'] ?? 'Ordonnance'}'
                            : 'Saisie laboratoire',
                        style: const TextStyle(
                            color: JetonsShell.slate400,
                            fontSize: 10,
                            height: 15 / 10)),
                  ])),
      ColonneTableau(
          cle: 'origine',
          libelle: 'Origine',
          sansCoupure: true,
          texte: demOrigineLibelle,
          rendu: (_, r) {
            if (r['origine'] == 'service') {
              return const BadgeSigh('Fiche de service', ton: TonSigh.info);
            }
            if (r['origine'] == 'accueil-externe') {
              return const BadgeSigh('Accueil — externe', ton: TonSigh.info);
            }
            if (r['origine'] != 'ordonnance') {
              return const BadgeSigh('Manuelle', ton: TonSigh.neutre);
            }
            return vrai(r['bloqueParPaiement'])
                ? const BadgeSigh('Attente caisse', ton: TonSigh.attention)
                : const BadgeSigh('Prépayée', ton: TonSigh.succes);
          }),
      ColonneTableau(
          cle: 'dateHeure',
          libelle: 'Date',
          sansCoupure: true,
          valeur: (r) => dateDe(r['dateHeure'])?.millisecondsSinceEpoch ?? 0,
          texte: (r) => dateCourte(r['dateHeure'])),
      ColonneTableau(
          cle: 'patient',
          libelle: 'Patient',
          texte: (r) => '${r['patient'] ?? ''}',
          rendu: (_, r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${r['patient'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: JetonsShell.slate800,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w500)),
                    monoTexte('${r['patientCode'] ?? ''}',
                        couleur: JetonsShell.slate400),
                  ])),
      ColonneTableau(
          cle: 'analyse',
          libelle: 'Analyse',
          texte: (r) => '${r['analyse'] ?? ''}',
          rendu: (_, r) =>
              _deuxLignes('${r['analyse'] ?? ''}', '${r['categorie'] ?? ''}')),
      const ColonneTableau(cle: 'echantillon', libelle: 'Échantillon'),
      const ColonneTableau(cle: 'prescripteur', libelle: 'Prescripteur'),
      ColonneTableau(
          cle: 'urgent',
          libelle: 'Priorité',
          texte: (r) => vrai(r['urgent']) ? 'Urgent' : 'Normale',
          rendu: (_, r) => vrai(r['urgent'])
              ? const BadgeSigh('Urgent', ton: TonSigh.danger)
              : const Text('Normale',
                  style: TextStyle(
                      color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
      ColonneTableau(
          cle: 'etatAnalyse',
          libelle: 'État',
          texte: (r) => '${r['etatAnalyse'] ?? ''}',
          rendu: (_, r) => statutBadge(r['etatAnalyse'])),
    ];

/// `detailDemande(r)` : la fiche en tiroir — l'identité de la demande, puis le résultat ou l'attente du résultat.
Widget detailDemande(Fiche r) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DescListeSigh([
            ('Référence', monoTexte('${r['reference'] ?? ''}', taille: 14, couleur: JetonsShell.slate800)),
            (
              'Code d’analyse',
              vrai(r['codeAnalyse'])
                  ? Text('${r['codeAnalyse']}',
                      style: const TextStyle(
                          fontFamily: _mono,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          color: JetonsShell.navy800))
                  : const Text('antérieur à la série annuelle',
                      style: TextStyle(color: JetonsShell.slate400, fontSize: 12))
            ),
            ('Date de la demande', dateHeureDe(r['dateHeure'])),
            ('Patient', r['patient']),
            ('Dossier', monoTexte('${r['patientCode'] ?? ''}', taille: 14, couleur: JetonsShell.slate800)),
            ('Analyse', r['analyse']),
            ('Code', monoTexte('${r['analyseCode'] ?? ''}', taille: 14, couleur: JetonsShell.slate800)),
            ('Catégorie', r['categorie']),
            ('Échantillon', r['echantillon']),
            ('Tarif', money(r['prix'])),
            ('Prescripteur', r['prescripteur']),
            ('Laborantin', r['laborantin']),
            (
              'Priorité',
              vrai(r['urgent'])
                  ? const BadgeSigh('Urgent', ton: TonSigh.danger)
                  : const BadgeSigh('Normale')
            ),
            ('État', statutBadge(r['etatAnalyse'])),
          ]),
          const SizedBox(height: 16),
          if (vrai(r['resultat']))
            CarteSigh(
                titre: 'Résultat',
                child: DescListeSigh([
                  (
                    'Valeur mesurée',
                    Text('${r['resultat']}',
                        style: const TextStyle(
                            color: JetonsShell.navy900,
                            fontSize: 16,
                            height: 24 / 16,
                            fontWeight: FontWeight.w600))
                  ),
                  (
                    'Conclusion',
                    r['conclusion'] == 'Normal'
                        ? const BadgeSigh('Normal', ton: TonSigh.succes)
                        : BadgeSigh('${r['conclusion'] ?? '—'}',
                            ton: TonSigh.attention)
                  ),
                ]))
          else
            const VideSigh('Résultat non encore saisi.',
                icone: LucideIcons.hourglass),
        ]);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Pièces imprimées
// ---------------------------------------------------------------------------------------------------------------------------------------------

String _refPiece(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

/// `etat` de m5-demandes : le résultat d'analyse si la demande est validée, sinon le bon de prélèvement.
Future<void> imprimerDemande(BuildContext ctx, Fiche r) {
  final c = ContexteEcran.of(ctx);
  if (r['etatAnalyse'] == 'valide') {
    final p = c.magasin.collection('patients').actives.where((x) => x['id'] == r['patientId']).firstOrNull;
    return afficherApercu(
        ctx,
        PieceA4(
          titre: 'Résultat d’analyse de laboratoire',
          sousTitre: '${r['reference']}',
          reference: _refPiece(c),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Patient', '${r['patient'] ?? ''}'),
            ('Dossier', '${r['patientCode'] ?? ''}'),
            ('Âge', demAgeTexte(p, maintenant: c.aujourdhui)),
            ('Date de prélèvement', dateCourte(r['dateHeure'])),
            ('Prescripteur', '${r['prescripteur'] ?? ''}'),
            ('Laborantin', '${r['laborantin'] ?? ''}'),
          ],
          blocs: [
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Code', valeur: (x) => x['analyseCode']),
              ColonneEtat(libelle: 'Analyse', valeur: (x) => x['analyse']),
              ColonneEtat(libelle: 'Échantillon', valeur: (x) => x['echantillon']),
              ColonneEtat(
                  libelle: 'Résultat',
                  valeur: (x) => vrai(x['resultat']) ? x['resultat'] : 'En cours'),
              ColonneEtat(
                  libelle: 'Conclusion',
                  valeur: (x) => vrai(x['conclusion']) ? x['conclusion'] : '—'),
            ], lignes: [r])),
            const BlocTexte(
                'Les résultats doivent être interprétés par le médecin prescripteur en fonction du contexte clinique. Ce document est archivé au dossier patient conformément à la politique de conservation de l’établissement.',
                italique: true),
          ],
          signatures: [
            Signature('Le Laborantin', nom: '${r['laborantin'] ?? ''}'),
            const Signature('Le Biologiste responsable',
                nom: 'KINNOU Addoul Ganiou'),
          ],
        ));
  }
  return afficherApercu(
      ctx,
      PieceA4(
        titre: 'Bon de prélèvement',
        sousTitre: '${r['reference']}',
        reference: _refPiece(c),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        cartouche: [
          ('Patient', '${r['patient'] ?? ''}'),
          ('Dossier', '${r['patientCode'] ?? ''}'),
          ('Date', dateCourte(r['dateHeure'])),
          ('Prescripteur', '${r['prescripteur'] ?? ''}'),
          ('Priorité', vrai(r['urgent']) ? 'URGENT' : 'Normale'),
        ],
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Code', valeur: (x) => x['analyseCode']),
            ColonneEtat(libelle: 'Analyse', valeur: (x) => x['analyse']),
            ColonneEtat(libelle: 'Échantillon', valeur: (x) => x['echantillon']),
            ColonneEtat(
                libelle: 'Tarif',
                droite: true,
                valeur: (x) => money(x['prix'], avecDevise: false)),
          ], lignes: [r])),
        ],
        signatures: [
          Signature('Le Médecin prescripteur', nom: '${r['prescripteur'] ?? ''}'),
          const Signature('Le Laborantin'),
        ],
      ));
}

/// `bon(r)` de m5-prelevement : le BON D'ANALYSE — la pièce qui accompagne le patient à la caisse, à la salle de prélèvement, puis l'échantillon
/// jusqu'au laboratoire.
Future<void> imprimerBonAnalyse(BuildContext ctx, Fiche r) {
  final c = ContexteEcran.of(ctx);
  final m = c.magasin;
  final pat = m.collection('patients').actives.where((x) => x['id'] == r['patientId']).firstOrNull;
  final ex = demExamenDe(r, m.collection('examensLabo').actives);
  final section = ex == null ? '—' : (demSections['${ex['section']}'] ?? '${ex['section']}');
  final dp = dateDe(pat?['dateNaissance']);
  final preleve = dateDe(r['preleveLe']);
  return afficherApercu(
      ctx,
      PieceA4(
        titre: 'Bulletin d’analyses bio-médicales',
        sousTitre: 'Bon n° ${r['reference']}',
        reference: _refPiece(c),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        cartouche: [
          ('Patient', '${r['patient'] ?? ''}'),
          ('Dossier', '${r['patientCode'] ?? ''}'),
          (
            'Âge',
            pat != null && dp != null
                ? '${_annees(dp, c.aujourdhui)} ans'
                : '—'
          ),
          ('Sexe', pat == null ? '—' : (pat['sexe'] == 'F' ? 'Féminin' : 'Masculin')),
          (
            'Service demandeur',
            '${r['serviceDemandeur'] ?? r['secteurDemandeur'] ?? '—'}'
          ),
          ('Indication', '${vrai(r['indication']) ? r['indication'] : '—'}'),
          ('Prescripteur', '${vrai(r['prescripteur']) ? r['prescripteur'] : '—'}'),
          (
            'Heure de prélèvement',
            preleve == null ? '—' : heure(preleve)
          ),
          ('Priorité', vrai(r['urgent']) ? 'URGENT' : 'Courant'),
        ],
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Section', valeur: (_) => section),
            ColonneEtat(libelle: 'Examen demandé', valeur: (x) => x['analyse']),
            ColonneEtat(libelle: 'Échantillon', valeur: (x) => x['echantillon']),
          ], lignes: [r])),
          const BlocTexte(
              'Ce bon accompagne le patient à la caisse puis à la salle de prélèvement, et suit ensuite l’échantillon jusqu’au laboratoire. Le résultat est transmis au clinicien prescripteur ; il est remis directement au patient lorsque celui-ci est adressé de l’extérieur.',
              italique: true),
        ],
        signatures: [
          Signature('Le Prescripteur', nom: '${r['prescripteur'] ?? ''}'),
          Signature('Le Préleveur', nom: '${r['preleveur'] ?? ''}'),
        ],
      ));
}

int _annees(DateTime n, DateTime auj) {
  var a = auj.year - n.year;
  if (auj.month < n.month || (auj.month == n.month && auj.day < n.day)) a--;
  return a;
}
