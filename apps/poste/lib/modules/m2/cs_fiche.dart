import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cs_commun.dart';
import 'cs_dossiers.dart' show chaineParcours;

const _plein = ColChamp.plein;

/// L'éditeur de lignes de médicaments (`editeurMedicaments`) : produit, quantité, posologie, durée — une carte par ligne.
class EditeurMedicamentsCs extends StatefulWidget {
  const EditeurMedicamentsCs(
      {super.key, required this.magasin, required this.peutEditer, this.alChangement});
  final Magasin magasin;
  final bool peutEditer;
  final VoidCallback? alChangement;

  @override
  State<EditeurMedicamentsCs> createState() => EditeurMedicamentsCsState();
}

class EditeurMedicamentsCsState extends State<EditeurMedicamentsCs> {
  final List<ControleurFormulaire> _lignes = [];

  @override
  void initState() {
    super.initState();
    if (widget.peutEditer) _lignes.add(_creer());
  }

  @override
  void dispose() {
    for (final l in _lignes) {
      l.dispose();
    }
    super.dispose();
  }

  ControleurFormulaire _creer() {
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'produitId',
          libelle: 'Médicament',
          type: TypeChamp.select,
          indicatif: '— Médicament —',
          col: ColChamp.demi,
          options: optionsMedicamentsCs(widget.magasin)),
      const ChampDef(nom: 'quantite', libelle: 'Quantité', type: TypeChamp.nombre, col: ColChamp.tiers),
      const ChampDef(
          nom: 'posologie',
          libelle: 'Posologie',
          indicatif: 'Posologie (ex. 1 cp × 3/j)',
          col: ColChamp.demi),
      const ChampDef(nom: 'duree', libelle: 'Durée', indicatif: 'Durée', col: ColChamp.tiers),
    ], {'quantite': '1'});
    f.addListener(() => widget.alChangement?.call());
    return f;
  }

  void ajouter() {
    setState(() => _lignes.add(_creer()));
    widget.alChangement?.call();
  }

  void _retirer(ControleurFormulaire f) {
    setState(() => _lignes.remove(f));
    f.dispose();
    widget.alChangement?.call();
  }

  /// Les lignes saisies : produit choisi et quantité positive.
  List<Map<String, Object?>> collecter() => [
        for (final l in _lignes)
          if ('${l['produitId'] ?? ''}'.isNotEmpty &&
              (num.tryParse('${l['quantite'] ?? ''}') ?? 0) > 0)
            {
              'produitId': l['produitId'],
              'quantite': num.parse('${l['quantite']}'),
              'posologie': '${l['posologie'] ?? ''}',
              'duree': '${l['duree'] ?? ''}',
            }
      ];

  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          key: const Key('prescription-medicaments'),
          children: [
            const Text('Médicaments prescrits (pharmacie & stock)',
                style: TextStyle(
                    color: JetonsShell.slate600,
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            for (final l in _lignes)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: JetonsShell.slate200)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: FormulaireSigh(controleur: l)),
                  BoutonIcone(
                      icone: LucideIcons.trash2,
                      libelle: 'Retirer la ligne',
                      onPressed: () => _retirer(l)),
                ]),
              ),
            // Une commande d'écriture : absente sans le droit d'écrire M2.
            if (widget.peutEditer)
              Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonSigh(
                      libelle: 'Ajouter un médicament',
                      icone: LucideIcons.plus,
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.secondaire,
                      onPressed: ajouter)),
            const SizedBox(height: 4),
            const Text(
                'Catalogue de la pharmacie, au prix d’achat sans marge (RG-02). Le stock affiché est indicatif : la délivrance le contrôle (RG-03).',
                style: TextStyle(color: JetonsShell.slate400, fontSize: 12)),
          ]);
}

/// `m2-consultation-fiche` — « Fiche de consultation » : la synthèse du dossier enregistré (diagnostic, conduite à tenir) et la SEULE étape de
/// prescription — médicaments, analyses, imagerie médicale. Elle REFUSE sans dossier enregistré (`SANS_DOSSIER`). Une ordonnance, UNE facture
/// globale à la caisse (part assureur / part patient) ; l'exécution — dispensation, prélèvement, imagerie — reste bloquée jusqu'au règlement.
class EcranFicheConsultation extends StatefulWidget with EcranMaquette {
  const EcranFicheConsultation({super.key});

  @override
  String get titre => 'Fiche de consultation';

  @override
  String get description =>
      'Synthèse du dossier de consultation : diagnostic, conduite à tenir, et SEULE étape de prescription — médicaments, analyses, imagerie médicale.';

  @override
  String get regle =>
      'La fiche récapitule un dossier de consultation enregistré et refuse sans lui. C’est uniquement ici que se prescrivent médicaments, analyses et imagerie : une ordonnance, une facture globale à la caisse (part assureur / part patient), et l’exécution — dispensation, prélèvement, imagerie — bloquée jusqu’au règlement.';

  @override
  State<EcranFicheConsultation> createState() => _EtatFiche();
}

class _EtatFiche extends State<EcranFicheConsultation> {
  bool _pret = false;
  Fiche? _dossierVise;
  Fiche? _dossierCourant;
  String? _derniereOrdonnance;
  late ControleurFormulaire _entete, _synthese, _examens, _orientation;
  final _editeur = GlobalKey<EditeurMedicamentsCsState>();

  @override
  void dispose() {
    if (_pret) {
      for (final f in [_entete, _synthese, _examens, _orientation]) {
        f.dispose();
      }
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final id = CsNav.ficheDossierId;
    CsNav.ficheDossierId = null;
    _dossierVise = id == null ? null : m.collection('dossiersConsultation').parId(id);
    final maintenant = c.aujourdhui;
    String local(DateTime d) =>
        '${iso(d)}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    _entete = ControleurFormulaire([
      const ChampDef.section('Patient et dossier de consultation'),
      ChampDef(
          nom: 'patientCode',
          libelle: 'Dossier patient',
          type: TypeChamp.select,
          requis: true,
          col: _plein,
          options: optionsPatientsCs(m)),
      ChampDef(
          nom: 'medecin',
          libelle: 'Praticien',
          type: TypeChamp.select,
          requis: true,
          options: optionsPraticiensCs(m)),
      const ChampDef(
          nom: 'date',
          libelle: 'Date et heure',
          requis: true,
          indicatif: 'AAAA-MM-JJThh:mm'),
    ], {
      if (_dossierVise != null) 'patientCode': _dossierVise!['patientCode'],
      if (_dossierVise != null && vrai(_dossierVise!['soignant']))
        'medecin': _dossierVise!['soignant'],
      'date': local(maintenant),
    });
    _synthese = ControleurFormulaire([
      const ChampDef.section('Synthèse et diagnostic'),
      const ChampDef(
          nom: 'resumeSyndromique',
          libelle: 'Résumé syndromique',
          type: TypeChamp.textarea,
          lignes: 2,
          col: _plein),
      const ChampDef(
          nom: 'hypotheses',
          libelle: 'Hypothèses diagnostiques',
          type: TypeChamp.textarea,
          lignes: 2,
          col: _plein),
      ChampDef(
          nom: 'pathologies',
          libelle: 'Pathologie(s) retenue(s)',
          type: TypeChamp.multiselect,
          requis: true,
          col: _plein,
          options: optionsPathologiesCs(m),
          aide: 'Référentiel de morbidité de la clinique. La première citée est retenue comme principale.'),
      const ChampDef(
          nom: 'diagnostic',
          libelle: 'Diagnostic retenu',
          type: TypeChamp.textarea,
          lignes: 2,
          requis: true,
          col: _plein,
          aide: 'La phrase clinique — la pathologie ci-dessus sert au comptage.'),
      const ChampDef(
          nom: 'traitementEmblee',
          libelle: 'Traitement d’emblée',
          type: TypeChamp.textarea,
          lignes: 2,
          col: _plein,
          aide: 'Si nécessaire avant les résultats.'),
      const ChampDef(
          nom: 'conduite',
          libelle: 'Conduite à tenir',
          type: TypeChamp.textarea,
          lignes: 2,
          col: _plein),
    ]);
    _examens = ControleurFormulaire([
      ChampDef(
          nom: 'analyses',
          libelle: 'Analyses de laboratoire prescrites',
          type: TypeChamp.multiselect,
          col: _plein,
          options: optionsAnalysesCs(m),
          aide: 'Chaque analyse engendre sa demande au laboratoire, bloquée jusqu’au règlement.'),
      ChampDef(
          nom: 'imagerie',
          libelle: 'Imagerie médicale prescrite',
          type: TypeChamp.multiselect,
          col: _plein,
          options: optionsImagerieCs(m),
          aide: 'Échographie, radiographie, mammographie, scanner, IRM — la demande part au poste d’imagerie, exécutable après la caisse.'),
    ]);
    _orientation = ControleurFormulaire([
      const ChampDef.section('Orientation et décision médicale'),
      ChampDef(
          nom: 'orientation',
          libelle: 'Orientation',
          type: TypeChamp.select,
          requis: true,
          options: [for (final o in csOrientations) OptionChamp(o.valeur, o.libelle)]),
      const ChampDef(
          nom: 'prochainRdv',
          libelle: 'Prochain rendez-vous (retour à domicile)',
          indicatif: 'AAAA-MM-JJThh:mm',
          aide: 'Posé à l’agenda comme un contrôle planifié.'),
      const ChampDef(nom: 'tarif', libelle: 'Tarif de la consultation (FCFA)', type: TypeChamp.nombre),
    ], {'tarif': '3000'});
    _pret = true;
  }

  Fiche? _patient(ContexteEcran c) {
    final code = '${_entete['patientCode'] ?? ''}';
    if (code.isEmpty) return null;
    return c.magasin.collection('patients').actives.where((p) => p['code'] == code).firstOrNull;
  }

  /// Le dossier sur lequel la fiche s'appuie : le dossier visé s'il appartient au patient, sinon le plus récent des dossiers enregistrés.
  Fiche? _dossierDe(ContexteEcran c, Fiche? p) {
    if (p == null) return null;
    final s = stockDe(c);
    var d = (_dossierVise != null &&
            _dossierVise!['patientCode'] == p['code'] &&
            csDossierEnregistre(_dossierVise))
        ? _dossierVise
        : csDossierActifDe(s, p['code']);
    if (d != null) d = c.magasin.collection('dossiersConsultation').parId(d['id']);
    return d;
  }

  String _total(ContexteEcran c, Fiche? p) {
    final m = c.magasin;
    final s = stockDe(c);
    final assure = p != null &&
        carteValide(p, m.collection('couverturesAssurance').toutes, c.aujourdhui.toIso8601String());
    double mMed = 0, mAna = 0, mImg = 0;
    for (final l in _editeur.currentState?.collecter() ?? const <Map<String, Object?>>[]) {
      final pr = m.collection('produits').parId(l['produitId']);
      mMed += nombreOuZero(pr?['prixAchat']) * nombreOuZero(l['quantite']);
    }
    final analyses = m.referentiel('analyses');
    for (final code in (_examens['analyses'] as List? ?? const [])) {
      final a = analyses.where((x) => x['code'] == code).firstOrNull;
      mAna += nombreOuZero(a?['prix']);
    }
    final sansTarif = <String>[];
    final examens = m.collection('examensImagerie').actives;
    for (final code in (_examens['imagerie'] as List? ?? const [])) {
      final ex = examens.where((x) => x['code'] == code).firstOrNull;
      final pr = csTarifPrix(s, vrai(ex?['tarifCode']) ? ex!['tarifCode'] : code, assure);
      if (pr.montant == null) sansTarif.add('${ex?['label'] ?? code}');
      mImg += nombreOuZero(pr.montant);
    }
    return '${money(mMed + mAna + mImg)}  (médicaments ${money(mMed, avecDevise: false)} · analyses ${money(mAna, avecDevise: false)} · imagerie ${money(mImg, avecDevise: false)})${sansTarif.isNotEmpty ? ' — sans tarif : ${sansTarif.join(', ')}' : ''}';
  }

  Fiche? _exigerOrdonnance(ContexteEcran c, String quoi) {
    final ord = _derniereOrdonnance == null
        ? null
        : c.magasin.collection('ordonnances').parId(_derniereOrdonnance);
    if (ord != null) return ord;
    ToastsSigh.afficher(context, 'Aucune ordonnance à imprimer.',
        type: TypeToast.erreur,
        detail:
            'Cliquer d’abord sur « Enregistrer et prescrire » : $quoi reprend ce qui a réellement été transmis, et non le contenu du formulaire.');
    return null;
  }

  void _enregistrer(ContexteEcran c) {
    final a = _entete.valider(),
        b = _synthese.valider(),
        o = _orientation.valider(),
        x = _examens.valider();
    if (a == null || b == null || o == null || x == null) {
      ToastsSigh.afficher(context, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    if (DateTime.tryParse('${a['date']}'.replaceFirst(' ', 'T')) == null) {
      ToastsSigh.afficher(context, 'Date et heure invalides : saisir AAAA-MM-JJThh:mm.',
          type: TypeToast.erreur);
      return;
    }
    final tarif = '${o['tarif'] ?? ''}'.isEmpty ? null : num.tryParse('${o['tarif']}');
    final ResultatFiche res;
    try {
      res = csEnregistrerFiche(
          stockDe(c),
          {
            ...a, ...b, ...o, ...x,
            'date': '${a['date']}'.replaceFirst(' ', 'T'),
            'prochainRdv': '${o['prochainRdv'] ?? ''}'.isEmpty ? null : '${o['prochainRdv']}'.replaceFirst(' ', 'T'),
            'tarif': tarif,
            'dossierConsultationId': _dossierCourant?['id'],
            'medicaments': _editeur.currentState?.collecter() ?? const [],
          },
          sessionDe(c));
    } on RefusCs catch (e) {
      ToastsSigh.afficher(
          context,
          e.code == 'SANS_DOSSIER' ? 'Fiche refusée : aucun dossier de consultation.' : 'Enregistrement refusé.',
          type: TypeToast.erreur,
          detail: e.message,
          duree: const Duration(seconds: 10));
      return;
    }
    final ord = res.prescription;
    _derniereOrdonnance = ord == null ? null : '${ord.ordonnance['id']}';
    _dossierVise = null;
    final envois = <String>[];
    if (ord != null) {
      if (ord.demandes.isNotEmpty) envois.add('${ord.demandes.length} analyse(s) au laboratoire');
      if (ord.demandesImagerie.isNotEmpty) {
        envois.add('${ord.demandesImagerie.length} examen(s) à l’imagerie');
      }
      if (((ord.ordonnance['medicaments'] as List?) ?? const []).isNotEmpty) {
        envois.add('pharmacie informée');
      }
      envois.add('facture ${ord.facture['numero']} en attente à la caisse');
    }
    setState(() {});
    ToastsSigh.afficher(context,
        'Fiche de consultation enregistrée — dossier ${csEtatDossier(res.dossier['etat'])['label']}.',
        type: TypeToast.succes,
        duree: const Duration(seconds: 9),
        detail: envois.isEmpty ? 'Aucune prescription.' : envois.join(' · '));
    final ecran = context;
    afficherModale<void>(ecran,
        titre: 'Consultation enregistrée',
        sousTitre: ord != null
            ? 'Ordonnance ${ord.ordonnance['numero']} — facture ${ord.facture['numero']}'
            : '${res.consultation['patient']}',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (ord != null)
            const NoteSigh(
                'Une facture globale attend à la caisse. La dispensation, le prélèvement et l’imagerie restent bloqués jusqu’au règlement.',
                icone: LucideIcons.coins)
          else
            const NoteSigh('Aucune prescription : rien ne part à la caisse.',
                ton: TonSigh.neutre, icone: LucideIcons.info),
          if (ord != null) ...[
            const SizedBox(height: 12),
            DescListeSigh([
              ('Médicaments', nombre(((ord.ordonnance['medicaments'] as List?) ?? const []).length)),
              ('Analyses', nombre(ord.demandes.length)),
              ('Imagerie médicale', nombre(ord.demandesImagerie.length)),
              (
                'À régler à la caisse',
                money(ord.facture['partPatient'] ?? ord.facture['montantTTC'])
              ),
              ('Part assureur', money(ord.facture['partAssurance'] ?? 0)),
              ('Dossier', '${res.dossier['reference']} — ${csEtatDossier(res.dossier['etat'])['label']}'),
            ]),
          ],
          if (res.suites.isNotEmpty) ...[
            const SizedBox(height: 12),
            NoteSigh('Orientation : ${csLibelleOrientation(res.consultation['orientation'])}.',
                ton: TonSigh.attention, icone: LucideIcons.route),
          ],
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Fermer',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              if (ord != null && ((ord.ordonnance['medicaments'] as List?) ?? const []).isNotEmpty)
                BoutonSigh(
                    libelle: 'Ordonnance',
                    icone: LucideIcons.fileText,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => imprimerOrdonnance(
                        ecran, c.magasin.collection('ordonnances').parId(ord.ordonnance['id'])!)),
              if (ord != null && ord.demandes.isNotEmpty)
                BoutonSigh(
                    libelle: 'Bulletin d’analyses',
                    icone: LucideIcons.flaskConical,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => imprimerBulletin(
                        ecran, c.magasin.collection('ordonnances').parId(ord.ordonnance['id'])!)),
              for (final s in res.suites)
                BoutonSigh(
                    libelle: s.label,
                    icone: LucideIcons.arrowRight,
                    onPressed: () {
                      fermer();
                      c.aller(s.ecran);
                    }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([
          _entete,
          _synthese,
          _examens,
          _orientation,
          m.collection('dossiersConsultation'),
        ]),
        builder: (ctx, _) {
          final p = _patient(c);
          _dossierCourant = _dossierDe(c, p);
          final releve = p == null ? null : csDernierReleve(stockDe(c), p['code'], p['id']);
          final recap = p == null
              ? const SizedBox()
              : (_dossierCourant == null
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const NoteSigh(
                          'Fiche impossible sans dossier. $csMessageSansDossier',
                          ton: TonSigh.danger,
                          icone: LucideIcons.folderX),
                      const SizedBox(height: 12),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: BoutonSigh(
                              libelle: 'Ouvrir les dossiers de consultation',
                              icone: LucideIcons.folderHeart,
                              onPressed: () => c.aller('m2-dossiers-consultation'))),
                      const SizedBox(height: 12),
                      SectionSigh(
                          titre: 'Zone 1 — constantes de l’accueil',
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: blocConstantes(releve == null
                                  ? null
                                  : (valeurs: csCopieReleve(releve)!, source: 'accueil')))),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      NoteSigh(
                          'Récapitulatif du dossier ${_dossierCourant!['reference'] ?? _dossierCourant!['id']} — ${csEtatDossier(_dossierCourant!['etat'])['label']}. Pour corriger l’anamnèse ou l’examen, revenir au dossier : la fiche le lit, elle ne le réécrit pas.',
                          ton: TonSigh.succes,
                          icone: LucideIcons.folderCheck),
                      const SizedBox(height: 12),
                      recapDossier(m, _dossierCourant!, releve: releve),
                    ]));
          final principal = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(
                titre: 'Dossier de consultation — récapitulatif',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormulaireSigh(controleur: _entete),
                  const SizedBox(height: 16),
                  recap,
                ])),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Synthèse, diagnostic et conduite à tenir',
                child: FormulaireSigh(controleur: _synthese)),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Prescription — la seule étape où l’on prescrit',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  EditeurMedicamentsCs(
                      key: _editeur,
                      magasin: m,
                      peutEditer: c.droit.editer,
                      alChangement: () {
                        if (mounted) setState(() {});
                      }),
                  const SizedBox(height: 16),
                  FormulaireSigh(controleur: _examens),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: JetonsShell.slate50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: JetonsShell.slate200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text(
                          'Total de la prescription (avant répartition assureur / patient)',
                          style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                      Text(_total(c, p),
                          style: const TextStyle(
                              color: JetonsShell.slate800,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ])),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Orientation',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormulaireSigh(controleur: _orientation),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    // Une commande d'écriture : absente sans le droit d'écrire M2 (aide-soignante, surveillant, technicien d'échographie).
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Enregistrer et prescrire',
                          icone: LucideIcons.save,
                          onPressed: () => _enregistrer(c)),
                    BoutonSigh(
                        libelle: 'Éditer l’ordonnance',
                        icone: LucideIcons.fileText,
                        variante: VarianteBouton.secondaire,
                        onPressed: () {
                          final o = _exigerOrdonnance(c, 'l’ordonnance');
                          if (o != null) imprimerOrdonnance(context, o);
                        }),
                    BoutonSigh(
                        libelle: 'Éditer le bulletin d’analyses',
                        icone: LucideIcons.flaskConical,
                        variante: VarianteBouton.secondaire,
                        onPressed: () {
                          final o = _exigerOrdonnance(c, 'le bulletin');
                          if (o != null) imprimerBulletin(context, o);
                        }),
                  ]),
                ])),
          ]);
          final aside = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(titre: 'Enchaînement du parcours', child: chaineParcours(const [
              ('Accueil — Zone 1', 'Identité, couverture, constantes saisies et verrouillées', 'Étape 1', TonSigh.succes),
              ('Dossier de consultation', 'Anamnèse, antécédents, examen IPPOA — enregistré d’abord', 'Étape 2', TonSigh.succes),
              ('Fiche de consultation', 'Synthèse, diagnostic, conduite à tenir', 'Étape 3', TonSigh.navy),
              ('Prescription', 'Médicaments (M6), analyses (M5), imagerie (M2) — ici seulement', 'Étape 4', TonSigh.info),
              ('Caisse', 'Facture globale, part assureur / patient ; l’aval se débloque au règlement (M8)', 'Étape 5', TonSigh.attention),
            ])),
            const SizedBox(height: 16),
            const CarteSigh(
                titre: 'Rappels de facturation',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  NoteSigh(
                      'RG-02 — Les médicaments sont facturés au prix d’achat, sans marge.'),
                  SizedBox(height: 12),
                  NoteSigh(
                      'RG-09 — La prise en charge n’est appliquée que si la carte est valide à la date de facturation.',
                      ton: TonSigh.attention,
                      icone: LucideIcons.shieldAlert),
                ])),
          ]);
          return LayoutBuilder(builder: (_, w) {
            if (w.maxWidth >= 1024) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: principal),
                const SizedBox(width: 16),
                Expanded(child: aside),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              principal,
              const SizedBox(height: 16),
              aside,
            ]);
          });
        });
  }
}
