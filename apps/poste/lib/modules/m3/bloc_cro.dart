import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show bandeauLectureSeule, imprimerM1;
import 'bloc_commun.dart';
import 'bloc_registre.dart';

/// `m3-bloc-cro` — « Comptes rendus opératoires » : la rédaction et l'impression du compte rendu du secteur Bloc.
///
/// Le compte rendu opératoire est une PIÈCE DE PREUVE : il porte ses TROIS intervenants NOMMÉS — opérateur, aide-opérateur, anesthésiste. Le NIP y est
/// recopié du dossier. Les noms portés par la fiche suivent les identifiants, à la création comme à la modification (écart E411 : la maquette
/// laissait l'ancien nom sur une pièce corrigée).
class EcranCro extends StatelessWidget with EcranMaquette {
  const EcranCro({super.key});

  @override
  String get titre => 'Comptes rendus opératoires';

  @override
  String get description => 'Rédaction et impression du compte rendu opératoire du secteur Bloc.';

  @override
  String get regle =>
      'Le compte rendu opératoire est une pièce de preuve : il porte ses trois intervenants nommés — opérateur, aide-opérateur et anesthésiste. Le NIP y est recopié du dossier. Un compte rendu sans opérateur ne vaut rien le jour où une suite opératoire est contestée.';

  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient',
            type: TypeChamp.select,
            requis: true,
            options: optionsPatientsBloc(m)),
        const ChampDef(
            nom: 'nip',
            libelle: 'NIP',
            requis: true,
            aide: 'Recopié du dossier — c’est le numéro que porte la fiche d’observation.'),
        const ChampDef(nom: 'dateOperation', libelle: 'Date de l’intervention', type: TypeChamp.date, requis: true),
        const ChampDef(
            nom: 'diagnosticPeroperatoire',
            libelle: 'Diagnostic peropératoire',
            type: TypeChamp.textarea,
            lignes: 2,
            requis: true),
        const ChampDef(
            nom: 'intervention', libelle: 'Intervention chirurgicale', type: TypeChamp.textarea, lignes: 2, requis: true),
        const ChampDef(nom: 'anesthesie', libelle: 'Anesthésie', type: TypeChamp.textarea, lignes: 2, requis: true),
        const ChampDef(
            nom: 'cro',
            libelle: 'Compte rendu opératoire proprement dit',
            type: TypeChamp.textarea,
            lignes: 10,
            requis: true),
        ChampDef(
            nom: 'operateurId',
            libelle: 'Opérateur',
            type: TypeChamp.select,
            requis: true,
            options: optionsSoignantsBloc(m, (x) => x['qualite'] == 'medecin')),
        ChampDef(nom: 'aideOperateurId', libelle: 'Aide-opérateur', type: TypeChamp.select, options: [
          const OptionChamp('', '— aucun —'),
          ...optionsSoignantsBloc(m),
        ]),
        ChampDef(
            nom: 'anesthesisteId',
            libelle: 'Anesthésiste',
            type: TypeChamp.select,
            requis: true,
            options: optionsSoignantsBloc(m)),
      ];

  static Fiche construire(ContexteEcran c, Map<String, Object?> v, Fiche? existante) => blocConstruireCro(v,
      patient: patientParCodeBloc(c.magasin, v['patientCode']),
      nomSoignant: (id) => nomSoignantBloc(c.magasin, id),
      existante: existante,
      toutes: c.magasin.collection('crOperatoires').toutes);

  static String _ou(Object? v) => '${v ?? ''}'.isEmpty ? '—' : '$v';

  static Widget detail(BuildContext ctx, Fiche r) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('Référence', r['reference']),
          ('Date', dateBloc(r['dateOperation'])),
          ('Patient', r['patient']),
          ('NIP', _ou(r['nip'])),
          ('Opérateur', r['operateur']),
          ('Aide-opérateur', _ou(r['aideOperateur'])),
          ('Anesthésiste', r['anesthesiste']),
        ]),
        sectionBloc('Diagnostic peropératoire', texteBloc(_ou(r['diagnosticPeroperatoire']))),
        sectionBloc('Intervention chirurgicale', texteBloc(_ou(r['intervention']))),
        sectionBloc('Anesthésie', texteBloc(_ou(r['anesthesie']))),
        sectionBloc('Compte rendu opératoire', texteBloc(_ou(r['cro']))),
      ]);

  /// Une rubrique : un intitulé, puis le texte tel qu'il a été rédigé — les retours à la ligne du praticien sont conservés.
  static List<BlocPiece> _rubrique(String titre, Object? texte) =>
      [BlocTexte(titre.toUpperCase(), gras: true), BlocTexte(_ou(texte))];

  /// TROIS signatures, parce que trois responsabilités distinctes sont engagées : les fondre ferait porter à l'opérateur ce qui relève de
  /// l'anesthésiste.
  static void imprimer(BuildContext ctx, Fiche r) => imprimerM1(ctx,
      titre: 'COMPTE RENDU OPÉRATOIRE',
      sousTitre: '${r['reference']} — ${r['patient']}',
      cartouche: [
        ('Patient', '${r['patient']}'),
        ('NIP', _ou(r['nip'])),
        ('Dossier', _ou(r['patientCode'])),
        ('Date de l’intervention', dateBloc(r['dateOperation'])),
        ('Opérateur', '${r['operateur']}'),
        ('Aide-opérateur', _ou(r['aideOperateur'])),
        ('Anesthésiste', '${r['anesthesiste']}'),
      ],
      blocs: [
        ..._rubrique('Diagnostic peropératoire', r['diagnosticPeroperatoire']),
        ..._rubrique('Intervention chirurgicale', r['intervention']),
        ..._rubrique('Anesthésie', r['anesthesie']),
        ..._rubrique('Compte rendu opératoire', r['cro']),
      ],
      signatures: [
        Signature('L’opérateur', nom: '${r['operateur']}'),
        Signature('L’aide-opérateur', nom: _ou(r['aideOperateur'])),
        Signature('L’anesthésiste', nom: '${r['anesthesiste']}'),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('crOperatoires');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final k = blocKpisCro(col.actives, c.aujourdhui);
        final actesGyneco = c.magasin
            .collection('catalogueTarifs')
            .actives
            .where((e) => e['famille'] == 'GYNECO')
            .length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bandeauLectureSeule(c),
          kpisBloc([
            KpiSigh(libelle: 'Comptes rendus', valeur: nombre(k.total), icone: LucideIcons.scissors),
            KpiSigh(libelle: 'Ce mois-ci', valeur: nombre(k.mois), icone: LucideIcons.calendar, ton: TonSigh.info),
            KpiSigh(
                libelle: 'Sans aide-opérateur',
                valeur: nombre(k.sansAide),
                icone: LucideIcons.userMinus,
                ton: TonSigh.neutre,
                indice: 'l’aide-opérateur n’est pas obligatoire'),
            KpiSigh(
                libelle: 'Interventions au catalogue',
                valeur: nombre(actesGyneco),
                icone: LucideIcons.list,
                ton: TonSigh.neutre,
                indice: 'actes gynéco-obstétricaux'),
          ]),
          RegistreBloc(
            collection: col,
            entite: 'Compte rendu opératoire',
            prefixeId: 'CRO',
            libelleNouveau: 'Nouveau compte rendu',
            titreNouveau: 'Compte rendu opératoire',
            messageVide: 'Aucun compte rendu opératoire enregistré.',
            lignes: (a) => trierPar([...a], (r) => r['dateOperation']).reversed.toList(),
            champs: (c, _) => champs(c.magasin),
            transformer: construire,
            detail: detail,
            actionsSup: (ctx, r) => [
              BoutonIcone(
                  icone: LucideIcons.printer,
                  libelle: 'Imprimer le compte rendu',
                  onPressed: () => imprimer(ctx, r)),
            ],
            colonnes: [
              const ColonneTableau(cle: 'reference', libelle: 'Référence'),
              ColonneTableau(
                  cle: 'dateOperation',
                  libelle: 'Date',
                  texte: (r) => dateBloc(r['dateOperation']),
                  valeur: (r) => '${r['dateOperation'] ?? ''}'),
              ColonneTableau(
                  cle: 'patient',
                  libelle: 'Patient',
                  texte: (r) => '${r['patient']} — NIP ${_ou(r['nip'])}'),
              const ColonneTableau(cle: 'intervention', libelle: 'Intervention'),
              const ColonneTableau(cle: 'operateur', libelle: 'Opérateur'),
              const ColonneTableau(cle: 'anesthesiste', libelle: 'Anesthésiste'),
            ],
          ),
        ]);
      },
    );
  }
}
