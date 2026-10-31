import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cr_commun.dart';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// L'en-tête : une MODALE (quinze secondes, debout) ; le compte rendu : une PAGE (dix minutes, toute la largeur)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `champsEnteteCR(mod, opts)`. Le prescripteur peut être EXTÉRIEUR à la clinique (c'est ce qui permet de lui renvoyer le compte rendu) ; la DDR
/// est une donnée d'échographie ; la provenance s'ouvre selon la modalité.
List<ChampDef> champsEnteteCR(Magasin m, ModaliteImagerie mod,
    {String indicationHint = ''}) {
  final patients = trierPar(m.collection('patients').actives, (p) => p['code']);
  final soignants = m.collection('soignants').actives;
  return [
    ChampDef(
        nom: 'examenCode',
        libelle: 'Examen',
        type: TypeChamp.select,
        requis: true,
        options: [
          for (final x in examensImagerie(m))
            if (modaliteDeExamen(x) == mod.code)
              OptionChamp('${x['code']}', '${x['label']}')
        ]),
    ChampDef(
        nom: 'patientCode',
        libelle: 'Patient',
        type: TypeChamp.select,
        requis: true,
        options: [
          for (final p in patients)
            OptionChamp(
                '${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
        ]),
    ChampDef(
        nom: 'indication',
        libelle: 'Indication',
        requis: true,
        aide: indicationHint.isNotEmpty
            ? indicationHint
            : 'Ce que le prescripteur cherche.'),
    ChampDef(
        nom: 'prescripteurId',
        libelle: 'Prescripteur',
        type: TypeChamp.select,
        requis: true,
        options: [
          for (final s in soignants)
            if (s['prescrit'] == true)
              OptionChamp('${s['id']}', '${s['nomComplet']} — ${s['poste']}'),
          const OptionChamp(
              prescripteurExterne, '— Prescripteur extérieur à la clinique —'),
        ]),
    const ChampDef(
        nom: 'prescripteurIdExterne',
        libelle: 'Prescripteur extérieur — nom, qualification et structure',
        col: ColChamp.plein,
        condition: (controle: 'prescripteurId', quand: [prescripteurExterne]),
        aide:
            'Ex. : Dr SALIFOU Aminou, médecin généraliste, Centre de santé de Perma. C’est ce qui permet de lui renvoyer le compte rendu.'),
    ChampDef(
        nom: 'realisateurId',
        libelle: 'Réalisé par',
        type: TypeChamp.select,
        requis: true,
        options: [
          for (final s in soignants)
            if (s['realiseImagerie'] == true || s['qualite'] == 'medecin')
              OptionChamp('${s['id']}', '${s['nomComplet']} — ${s['poste']}'),
        ]),
    if (mod.code == 'echographie')
      const ChampDef(
          nom: 'ddr',
          libelle: 'DDR — date des dernières règles',
          aide:
              'Laisser « inconnue » si la patiente ne la connaît pas — c’est le cas sur les pièces réelles.'),
    if (mod.provenance)
      const ChampDef(
          nom: 'provenance',
          libelle: 'Provenance',
          aide: 'Service ou établissement d’où vient le patient.'),
    const ChampDef(
        nom: 'condition',
        libelle: 'Condition de l’examen',
        type: TypeChamp.select,
        options: [
          OptionChamp('Bonne'),
          OptionChamp('Moyenne'),
          OptionChamp('Difficile'),
        ]),
  ];
}

/// `modaleEnteteCR(mod, {retour, indicationHint})` : sa validation OUVRE la page de saisie — elle n'enregistre rien. L'en-tête est déposé pour le
/// chargement suivant (jamais dans l'adresse : il porte un nom de prescripteur extérieur en toutes lettres).
Future<void> modaleEnteteCR(BuildContext ecran, ModaliteImagerie mod,
    {String? retour, String indicationHint = ''}) {
  final c = ContexteEcran.of(ecran);
  final ctl = ControleurFormulaire(
      champsEnteteCR(c.magasin, mod, indicationHint: indicationHint),
      {'ddr': 'inconnue', 'condition': 'Bonne'});
  return afficherModale<void>(ecran,
      titre: 'Nouveau compte rendu — ${mod.label}',
      sousTitre:
          'L’examen et le patient d’abord ; la rédaction s’ouvre ensuite en pleine page.',
      taille: TailleModale.lg,
      corps: FormulaireSigh(controleur: ctl),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: 'Continuer vers la saisie',
                icone: LucideIcons.arrowRight,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(
                        ecran, 'L’en-tête comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  AdresseCompteRendu.enAttente = AdresseCompteRendu(
                      nouveau: true,
                      modalite: mod.code,
                      retour: retour ?? mod.ecran,
                      entete: v);
                  fermer();
                  c.aller('m2-imagerie-cr');
                }),
          ]);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le corps du compte rendu — RÉUTILISABLE (modale ou page)
// ---------------------------------------------------------------------------------------------------------------------------------------------

ChampDef _champDef(ChampCR c) => ChampDef(
      nom: c.nom,
      libelle: c.libelle,
      type: switch (c.genre) {
        GenreChampCR.texte => TypeChamp.texte,
        GenreChampCR.nombre => TypeChamp.nombre,
        GenreChampCR.selection => TypeChamp.select,
        GenreChampCR.multiple => TypeChamp.multiselect,
        GenreChampCR.zone => TypeChamp.textarea,
      },
      lignes: 3,
      options: [for (final o in c.options) OptionChamp(o)],
      condition:
          c.controle == null ? null : (controle: c.controle!, quand: c.quand),
    );

/// `corpsCR(rec)` : une CARTE par rubrique (un compte rendu de trente champs, sans elles, fait remplir la taille d'un ovaire dans la ligne du
/// cul-de-sac), les exemplaires n°2 et n°3 REPLIABLES et présents seulement si le nombre déclaré les appelle, puis les rubriques RÉDIGÉES.
class CorpsCR extends StatefulWidget {
  const CorpsCR(
      {super.key,
      required this.examenCode,
      required this.valeursInitiales,
      required this.rubriquesInitiales});
  final String examenCode;
  final Map<String, Object?> valeursInitiales;

  /// La valeur de départ de chaque rubrique rédigée (`rec[r.code]`).
  final Map<String, Object?> rubriquesInitiales;

  @override
  State<CorpsCR> createState() => CorpsCRState();
}

class _BlocForm {
  _BlocForm(this.rubrique, this.principal, this.exemplaires, this.controle);
  final String rubrique;
  final ControleurFormulaire principal;
  final Map<int, ControleurFormulaire> exemplaires;
  final String? controle;
}

class CorpsCRState extends State<CorpsCR> {
  late List<RubriqueLibre> _libres;
  late List<_BlocForm> _blocs;
  late List<ControleurFormulaire> _libresCtl;
  bool _pret = false;

  void _preparer(Magasin m) {
    _pret = true;
    final vars = variablesDe(m, widget.examenCode);
    _libres = libresDe(m, widget.examenCode);
    final texte = saisieTexteDe(examensImagerie(m), widget.examenCode);
    final plan = planSaisieCR(vars, texte: texte, libres: _libres);
    _blocs = [
      for (final r in plan.rubriques)
        _BlocForm(
            r.rubrique,
            ControleurFormulaire([for (final c in r.champs) _champDef(c)],
                widget.valeursInitiales),
            {
              for (final e in r.exemplaires.entries)
                e.key: ControleurFormulaire(
                    [for (final c in e.value) _champDef(c)],
                    widget.valeursInitiales)
            },
            r.controle)
    ];
    _libresCtl = [
      for (final l in _libres)
        ControleurFormulaire([
          ChampDef(
              nom: l.code,
              libelle: l.label,
              type: TypeChamp.textarea,
              lignes: 4,
              requis: l.requis,
              aide: l.note)
        ], {
          l.code: widget.rubriquesInitiales[l.code] ?? ''
        })
    ];
    for (final k in _tous) {
      k.addListener(() => setState(() {}));
    }
  }

  Iterable<ControleurFormulaire> get _tous => [
        for (final b in _blocs) ...[b.principal, ...b.exemplaires.values],
        ..._libresCtl,
      ];

  @override
  void dispose() {
    if (_pret) {
      for (final k in _tous) {
        k.dispose();
      }
    }
    super.dispose();
  }

  /// `controle(nom)` : le champ qui commande un bloc répété vit dans UN des formulaires principaux.
  Object? _valeurDe(String? nom) {
    if (nom == null) return null;
    for (final b in _blocs) {
      if (b.principal.champs.any((c) => c.nom == nom)) return b.principal[nom];
    }
    return null;
  }

  /// `enregistrer()` : relève tous les formulaires. Un bloc masqué (sac non déclaré) ou une précision masquée ne s'enregistrent pas — une valeur
  /// invisible est une valeur qu'on ne relira jamais, et qu'on imprimerait pourtant. `null` : le formulaire comporte des erreurs.
  Map<String, Object?>? releve() {
    var erreur = false;
    final v = <String, Object?>{};
    for (final b in _blocs) {
      final bloc = b.principal.valider();
      if (bloc == null) {
        erreur = true;
      } else {
        v.addAll(bloc);
      }
      for (final e in b.exemplaires.entries) {
        if (!exemplaireVisible(_valeurDe(b.controle), e.key)) continue;
        final x = e.value.valider();
        if (x == null) {
          erreur = true;
        } else {
          v.addAll(x);
        }
      }
    }
    for (final k in _libresCtl) {
      final x = k.valider();
      if (x == null) {
        erreur = true;
      } else {
        v.addAll(x);
      }
    }
    return erreur ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    if (!_pret) _preparer(ContexteEcran.of(context).magasin);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final b in _blocs) ...[
        CarteSigh(
            titre: b.rubrique,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormulaireSigh(controleur: b.principal),
                  for (final e in b.exemplaires.entries)
                    if (exemplaireVisible(_valeurDe(b.controle), e.key)) ...[
                      const SizedBox(height: 12),
                      _Repliable(
                          key: Key('cr:exemplaire:${b.rubrique}|${e.key}'),
                          resume: '${b.rubrique} n°${e.key}',
                          child: FormulaireSigh(controleur: e.value)),
                    ],
                ])),
        const SizedBox(height: 16),
      ],
      for (final (i, l) in _libres.indexed) ...[
        CarteSigh(
            titre: l.label, child: FormulaireSigh(controleur: _libresCtl[i])),
        if (i < _libres.length - 1) const SizedBox(height: 16),
      ],
    ]);
  }
}

/// Le bloc `details` de la maquette : ouvert d'emblée, repliable, fond slate-50 et filet navy.
class _Repliable extends StatefulWidget {
  const _Repliable({super.key, required this.resume, required this.child});
  final String resume;
  final Widget child;
  @override
  State<_Repliable> createState() => _EtatRepliable();
}

class _EtatRepliable extends State<_Repliable> {
  bool _ouvert = true;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: JetonsShell.slate50,
            border: Border.all(color: JetonsShell.navy200),
            borderRadius: BorderRadius.circular(8)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
              onTap: () => setState(() => _ouvert = !_ouvert),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(widget.resume,
                      style: const TextStyle(
                          color: JetonsShell.navy800,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600)))),
          if (_ouvert)
            Container(
                decoration: const BoxDecoration(
                    border:
                        Border(top: BorderSide(color: JetonsShell.slate200))),
                padding: const EdgeInsets.all(12),
                child: widget.child),
        ]),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La page : m2-imagerie-cr
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `m2-imagerie-cr` — le compte rendu en PAGE PLEINE. La page montre tout d'un bloc (en-tête ET variables) et n'écrit qu'à l'enregistrement : un
/// compte rendu ne doit pas exister au registre tant que personne ne l'a écrit, sinon chaque saisie ouverte puis abandonnée y laisserait un brouillon
/// vide. UNE page pour les cinq modalités : elle lit sa modalité dans son adresse.
class EcranCompteRenduImagerie extends StatefulWidget with EcranMaquette {
  const EcranCompteRenduImagerie({super.key});

  @override
  String get titre => 'Compte rendu d’imagerie';

  @override
  String get description =>
      'En-tête et variables d’un compte rendu d’imagerie — échographie, radiographie, mammographie, scanner ou IRM.';

  @override
  String get regle =>
      'Le compte rendu porte le prescripteur (qui peut être extérieur à la clinique), le réalisateur et la provenance. Les mesures se saisissent en texte, et un champ de précision n’apparaît que lorsque la valeur l’appelle. Rien n’est écrit au registre tant que l’enregistrement n’a pas eu lieu.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.maybeOf(context);
    if (c == null || !c.droit.editer) return const [];
    return [
      BoutonSigh(
          libelle: 'Enregistrer le compte rendu',
          icone: LucideIcons.save,
          taille: TailleBouton.sm,
          onPressed: () => _EtatCompteRendu._courant?.enregistrer()),
    ];
  }

  @override
  State<EcranCompteRenduImagerie> createState() => _EtatCompteRendu();
}

class _EtatCompteRendu extends State<EcranCompteRenduImagerie> {
  static _EtatCompteRendu? _courant;

  final _corps = GlobalKey<CorpsCRState>();
  late AdresseCompteRendu _adresse;
  Fiche? _rec;
  bool _pret = false;
  bool _enregistre = false;

  @override
  void dispose() {
    if (_courant == this) _courant = null;
    super.dispose();
  }

  void _preparer(ContexteEcran c) {
    _pret = true;
    _courant = this;
    _adresse = AdresseCompteRendu.consommer();
    _rec = _adresse.id != null ? colCR(c.magasin).parId(_adresse.id) : null;
  }

  String _retour(ModaliteImagerie mod) => _adresse.retour ?? mod.ecran;

  /// `enregistrer()` : une fiche existante est mise à jour ; une fiche NOUVELLE naît ICI (jamais à la validation de la modale), et si la saisie
  /// est refusée la fiche qu'on venait d'ouvrir est archivée — aucun brouillon vide ne reste au registre (RG-14).
  void enregistrer() {
    if (!mounted || _enregistre) return;
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) return;
    final m = c.magasin;
    final col = colCR(m);
    final rec = _rec;
    final entete = _adresse.entete;
    if (rec == null && entete == null) {
      ToastsSigh.afficher(context,
          'Aucun en-tête relevé : rouvrez la saisie depuis le tableau.',
          type: TypeToast.attention, duree: const Duration(seconds: 8));
      return;
    }
    final corps = _corps.currentState;
    if (corps == null) return;
    final maintenant = c.aujourdhui.toUtc().toIso8601String();
    final releve = corps.releve();
    if (releve == null) {
      ToastsSigh.afficher(context, 'Le formulaire comporte des erreurs.',
          type: TypeToast.erreur);
      return;
    }
    final examenCode =
        rec != null ? '${rec['examenCode']}' : '${entete!['examenCode']}';
    final libres = libresDe(m, examenCode);
    Fiche fiche;
    if (rec != null) {
      fiche = rec;
    } else {
      final e = entete!;
      final pt = m
          .collection('patients')
          .actives
          .where((x) => x['code'] == e['patientCode'])
          .firstOrNull;
      final ex =
          examensImagerie(m).where((x) => x['code'] == examenCode).firstOrNull;
      fiche = col
          .inserer(
              ficheDepuisEntete(e,
                  reference: referenceSuivante('IMG-', 4, col.toutes),
                  dateIso: maintenant,
                  examenLibelle: ex != null ? '${ex['label']}' : examenCode,
                  patient: pt,
                  age: ageDePatient(pt, c.aujourdhui),
                  prescripteur:
                      nomPrescripteurCR(e, (id) => nomSoignant(m, id)),
                  prescripteurId: idPrescripteurCR(e),
                  realisateur: nomSoignant(m, e['realisateurId'])),
              prefixe: 'IMG')
          .fiche;
    }
    final demande = fiche['demandeImagerieId'] != null
        ? colDemandesImagerie(m).parId(fiche['demandeImagerieId'])
        : null;
    final p = patchEnregistrerCR(releve, libres,
        demande: demande, maintenantIso: maintenant);
    col.mettreAJour(fiche['id'], p.patch);
    if (demande != null && p.patchDemande != null) {
      colDemandesImagerie(m).mettreAJour(demande['id'], p.patchDemande!);
    }
    _enregistre = true;
    // Le message survit à la navigation : il est posé AVANT, sur l'overlay racine.
    ToastsSigh.afficher(context, 'Compte rendu enregistré.',
        type: TypeToast.succes, detail: '${fiche['reference']}');
    c.aller(_retour(modaliteOuInconnue(modaliteDe(m, examenCode))));
  }

  Widget _retourBouton(ContexteEcran c, ModaliteImagerie mod,
          {bool primaire = true}) =>
      BoutonSigh(
          libelle: 'Revenir au tableau',
          icone: LucideIcons.arrowLeft,
          variante:
              primaire ? VarianteBouton.primaire : VarianteBouton.secondaire,
          onPressed: () => c.aller(_retour(mod)));

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (!_pret) _preparer(c);
    final m = c.magasin;
    final rec = _rec;
    final entete = rec == null ? _adresse.entete : null;
    final codeMod = rec != null
        ? modaliteDe(m, rec['examenCode'])
        : (entete != null && entete['examenCode'] != null
            ? modaliteDe(m, entete['examenCode'])
            : (_adresse.modalite ?? 'echographie'));
    final mod = modaliteOuInconnue(codeMod);

    if (_adresse.id != null && rec == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh(
            'Ce compte rendu est introuvable — il a pu être archivé depuis que le lien a été ouvert.',
            ton: TonSigh.attention,
            icone: LucideIcons.triangleAlert),
        const SizedBox(height: 12),
        _retourBouton(c, mod),
      ]);
    }
    if (!c.droit.editer) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh(
            'Votre profil consulte les comptes rendus sans les saisir.',
            ton: TonSigh.attention,
            icone: LucideIcons.lock),
        const SizedBox(height: 12),
        _retourBouton(c, mod, primaire: false),
      ]);
    }

    final principal = <Widget>[];
    if (rec != null) {
      // Fiche existante : son en-tête est arrêté, on le RAPPELLE en lecture — le rouvrir changerait le patient d'un compte rendu déjà au registre.
      principal.add(CarteSigh(
          titre: 'Examen',
          child: DescListeSigh([
            ('Référence', rec['reference']),
            ('Examen', rec['examen']),
            (
              'Patient',
              '${rec['patient'] ?? ''} — ${rec['patientCode'] ?? ''}'
            ),
            ('Indication', _ou(rec['indication'])),
            ('Prescripteur', _ou(rec['prescripteur'])),
            ('Réalisé par', _ou(rec['realisateur'])),
            ('Provenance', _ou(rec['provenance'])),
          ])));
      principal.add(CorpsCR(
          key: _corps,
          examenCode: '${rec['examenCode']}',
          valeursInitiales:
              ((rec['valeurs'] as Map?) ?? const {}).cast<String, Object?>(),
          rubriquesInitiales: rec));
    } else if (entete != null) {
      // L'en-tête vient de la modale : rappelé en LECTURE (deux endroits où changer le patient, et l'on ne saurait plus lequel fait foi).
      final ex = examensImagerie(m)
          .where((x) => x['code'] == entete['examenCode'])
          .firstOrNull;
      principal.add(CarteSigh(
          titre: 'Nouveau compte rendu — ${mod.label}',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DescListeSigh([
              ('Examen', ex != null ? ex['label'] : entete['examenCode']),
              ('Patient', _ou(entete['patientCode'])),
              ('Indication', _ou(entete['indication'])),
              (
                'Prescripteur',
                _ou(nomPrescripteurCR(entete, (id) => nomSoignant(m, id)))
              ),
              ('Réalisé par', _ou(nomSoignant(m, entete['realisateurId']))),
              ('Provenance', _ou(entete['provenance'])),
              ('Condition', _ou(entete['condition'])),
            ]),
            const SizedBox(height: 12),
            const NoteSigh(
                'Rien n’est encore écrit au registre : la fiche naîtra à l’enregistrement. Pour corriger l’en-tête, revenez au tableau et rouvrez un compte rendu.',
                icone: LucideIcons.filePlus),
          ])));
      principal.add(CorpsCR(
          key: _corps,
          examenCode: '${entete['examenCode']}',
          valeursInitiales: const {},
          rubriquesInitiales: const {}));
    } else {
      // Ni fiche, ni en-tête : l'adresse a été ouverte à froid. On ne devine pas un patient — on renvoie là où l'en-tête se choisit.
      principal.add(CarteSigh(
          titre: 'Nouveau compte rendu — ${mod.label}',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NoteSigh(
                'L’en-tête de ce compte rendu n’a pas été relevé — la saisie s’ouvre depuis le tableau de la modalité, qui demande l’examen et le patient.',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert),
            const SizedBox(height: 12),
            _retourBouton(c, mod),
          ])));
    }
    final colonnePrincipale =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, w) in principal.indexed) ...[
        if (i > 0) const SizedBox(height: 16),
        w,
      ]
    ]);
    final aside =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Enchaînement du parcours',
          child: Column(children: [
            _etape(
                'Demande',
                'Prescrite en consultation ou apportée de l’extérieur',
                'Étape 1',
                JetonsShell.success600),
            _etape(
                'Caisse',
                'L’examen ne s’exécute qu’une fois la ligne réglée (M8)',
                'Étape 2',
                JetonsShell.success600),
            _etape(
                'Compte rendu',
                'En-tête, variables et rubriques rédigées — vous y êtes',
                'Étape 3',
                JetonsShell.navy700),
            _etape(
                'Rendu au prescripteur',
                'La demande passe de « exécutée » à « validée »',
                'Étape 4',
                JetonsShell.info600),
            _etape(
                'Galerie des clichés',
                'Images rattachées au patient et au compte rendu',
                'Étape 5',
                JetonsShell.slate600,
                dernier: true),
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Règles de saisie',
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                NoteSigh(
                    'Les mesures se saisissent en texte : « environ 12 mm », « sup à 5 cm ». Un champ numérique refuserait ce que le praticien écrit réellement.',
                    icone: LucideIcons.ruler),
                SizedBox(height: 12),
                NoteSigh(
                    'Un champ de précision n’apparaît que lorsque la valeur l’appelle — « Autre » ouvre le sien.',
                    ton: TonSigh.neutre,
                    icone: LucideIcons.listPlus),
                SizedBox(height: 12),
                NoteSigh(
                    'Le prescripteur peut être extérieur à la clinique : c’est ce qui permet de lui renvoyer le compte rendu.',
                    ton: TonSigh.neutre,
                    icone: LucideIcons.userPlus),
              ])),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (_, w) {
        if (w.maxWidth >= 1024) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: colonnePrincipale),
            const SizedBox(width: 16),
            Expanded(child: aside),
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [colonnePrincipale, const SizedBox(height: 16), aside]);
      }),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: JetonsShell.slate200))),
        child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              BoutonSigh(
                  libelle: 'Annuler',
                  icone: LucideIcons.x,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => c.aller(_retour(mod))),
              BoutonSigh(
                  libelle: 'Enregistrer le compte rendu',
                  icone: LucideIcons.save,
                  onPressed: enregistrer),
            ]),
      ),
    ]);
  }

  String _ou(Object? v) => (v == null || v == '') ? '—' : '$v';

  Widget _etape(String titre, String detail, String date, Color couleur,
          {bool dernier = false}) =>
      Padding(
        padding: EdgeInsets.only(bottom: dernier ? 0 : 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: couleur, shape: BoxShape.circle))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(titre,
                    style: const TextStyle(
                        color: JetonsShell.slate800,
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: FontWeight.w500)),
                Text(detail,
                    style: const TextStyle(
                        color: JetonsShell.slate500,
                        fontSize: 12,
                        height: 16 / 12)),
                Text(date,
                    style: const TextStyle(
                        color: JetonsShell.slate400,
                        fontSize: 11,
                        height: 15 / 11)),
              ])),
        ]),
      );
}
