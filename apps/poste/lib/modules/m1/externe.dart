import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m2/img_commun.dart' show catalogueExamens, nouvelIdImagerie, prixDepuisMagasin;
import '../m5/cat_commun.dart' show collectionAnalyses;
import '../m5/res_commun.dart' show profilLabo;
import 'commun_m1.dart';

String _t(Object? v, [String vide = '—']) => patVrai(v) ? '$v' : vide;

const _services = ['Maternité', 'Médecine', 'Médecine et spécialité'];
const _urgences = [
  OptionChamp('aucune', 'Examen courant'),
  OptionChamp('examen', 'Un examen urgent'),
  OptionChamp('bilan', 'Bilan entier en urgence'),
];

/// `m1-externe` — le patient externe : la demande naît à l'ACCUEIL (il TRANSCRIT une ordonnance extérieure, il ne prescrit pas), la caisse ne crée
/// jamais la demande, et RIEN NE SE SAISIT AVANT LA CAISSE : la commande de saisie reste visible et verrouillée, et dit chez qui la balle se trouve.
class EcranExterne extends StatelessWidget with EcranMaquette {
  const EcranExterne({super.key});

  @override
  String get titre => 'Patient externe — demande d’analyses';

  @override
  String get description => 'Transcription de l’ordonnance d’un médecin extérieur, puis orientation vers la caisse.';

  @override
  String get regle =>
      'L’accueil transcrit une ordonnance extérieure, il ne prescrit pas. Les examens se cochent au catalogue — jamais un montant libre — pour que la caisse puisse encaisser prestation par prestation. La caisse ne crée jamais la demande : elle encaisse, elle ne prescrit pas. Le résultat est remis directement au patient, d’où l’identité obligatoire.';

  static const _note =
      'Le patient externe arrive avec une ordonnance d’un médecin extérieur. L’accueil la transcrit en cochant les examens au catalogue, puis l’oriente vers la caisse. Le prélèvement n’a lieu qu’après règlement, et le résultat lui est remis directement — il n’a pas de clinicien dans la maison à qui l’adresser.';

  List<ChampDef> _champs(ContexteEcran c) {
    final analyses = collectionAnalyses(c.magasin).actives;
    return [
      const ChampDef.section('Identité du patient — obligatoire pour lui remettre son résultat'),
      const ChampDef(nom: 'nom', libelle: 'Nom', requis: true),
      const ChampDef(nom: 'prenom', libelle: 'Prénoms', requis: true),
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
          valider: (v, _) {
            final d = dateM1(v);
            return d != null && d.isAfter(c.aujourdhui) ? 'La date ne peut pas être dans le futur.' : null;
          }),
      const ChampDef(
          nom: 'age',
          libelle: 'Âge déclaré (ans)',
          type: TypeChamp.nombre,
          requis: true,
          condition: (controle: 'naissanceConnue', quand: ['age'])),
      const ChampDef(
          nom: 'telephone',
          libelle: 'Téléphone',
          requis: true,
          aide: 'Le résultat lui est remis directement : sans téléphone, on ne peut pas le joindre.'),
      const ChampDef(nom: 'residence', libelle: 'Lieu de résidence', requis: true),
      const ChampDef.section('Ordonnance extérieure'),
      const ChampDef(
          nom: 'prescripteur',
          libelle: 'Médecin prescripteur',
          requis: true,
          col: ColChamp.plein,
          aide: 'Nom du médecin extérieur qui a demandé les examens.'),
      const ChampDef(nom: 'indication', libelle: 'Indication clinique', col: ColChamp.plein),
      ChampDef(nom: 'serviceDemandeur', libelle: 'Service concerné', type: TypeChamp.select, options: [for (final s in _services) OptionChamp(s)]),
      const ChampDef(nom: 'urgence', libelle: 'Caractère d’urgence', type: TypeChamp.select, requis: true, options: _urgences),
      const ChampDef.section('Examens demandés — au catalogue'),
      const ChampDef(
          nom: 'nature',
          libelle: 'Nature de la demande',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            OptionChamp('analyses', 'Analyses de laboratoire'),
            OptionChamp('imagerie', 'Imagerie médicale (échographie, ECG, radiographie)')
          ],
          aide: 'Le catalogue à cocher ci-dessous dépend de la nature choisie.'),
      ChampDef(
          nom: 'analyses',
          libelle: 'Examens de laboratoire',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final a in analyses) OptionChamp('${a['code']}', '${a['designation']}')],
          aide:
              'Les examens se cochent au catalogue : c’est ce qui permet à la caisse d’encaisser prestation par prestation, et au patient de n’en régler qu’une partie s’il le faut.'),
      ChampDef(
          nom: 'examens',
          libelle: 'Examens d’imagerie',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final x in catalogueExamens(c.magasin)) OptionChamp('${x['code']}', '${x['label']}')],
          aide: 'Un examen sans tarif validé est refusé en le nommant : un tiret n’est pas un zéro.'),
      const ChampDef.section('Prise en charge'),
      ChampDef(
          nom: 'assureur',
          libelle: 'Assurance',
          type: TypeChamp.select,
          options: [const OptionChamp('', 'Aucune — paiement intégral'), for (final a in patAssureurs) OptionChamp(a.$2)]),
      const ChampDef(nom: 'taux', libelle: 'Taux de prise en charge (%)', type: TypeChamp.nombre),
    ];
  }

  void _nouvelle(BuildContext ctx, ContexteEcran c) {
    final defs = _champs(c);
    final ctl = ControleurFormulaire(defs, {'sexe': 'M', 'urgence': 'aucune', 'taux': '0', 'nature': 'analyses', 'naissanceConnue': 'date', 'assureur': ''});
    afficherModale<void>(ctx,
        titre: 'Nouvelle demande — patient externe',
        sousTitre: 'Transcription d’une ordonnance extérieure',
        taille: TailleModale.xl,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Transcription, pas prescription. L’accueil reporte les examens portés sur l’ordonnance du médecin extérieur. Un dossier patient est ouvert, une facture part à la caisse, et le prélèvement reste bloqué tant qu’elle n’est pas réglée.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer et envoyer à la caisse',
                  icone: LucideIcons.coins,
                  onPressed: () {
                    final brut = ctl.valider();
                    if (brut == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final v = convertirSaisie(defs, brut);
                    final imagerie = v['nature'] == 'imagerie';
                    final coches = [for (final x in ((imagerie ? v['examens'] : v['analyses']) as List? ?? const [])) '$x'];
                    if (coches.isEmpty) {
                      ToastsSigh.afficher(ctx, 'Cocher au moins un examen au catalogue.',
                          type: TypeToast.erreur, detail: imagerie ? 'Catalogue d’imagerie médicale.' : 'Catalogue des analyses.');
                      return;
                    }
                    try {
                      final res = imagerie ? _ouvrirImagerie(c, v, coches) : _ouvrirAnalyses(c, v, coches);
                      fermer();
                      _recapitulatif(ctx, c, res);
                    } on PatRefus catch (e) {
                      ToastsSigh.afficher(ctx, 'Demande impossible : ${e.message}', type: TypeToast.erreur);
                    } on RefusImagerie catch (e) {
                      ToastsSigh.afficher(ctx, 'Demande impossible : ${e.message}', type: TypeToast.erreur);
                    }
                  }),
            ]);
  }

  /// Chaque nature passe par SA fabrique — celle-là même qui sert la consultation et le laboratoire : une troisième voie donnerait une troisième
  /// forme de demande dans les mêmes registres.
  Map<String, Object?> _ouvrirAnalyses(ContexteEcran c, Map<String, Object?> v, List<String> codes) {
    final m = c.magasin;
    final r = patOuvrirDemandeExterne(
        saisie: {
          ...v,
          if (v['naissanceConnue'] == 'age') 'dateNaissance': null else 'age': null,
        },
        codesAnalyses: codes,
        catalogue: collectionAnalyses(m).actives,
        patients: m.collection('patients').toutes,
        demandesExistantes: m.collection('demandesAnalyses').toutes,
        nbFactures: m.collection('factures').toutes.length,
        nouvelId: nouvelIdImagerie,
        date: c.aujourdhui);
    if (r.dossierCree) m.collection('patients').inserer(r.patient, prefixe: 'PAT');
    for (final d in r.demandes.reversed) {
      m.collection('demandesAnalyses').inserer(d, prefixe: 'DEM');
    }
    m.collection('factures').inserer(r.facture, prefixe: 'FAC');
    for (final t in r.taches) {
      m.collection('taches').inserer(t, prefixe: 'TCH');
    }
    return {'patient': r.patient, 'nbExamens': r.demandes.length, 'facture': r.facture, 'demandes': r.demandes, 'imagerie': false};
  }

  Map<String, Object?> _ouvrirImagerie(ContexteEcran c, Map<String, Object?> v, List<String> codes) {
    final m = c.magasin;
    final maintenant = c.aujourdhui.toIso8601String();
    final r = ouvrirDemandeImagerie(
        examens: codes,
        catalogue: catalogueExamens(m),
        patients: m.collection('patients').toutes,
        couvertures: m.collection('couverturesAssurance').actives,
        demandesExistantes: m.collection('demandesImagerie').toutes,
        nbFactures: m.collection('factures').toutes.length,
        prixDe: prixDepuisMagasin(m),
        nouvelId: nouvelIdImagerie,
        date: maintenant,
        maintenant: maintenant,
        nom: v['nom'] as String?,
        prenom: v['prenom'] as String?,
        sexe: v['sexe'] as String?,
        dateNaissance: v['naissanceConnue'] == 'date' ? v['dateNaissance'] as String? : null,
        age: v['naissanceConnue'] == 'age' ? v['age'] : null,
        telephone: v['telephone'] as String?,
        residence: v['residence'] as String?,
        prescripteur: v['prescripteur'] as String?,
        indication: v['indication'] as String?,
        secteurDemandeur: v['serviceDemandeur'] as String?,
        origine: 'externe');
    if (r.dossierCree) m.collection('patients').inserer(r.patient, prefixe: 'PAT');
    for (final d in r.demandes) {
      m.collection('demandesImagerie').inserer(d, prefixe: 'IME');
    }
    m.collection('factures').inserer(r.facture, prefixe: 'FAC');
    m.collection('taches').inserer(r.tacheEncaissement, prefixe: 'TCH');
    m.collection('taches').inserer(r.tacheExamen, prefixe: 'TCH');
    m.collection('notifications').inserer(r.notification, prefixe: 'NOT');
    return {'patient': r.patient, 'nbExamens': r.demandes.length, 'facture': r.facture, 'demandes': r.demandes, 'imagerie': true};
  }

  void _recapitulatif(BuildContext ctx, ContexteEcran c, Map<String, Object?> res) {
    final p = res['patient'] as Fiche;
    final f = res['facture'] as Fiche;
    afficherModale<void>(ctx,
        titre: 'Demande enregistrée',
        sousTitre: '${p['nom']} ${p['prenom']} — ${p['code']}',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Dossier ouvert', '${p['code']}'),
            ('Examens demandés', nombre(res['nbExamens'])),
            ('Facture', '${f['numero']}'),
            ('À régler à la caisse', money(f['partPatient'])),
          ]),
          const SizedBox(height: 12),
          const NoteSigh(
              'Le patient se présente maintenant à la caisse avec son bulletin. Le prélèvement n’aura lieu qu’après règlement — et seuls les examens réglés seront transmis au laboratoire.',
              ton: TonSigh.attention,
              icone: LucideIcons.coins),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Imprimer le bulletin',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => _bulletin(ctx, res)),
              BoutonSigh(
                  libelle: 'Aller à la caisse',
                  icone: LucideIcons.coins,
                  onPressed: () {
                    fermer();
                    c.aller('m8-caisse');
                  }),
            ]);
  }

  void _bulletin(BuildContext ctx, Map<String, Object?> res) {
    final p = res['patient'] as Fiche;
    final f = res['facture'] as Fiche;
    final c = ContexteEcran.of(ctx);
    final dem = (res['demandes'] as List).cast<Fiche>();
    imprimerM1(ctx,
        titre: 'Bulletin d’analyses bio-médicales',
        sousTitre: 'Patient externe — ${f['numero']}',
        cartouche: [
          ('Patient', '${p['nom']} ${p['prenom']}'),
          ('Dossier', '${p['code']}'),
          ('Âge', ageTexte(p, c.aujourdhui)),
          ('Sexe', p['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
          ('Téléphone', _t(p['telephone'])),
          ('Résidence', _t(p['adresse'])),
          ('Prescripteur extérieur', _t(p['prescripteurExterieur'])),
          ('Date', dateFR(c.aujourdhui)),
          ('À régler à la caisse', money(f['partPatient'])),
        ],
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Examen demandé', valeur: (d) => d['analyse'] ?? d['examen']),
            ColonneEtat(libelle: 'Échantillon', valeur: (d) => d['echantillon'] ?? ''),
            ColonneEtat(libelle: 'Tarif', valeur: (d) => money(d['prix'], avecDevise: false), droite: true, somme: (d) => nombreOuZero(d['prix'])),
          ], lignes: dem)),
          const BlocTexte(
              'Patient adressé de l’extérieur. Ce bulletin accompagne le patient à la caisse puis à la salle de prélèvement. Le résultat lui est remis directement — la clinique ne dispose pas d’un clinicien prescripteur à qui l’adresser.',
              italique: true),
        ],
        signatures: const [Signature('L’Accueil', mention: 'Transcription'), Signature('Le Caissier', mention: 'Règlement')]);
  }

  void _voir(BuildContext ctx, ContexteEcran c, Fiche r) {
    if (patVrai(r['examenCode'])) {
      final cr = c.magasin
          .collection('resultatsImagerie')
          .actives
          .where((x) => x['demandeId'] == r['id'] || x['demandeImagerieId'] == r['id'])
          .firstOrNull;
      afficherTiroir<void>(ctx,
          titre: 'Compte rendu — ${_t(r['examen'], '')}',
          sousTitre: '${r['patient']} · ${r['patientCode']}',
          corps: cr == null
              ? const VideSigh('Le compte rendu n’est pas encore rédigé.', icone: LucideIcons.fileQuestionMark)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DescListeSigh([
                    ('Examen', r['examen']),
                    ('Date', dateFrM1(r['dateHeure'])),
                    ('Réalisé par', _t(cr['realisateur'])),
                    ('Prescripteur', _t(r['prescripteur'])),
                  ]),
                  const SizedBox(height: 12),
                  CarteSigh(titre: 'Conclusion', child: paragrapheM1(_t(cr['conclusion'], 'Non renseignée.'))),
                ]));
      return;
    }
    // Laboratoire : la règle des DEUX VERROUS s'applique ici comme ailleurs — un résultat non validé biologiquement ne se lit pas.
    final vu = peutVoirResultat(r, profilLabo(c).session);
    if (!vu.autorise) {
      ToastsSigh.afficher(ctx, 'Résultat non consultable.', type: TypeToast.erreur, detail: vu.motif);
      return;
    }
    final valeurs = r['valeurs'];
    final vars = c.magasin.collection('variablesLabo').actives.where((x) => x['examen'] == r['analyseCode']).toList();
    afficherTiroir<void>(ctx,
        titre: 'Résultat — ${_t(r['analyse'], '')}',
        sousTitre: '${r['patient']} · ${r['patientCode']}',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Code d’analyse', enMono(_t(r['codeAnalyse']))),
            ('Référence', enMono(_t(r['reference']))),
            ('Examen', r['analyse']),
            ('Date', dateFrM1(r['dateHeure'])),
            ('Prescripteur extérieur', _t(r['prescripteur'])),
            ('Validé par', _t(r['valideBiologiquePar'] ?? r['valideParBio'] ?? r['laborantin'])),
          ]),
          const SizedBox(height: 12),
          if (valeurs is Map && valeurs.isNotEmpty)
            CarteSigh(
                titre: 'Valeurs',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Variable', (x) => '${x['v']}'),
                  ColonneMini('Résultat', (x) => '${x['r']}'),
                ], lignes: [
                  for (final k in valeurs.keys)
                    {'v': vars.where((x) => x['code'] == k).firstOrNull?['libelle'] ?? k, 'r': '${valeurs[k]}'}
                ]))
          else
            CarteSigh(titre: 'Résultat', child: paragrapheM1(_t(r['resultat'], 'Non renseigné.'))),
          const SizedBox(height: 12),
          const NoteSigh('Le résultat d’un patient externe lui est remis directement : il n’a pas de clinicien dans la maison à qui l’adresser.',
              icone: LucideIcons.hand),
        ]));
  }

  List<Widget> _actions(BuildContext ctx, ContexteEcran c, Fiche r) {
    final imagerie = patVrai(r['examenCode']);
    final bloc = patBlocageResultat(r);
    final rendu = patResultatRendu(r);
    return [
      if (patVrai(r['factureId']) || patVrai(r['facture']))
        BoutonIcone(icone: LucideIcons.coins, libelle: 'Voir la facture à la caisse', onPressed: () => c.aller('m8-caisse')),
      if (rendu) BoutonIcone(icone: LucideIcons.eye, libelle: 'Voir le résultat', onPressed: () => _voir(ctx, c, r)),
      if (bloc != null)
        // Verrouillé, et NOMMÉ : le laboratoire comme l'accueil doivent savoir chez qui la balle se trouve.
        Opacity(
            opacity: 0.5,
            child: BoutonIcone(
                icone: LucideIcons.lock,
                libelle: '${bloc.motif} ${bloc.suite}',
                onPressed: () => ToastsSigh.afficher(ctx, 'Saisie impossible.', type: TypeToast.erreur, detail: '${bloc.motif} ${bloc.suite}')))
      else if (!rendu && c.droit.editer)
        BoutonIcone(
            icone: LucideIcons.fileSignature,
            libelle: imagerie ? 'Saisir le compte rendu (poste d’imagerie)' : 'Saisir le résultat (laboratoire)',
            onPressed: () => c.aller(imagerie ? 'm2-imagerie-demandes' : 'm5-resultats')),
      BoutonIcone(icone: LucideIcons.folderOpen, libelle: 'Ouvrir le dossier du patient', onPressed: () => c.aller('m1-patient-profil')),
    ];
  }

  Widget _tableau(BuildContext ctx, ContexteEcran c, List<Fiche> rows, {required String titre, required String vide, String libelleExamen = 'Examen'}) {
    final l = trierPar(rows, (r) => r['dateHeure'], descendant: true);
    return TableauSigh(
      titre: titre,
      lignes: l,
      taillePage: 12,
      nomExport: 'demandes-externes',
      messageVide: vide,
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => enMono('${r['reference']}'), texte: (r) => '${r['reference']}'),
        ColonneTableau(cle: 'dateHeure', libelle: 'Date', sansCoupure: true, texte: (r) => dateFrM1(r['dateHeure']), valeur: (r) => r['dateHeure']),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Patient',
            texte: (r) => '${r['patient']} ${r['patientCode']}',
            rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${r['patient']}', overflow: TextOverflow.ellipsis, style: styleM1(c: JetonsShell.slate800, p: FontWeight.w500)),
                  Text('${r['patientCode']}', style: styleM1(t: 12, c: JetonsShell.slate400)),
                ])),
        ColonneTableau(cle: 'examen', libelle: libelleExamen, valeur: (r) => r['analyse'] ?? r['examen'] ?? '', texte: (r) => '${r['analyse'] ?? r['examen'] ?? ''}'),
        ColonneTableau(
            cle: 'service',
            libelle: 'Service demandeur',
            valeur: (r) => r['serviceDemandeur'] ?? r['secteurDemandeur'] ?? '—',
            texte: (r) => '${patVrai(r['serviceDemandeur']) ? r['serviceDemandeur'] : (patVrai(r['secteurDemandeur']) ? r['secteurDemandeur'] : '—')}'),
        const ColonneTableau(cle: 'prescripteur', libelle: 'Prescripteur extérieur'),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            droite: true,
            triable: false,
            texte: (r) => patEtatLigne(r).$1,
            rendu: (_, r) {
              final e = patEtatLigne(r);
              return BadgeSigh(e.$1, ton: tonDe(e.$2));
            }),
      ],
      actionsLigne: (cx, r) => _actions(cx, c, r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection('demandesAnalyses'), m.collection('demandesImagerie'), m.collection('patients')]),
        builder: (context, _) {
          final dem = patDemandesExternes(m.collection('demandesAnalyses').actives);
          final img = patImagerieExterne(m.collection('demandesImagerie').actives, m.collection('patients').toutes);
          final k = patKpisExterne(dem);
          final rendus = [
            ...dem.where((d) => patResultatRendu(d)),
            ...img.where((d) => d['statut'] == 'validee'),
          ];
          Widget note(String t, IconData i) => Padding(padding: const EdgeInsets.only(bottom: 12), child: NoteSigh(t, icone: i));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Demandes externes', valeur: nombre(k.demandes), icone: LucideIcons.userPlus),
              KpiSigh(
                  libelle: 'En attente de caisse',
                  valeur: nombre(k.enAttente),
                  icone: LucideIcons.coins,
                  ton: k.enAttente > 0 ? TonSigh.attention : TonSigh.succes),
              KpiSigh(libelle: 'Résultats rendus', valeur: nombre(k.rendus), icone: LucideIcons.fileCheck2, ton: TonSigh.succes),
              KpiSigh(libelle: 'Patients externes', valeur: nombre(k.patients), icone: LucideIcons.users, ton: TonSigh.info),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(_note, icone: LucideIcons.route),
            if (c.droit.editer) ...[
              const SizedBox(height: 16),
              Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonSigh(
                      libelle: 'Nouvelle demande externe',
                      icone: LucideIcons.plus,
                      taille: TailleBouton.sm,
                      onPressed: () => _nouvelle(context, c))),
            ],
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(
                  id: 'analyses',
                  libelle: 'Demandes — analyses (${dem.length})',
                  construire: (cx) => _tableau(cx, c, dem, titre: 'Demandes d’analyses — patients externes', vide: 'Aucune demande d’analyse externe.')),
              OngletDef(
                  id: 'maternite',
                  libelle: 'Demandes — maternité',
                  construire: (cx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        note('Les demandes dont l’ordonnance extérieure porte le service maternité — analyses et imagerie confondues. C’est une vue des registres, jamais un second registre.', LucideIcons.baby),
                        _tableau(cx, c, [...patDuService(dem, patMotifMaternite), ...patDuService(img, patMotifMaternite)],
                            titre: 'Demandes — maternité', vide: 'Aucune demande externe adressée à la maternité.'),
                      ])),
              OngletDef(
                  id: 'hospitalisation',
                  libelle: 'Demandes — hospitalisation',
                  construire: (cx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        note('Les demandes dont l’ordonnance extérieure porte le service hospitalisation. Vue des registres, jamais un second registre.', LucideIcons.bedDouble),
                        _tableau(cx, c, [...patDuService(dem, patMotifHospitalisation), ...patDuService(img, patMotifHospitalisation)],
                            titre: 'Demandes — hospitalisation', vide: 'Aucune demande externe adressée à l’hospitalisation.'),
                      ])),
              OngletDef(
                  id: 'imagerie',
                  libelle: 'Demandes — imagerie médicale (${img.length})',
                  construire: (cx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        note('Une échographie prescrite ailleurs se pratique ici comme une analyse prescrite ailleurs : la demande s’ouvre à l’accueil, la facture part à la caisse, et l’examen n’est exécutable qu’une fois réglé.', LucideIcons.scanLine),
                        _tableau(cx, c, img,
                            titre: 'Demandes d’imagerie — patients externes',
                            vide: 'Aucune demande d’imagerie externe.',
                            libelleExamen: 'Examen d’imagerie'),
                      ])),
              OngletDef(
                  id: 'resultats',
                  libelle: 'Résultats (${rendus.length})',
                  construire: (cx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        note('Rien ne se saisit avant la caisse. Le biologiste comme l’échographiste ne saisissent qu’un examen réglé : tant que la facture ne l’est pas, la commande de saisie reste visible et verrouillée, et elle dit chez qui la balle se trouve. La saisie elle-même se fait à son poste — l’accueil voit l’état et y mène, il n’ouvre pas une seconde voie d’écriture sur la même donnée.', LucideIcons.lock),
                        _tableau(cx, c, [...dem, ...img], titre: 'Résultats des patients externes', vide: 'Aucune demande externe.'),
                      ])),
            ]),
          ]);
        });
  }
}
