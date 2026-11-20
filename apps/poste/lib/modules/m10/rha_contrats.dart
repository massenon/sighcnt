import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import '../../donnees/magasin.dart';

import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';
import '../m4/mat_crud.dart';
import 'rha_commun.dart';

/// `m10-contrats` — contrats de travail (nature, durée, période d'essai, échéances). La RÉFÉRENCE est la suivante de la série lue sur les contrats
/// existants (archivés compris) et reste celle de la fiche à la modification — la maquette la tirait d'un compteur de page (E620).
class EcranContrats extends StatelessWidget with EcranMaquette {
  const EcranContrats({super.key});
  @override
  String get titre => 'Contrats';
  @override
  String get description => 'Contrats de travail des agents : nature, durée, période d’essai et échéances.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('contrats');
    Fiche fiche(BuildContext ctx, Map<String, Object?> v, Fiche? existante) => rhaContratEnregistrable(
        {...v, 'salaire': rhaNum(v['salaire'])}, rhaAgentPar(c.magasin, v['employeId']),
        reference: '${existante?['reference'] ?? ''}'.isNotEmpty ? '${existante!['reference']}' : admReferenceSuivante('CT-', 4, col.toutes));

    return CrudMat(
      collection: col,
      entite: 'contrat',
      entiteP: 'contrats',
      prefixeId: 'CON',
      triInitial: 'dateDebut',
      sensInitial: 'desc',
      taillePage: 15,
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
        ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true),
        const ColonneTableau(cle: 'employe', libelle: 'Agent'),
        const ColonneTableau(cle: 'poste', libelle: 'Poste'),
        ColonneTableau(cle: 'nature', libelle: 'Nature', rendu: (_, r) => BadgeSigh('${r['nature']}', ton: r['nature'] == 'CDI' ? TonSigh.succes : TonSigh.attention)),
        ColonneTableau(cle: 'dateDebut', libelle: 'Début', sansCoupure: true, texte: (r) => rhaDateFR(r['dateDebut'])),
        ColonneTableau(
            cle: 'dateFin',
            libelle: 'Échéance',
            sansCoupure: true,
            texte: (r) => rhaVrai(r['dateFin']) ? rhaDateFR(r['dateFin']) : 'Indéterminée',
            rendu: (_, r) {
              final e = rhaEcheanceContrat(r, c.aujourdhui);
              if (e.ton == null) return rhaVrai(r['dateFin']) ? Text(e.texte) : rhaTexteMuet(e.texte);
              return BadgeSigh(e.texte, ton: matTon(e.ton!));
            }),
        const ColonneTableau(cle: 'essai', libelle: 'Période d’essai'),
        ColonneTableau(cle: 'salaire', libelle: 'Salaire', droite: true, texte: (r) => money(r['salaire'], avecDevise: false)),
      ],
      champs: (m) => [
        ChampDef(nom: 'employeId', libelle: 'Agent', type: TypeChamp.select, requis: true, options: rhaOptionsEmployes(m), col: ColChamp.plein),
        ChampDef(nom: 'nature', libelle: 'Nature du contrat', type: TypeChamp.select, requis: true, options: rhaOptions(rhaNaturesContrat)),
        const ChampDef(nom: 'dateDebut', libelle: 'Date de début', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'dateFin', libelle: 'Date de fin (CDD)', type: TypeChamp.date),
        ChampDef(nom: 'essai', libelle: 'Période d’essai', type: TypeChamp.select, options: rhaOptions(rhaPeriodesEssai)),
        const ChampDef(nom: 'salaire', libelle: 'Salaire mensuel (FCFA)', type: TypeChamp.nombre, requis: true),
      ],
      valeursInitiales: () => const {},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [FiltreTableau(nom: 'nature', libelle: 'Nature', options: rhaOptions(rhaNaturesContrat))],
      kpis: (ctx, rows) => rhaKpisW(rhaKpisContrats(rows, c.aujourdhui), const [LucideIcons.fileSignature, LucideIcons.shieldCheck, LucideIcons.clock, LucideIcons.calendarClock]),
      etat: (ctx, r) => matImprimer(ctx,
          titre: 'Contrat de travail',
          sousTitre: '${r['nature']} — ${r['employe']}',
          cartouche: [
            ('Référence', '${r['reference']}'),
            ('Agent', '${r['employe']}'),
            ('Matricule', '${r['matricule']}'),
            ('Poste', '${r['poste']}'),
            ('Nature', '${r['nature']}'),
            ('Date de début', rhaDateFR(r['dateDebut'])),
          ],
          blocs: [
            const BlocTexte('Entre la CLINIQUE NASSIERA TOO SARL, représentée par sa Directrice Administrative, ci-après dénommée « l’Employeur », d’une part,'),
            BlocTexte('Et ${r['employe']}, matricule ${r['matricule']}, ci-après dénommé(e) « l’Employé(e) », d’autre part,'),
            const BlocTexte('Il a été convenu ce qui suit :', gras: true),
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Article', valeur: (l) => l['k']),
              ColonneEtat(libelle: 'Disposition', valeur: (l) => l['v']),
            ], lignes: [
              for (final a in rhaArticlesContrat(r)) {'k': a.$1, 'v': a.$2}
            ])),
          ],
          signatures: [Signature('L’Employé(e)', nom: '${r['employe']}', mention: 'Lu et approuvé'), rhaSignDa]),
    );
  }
}
