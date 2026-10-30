import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m1.dart';
import 'fiche.dart';

/// Les champs du dossier patient (`champs(record)` de `m1-patients.js`) : UNE déclaration pour la modale de modification ET la page d'ouverture.
/// Le code (RG-01) n'est PAS un champ : il est attribué et ne se modifie plus — il s'affiche en tête (`enteteCode`).
List<ChampDef> champsPatient(ContexteEcran c, Fiche? r) {
  final quartiers = {
    for (final p in c.magasin.collection('patients').actives)
      if (patVrai(p['quartier'])) '${p['quartier']}'
  }.toList()
    ..sort();
  bool futur(Object? v) {
    final d = dateM1(v);
    return d != null && d.isAfter(c.aujourdhui);
  }

  return [
    const ChampDef.section('Identification'),
    const ChampDef(nom: 'nom', libelle: 'Nom', requis: true),
    const ChampDef(nom: 'prenom', libelle: 'Prénom(s)', requis: true),
    const ChampDef(
        nom: 'sexe',
        libelle: 'Sexe',
        type: TypeChamp.select,
        requis: true,
        options: [OptionChamp('M', 'Masculin'), OptionChamp('F', 'Féminin')]),
    const ChampDef(
        nom: 'naissanceConnue',
        libelle: 'Date de naissance',
        type: TypeChamp.select,
        requis: true,
        recherche: false,
        options: [OptionChamp('date', 'Connue — la saisir'), OptionChamp('age', 'Inconnue — indiquer l’âge déclaré')]),
    ChampDef(
        nom: 'dateNaissance',
        libelle: 'Date de naissance',
        type: TypeChamp.date,
        requis: true,
        condition: (controle: 'naissanceConnue', quand: const ['date']),
        valider: (v, _) => futur(v) ? 'La date ne peut pas être dans le futur.' : null),
    ChampDef(
        nom: 'age',
        libelle: 'Âge déclaré (ans)',
        type: TypeChamp.nombre,
        requis: true,
        condition: (controle: 'naissanceConnue', quand: const ['age']),
        valider: (v, _) {
          final n = num.tryParse('$v');
          return n == null || n < 0 || n > 120 ? 'Âge compris entre 0 et 120 ans.' : null;
        }),
    ChampDef(
        nom: 'groupeSanguin',
        libelle: 'Groupe sanguin',
        type: TypeChamp.select,
        options: [for (final g in patGroupesSanguins) OptionChamp(g)]),
    const ChampDef.section('Coordonnées'),
    const ChampDef(nom: 'telephone', libelle: 'Téléphone', type: TypeChamp.tel, requis: true),
    ChampDef(nom: 'quartier', libelle: 'Quartier', type: TypeChamp.select, options: [for (final q in quartiers) OptionChamp(q)]),
    const ChampDef(nom: 'adresse', libelle: 'Adresse', col: ColChamp.plein),
    const ChampDef(nom: 'personneAPrevenir', libelle: 'Personne à prévenir', col: ColChamp.plein),
    const ChampDef.section('Éléments médicaux'),
    ChampDef(
        nom: 'antecedents',
        libelle: 'Antécédents',
        type: TypeChamp.multiselect,
        col: ColChamp.plein,
        options: [for (final a in patAntecedents) if (a != 'Aucun antécédent notable') OptionChamp(a)],
        aide: 'Repris automatiquement sur toute prescription et à la dispensation en pharmacie. Laisser vide si aucun antécédent notable.'),
    const ChampDef(nom: 'antecedentsAutres', libelle: 'Autres antécédents (texte libre)', col: ColChamp.plein),
    ChampDef(
        nom: 'allergies',
        libelle: 'Allergies connues',
        type: TypeChamp.multiselect,
        col: ColChamp.plein,
        options: [for (final a in patAllergies) if (a != 'Aucune allergie connue') OptionChamp(a)],
        aide: 'Toute allergie déclarée bloque la délivrance du produit correspondant (M6). Laisser vide si aucune allergie connue.'),
    const ChampDef(nom: 'traitementEnCours', libelle: 'Traitement en cours', col: ColChamp.plein),
    const ChampDef.section('Couverture assurance (M9)'),
    ChampDef(
        nom: 'assureur',
        libelle: 'Compagnie d’assurance',
        type: TypeChamp.select,
        options: [for (final a in patAssureurs) OptionChamp(a.$1, a.$2)]),
    const ChampDef(nom: 'numeroPolice', libelle: 'Numéro de police'),
    const ChampDef(nom: 'tauxPriseEnCharge', libelle: 'Taux de prise en charge (%)', type: TypeChamp.nombre),
    const ChampDef(
        nom: 'carteExpiration',
        libelle: 'Expiration de la carte',
        type: TypeChamp.date,
        aide: 'RG-09 — au-delà de cette date, la facturation est intégrale au patient.'),
  ];
}

/// Les valeurs du formulaire pour un dossier : la branche « âge déclaré » se lit SUR LA FICHE (rouvrir un dossier sans date doit proposer « Inconnue »).
Map<String, Object?> valeursPatient(Fiche? r) {
  if (r == null) return {'naissanceConnue': 'date', 'tauxPriseEnCharge': '0'};
  final v = valeursFormulaire(r);
  v['naissanceConnue'] = (!patVrai(r['dateNaissance']) && r['age'] != null && r['age'] != '') ? 'age' : 'date';
  v['antecedents'] = patListe(r['antecedents']);
  v['allergies'] = patListe(r['allergies']);
  return v;
}

/// RG-01, en tête du formulaire : le code est attribué d'office et ne se modifie plus.
Widget enteteCode(String code) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const LibelleChamp('Code dossier'),
      Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
              color: JetonsShell.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: JetonsShell.slate300)),
          child: Text(code, key: const Key('m1:code'), style: monoM1.copyWith(fontSize: 14, color: JetonsShell.slate900))),
      const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('RG-01 — attribué automatiquement au format CNT/[n° d’ordre]/[année] ; non modifiable après création.',
              style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
    ]));

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m1-patients
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranPatients extends StatelessWidget with EcranMaquette {
  const EcranPatients({super.key});

  @override
  String get description =>
      'Dossier patient unique et centralisé : identification, coordonnées, couverture assurance, historique médical et financier.';

  @override
  String get regle =>
      'RG-01 — Chaque patient est identifié par un code unique au format CNT/[n° d’ordre]/[année], généré automatiquement et non modifiable après création.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Plan de numérisation',
          icone: LucideIcons.scanLine,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m1-numerisation')),
    ];
  }

  static Widget _celluleAssurance(BuildContext ctx, Fiche r, bool ok) {
    if (!patVrai(r['assureur'])) return const BadgeSigh('Non assuré');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        BadgeSigh('${r['assureur']}', ton: TonSigh.navy),
        ok
            ? const BadgeSigh('Carte valide', ton: TonSigh.succes)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: JetonsShell.danger50, borderRadius: BorderRadius.circular(4)),
                child: const Text('CARTE NON VALIDE',
                    style: TextStyle(color: JetonsShell.danger700, fontSize: 10, height: 15 / 10, fontWeight: FontWeight.w600))),
      ]),
      Text('${r['souscripteur'] ?? ''}', style: styleM1(t: 12, c: JetonsShell.slate400)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('patients');
    final couvertures = c.magasin.collection('couverturesAssurance').actives;
    bool valide(Fiche r) => patCarteValide(r, couvertures, c.aujourdhui);
    final colonnes = <ColonneTableau>[
      ColonneTableau(
          cle: 'code',
          libelle: 'Code dossier',
          sansCoupure: true,
          rendu: (_, r) => Text('${r['code']}',
              style: monoM1.copyWith(color: JetonsShell.navy800, fontWeight: FontWeight.w600)),
          texte: (r) => '${r['code']}'),
      ColonneTableau(
          cle: 'nom',
          libelle: 'Patient',
          valeur: (r) => '${r['nom']} ${r['prenom']}',
          texte: (r) => '${r['nom']} ${r['prenom']}',
          rendu: (_, r) {
            final age = patAge(r, c.aujourdhui);
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: JetonsShell.slate100, shape: BoxShape.circle),
                  child: Text(initiales('${r['nom']} ${r['prenom']}'),
                      style: const TextStyle(color: JetonsShell.slate600, fontSize: 10, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${r['nom']} ${r['prenom']}',
                    overflow: TextOverflow.ellipsis, style: styleM1(c: JetonsShell.slate800, p: FontWeight.w500)),
                Text('${r['sexe'] == 'F' ? 'Femme' : 'Homme'} — ${age != null ? '$age ans' : '—'}',
                    style: styleM1(t: 12, c: JetonsShell.slate400)),
              ])),
            ]);
          }),
      const ColonneTableau(cle: 'telephone', libelle: 'Téléphone', sansCoupure: true),
      const ColonneTableau(cle: 'quartier', libelle: 'Quartier'),
      const ColonneTableau(cle: 'groupeSanguin', libelle: 'Groupe', droite: true),
      ColonneTableau(
          cle: 'assureur',
          libelle: 'Assurance',
          texte: (r) => !patVrai(r['assureur'])
              ? 'Non assuré'
              : '${r['assureurNom'] ?? r['assureur']} — ${valide(r) ? 'carte valide' : 'carte non valide'}',
          rendu: (ctx, r) => _celluleAssurance(ctx, r, valide(r))),
      ColonneTableau(
          cle: 'dateCreation',
          libelle: 'Créé le',
          sansCoupure: true,
          texte: (r) => dateFrM1(r['dateCreation']),
          valeur: (r) => r['dateCreation']),
    ];
    final quartiers = {
      for (final p in col.actives)
        if (patVrai(p['quartier'])) '${p['quartier']}'
    }.toList()
      ..sort();
    final filtres = [
      const FiltreTableau(
          nom: 'sexe', libelle: 'Sexe', options: [OptionChamp('M', 'Masculin'), OptionChamp('F', 'Féminin')]),
      FiltreTableau(
          nom: 'couverture',
          libelle: 'Couverture',
          options: const [OptionChamp('assure', 'Assurés'), OptionChamp('non', 'Non assurés'), OptionChamp('expiree', 'Carte expirée')],
          correspond: (r, v) => patFiltreCouverture(r, v, couvertures, c.aujourdhui)),
      FiltreTableau(
          nom: 'quartier',
          libelle: 'Quartier',
          options: [for (final q in quartiers) OptionChamp(q)],
          correspond: (r, v) => r['quartier'] == v),
    ];
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final k = patKpisRepertoire(col.actives, couvertures, c.aujourdhui);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Dossiers actifs', valeur: nombre(k.actifs), icone: LucideIcons.users),
              KpiSigh(libelle: 'Créés en 2026', valeur: nombre(k.crees2026), icone: LucideIcons.userPlus, ton: TonSigh.succes),
              KpiSigh(
                  libelle: 'Patients assurés',
                  valeur: nombre(k.assures),
                  icone: LucideIcons.shieldCheck,
                  ton: TonSigh.info,
                  indice: '${k.partAssures} du répertoire'),
              KpiSigh(
                  libelle: 'Cartes expirées',
                  valeur: nombre(k.expirees),
                  icone: LucideIcons.shieldAlert,
                  ton: k.expirees > 0 ? TonSigh.danger : TonSigh.neutre,
                  indice: 'Facturation intégrale (RG-09)'),
            ]),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(
                  id: 'liste',
                  libelle: 'Tous les patients',
                  compte: col.actives.length,
                  construire: (ctx) => RegistreM1(
                      collection: col,
                      colonnes: colonnes,
                      filtres: filtres,
                      entite: 'Patient',
                      libelleNouveau: 'Nouveau',
                      creerVers: 'm1-patient-nouveau',
                      champs: champsPatient,
                      valeursInitiales: (_) => valeursPatient(null),
                      libelleRecherche: 'Rechercher un patient…',
                      messageVide: 'Aucun patient enregistré.',
                      triInitial: 'code',
                      transformer: (cc, s, e) {
                        final v = patTransformerPatient(s, e, cc.aujourdhui);
                        return v;
                      },
                      detail: (cc, f) => FichePatient(f),
                      titreDetail: (f) => '${f['nom']} ${f['prenom']}',
                      sousTitreDetail: (f) => '${f['code']} — ${f['quartier'] ?? ''}',
                      etat: (cc, f) => imprimerFichePatient(cc, f),
                      titreModification: 'Modifier l’enregistrement')),
              OngletDef(
                  id: 'archives',
                  libelle: 'Archivés',
                  compte: col.archivees.length,
                  construire: (ctx) => RegistreM1(
                      collection: col,
                      archive: true,
                      colonnes: colonnes,
                      entite: 'Patient',
                      libelleRecherche: 'Rechercher un patient…',
                      messageVide: 'Aucun enregistrement archivé.')),
            ]),
          ]);
        });
  }
}

/// L'état imprimable de la fiche patient (`etatFiche`).
void imprimerFichePatient(BuildContext ctx, Fiche p) {
  final c = ContexteEcran.of(ctx);
  final consultations = trierPar([
    for (final x in c.magasin.collection('consultations').actives)
      if (x['patientId'] == p['id']) x
  ], (x) => x['date'], descendant: true);
  final age = ageTexte(p, c.aujourdhui);
  imprimerM1(ctx,
      titre: 'Fiche patient',
      sousTitre: 'Dossier ${p['code']}',
      cartouche: [
        ('Patient', '${p['nom']} ${p['prenom']}'),
        ('Code dossier', '${p['code']}'),
        ('Âge', age),
        ('Groupe sanguin', patVrai(p['groupeSanguin']) ? '${p['groupeSanguin']}' : '—'),
      ],
      blocs: [
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Rubrique', valeur: (l) => l['k']),
          ColonneEtat(libelle: 'Information', valeur: (l) => l['v']),
        ], lignes: [
          {'k': 'Code dossier', 'v': p['code']},
          {'k': 'Nom et prénoms', 'v': '${p['nom']} ${p['prenom']}'},
          {'k': 'Sexe', 'v': p['sexe'] == 'F' ? 'Féminin' : 'Masculin'},
          {'k': 'Âge', 'v': age},
          {'k': 'Groupe sanguin', 'v': patVrai(p['groupeSanguin']) ? p['groupeSanguin'] : '—'},
          {'k': 'Antécédents', 'v': patTexteListe(p['antecedents'], 'Aucun antécédent notable')},
          {'k': 'Allergies connues', 'v': patTexteListe(p['allergies'], 'Aucune allergie connue')},
          {'k': 'Traitement en cours', 'v': patVrai(p['traitementEnCours']) ? p['traitementEnCours'] : '—'},
          {'k': 'Téléphone', 'v': p['telephone']},
          {'k': 'Adresse', 'v': patVrai(p['adresse']) ? p['adresse'] : p['quartier']},
          {'k': 'Personne à prévenir', 'v': patVrai(p['personneAPrevenir']) ? p['personneAPrevenir'] : '—'},
          {
            'k': 'Assurance',
            'v': patVrai(p['assureurNom'])
                ? '${p['assureurNom']} — ${p['tauxPriseEnCharge']} % (carte au ${dateFrM1(p['carteExpiration'])})'
                : 'Aucune'
          },
        ])),
        if (consultations.isNotEmpty)
          BlocTableau(
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Date', valeur: (l) => dateFrM1(l['date'])),
                ColonneEtat(libelle: 'Motif', valeur: (l) => l['motif']),
                ColonneEtat(libelle: 'Diagnostic', valeur: (l) => l['diagnostic']),
                ColonneEtat(libelle: 'Médecin', valeur: (l) => l['medecin']),
              ], lignes: consultations.take(20).toList()),
              titre: 'Historique des consultations'),
      ],
      signatures: const [Signature('Le Secrétaire Médical'), Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko')]);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m1-patient-nouveau — la page d'ouverture d'un dossier
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranPatientNouveau extends StatefulWidget with EcranMaquette {
  const EcranPatientNouveau({super.key});

  @override
  String get description =>
      'Identité, coordonnées, âge déclaré à défaut de date de naissance et couverture d’assurance — le premier acte du parcours.';

  @override
  String get regle =>
      'RG-01 — le code CNT/[n° d’ordre]/[année] est attribué d’office et ne se modifie plus. Il est réservé à l’ouverture de l’écran : deux guichets qui saisissent en même temps n’obtiennent pas le même numéro.';

  @override
  State<EcranPatientNouveau> createState() => _EtatPatientNouveau();
}

class _EtatPatientNouveau extends State<EcranPatientNouveau> {
  ControleurFormulaire? _f;
  List<ChampDef> _champs = const [];
  String _code = '';

  void _preparer(ContexteEcran c) {
    if (_f != null) return;
    _champs = champsPatient(c, null);
    _f = ControleurFormulaire(_champs, valeursPatient(null));
    // Le code est réservé à l'ouverture de l'écran.
    _code = patProchainCode(c.magasin.collection('patients').toutes, c.aujourdhui);
  }

  Widget _etape(String titre, String detail, String date, Color couleur) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(width: 10, height: 10, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle))),
        const SizedBox(width: 10),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: styleM1(p: FontWeight.w500, c: JetonsShell.slate800)),
          Text(detail, style: styleM1(t: 12, c: JetonsShell.slate500)),
          Text(date, style: const TextStyle(color: JetonsShell.slate400, fontSize: 11, height: 15 / 11)),
        ])),
      ]));

  void _enregistrer(ContexteEcran c) {
    final brut = _f!.valider();
    if (brut == null) {
      ToastsSigh.afficher(context, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final col = c.magasin.collection('patients');
    final refus = patRefusCode(col.toutes, _code);
    if (refus != null) {
      ToastsSigh.afficher(context, refus, type: TypeToast.erreur);
      return;
    }
    final v = patTransformerPatient(convertirSaisie(_champs, brut), null, c.aujourdhui);
    final r = col.inserer({
      'statut': 'actif',
      'code': _code,
      'dateCreation': iso(c.aujourdhui),
      ...v,
    }, prefixe: 'PAT');
    ToastsSigh.afficher(context, 'Dossier patient créé.',
        type: TypeToast.succes, detail: '${r.fiche['code']}', duree: const Duration(seconds: 7));
    c.aller('m1-patients');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh(
            'Votre profil consulte le répertoire sans y ouvrir de dossier. L’ouverture appartient à l’accueil (RG-13).',
            ton: TonSigh.attention,
            icone: LucideIcons.lock),
        const SizedBox(height: 12),
        BoutonSigh(
            libelle: 'Revenir au registre',
            icone: LucideIcons.arrowLeft,
            variante: VarianteBouton.secondaire,
            onPressed: () => c.aller('m1-patients')),
      ]);
    }
    _preparer(c);
    final principal = CarteSigh(
        titre: 'Identité, coordonnées et couverture',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          enteteCode(_code),
          FormulaireSigh(controleur: _f!),
        ]));
    final aside = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Enchaînement du parcours',
          child: Column(children: [
            _etape('Ouverture du dossier', 'Identité, coordonnées, couverture — vous y êtes', 'Étape 1', JetonsShell.navy700),
            _etape('Constantes à l’accueil', 'Température, tension, poids, pouls — reprises ensuite en consultation (M1)', 'Étape 2', JetonsShell.info600),
            _etape('File d’attente', 'Le patient est appelé au cabinet ou au poste concerné (M2)', 'Étape 3', JetonsShell.info600),
            _etape('Dossier puis fiche de consultation', 'Le geste clinique, et la prescription (M2)', 'Étape 4', JetonsShell.slate600),
            _etape('Caisse', 'Facture globale ; la couverture saisie ici décide de la part patient (M8)', 'Étape 5', JetonsShell.warning600),
          ])),
      const SizedBox(height: 16),
      const CarteSigh(
          titre: 'Ce que l’ouverture engage',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            NoteSigh(
                'RG-01 — le code est unique et non modifiable. Les dossiers antérieurs gardent l’ancien format : renuméroter romprait le lien avec l’archive papier.',
                icone: LucideIcons.idCard),
            SizedBox(height: 12),
            NoteSigh(
                'RG-09 — une carte d’assurance n’ouvre droit à la prise en charge que si elle est valide à la date de facturation. Saisir la validité ici évite un litige au guichet.',
                ton: TonSigh.attention,
                icone: LucideIcons.shieldAlert),
            SizedBox(height: 12),
            NoteSigh(
                '« Je ne connais pas ma date de naissance » est la réponse ordinaire au guichet : l’âge déclaré est prévu pour cela. Inscrire un 1ᵉʳ janvier de fantaisie le ferait ressortir sur chaque pièce comme un fait établi.',
                ton: TonSigh.neutre,
                icone: LucideIcons.calendar),
          ])),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (_, w) => w.maxWidth >= 1024
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: principal),
              const SizedBox(width: 16),
              Expanded(child: aside),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [principal, const SizedBox(height: 16), aside])),
      const SizedBox(height: 16),
      Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate200))),
          child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            BoutonSigh(
                libelle: 'Annuler',
                icone: LucideIcons.x,
                variante: VarianteBouton.secondaire,
                onPressed: () => c.aller('m1-patients')),
            BoutonSigh(
                libelle: 'Ouvrir le dossier',
                icone: LucideIcons.plus,
                onPressed: () => _enregistrer(c)),
          ])),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m1-patient-profil
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranPatientProfil extends StatefulWidget with EcranMaquette {
  const EcranPatientProfil({super.key});

  @override
  String get description =>
      'Vue consolidée d’un dossier : administratif, médical, hospitalisations, financier et assurance.';

  @override
  State<EcranPatientProfil> createState() => _EtatProfil();
}

class _EtatProfil extends State<EcranPatientProfil> {
  ControleurFormulaire? _sel;

  @override
  void dispose() {
    _sel?.dispose();
    super.dispose();
  }

  void _modifier(BuildContext ctx, ContexteEcran c, Fiche p) {
    final defs = champsPatient(c, p);
    final ctl = ControleurFormulaire(defs, valeursPatient(p));
    afficherModale<void>(ctx,
        titre: 'Modifier l’enregistrement',
        sousTitre: '${p['code']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          enteteCode('${p['code']}'),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final brut = ctl.valider();
                    if (brut == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    // La MÊME transformation que le répertoire (écart E315).
                    final v = patTransformerPatient(convertirSaisie(defs, brut), p, c.aujourdhui);
                    fermer();
                    final annuler = c.magasin.collection('patients').mettreAJour(p['id'], v);
                    ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler);
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('patients');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final tries = trierPar([...col.actives], (p) => p['code']);
          _sel ??= ControleurFormulaire([
            ChampDef(
                nom: 'dossier',
                libelle: 'Sélectionner un dossier patient',
                type: TypeChamp.select,
                col: ColChamp.plein,
                options: [for (final p in tries) OptionChamp('${p['id']}', '${p['nom']} ${p['prenom']} — ${p['code']} — ${p['quartier'] ?? ''}')])
          ], {
            'dossier': tries.isEmpty ? '' : '${tries.first['id']}'
          });
          return ListenableBuilder(
              listenable: _sel!,
              builder: (context, _) {
                final courant = tries.where((p) => '${p['id']}' == '${_sel!['dossier']}').firstOrNull ?? tries.firstOrNull;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CarteSigh(
                      child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 448, minWidth: 280),
                        child: FormulaireSigh(controleur: _sel!)),
                    if (!c.droit.editer)
                      const NoteSigh(
                          'Lecture seule — votre profil consulte le dossier sans le modifier. Ce périmètre est fixé par la matrice des droits (écran Rôles & permissions), non par cet écran.',
                          ton: TonSigh.neutre,
                          icone: LucideIcons.lock),
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Modifier le dossier',
                          icone: LucideIcons.pencil,
                          onPressed: courant == null ? null : () => _modifier(context, c, courant)),
                    BoutonSigh(
                        libelle: 'Fiche de consultation',
                        icone: LucideIcons.clipboardList,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => c.aller('m2-consultation-fiche')),
                    BoutonSigh(
                        libelle: 'Documents numérisés',
                        icone: LucideIcons.paperclip,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => c.aller('m1-documents')),
                    BoutonSigh(
                        libelle: 'Imprimer la fiche',
                        icone: LucideIcons.printer,
                        variante: VarianteBouton.secondaire,
                        onPressed: courant == null ? null : () => imprimerFichePatient(context, courant)),
                    BoutonSigh(
                        libelle: 'Retour au répertoire',
                        icone: LucideIcons.arrowLeft,
                        variante: VarianteBouton.fantome,
                        onPressed: () => c.aller('m1-patients')),
                  ])),
                  const SizedBox(height: 16),
                  courant == null
                      ? const VideSigh('Aucun patient enregistré.', icone: LucideIcons.users)
                      : FichePatient(courant, key: ValueKey('${courant['id']}:${courant['_modifieLe']}')),
                ]);
              });
        });
  }
}
