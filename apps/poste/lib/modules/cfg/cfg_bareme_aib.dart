import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/aib_poste.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
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
  String get description =>
      'Taux de l’acompte sur impôt assis sur les bénéfices par situation de l’acheteur et par qualité du tiers, daté, versionné et modifiable sans toucher au code.';
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
          final fileul = ServiceInstallation.de(c.magasin).rattache;
          return cfaPile([
            if (aValider > 0)
              NoteSigh(
                  'Proposition à valider. $aValider version(s) du barème ne sont pas encore arrêtées : la source de chaque taux est écrite sur sa fiche, et aucun texte réglementaire n’est au dépôt (articles 132 d) et 135 du CGI et mesure DGI du 07/09/2026 cités par la Direction, jamais lus au texte officiel).',
                  ton: TonSigh.attention,
                  icone: LucideIcons.clipboardCheck),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Situations actives', valeur: nombre(situations.length), icone: LucideIcons.users, ton: TonSigh.navy),
              KpiSigh(libelle: 'Versions du barème', valeur: nombre(versions.length), icone: LucideIcons.percent, ton: TonSigh.succes, indice: 'Deux barèmes datés'),
              KpiSigh(libelle: 'Versions en attente de validation', valeur: nombre(aValider), icone: LucideIcons.clipboardCheck, ton: aValider > 0 ? TonSigh.attention : TonSigh.neutre),
              KpiSigh(libelle: 'Imputations', valeur: nombre(imputations.length), icone: LucideIcons.scale, ton: TonSigh.info, indice: 'Opération par opération'),
            ]),
            OngletsSigh(onglets: [
              OngletDef(
                  id: 'versions',
                  libelle: 'Barème par version (${versions.length})',
                  construire: (_) => MiniTableauSigh(
                          vide: 'Aucune version : sans version, le taux est refusé (AIB_SANS_BAREME), jamais rendu à zéro.',
                          colonnes: [
                            ColonneMini('Situation', (v) => libSit(v['situation'])),
                            ColonneMini('Barème', (v) => famille(v['situation'])),
                            ColonneMini('Taux', (v) => '${v['taux']} %', droite: true),
                            ColonneMini('Du', (v) => aibDateFr('${v['dateEffet']}')),
                            ColonneMini('Au', (v) => v['dateFin'] == null ? 'Ouverte' : aibDateFr('${v['dateFin']}')),
                            ColonneMini('État', (v) => _etat(v, auj)),
                            ColonneMini('Arrêtée', (v) => v['aValider'] == true ? 'À valider' : 'Validée',
                                rendu: (v) => v['aValider'] == true ? const BadgeSigh('À valider', ton: TonSigh.attention) : const BadgeSigh('Validée', ton: TonSigh.succes)),
                            ColonneMini('Source', (v) => '${v['source'] ?? 'Non renseignée'}'.length > 90 ? '${v['source']}'.substring(0, 90) : '${v['source'] ?? 'Non renseignée'}'),
                          ],
                          lignes: versions)),
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
              OngletDef(id: 'achats', libelle: 'Achats à écrire', construire: (_) => SectionAibAchats(c: c, estMere: !fileul)),
            ]),
          ], espace: 12);
        });
  }
}
