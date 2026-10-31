import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'surv_commun.dart';

/// `m3-rapport` — « Rapport médical » : le compte rendu complet d'un séjour, quatorze rubriques reprises du document officiel. Les HYPOTHÈSES
/// diagnostiques, le diagnostic RETENU et le diagnostic de SORTIE sont trois champs distincts : les fondre ferait perdre le cheminement.
/// E380 : la référence `RAP-` est lue sur le registre (la maquette la tirait d'un compteur de page : doublon à la première création de chaque session).
/// Écart signalé, porté fidèlement (E381) : la modification n'a pas de `transform` — changer le patient laisse son nom, son âge et son adresse d'avant.
class EcranRapport extends StatelessWidget with EcranMaquette {
  const EcranRapport({super.key});

  @override
  String get titre => 'Rapport médical';

  @override
  String get description =>
      'Compte rendu complet d’un séjour : anamnèse, examen physique, diagnostics et traitements.';

  @override
  String get regle =>
      'Les hypothèses diagnostiques, le diagnostic retenu et le diagnostic de sortie sont trois champs distincts, comme sur le formulaire officiel. Les fondre ferait perdre le cheminement, qui est précisément ce qui rend un rapport médical utile. Le rapport s’imprime sous la variante C de l’en-tête, celle du document réel.';

  /// Les rubriques rédigées, dans l'ordre du formulaire officiel (clé, intitulé).
  static const rubriques = [
    ('motif', 'Motif de consultation'),
    ('anamnese', 'Anamnèse'),
    ('examenPhysique', 'Examen physique'),
    ('hypotheses', 'Hypothèses diagnostiques'),
    ('traitementEntree', 'Traitement d’entrée'),
    ('examensParacliniques', 'Examens paracliniques'),
    ('diagnosticRetenu', 'Diagnostic retenu'),
    ('traitementReajuste', 'Traitement réajusté'),
    ('evolution', 'Évolution et traitement des complications'),
    ('traitementSortie', 'Traitement de sortie'),
    ('diagnosticSortie', 'Diagnostic de sortie'),
  ];

  static ChampDef _zone(String nom, String libelle, int lignes, {bool requis = false, String? aide}) => ChampDef(
      nom: nom,
      libelle: libelle,
      type: TypeChamp.textarea,
      lignes: lignes,
      requis: requis,
      aide: aide,
      col: ColChamp.plein);

  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient',
            type: TypeChamp.select,
            requis: true,
            options: optionsPatientsM3(m)),
        const ChampDef(nom: 'dateEntree', libelle: 'Date d’entrée', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'dateSortie', libelle: 'Date de sortie', type: TypeChamp.date),
        _zone('motif', 'Motif de consultation', 2, requis: true),
        _zone('anamnese', 'Anamnèse', 4, requis: true),
        _zone('examenPhysique', 'Examen physique', 5, requis: true),
        _zone('hypotheses', 'Hypothèses diagnostiques', 2,
            requis: true, aide: 'Ce que l’on suspecte à l’entrée — à distinguer du diagnostic retenu.'),
        _zone('traitementEntree', 'Traitement d’entrée', 3, requis: true),
        _zone('examensParacliniques', 'Examens paracliniques', 3),
        _zone('diagnosticRetenu', 'Diagnostic retenu', 2, requis: true, aide: 'Ce que les examens ont confirmé.'),
        _zone('traitementReajuste', 'Traitement réajusté', 4),
        _zone('evolution', 'Évolution et traitement des complications', 4),
        _zone('traitementSortie', 'Traitement de sortie', 3),
        _zone('diagnosticSortie', 'Diagnostic de sortie', 2,
            requis: true, aide: 'Tient compte de l’évolution et des complications.'),
        ChampDef(
            nom: 'medecinId',
            libelle: 'Médecin traitant',
            type: TypeChamp.select,
            requis: true,
            options: optionsSoignants(m, (x) => x['qualite'] == 'medecin')),
      ];

  static Map<String, Object?> initiales(Fiche? r) => r == null
      ? {}
      : {
          for (final k in [
            'patientCode', 'dateEntree', 'dateSortie', 'medecinId',
            for (final x in rubriques) x.$1,
          ])
            k: r[k] ?? ''
        };

  /// Création : la fiche complète (identité recopiée du patient) ; modification : le correctif — exactement les valeurs du formulaire (E381).
  static Fiche construire(Magasin m, CollectionMagasin col, Map<String, Object?> v, Fiche? r, DateTime maintenant) {
    if (r != null) return {...v};
    final pt = patientParCode(m, v['patientCode']);
    return {
      'statut': 'actif',
      ...v,
      'reference': referenceSuivante('RAP-', 4, col.toutes),
      'patientId': pt?['id'],
      'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : v['patientCode'],
      'age': pt != null ? ageAnnees(pt['dateNaissance'], maintenant) : null,
      'sexe': pt?['sexe'],
      'adresse': pt?['quartier'],
      'telephone': pt?['telephone'],
      'medecin': nomSoignant(m, v['medecinId']),
    };
  }

  static void imprimer(BuildContext context, ContexteEcran c, Fiche r) {
    afficherApercu(
        context,
        PieceA4(
            titre: 'RAPPORT MÉDICAL',
            sousTitre: '${r['reference']} — ${r['patient']}',
            cartouche: [
              ('Nom et prénoms', '${r['patient']}'),
              ('Âge', r['age'] != null ? '${r['age']} ans' : '—'),
              ('Sexe', vrai(r['sexe']) ? '${r['sexe']}' : '—'),
              ('Adresse', vrai(r['adresse']) ? '${r['adresse']}' : '—'),
              ('Téléphone', vrai(r['telephone']) ? '${r['telephone']}' : '—'),
              ('Date d’entrée', dateTexte(r['dateEntree'])),
              ('Date de sortie', vrai(r['dateSortie']) ? dateTexte(r['dateSortie']) : '—'),
            ],
            blocs: [
              for (final x in rubriques)
                if (vrai(r[x.$1])) ...[
                  BlocTexte('${x.$2} :', gras: true),
                  BlocTexte('${r[x.$1]}'),
                ],
            ],
            signatures: [Signature('Le Médecin traitant', nom: '${r['medecin']}', mention: 'Signature et cachet')],
            reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: c.aujourdhui));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('rapportsMedicaux');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final clos = rows.where((r) => vrai(r['dateSortie'])).length;
        final tri = trierPar(rows, (r) => r['dateEntree']).reversed.toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Rapports médicaux', valeur: nombre(rows.length), icone: LucideIcons.fileText, ton: TonSigh.navy),
            KpiSigh(libelle: 'Séjours clos', valeur: nombre(clos), icone: LucideIcons.logOut, ton: TonSigh.succes),
            KpiSigh(
                libelle: 'En cours',
                valeur: nombre(rows.length - clos),
                icone: LucideIcons.clock,
                ton: rows.length - clos > 0 ? TonSigh.attention : TonSigh.neutre),
            KpiSigh(
                libelle: 'Rubriques du formulaire',
                valeur: '14',
                icone: LucideIcons.list,
                ton: TonSigh.neutre,
                indice: 'reprises du document officiel'),
          ]),
          const SizedBox(height: 16),
          RegistreFormulaire(
            collection: col,
            lignes: tri,
            prefixe: 'RAP',
            nomExport: 'rapportsMedicaux',
            messageVide: 'Aucun rapport médical enregistré.',
            libelleNouveau: 'Nouveau rapport',
            titreCreation: 'Rapport médical',
            toastCreation: 'Rapport médical créé.',
            tailleCreation: TailleModale.xl,
            champs: (_) => champs(c.magasin),
            initiales: initiales,
            construire: (v, r) => construire(c.magasin, col, v, r, c.aujourdhui),
            titreFiche: (r) => '${r['reference']}',
            actionsLigneSupp: (ctx, r) => [
              BoutonIcone(
                  icone: LucideIcons.printer,
                  libelle: 'Imprimer le rapport',
                  onPressed: () => imprimer(context, c, r)),
            ],
            colonnes: [
              const ColonneTableau(cle: 'reference', libelle: 'Référence'),
              ColonneTableau(
                  cle: 'patient',
                  libelle: 'Patient',
                  texte: (r) => '${r['patient']} — ${r['patientCode']}'),
              ColonneTableau(cle: 'dateEntree', libelle: 'Entrée', texte: (r) => dateTexte(r['dateEntree'])),
              ColonneTableau(
                  cle: 'dateSortie',
                  libelle: 'Sortie',
                  texte: (r) => vrai(r['dateSortie']) ? dateTexte(r['dateSortie']) : 'en cours',
                  rendu: (_, r) => vrai(r['dateSortie'])
                      ? Text(dateTexte(r['dateSortie']))
                      : const BadgeSigh('en cours', ton: TonSigh.attention)),
              const ColonneTableau(cle: 'diagnosticSortie', libelle: 'Diagnostic de sortie'),
              const ColonneTableau(cle: 'medecin', libelle: 'Médecin traitant'),
            ],
            detail: (ctx, x) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DescListeSigh([
                ('Référence', x['reference']),
                ('Patient', x['patient']),
                ('Âge', x['age'] != null ? '${x['age']} ans' : '—'),
                ('Sexe', vrai(x['sexe']) ? x['sexe'] : '—'),
                ('Adresse', vrai(x['adresse']) ? x['adresse'] : '—'),
                ('Téléphone', vrai(x['telephone']) ? x['telephone'] : '—'),
                ('Date d’entrée', dateTexte(x['dateEntree'])),
                ('Date de sortie', vrai(x['dateSortie']) ? dateTexte(x['dateSortie']) : 'séjour en cours'),
                ('Médecin traitant', x['medecin']),
              ]),
              for (final r in rubriques)
                if (vrai(x[r.$1])) sectionDetail(r.$2, paragrapheDetail('${x[r.$1]}')),
            ]),
          ),
        ]);
      },
    );
  }
}
