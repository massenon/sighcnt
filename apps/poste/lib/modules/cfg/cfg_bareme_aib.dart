import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/aib_poste.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../kit/validation_poste.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfg_aib_achats.dart';
import '../../core/service_installation.dart';

/// « BARÈME DE L'AIB » AU POSTE (lot FISC-2, Direction du 16/11/2026) : le pendant de l'écran `cfg-bareme-aib` de la maquette. DEUX barèmes datés en base : la situation de
/// l'acheteur (1 % IFU actif, 5 % sans IFU actif, 3 % prestation de service) et la retenue sur la facture d'un tiers (3 % personne physique, 5 % personne morale). La facture d'un
/// PATIENT ne porte aucun AIB (le patient paie le montant total) : l'AIB s'impute opération par opération, par le comptable (onglet « Imputations ») ; le logiciel propose le
/// taux du barème à la date de l'opération, il ne décide jamais. Le barème se LIT ici (versions, situations, taux du jour, états) ; ses versions datées s'écrivent à la
/// maquette et à la mère (écriture d'une version au poste : hors lot, voir l'écart). Aucune collection fiscale ne va vers un téléphone.
class EcranBaremeAib extends StatefulWidget with EcranMaquette {
  const EcranBaremeAib({super.key});
  @override
  String get titre => 'Barème de l’AIB';
  @override
  String get description => 'Taux de l’acompte sur impôt assis sur les bénéfices par situation de l’acheteur, daté, versionné et modifiable sans toucher au code.';
  @override
  String get regle =>
      'Deux barèmes datés : la situation de l’acheteur et la retenue sur la facture d’un tiers (personne physique, personne morale). La facture d’un patient ne porte aucun AIB : il s’impute opération par opération, par le comptable, à l’onglet « Imputations » ; le logiciel propose le taux du barème à la date de l’opération, il ne décide jamais.';

  @override
  State<EcranBaremeAib> createState() => _EtatBaremeAib();
}

const _libOperation = {
  'achat_fournisseur': 'Achat auprès d’un fournisseur',
  'reglement_prescripteur': 'Règlement d’un prescripteur ou d’un prestataire externe',
  'reglement_assureur': 'Règlement reçu d’un assureur',
};

class _EtatBaremeAib extends State<EcranBaremeAib> {
  AibPoste _aib(ContexteEcran c) => AibPoste(c.magasin,
      auteur: () => c.agent.nom.isEmpty ? 'Utilisateur' : c.agent.nom,
      role: c.role,
      libelleRole: c.donnees?.matrice.libelle(c.role) ?? c.role,
      fileul: ServiceInstallation.de(c.magasin).rattache,
      horloge: () => c.aujourdhui);

  bool _droitImputer(ContexteEcran c) => c.donnees?.matrice.droitGeste(c.role, 'imputer_aib') ?? false;

  String _etat(Map<String, Object?> v, String auj) {
    if ('${v['dateEffet']}'.compareTo(auj) > 0) return 'À venir';
    if (v['dateFin'] != null && '${v['dateFin']}'.compareTo(auj) < 0) return 'Clôturée';
    return 'En vigueur';
  }

  void _imputer(BuildContext ctx, ContexteEcran c, AibPoste aib, List<Fiche> comptes) {
    final situations = aibSituationsActives(aib.donnees(), famille: 'tous');
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'operation',
          libelle: 'Opération',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [for (final e in _libOperation.entries) OptionChamp(e.key, e.value)]),
      const ChampDef(nom: 'reference', libelle: 'Référence de la pièce', requis: true, aide: 'Facture, règlement ou relevé auquel l’imputation se rattache.'),
      const ChampDef(nom: 'tiers', libelle: 'Tiers (fournisseur, prescripteur, prestataire, assureur)'),
      const ChampDef(nom: 'dateOperation', libelle: 'Date de l’opération', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'base', libelle: 'Base hors taxes (FCFA)', type: TypeChamp.nombre, requis: true),
      const ChampDef(
          nom: 'appliquer',
          libelle: 'Appliquer l’AIB à cette opération ?',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [OptionChamp('oui', 'Oui, appliquer'), OptionChamp('non', 'Non, ne pas appliquer')],
          aide: 'Le logiciel ne décide jamais : il propose un taux, vous répondez.'),
      ChampDef(
          nom: 'situation',
          libelle: 'Ligne du barème',
          type: TypeChamp.select,
          col: ColChamp.plein,
          condition: (controle: 'appliquer', quand: ['oui']),
          options: [for (final s in situations) OptionChamp('${s['code']}', '${s['libelle']}')]),
      const ChampDef(nom: 'taux', libelle: 'Taux retenu (%)', type: TypeChamp.nombre, col: ColChamp.tiers, condition: (controle: 'appliquer', quand: ['oui'])),
      ChampDef(
          nom: 'compte',
          libelle: 'Compte d’imputation',
          type: TypeChamp.select,
          col: ColChamp.plein,
          condition: (controle: 'appliquer', quand: ['oui']),
          options: [for (final k in comptes) OptionChamp('${k['num']}', '${k['num']} ${k['libelle']}')]),
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein,
          aide: 'Obligatoire pour ne pas appliquer, ou si le taux retenu n’est pas celui du barème à la date de l’opération.'),
    ], {'dateOperation': isoJour(c.aujourdhui)});
    afficherModale<void>(ctx,
        titre: 'Imputer l’AIB d’une opération',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh(
              'Appliquer ou non, quelle ligne, quel taux, quel compte : le comptable décide, opération par opération. Le taux du barème à la date de l’opération est une proposition. L’imputation est signée et journalisée ; elle n’écrit aucune écriture comptable.',
              icone: LucideIcons.scale),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('aib:imputer:enregistrer'),
                  libelle: 'Enregistrer l’imputation',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final saisie = {
                      'operation': v['operation'],
                      'reference': v['reference'],
                      'tiers': v['tiers'],
                      'dateOperation': v['dateOperation'],
                      'base': v['base'],
                      'appliquer': v['appliquer'] == 'oui' ? true : (v['appliquer'] == 'non' ? false : null),
                      'situation': v['situation'],
                      'taux': v['taux'],
                      'compte': v['compte'],
                      'motif': v['motif'],
                    };
                    final r = aib.imputer(saisie, droit: _droitImputer(c));
                    if (r['ok'] != true) {
                      ToastsSigh.afficher(ctx, '${r['code']} : ${r['motif']}', type: TypeToast.erreur, detail: '${r['geste'] ?? ''}', duree: const Duration(seconds: 12));
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Imputation enregistrée.', type: TypeToast.succes);
                  }),
            ]);
  }

  bool _peutEcrire(ContexteEcran c) => aibRolesEcriture.contains(c.role) && !ServiceInstallation.de(c.magasin).rattache;

  /// « Nouvelle version » : une version DATÉE du barème (situation, taux, date d'effet, source, motif). Elle ferme la précédente à la veille ; une version ne se réécrit pas ; la source
  /// est dite (on n'invente pas un taux). Arrêtée à l'enregistrement par un profil de la famille de validation, « à valider » sinon.
  void _nouvelleVersion(BuildContext ctx, ContexteEcran c, AibPoste aib) {
    final situations = aibSituationsActives(aib.donnees(), famille: 'tous');
    final f = ControleurFormulaire([
      ChampDef(nom: 'situation', libelle: 'Situation', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [for (final s in situations) OptionChamp('${s['code']}', '${s['libelle']}')]),
      const ChampDef(nom: 'taux', libelle: 'Taux (%)', type: TypeChamp.nombre, requis: true, col: ColChamp.tiers, aide: 'Pourcentage entier.'),
      const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true, col: ColChamp.tiers, aide: 'Postérieure à la version la plus récente de la situation, qui sera fermée à la veille.'),
      const ChampDef(nom: 'source', libelle: 'Source du taux', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein, aide: 'Le texte, la décision ou la déclaration d’où vient le taux. On n’invente pas un taux.'),
      const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
    ], {'dateEffet': isoJour(c.aujourdhui)});
    afficherModale<void>(ctx,
        titre: 'Nouvelle version du barème',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh('La version ferme la précédente de la même situation à la veille de sa date d’effet ; une version ne se réécrit pas.', icone: LucideIcons.calendarClock),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('aib:version:enregistrer'),
                  libelle: 'Enregistrer la version',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final r = aib.nouvelleVersion({'situation': v['situation'], 'taux': v['taux'], 'dateEffet': v['dateEffet'], 'source': v['source'], 'motif': v['motif']});
                    if (r['ok'] != true) {
                      ToastsSigh.afficher(ctx, '${r['code']} : ${r['motif']}', type: TypeToast.erreur, detail: '${r['geste'] ?? ''}', duree: const Duration(seconds: 12));
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Version enregistrée.', type: TypeToast.succes, detail: r['enAttenteDeValidation'] == true ? 'Elle naît « à valider ».' : 'Arrêtée à l’enregistrement (profil de validation).');
                  }),
            ]);
  }

  void _annuler(BuildContext ctx, ContexteEcran c, AibPoste aib, Fiche x) {
    final f = ControleurFormulaire(const [ChampDef(nom: 'motif', libelle: 'Motif de l’annulation', requis: true, col: ColChamp.plein)], const {});
    afficherModale<void>(ctx,
        titre: 'Annuler l’imputation ${x['reference']}',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh('L’imputation est archivée avec son motif (RG-14) ; l’opération redevient imputable.', icone: LucideIcons.undo2),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Retour', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('aib:imputer:annuler'),
                  libelle: 'Annuler l’imputation',
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final r = aib.annuler('${x['id']}', '${v['motif']}', droit: _droitImputer(c));
                    if (r['ok'] != true) {
                      ToastsSigh.afficher(ctx, '${r['code']} : ${r['motif']}', type: TypeToast.erreur, detail: '${r['geste'] ?? ''}');
                      return;
                    }
                    fermer();
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final aib = _aib(c);
    AibPoste.amorcer(c.magasin);
    return ListenableBuilder(
        listenable: Listenable.merge([for (final n in const ['situationsAib', 'baremeAib', 'imputationsAib', 'parametres', 'comptes', 'facturesFournisseurs']) c.magasin.collection(n)]),
        builder: (ctx, _) {
          final d = aib.donnees();
          final auj = aib.aujourdhui;
          final versions = c.magasin.collection('baremeAib').actives.toList()
            ..sort((a, b) {
              final k = '${a['situation']}'.compareTo('${b['situation']}');
              return k != 0 ? k : '${b['dateEffet']}'.compareTo('${a['dateEffet']}');
            });
          final situations = aibSituationsActives(d, famille: 'tous');
          String libSit(Object? code) {
            for (final s in situations) {
              if (s['code'] == code) return '${s['libelle']}';
            }
            return '$code';
          }

          String famille(Object? code) {
            for (final s in situations) {
              if (s['code'] == code) return (s['famille'] ?? 'acheteur') == 'retenue_tiers' ? 'Retenue sur facture d’un tiers' : 'Situation de l’acheteur';
            }
            return '—';
          }

          final aValider = versions.where((v) => v['aValider'] == true).length;
          final imputations = aib.imputations.actives.toList()..sort((a, b) => '${b['dateOperation']}'.compareTo('${a['dateOperation']}'));
          final comptes = [
            for (final k in c.magasin.collection('comptes').actives) k
          ]..sort((a, b) => '${a['num']}'.compareTo('${b['num']}'));
          final droit = _droitImputer(c);
          final br0 = aibBranchementALaDate(d, auj);
          final fileul = ServiceInstallation.de(c.magasin).rattache;
          return cfaPile([
            if (aValider > 0)
              NoteSigh(
                  'Proposition à valider. $aValider version(s) du barème ne sont pas encore arrêtées : la source de chaque taux est écrite sur sa fiche, et aucun texte réglementaire n’est au dépôt (articles 132 d) et 135 du CGI et mesure DGI du 07/09/2026 cités par la Direction, jamais lus au texte officiel).',
                  ton: TonSigh.attention,
                  icone: LucideIcons.clipboardCheck),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Situations actives', valeur: nombre(situations.length), icone: LucideIcons.users, ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Versions en vigueur',
                  valeur: nombre(versions.where((v) => _etat(v, auj) == 'En vigueur').length),
                  icone: LucideIcons.percent,
                  ton: TonSigh.succes,
                  indice: 'À la date du jour'),
              KpiSigh(libelle: 'Versions en attente de validation', valeur: nombre(aValider), icone: LucideIcons.clipboardCheck, ton: aValider > 0 ? TonSigh.attention : TonSigh.neutre),
              KpiSigh(libelle: 'Versions archivées', valeur: nombre(c.magasin.collection('baremeAib').toutes.where((v) => v['statut'] == 'archive').length), icone: LucideIcons.archive, ton: TonSigh.neutre),
              KpiSigh(libelle: 'Imputations', valeur: nombre(imputations.length), icone: LucideIcons.scale, ton: TonSigh.info, indice: 'Opération par opération'),
            ]),
            OngletsSigh(onglets: [
              OngletDef(
                  id: 'versions',
                  libelle: 'Barème par version (${versions.length})',
                  construire: (_) => TableauSigh(
                      titre: 'Versions du barème',
                      lignes: versions,
                      taillePage: 20,
                      nomExport: 'bareme-aib',
                      messageVide: 'Aucune version : sans version, le taux est refusé (AIB_SANS_BAREME), jamais rendu à zéro.',
                      actions: [
                        if (c.droit.editer && _peutEcrire(c))
                          BoutonSigh(key: const Key('aib:nouvelle-version'), libelle: 'Nouvelle version', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _nouvelleVersion(context, c, aib)),
                      ],
                      actionsLigne: (ctx, v) => [
                            if (ValidationPoste(c).bouton(ctx, 'bareme_aib', v['id'], apres: () => setState(() {})) case final b?) b,
                          ],
                      colonnes: [
                        ColonneTableau(cle: 'situation', libelle: 'Situation', texte: (v) => libSit(v['situation']), rendu: (_, v) => Text(libSit(v['situation']), style: const TextStyle(fontWeight: FontWeight.w500))),
                        ColonneTableau(cle: 'taux', libelle: 'Taux', droite: true, texte: (v) => '${v['taux']} %', rendu: (_, v) => Text('${v['taux']} %', style: const TextStyle(fontWeight: FontWeight.w600))),
                        ColonneTableau(cle: 'dateEffet', libelle: 'Du', texte: (v) => aibDateFr('${v['dateEffet']}'), valeur: (v) => '${v['dateEffet']}'),
                        ColonneTableau(cle: 'dateFin', libelle: 'Au', texte: (v) => v['dateFin'] == null ? 'Ouverte' : aibDateFr('${v['dateFin']}'), valeur: (v) => '${v['dateFin'] ?? '9999'}'),
                        ColonneTableau(cle: 'etat', libelle: 'État', texte: (v) => _etat(v, auj), valeur: (v) => _etat(v, auj)),
                        ColonneTableau(
                            cle: 'arrete',
                            libelle: 'Arrêtée',
                            texte: (v) => ValidationPoste(c).texteBadge('bareme_aib', v['id']),
                            rendu: (ctx, v) => ValidationPoste(c).badge('bareme_aib', v['id']) ?? const BadgeSigh('À valider', ton: TonSigh.attention)),
                        ColonneTableau(cle: 'source', libelle: 'Source', texte: (v) => '${v['source'] ?? 'Non renseignée'}', rendu: (_, v) => Text(('${v['source'] ?? 'Non renseignée'}').length > 90 ? ('${v['source']}').substring(0, 90) : '${v['source'] ?? 'Non renseignée'}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500))),
                      ])),
              OngletDef(
                  id: 'situations',
                  libelle: 'Situations et lignes (${situations.length})',
                  construire: (_) => MiniTableauSigh(colonnes: [
                        ColonneMini('Code', (s) => '${s['code']}', rendu: (s) => cfaCode(s['code'])),
                        ColonneMini('Libellé', (s) => '${s['libelle']}'),
                        ColonneMini('Barème', (s) => famille(s['code'])),
                        ColonneMini('Taux du jour', (s) {
                          final t = aibTauxALaDate(d, '${s['code']}', auj);
                          return t['ok'] == true ? '${t['taux']} %' : 'Sans barème';
                        }, droite: true),
                      ], lignes: situations)),
              OngletDef(
                  id: 'imputations',
                  libelle: 'Imputations (${imputations.length})',
                  construire: (_) => cfaPile([
                        const NoteSigh(
                            'L’AIB s’impute opération par opération, par le comptable. Achats auprès des fournisseurs, règlements des prescripteurs et des prestataires externes, règlements reçus des assureurs : appliquer ou non, quelle ligne, quel compte, dépend de conditions que le logiciel ne connaît pas. Il propose le taux du barème à la date de l’opération ; il ne décide jamais. Le patient, lui, paie le montant total : sa facture ne porte aucun AIB.',
                            icone: LucideIcons.scale),
                        if (droit)
                          Align(
                              alignment: Alignment.centerLeft,
                              child: BoutonSigh(
                                  key: const Key('aib:imputer'),
                                  libelle: 'Imputer une opération',
                                  icone: LucideIcons.plus,
                                  taille: TailleBouton.sm,
                                  onPressed: () => _imputer(context, c, aib, comptes))),
                        MiniTableauSigh(
                            vide: 'Aucune imputation enregistrée.',
                            colonnes: [
                              ColonneMini('Date', (x) => aibDateFr('${x['dateOperation']}')),
                              ColonneMini('Opération', (x) => _libOperation['${x['operation']}'] ?? '${x['operation']}'),
                              ColonneMini('Référence', (x) => '${x['reference']}', rendu: (x) => cfaCode(x['reference'])),
                              ColonneMini('Tiers', (x) => '${x['tiers'] ?? '—'}'),
                              ColonneMini('Base', (x) => money(x['base'], avecDevise: false), droite: true),
                              ColonneMini('Décision', (x) => x['appliquer'] == true ? 'Appliqué ${x['taux']} %' : 'Non appliqué',
                                  rendu: (x) => x['appliquer'] == true
                                      ? BadgeSigh('Appliqué ${x['taux']} %', ton: x['horsProposition'] == true ? TonSigh.attention : TonSigh.succes)
                                      : const BadgeSigh('Non appliqué', ton: TonSigh.neutre)),
                              ColonneMini('AIB', (x) => x['appliquer'] == true ? money(x['montant'], avecDevise: false) : '—', droite: true),
                              ColonneMini('Compte', (x) => '${x['compte'] ?? '—'}'),
                              ColonneMini('Signée par', (x) => '${x['signeePar']} (${x['signeeRole']})'),
                              ColonneMini('', (x) => '', droite: true,
                                  rendu: (x) => droit
                                      ? BoutonIcone(key: Key('aib:annuler:${x['reference']}'), icone: LucideIcons.undo2, libelle: 'Annuler l’imputation', onPressed: () => _annuler(context, c, aib, x))
                                      : const SizedBox.shrink()),
                            ],
                            lignes: imputations),
                      ], espace: 12)),
              OngletDef(
                  id: 'reglages',
                  libelle: 'Réglages',
                  construire: (_) {
                    final charge = aibChargeALaDate(d, auj);
                    final br = aibBranchementALaDate(d, auj);
                    return cfaPile([
                      const NoteSigh(
                          'Les réglages de l’AIB (charge des 5 %, branchement différé sur les achats, deux comptes) se règlent aux paramètres du poste, carte « AIB » : droit, compte au plan, motif, date postérieure, activation complète. Ici, leur état à la date du jour.',
                          icone: LucideIcons.sliders),
                      MiniTableauSigh(colonnes: [
                        ColonneMini('Réglage', (x) => '${x['libelle']}'),
                        ColonneMini('Valeur à la date', (x) => '${x['valeur']}'),
                      ], lignes: [
                        {'libelle': 'Qui supporte le prélèvement de 5 %', 'valeur': charge['ok'] == true ? '${charge['libelle']}${charge['arrete'] == true ? '' : ' (réglage non arrêté)'}' : '${charge['code']}'},
                        {'libelle': 'Brancher l’AIB sur les écritures d’achat', 'valeur': br['actif'] == true ? 'Activé' : 'Désactivé (le moteur liste, n’écrit rien)'},
                      ]),
                    ], espace: 12);
                  }),
              OngletDef(id: 'achats', libelle: 'Achats à écrire', construire: (_) => SectionAibAchats(c: c, estMere: !fileul)),
              OngletDef(
                  id: 'abrancher',
                  libelle: 'Ce qu’il faudrait y brancher',
                  construire: (_) => cfaPile([
                        const NoteSigh(
                            'Cette liste est en lecture seule : le moteur dit ce qu’il faudrait brancher sur le barème, il ne branche rien. Brancher l’AIB sur les écritures d’achat fausserait la comptabilité sans décision de la Direction.',
                            icone: LucideIcons.listChecks),
                        MiniTableauSigh(colonnes: [
                          ColonneMini('Lieu', (x) => '${x['lieu']}'),
                          ColonneMini('État', (x) => '${x['etat']}', rendu: (x) => x['etat'] == 'Branché' ? const BadgeSigh('Branché', ton: TonSigh.succes) : const BadgeSigh('Non branché', ton: TonSigh.attention)),
                          ColonneMini('Ce qu’il faudrait faire', (x) => '${x['detail']}'),
                        ], lignes: [
                          {
                            'lieu': 'Factures fournisseurs et bons de commande (M7)',
                            'etat': br0['actif'] == true ? 'Branché' : 'Non branché',
                            'detail': br0['actif'] == true
                                ? 'Le branchement est actif : chaque facture listée à l’onglet « Achats à écrire » reçoit sa pièce en brouillon.'
                                : 'Désactivé : les achats sont listés avec leur taux, sans écriture. L’activation exige les deux comptes et la charge arrêtés.'
                          },
                          {
                            'lieu': 'Facture d’un patient (émission, registre des paiements, file de caisse)',
                            'etat': 'Branché',
                            'detail': 'Aucun AIB : le patient paie le montant total, seul affiché sur sa facture de caisse ; le moteur refuse un taux demandé (AIB_FACTURE_PATIENT). L’AIB s’impute opération par opération, par le comptable (onglet « Imputations »).'
                          },
                          {
                            'lieu': 'Règlements à des tiers et règlements reçus des assureurs',
                            'etat': 'Branché',
                            'detail': 'S’imputent un à un, par le comptable (onglet « Imputations »), sans écriture comptable.'
                          },
                          {
                            'lieu': 'Retenues à la source et échéance mensuelle de l’AIB (calendrier fiscal)',
                            'etat': 'Non branché',
                            'detail': 'L’échéance mensuelle ne lit aucun taux. À brancher pour rapprocher l’AIB retenu de l’AIB déclaré ; imputable sur l’impôt sur les bénéfices, pas une charge.'
                          },
                        ]),
                      ], espace: 12)),
            ]),
          ], espace: 12);
        });
  }
}
