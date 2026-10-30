import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'res_commun.dart';

/// Les états qu'un échantillon traverse AVANT que le laboratoire ait quelque chose à saisir (`aTraiter`).
const _etatsATraiter = ['en_attente', 'attente_prelevement', 'preleve', 'en_cours', 'saisi'];

/// QUAND LA SAISIE EST-ELLE OUVERTE ? Seulement sur un échantillon PARVENU au laboratoire. La demande reste VISIBLE — le laboratoire a besoin de
/// voir ce qui arrive — mais le bouton dit pourquoi il ne s'ouvre pas et à quel poste la balle se trouve.
const _blocagesSaisie = {
  'en_attente': (
    'La demande est en attente de règlement.',
    'Le patient doit d’abord passer à la caisse.'
  ),
  'attente_prelevement': (
    'Le prélèvement n’a pas encore été fait.',
    'La salle de prélèvement doit appeler le patient, puis acheminer l’échantillon.'
  ),
  'preleve': (
    'L’échantillon est prélevé mais pas encore parvenu au laboratoire.',
    'La salle de prélèvement doit le transmettre avec son bon.'
  ),
};

/// `m5-resultats` — « Saisie des résultats » : les DEUX VERROUS. La validation technique atteste la saisie ; le prescripteur ne voit encore rien.
/// La validation biologique rend le résultat opposable. Après elle, une correction devient une RECTIFICATION versionnée.
///
/// [fonction], [secteur], [agentId] : ce que la coque du poste ne porte pas encore (voir `ProfilLabo`).
class EcranResultats extends StatefulWidget with EcranMaquette {
  const EcranResultats(
      {super.key, this.fonction, this.secteur, this.agentId, this.du, this.au});

  /// Plage de dates initiale (ISO) — lien profond ; les champs « Du » / « Au » la reprennent.
  final String? du;
  final String? au;
  final String? fonction;
  final String? secteur;
  final String? agentId;

  @override
  String get titre => 'Saisie des résultats';

  @override
  String get description =>
      'Enregistrement, validation biologique et archivage numérique des résultats d’analyses.';

  @override
  String get regle =>
      'Un résultat d’analyse n’est pas visible de tous. Le médecin y accède intégralement ; la sage-femme aux seuls résultats demandés par son secteur ; l’infirmier, l’aide-soignant et l’accueil n’y accèdent pas. Le laboratoire produit les résultats et les remet directement aux patients adressés de l’extérieur. Ce qui est masqué est signalé comme tel, jamais présenté comme absent.';

  @override
  State<EcranResultats> createState() => _EtatResultats();
}

class _EtatResultats extends State<EcranResultats> {
  late final ControleurFormulaire _du = ControleurFormulaire(
      [const ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date)],
      {'du': widget.du ?? ''});
  late final ControleurFormulaire _au = ControleurFormulaire(
      [const ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date)],
      {'au': widget.au ?? ''});

  /// La maquette repeint toute sa vue (onglets compris) à chaque `afficher()` : le numéro de génération fait de même.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _du.addListener(_repeindre);
    _au.addListener(_repeindre);
  }

  void _repeindre() {
    if (mounted) setState(() => _gen++);
  }

  @override
  void dispose() {
    _du.dispose();
    _au.dispose();
    super.dispose();
  }

  bool _dansPlage(Fiche r) {
    final brut = _vrai(r['dateHeure']) ? '${r['dateHeure']}' : (_vrai(r['date']) ? '${r['date']}' : '');
    final d = brut.length > 10 ? brut.substring(0, 10) : brut;
    final du = '${_du['du'] ?? ''}', au = '${_au['au'] ?? ''}';
    if (du.isNotEmpty && d.compareTo(du) < 0) return false;
    if (au.isNotEmpty && d.compareTo(au) > 0) return false;
    return true;
  }

  static bool _vrai(Object? v) => v != null && v != false && v != '' && v != 0;

  void _poser(String du, String au) {
    _du.removeListener(_repeindre);
    _au.removeListener(_repeindre);
    _du.poser('du', du);
    _au.poser('au', au);
    _du.addListener(_repeindre);
    _au.addListener(_repeindre);
    _repeindre();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final p = profilLabo(c,
        fonction: widget.fonction,
        secteur: widget.secteur,
        agentId: widget.agentId);
    return ListenableBuilder(
      listenable: ecouteLabo(c),
      builder: (context, _) {
        final tous = c.magasin.collection('demandesAnalyses').actives;
        final visibles = demandesVisibles(c, p);
        final filtrees = visibles.where(_dansPlage).toList();
        final aTraiter = [
          for (final r in filtrees)
            if (_etatsATraiter.contains(r['etatAnalyse'])) r
        ];
        final aValider = [
          for (final r in filtrees)
            if (r['etatAnalyse'] == 'valide_technique') r
        ];
        final valides = [
          for (final r in filtrees)
            if (estRendu(r['etatAnalyse'])) r
        ];
        final cap = p.cap;
        final aujourdhui = DateTime(c.aujourdhui.year, c.aujourdhui.month, c.aujourdhui.day);
        final sect = libelleSecteur(p.session.secteur);

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                SizedBox(width: 170, child: FormulaireSigh(controleur: _du)),
                SizedBox(width: 170, child: FormulaireSigh(controleur: _au)),
                BoutonSigh(
                    key: const Key('res:aujourdhui'),
                    libelle: 'Aujourd’hui',
                    icone: LucideIcons.calendar,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _poser(iso(aujourdhui), iso(aujourdhui))),
                BoutonSigh(
                    key: const Key('res:sept-jours'),
                    libelle: 'Sept derniers jours',
                    icone: LucideIcons.calendarDays,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _poser(
                        iso(DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day - 6)),
                        iso(aujourdhui))),
                BoutonSigh(
                    key: const Key('res:toutes-dates'),
                    libelle: 'Toutes les dates',
                    icone: LucideIcons.x,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _poser('', '')),
              ])),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Résultats à saisir',
                valeur: nombre(aTraiter.length),
                icone: LucideIcons.filePenLine,
                ton: TonSigh.attention),
            KpiSigh(
                libelle: 'À valider biologiquement',
                valeur: nombre(aValider.length),
                icone: LucideIcons.shieldCheck,
                ton: aValider.isNotEmpty ? TonSigh.navy : TonSigh.neutre,
                indice: 'Non visibles du prescripteur'),
            KpiSigh(
                libelle: 'Rendus au prescripteur',
                valeur: nombre(valides.length),
                icone: LucideIcons.fileCheck2,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Rectifiés',
                valeur: nombre(valides.where((r) => r['etatAnalyse'] == 'rectifie').length),
                icone: LucideIcons.history,
                ton: TonSigh.danger,
                indice: 'Version rectificative émise'),
          ]),
          const SizedBox(height: 16),
          // Ce qui est masqué doit être annoncé : sans cela, l'agent croit à une donnée manquante au lieu d'une restriction.
          if (cap.voirResultats == 'aucun') ...[
            NoteSigh(
                '${cap.label} — aucun résultat d’analyse ne vous est accessible. ${cap.note ?? ''} Les ${nombre(tous.length)} résultats du laboratoire existent : ils sont réservés aux prescripteurs. Pour en obtenir un, en faire la demande au médecin.',
                ton: TonSigh.attention,
                icone: LucideIcons.shieldAlert),
            const SizedBox(height: 16),
          ] else if (cap.voirResultats == 'secteur') ...[
            NoteSigh(
                '${cap.label} — périmètre limité à ${sect ?? 'votre secteur'}. ${nombre(tous.length - visibles.length)} résultat(s) demandé(s) par d’autres secteurs sont masqués : ils ne relèvent pas de votre suivi.',
                icone: LucideIcons.shieldCheck),
            const SizedBox(height: 16),
          ] else if (cap.voirResultats == 'produits') ...[
            const NoteSigh(
                'Laboratoire. Vous produisez ces résultats et les remettez directement aux patients adressés de l’extérieur ; ceux des patients internes vont au médecin prescripteur.',
                icone: LucideIcons.flaskConical),
            const SizedBox(height: 16),
          ],
          const NoteSigh(
              'Deux verrous. La validation technique atteste la saisie ; le prescripteur ne voit encore rien. La validation biologique rend le résultat opposable — c’est elle qui le porte au dossier du médecin. Entre les deux, le laboratoire relit. Après elle, une correction devient une rectification versionnée, et le prescripteur est averti que ce qu’il a lu a changé.',
              icone: LucideIcons.shieldCheck),
          const SizedBox(height: 16),
          OngletsSigh(key: ValueKey(_gen), onglets: [
            OngletDef(
                id: 'attente',
                libelle: 'À saisir',
                compte: aTraiter.length,
                construire: (_) => _aSaisir(context, c, p, aTraiter)),
            OngletDef(
                id: 'relecture',
                libelle: 'À valider biologiquement',
                compte: aValider.length,
                construire: (_) => _relecture(context, c, p, aValider)),
            OngletDef(
                id: 'valides',
                libelle: 'Rendus au prescripteur',
                compte: valides.length,
                construire: (_) => _rendus(context, c, valides)),
          ]),
        ]);
      },
    );
  }

  // --- 1. À saisir ----------------------------------------------------------------------------------------------------

  Widget _aSaisir(BuildContext ctx, ContexteEcran c, ProfilLabo p, List<Fiche> rows) {
    void bloquee(({String motif, String suite}) b) => ToastsSigh.afficher(
        ctx, 'Saisie impossible.',
        type: TypeToast.erreur, detail: '${b.motif} ${b.suite}');
    ({String motif, String suite})? blocage(Fiche r) {
      final b = _blocagesSaisie['${r['etatAnalyse']}'];
      return b == null ? null : (motif: b.$1, suite: b.$2);
    }

    return TableauSigh(
      colonnes: colonnesDemande(),
      lignes: rows,
      taillePage: 12,
      nomExport: 'resultats-a-saisir',
      messageVide: 'Aucun résultat en attente de saisie.',
      // Un bouton désactivé que le clic sur la ligne contournerait ne protégerait rien.
      alClicLigne: (r) {
        final b = blocage(r);
        if (b != null) {
          bloquee(b);
          return;
        }
        _ouvrirSaisie(ctx, c, p, r);
      },
      actionsLigne: (_, r) {
        final b = blocage(r);
        if (b != null) {
          return [
            commandeVerrouillee(
                cle: Key('res:saisir-verrou:${r['reference']}'),
                libelle: 'Saisir le résultat',
                raison: '${b.motif} ${b.suite}',
                alClic: () => bloquee(b))
          ];
        }
        return [
          commandeLigne(BoutonSigh(
              key: Key('res:saisir:${r['reference']}'),
              libelle: 'Saisir le résultat',
              icone: LucideIcons.filePenLine,
              taille: TailleBouton.sm,
              onPressed: () => _ouvrirSaisie(ctx, c, p, r)))
        ];
      },
    );
  }

  // --- 2. À valider biologiquement -----------------------------------------------------------------------------------

  Widget _relecture(BuildContext ctx, ContexteEcran c, ProfilLabo p, List<Fiche> rows) {
    final cap = p.cap;
    final peut = cap.validerBiologique != null && cap.validerBiologique != false;
    final interim = cap.validerBiologique == 'interim';
    final tri = [for (var i = 0; i < rows.length; i++) (i, rows[i])]..sort((a, b) {
        final k = '${b.$2['valideTechniqueLe'] ?? ''}'.compareTo('${a.$2['valideTechniqueLe'] ?? ''}');
        return k != 0 ? k : a.$1.compareTo(b.$1);
      });
    final lignes = [for (final x in tri) x.$2];
    final colonnes = colonnesDemande();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          peut
              ? (interim
                  ? 'Validation par intérim. Vous portez la validation biologique en l’absence du biologiste médical. Votre qualité d’intérimaire sera portée sur le compte rendu : la pièce doit dire qui a signé, et à quel titre.'
                  : 'Validation biologique. Relire l’ensemble avant de valider : au-delà, le résultat est visible du prescripteur, et toute correction devient une rectification versionnée dont il sera averti.')
              : '${cap.label} — vous n’êtes pas habilité à porter la validation biologique. Ces résultats attendent le biologiste médical. Ils sont saisis et techniquement validés, mais le prescripteur ne les voit pas encore.',
          ton: peut ? (interim ? TonSigh.attention : TonSigh.info) : TonSigh.attention,
          icone: LucideIcons.shieldCheck),
      const SizedBox(height: 12),
      TableauSigh(
        colonnes: [
          ...colonnes.take(4),
          ColonneTableau(
              cle: 'resultat',
              libelle: 'Résultat saisi',
              texte: (r) => '${r['resultat'] ?? '—'}',
              rendu: (_, r) => Text('${_vrai2(r['resultat']) ? r['resultat'] : '—'}',
                  style: styleLabo(14))),
          ColonneTableau(
              cle: 'conclusion',
              libelle: 'Conclusion',
              texte: (r) => '${r['conclusion'] ?? '—'}',
              rendu: (_, r) => badgeConclusion(r['conclusion'])),
          const ColonneTableau(cle: 'valideTechniquePar', libelle: 'Validation technique'),
        ],
        lignes: lignes,
        taillePage: 12,
        nomExport: 'resultats-a-valider',
        messageVide: 'Aucun résultat en attente de validation biologique.',
        alClicLigne: (r) => afficherTiroir<void>(ctx,
            titre: '${r['analyse']}',
            sousTitre: '${r['patient']} — ${r['reference']}',
            corps: detailDemande(r),
            pied: (_) => [
                  BoutonSigh(
                      libelle: 'Relire et corriger',
                      icone: LucideIcons.pencil,
                      onPressed: () => _ouvrirSaisie(ctx, c, p, r))
                ]),
        actionsLigne: (_, r) {
          // LA CONTINUITÉ VAUT AUSSI POUR LA RELECTURE : laisser corriger la saisie d'un collègue puis le laisser signer viderait la règle de son sens.
          final cont = continuiteRespectee(r, agentId: p.agentId, agentNom: p.agentNom);
          return [
            if (cont.ok)
              commandeLigne(BoutonIcone(
                  key: Key('res:relire:${r['reference']}'),
                  icone: LucideIcons.pencil,
                  libelle: 'Relire et corriger avant validation',
                  onPressed: () => _ouvrirSaisie(ctx, c, p, r)))
            else
              // Désactivé et NOMMANT le préleveur : un bouton absent laisserait croire à un défaut d'affichage.
              commandeLigne(Tooltip(
                  message: 'Prélevé par ${cont.preleveur ?? 'un autre agent'} — à lui de relire',
                  child: Opacity(
                      opacity: 0.5,
                      child: BoutonIcone(
                          key: Key('res:verrou-relecture:${r['reference']}'),
                          icone: LucideIcons.lock,
                          libelle: 'Prélevé par ${cont.preleveur ?? 'un autre agent'} — à lui de relire',
                          onPressed: () => ToastsSigh.afficher(
                              ctx, 'Relecture réservée au préleveur.',
                              type: TypeToast.erreur, detail: cont.motif))))),
            if (peut && cont.ok)
              commandeLigne(BoutonSigh(
                  key: Key('res:valider-bio:${r['reference']}'),
                  libelle: interim ? 'Valider par intérim' : 'Validation biologique',
                  icone: LucideIcons.shieldCheck,
                  taille: TailleBouton.sm,
                  onPressed: () => _validerBio(ctx, c, p, r, interim))),
          ];
        },
      ),
    ]);
  }

  static bool _vrai2(Object? v) => v != null && v != false && v != '' && v != 0;

  // --- 3. Rendus au prescripteur --------------------------------------------------------------------------------------

  Widget _rendus(BuildContext ctx, ContexteEcran c, List<Fiche> rows) {
    final colonnes = colonnesDemande();
    return TableauSigh(
      colonnes: [
        ...colonnes.take(4),
        ColonneTableau(
            cle: 'resultat',
            libelle: 'Résultat',
            texte: (r) => '${r['resultat'] ?? '—'}',
            rendu: (_, r) => Text('${_vrai2(r['resultat']) ? r['resultat'] : '—'}',
                style: styleLabo(14,
                    couleur: JetonsShell.navy800, poids: FontWeight.w600))),
        ColonneTableau(
            cle: 'conclusion',
            libelle: 'Conclusion',
            texte: (r) => '${r['conclusion'] ?? '—'}',
            rendu: (_, r) => badgeConclusion(r['conclusion'])),
        ColonneTableau(
            cle: 'valideBiologiquePar',
            libelle: 'Validation biologique',
            texte: (r) => '${r['valideBiologiquePar'] ?? r['laborantin'] ?? '—'}',
            rendu: (_, r) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          '${_vrai2(r['valideBiologiquePar']) ? r['valideBiologiquePar'] : (_vrai2(r['laborantin']) ? r['laborantin'] : '—')}',
                          overflow: TextOverflow.ellipsis,
                          style: styleLabo(14)),
                      if (_vrai2(r['validationInterim']))
                        Text('par intérim',
                            style: styleLabo(12, couleur: JetonsShell.warning700)),
                    ])),
        ColonneTableau(
            cle: 'version',
            libelle: 'Version',
            droite: true,
            valeur: (r) => _vrai2(r['version']) ? r['version'] : 1,
            texte: (r) => r['etatAnalyse'] == 'rectifie'
                ? 'v${_vrai2(r['version']) ? r['version'] : 2} — rectifié'
                : 'v1',
            rendu: (_, r) => r['etatAnalyse'] != 'rectifie'
                ? Text('v1', style: styleLabo(12, couleur: JetonsShell.slate400))
                : BadgeSigh('v${_vrai2(r['version']) ? r['version'] : 2} — rectifié',
                    ton: TonSigh.danger)),
      ],
      lignes: rows,
      taillePage: 12,
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      nomExport: 'resultats-valides',
      alClicLigne: (r) => afficherTiroir<void>(ctx,
          titre: '${r['analyse']}',
          sousTitre: '${r['patient']} — ${r['reference']}',
          corps: detailDemande(r),
          pied: (_) => [
                BoutonSigh(
                    libelle: 'Imprimer',
                    icone: LucideIcons.printer,
                    onPressed: () => imprimerResultat(ctx, r))
              ]),
      actionsLigne: (_, r) => [
        BoutonIcone(
            key: Key('res:compte-rendu:${r['reference']}'),
            icone: LucideIcons.fileText,
            libelle: 'Compte rendu complet du patient',
            onPressed: () => imprimerCompteRendu(ctx, r['patientId'], [
                  for (final d in c.magasin.collection('demandesAnalyses').actives)
                    if (d['patientId'] == r['patientId']) d
                ])),
        BoutonIcone(
            key: Key('res:imprimer:${r['reference']}'),
            icone: LucideIcons.printer,
            libelle: 'Imprimer ce seul résultat',
            onPressed: () => imprimerResultat(ctx, r)),
        BoutonIcone(
            key: Key('res:corriger:${r['reference']}'),
            icone: LucideIcons.pencil,
            libelle: 'Corriger',
            onPressed: () => _ouvrirSaisie(ctx, c, p0(c), r)),
      ],
    );
  }

  ProfilLabo p0(ContexteEcran c) => profilLabo(c,
      fonction: widget.fonction, secteur: widget.secteur, agentId: widget.agentId);

  // --- Le second verrou ---------------------------------------------------------------------------------------------

  /// Applique le patch d'un geste et sa notification ; rend la fonction qui restitue la DEMANDE (la notification déjà émise reste).
  VoidCallback _ecrire(ContexteEcran c, Fiche r, GesteResultat g) {
    final undo = c.magasin.collection('demandesAnalyses').mettreAJour(r['id'], g.patch);
    final nt = g.notification;
    if (nt != null) {
      c.magasin
          .collection('notifications')
          .inserer({...nt, 'creeLe': c.aujourdhui.toUtc().toIso8601String()}, prefixe: 'NOT');
    }
    return undo;
  }

  void _validerBio(BuildContext ctx, ContexteEcran c, ProfilLabo p, Fiche r, bool interim) {
    // CONTINUITÉ — celui qui a prélevé valide. Le refus NOMME le préleveur, faute de quoi on chercherait la panne du côté du logiciel.
    final cont = continuiteRespectee(r, agentId: p.agentId, agentNom: p.agentNom);
    if (!cont.ok) {
      ToastsSigh.afficher(ctx, cont.motif ?? '', type: TypeToast.erreur);
      return;
    }
    confirmerSigh(ctx,
            titre: interim ? 'Valider par intérim ?' : 'Validation biologique',
            message:
                'Le résultat de ${r['analyse']} pour ${r['patient']} deviendra visible du prescripteur et fera foi.\n\n${interim ? 'Vous portez cette validation en l’absence du biologiste médical : votre qualité d’intérimaire sera portée sur le compte rendu.\n\n' : ''}Au-delà, une correction donnera une version rectificative et le prescripteur sera averti que ce qu’il a lu a changé. Avez-vous relu l’ensemble des valeurs ?',
            libelleOk: interim ? 'Valider par intérim' : 'Valider biologiquement')
        .then((ok) {
      if (!ok || !ctx.mounted) return;
      final GesteResultat g;
      try {
        g = validerBiologique(r,
            session: p.session, utilisateur: c.utilisateur, maintenant: c.aujourdhui);
      } on RefusResultat catch (e) {
        ToastsSigh.afficher(ctx, 'Validation impossible : ${e.motif}', type: TypeToast.erreur);
        return;
      }
      final undo = _ecrire(c, r, g);
      c.magasin.journaliser('Validation biologique', 'M5', 'ResultatAnalyse',
          '${r['reference']}', {'etat': 'valide_technique'}, {'etat': 'valide', 'interim': g.interim});
      _repeindre();
      ToastsSigh.afficher(ctx, 'Validation biologique portée.',
          type: TypeToast.succes,
          duree: const Duration(seconds: 8),
          detail:
              '${g.interim ? 'Intérim tracé sur la pièce. ' : ''}Le prescripteur ${r['prescripteur'] ?? ''} en est notifié.',
          annuler: () {
            undo();
            _repeindre();
          });
    });
  }

  // --- La rectification ---------------------------------------------------------------------------------------------

  void _demanderRectification(BuildContext ctx, ContexteEcran c, Fiche r,
      Map<String, Object?> valeurs, String commentaire) {
    final motif = ControleurFormulaire([
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif de la rectification',
          type: TypeChamp.textarea,
          lignes: 2,
          requis: true,
          col: ColChamp.plein,
          aide: 'Ce motif figure sur la version rectificative et dans la notification au prescripteur.')
    ]);
    final version = _vrai2(r['version']) ? (r['version'] as num).toInt() : 1;
    afficherModale<void>(ctx,
        titre: 'Rectifier un résultat déjà rendu',
        sousTitre: '${r['analyse']} — ${r['patient']}',
        taille: TailleModale.md,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: JetonsShell.danger50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JetonsShell.danger200)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(LucideIcons.triangleAlert, size: 20, color: JetonsShell.danger600),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ce résultat a déjà été validé biologiquement.',
                      style: styleLabo(14, couleur: JetonsShell.danger900, poids: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      'Le prescripteur ${r['prescripteur'] ?? ''} a pu le lire. La version actuelle sera CONSERVÉE, la correction deviendra la version ${version + 1}, et une notification lui sera adressée pour l’avertir que ce qu’il a lu a changé.',
                      style: styleLabo(12, couleur: JetonsShell.danger800)),
                ])),
              ])),
          const SizedBox(height: 12),
          DescListeSigh([
            ('Validé le', _vrai2(r['valideLe']) ? dateHeureFr(r['valideLe']) : '—'),
            ('Validé par', r['valideBiologiquePar'] ?? '—'),
            ('Version actuelle', 'v$version'),
            ('Nouvelle version', 'v${version + 1}'),
          ]),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: motif),
          const SizedBox(height: 16),
          Builder(builder: (mctx) => Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            BoutonSigh(
                libelle: 'Renoncer',
                variante: VarianteBouton.secondaire,
                onPressed: () => Navigator.of(mctx).pop()),
            const SizedBox(width: 8),
            BoutonSigh(
                key: const Key('res:emettre-rectification'),
                libelle: 'Émettre la rectification',
                icone: LucideIcons.history,
                variante: VarianteBouton.danger,
                onPressed: () {
                  final v = motif.valider();
                  if (v == null) return;
                  final GesteResultat g;
                  try {
                    g = rectifierResultat(r, valeurs,
                        motif: '${v['motif']}',
                        commentaireGeneral: commentaire,
                        utilisateur: c.utilisateur,
                        maintenant: c.aujourdhui);
                  } on RefusResultat catch (e) {
                    ToastsSigh.afficher(ctx, 'Rectification impossible : ${e.motif}',
                        type: TypeToast.erreur);
                    return;
                  }
                  _ecrire(c, r, g);
                  c.magasin.journaliser('Rectification de résultat', 'M5', 'ResultatAnalyse',
                      '${r['reference']}', {'version': version, 'valeurs': r['valeurs']},
                      {'version': version + 1, 'motif': v['motif']});
                  Navigator.of(mctx).pop();
                  _repeindre();
                  ToastsSigh.afficher(ctx, 'Version rectificative v${g.version} émise.',
                      type: TypeToast.attention,
                      duree: const Duration(seconds: 9),
                      detail:
                          'Le prescripteur ${r['prescripteur'] ?? ''} est notifié que le résultat a changé. La version précédente reste consultable.');
                }),
          ])),
        ]));
  }

  // --- La saisie structurée ---------------------------------------------------------------------------------------

  void _ouvrirSaisie(BuildContext ctx, ContexteEcran c, ProfilLabo p, Fiche r) {
    final code = codeExamenSaisie(r, examensLabo(c));
    final variables = [
      for (final v in variablesExamen(code, variablesLabo(c)))
        if (v['actif'] != false) v
    ];
    if (variables.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucune variable paramétrée pour cet examen.',
          type: TypeToast.erreur,
          detail:
              'Définir ses variables à l’écran « Valeurs de référence » avant de saisir un résultat.');
      return;
    }
    afficherModale<void>(ctx,
        titre: 'Saisie du résultat — ${r['analyse']}',
        sousTitre:
            '${_vrai2(r['codeAnalyse']) ? 'Code ${r['codeAnalyse']} · ' : ''}${_vrai2(r['reference']) ? '${r['reference']} · ' : ''}${r['patient']} (${r['patientCode']})',
        taille: TailleModale.xl,
        corps: _ModaleSaisie(
            contexte: c,
            ecran: ctx,
            demande: r,
            variables: variables,
            surEnregistrer: (valeurs, resume, anormales, general, valideur, valider) =>
                _enregistrer(ctx, c, r, valeurs, resume, anormales, general, valideur, valider),
            surRectifier: (valeurs, general) =>
                _demanderRectification(ctx, c, r, valeurs, general)));
  }

  void _enregistrer(BuildContext ctx, ContexteEcran c, Fiche r, Map<String, Object?> valeurs,
      String resume, int anormales, String general, String valideur, bool valider) {
    final maintenant = c.aujourdhui.toUtc().toIso8601String();
    final undo = c.magasin.collection('demandesAnalyses').mettreAJour(r['id'], {
      'valeurs': valeurs,
      'resultat': resume.isEmpty ? null : resume,
      'resultatStructure': true,
      'conclusion': anormales > 0 ? 'Anormal' : 'Normal',
      'anormales': anormales,
      'commentaireGeneral': general.isEmpty ? null : general,
      'laborantin': valideur,
      // PREMIER VERROU SEULEMENT. La validation biologique est un second geste, porté depuis l'onglet dédié après relecture.
      'etatAnalyse': valider ? 'valide_technique' : 'saisi',
      'valideTechniqueLe': valider ? maintenant : null,
      'valideTechniquePar': valider ? valideur : null,
    });
    _repeindre();
    ToastsSigh.afficher(ctx,
        valider ? 'Validation technique portée.' : 'Résultat enregistré, non validé.',
        type: TypeToast.succes,
        duree: const Duration(seconds: 8),
        detail: valider
            ? 'Le prescripteur NE VOIT PAS encore ce résultat. Il faut la validation biologique — onglet « À valider biologiquement ».'
            : (anormales > 0
                ? '${nombre(anormales)} valeur(s) hors référence.'
                : 'Toutes les valeurs sont dans les références.'),
        annuler: () {
          undo();
          _repeindre();
        });
  }
}

typedef _SurEnregistrer = void Function(Map<String, Object?> valeurs, String resume,
    int anormales, String general, String valideur, bool valider);

/// Le corps de la modale de saisie : une ligne par variable (champ qui convient au type, unité, références du LOT en service à la date de la
/// demande, écart calculé À LA SAISIE), le commentaire général du compte rendu et le validateur.
class _ModaleSaisie extends StatefulWidget {
  const _ModaleSaisie(
      {required this.contexte,
      required this.ecran,
      required this.demande,
      required this.variables,
      required this.surEnregistrer,
      required this.surRectifier});
  final ContexteEcran contexte;

  /// Le contexte de l'ÉCRAN : une modale vit au-dessus de la coque, hors du `ContexteEcran` — messages et impressions passent par lui.
  final BuildContext ecran;
  final Fiche demande;
  final List<Fiche> variables;
  final _SurEnregistrer surEnregistrer;
  final void Function(Map<String, Object?> valeurs, String general) surRectifier;

  @override
  State<_ModaleSaisie> createState() => _EtatModaleSaisie();
}

class _EtatModaleSaisie extends State<_ModaleSaisie> {
  late final Map<String, Object?> _saisies = {
    ...((widget.demande['valeurs'] as Map?)?.cast<String, Object?>() ?? const {})
  };
  final Map<String, TextEditingController> _libres = {};
  final TextEditingController _general = TextEditingController();
  String _motif = '';
  late String _valideur;
  late final List<String> _valideurs = [
    for (final e in widget.contexte.magasin.collection('personnel').actives)
      if (e['fonction'] == 'tsl') '${e['nomComplet']}'
  ];

  Fiche get _r => widget.demande;
  ContexteEcran get _c => widget.contexte;

  @override
  void initState() {
    super.initState();
    _valideur = _valideurs.isNotEmpty ? _valideurs.first : '';
    for (final v in widget.variables) {
      _libres['${v['code']}'] = TextEditingController(text: _initial(v));
    }
  }

  String _initial(Fiche v) {
    final x = _saisies[v['code']];
    return x == null ? '' : chaineJs(x);
  }

  @override
  void dispose() {
    for (final t in _libres.values) {
      t.dispose();
    }
    _general.dispose();
    super.dispose();
  }

  Fiche _auDate(Fiche v) => variableALaDate(v, plagesLabo(_c), _r['dateHeure'],
      aujourdhui: _c.aujourdhui);

  List<String> _options(Fiche v) {
    final propres = v['valeurs'];
    if (propres is List) return [for (final x in propres) '$x'];
    return valeursTypeVariable['${v['type']}'] ?? const [];
  }

  static bool _vrai(Object? v) => v != null && v != false && v != '' && v != 0;

  Widget _champ(Fiche v) {
    final code = '${v['code']}';
    final type = '${v['type']}';
    final ctl = _libres[code]!;
    InputDecoration deco() => decorationChamp();
    if (['binaire', 'ternaire', 'titre', 'liste', 'reactif', 'commentaire'].contains(type)) {
      final options = _options(v);
      final choisi = options.contains('${_saisies[code] ?? ''}') ? '${_saisies[code]}' : '';
      final selecteur = InputDecorator(
          decoration: deco(),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                  key: Key('res:champ:$code'),
                  isDense: true,
                  isExpanded: true,
                  value: choisi,
                  style: styleSaisie,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('—')),
                    for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
                  ],
                  onChanged: (x) => setState(() {
                        _saisies[code] = x ?? '';
                        if (type == 'commentaire' || type == 'reactif') {
                          ctl.text = ctl.text;
                        }
                      }))));
      if (type == 'commentaire' || type == 'reactif') {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          selecteur,
          const SizedBox(height: 4),
          TextField(
              key: Key('res:libre:$code'),
              controller: ctl,
              style: styleSaisie,
              decoration: decorationChamp(indicatif: 'ou saisir librement'),
              onChanged: (t) => setState(() => _saisies[code] =
                  t.isNotEmpty ? t : (options.contains('${_saisies[code]}') ? _saisies[code] : ''))),
        ]);
      }
      return selecteur;
    }
    if (type == 'expiration') {
      return TextField(
          key: Key('res:champ:$code'),
          controller: ctl,
          style: styleSaisie,
          decoration: decorationChamp(indicatif: 'AAAA-MM-JJ'),
          onChanged: (t) => setState(() => _saisies[code] = t));
    }
    if (type == 'texte') {
      return TextField(
          key: Key('res:champ:$code'),
          controller: ctl,
          minLines: 2,
          maxLines: 2,
          style: styleSaisie,
          decoration: deco(),
          onChanged: (t) => setState(() => _saisies[code] = t));
    }
    return TextField(
        key: Key('res:champ:$code'),
        controller: ctl,
        textAlign: TextAlign.right,
        keyboardType: type == 'numerique'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: styleSaisie,
        decoration: deco(),
        onChanged: (t) => setState(() => _saisies[code] = t));
  }

  Widget _badgeEcart(Fiche v) {
    final val = _saisies[v['code']];
    final e = ecart(_auDate(v), val);
    if (e == null) {
      return _vrai(val) ? const BadgeSigh('Normal', ton: TonSigh.succes) : const SizedBox.shrink();
    }
    return switch (e) {
      'bas' => const BadgeSigh('Bas', ton: TonSigh.info),
      'haut' => const BadgeSigh('Haut', ton: TonSigh.danger),
      _ => const BadgeSigh('Anormal', ton: TonSigh.danger),
    };
  }

  void _enregistrer(bool valider) {
    final manquantes = [
      for (final v in widget.variables)
        if (!_vrai(v['accompagnement']) &&
            !_vrai(v['parent']) &&
            (_saisies[v['code']] == null || _saisies[v['code']] == ''))
          v
    ];
    if (valider && manquantes.isNotEmpty) {
      ToastsSigh.afficher(widget.ecran, 'Résultat incomplet.',
          type: TypeToast.erreur,
          detail:
              '${nombre(manquantes.length)} variable(s) principale(s) non renseignée(s) : ${manquantes.take(3).map((v) => v['libelle']).join(', ')}${manquantes.length > 3 ? '…' : ''}');
      return;
    }
    final anormales = [
      for (final v in widget.variables)
        if (ecart(_auDate(v), _saisies[v['code']]) != null) v
    ];
    final resume = resumeResultat(widget.variables, _saisies, (u) => symbole(_c, u));
    // Une RECTIFICATION si le résultat était déjà validé biologiquement — jamais un écrasement.
    if (estRendu(_r['etatAnalyse'])) {
      Navigator.of(context).pop();
      widget.surRectifier({..._saisies}, _general.text);
      return;
    }
    Navigator.of(context).pop();
    widget.surEnregistrer(
        {..._saisies}, resume, anormales.length, _general.text, _valideur, valider);
  }

  Widget _cellule(Widget w, {bool droite = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Align(alignment: droite ? Alignment.centerRight : Alignment.centerLeft, child: w));

  @override
  Widget build(BuildContext context) {
    final plages = plagesLabo(_c);
    final enTete = TableRow(
        decoration: const BoxDecoration(color: JetonsShell.slate50),
        children: [
          for (final (i, t) in ['Variable', 'Résultat', 'Unité', 'Références', 'Écart'].indexed)
            _cellule(
                Text(t.toUpperCase(),
                    style: styleLabo(12, couleur: JetonsShell.slate500, poids: FontWeight.w600)),
                droite: i >= 2),
        ]);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // LES DEUX IDENTIFIANTS DU DOSSIER, EN TÊTE DE LA SAISIE : c'est EUX qu'on compare au bon papier posé à côté de l'automate.
      DescListeSigh([
        (
          'Code d’analyse',
          Text('${_vrai(_r['codeAnalyse']) ? _r['codeAnalyse'] : '— non attribué'}',
              style: styleLabo(16,
                  couleur: JetonsShell.navy900, poids: FontWeight.w600, police: 'monospace'))
        ),
        (
          'Référence de la demande',
          Text('${_r['reference'] ?? '—'}', style: styleLabo(14, police: 'monospace'))
        ),
        ('Patient', '${_r['patient']} (${_r['patientCode']})'),
        ('Examen', _r['analyse']),
        (
          'Prélevé le',
          _vrai(_r['preleveLe'])
              ? '${dateFrJs(_r['preleveLe'])} à ${heure(dateLocale(_r['preleveLe'])!)}'
              : '—'
        ),
        ('Prescripteur', _r['prescripteur'] ?? '—'),
      ]),
      const SizedBox(height: 12),
      DescListeSigh([
        ('Patient', _r['patient']),
        ('Dossier', _r['patientCode']),
        ('Examen', _r['analyse']),
        ('Échantillon', _r['echantillon'] ?? '—'),
        ('Prescripteur', _r['prescripteur'] ?? '—'),
        ('Demandé le', _vrai(_r['dateHeure']) ? dateHeureFr(_r['dateHeure']) : '—'),
      ]),
      const SizedBox(height: 12),
      Container(
          decoration: BoxDecoration(
              border: Border.all(color: JetonsShell.slate200),
              borderRadius: BorderRadius.circular(8)),
          constraints: const BoxConstraints(maxHeight: 384),
          child: SingleChildScrollView(
              child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(3),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(2.2),
                    4: FlexColumnWidth(1.4),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                enTete,
                for (final v in widget.variables)
                  TableRow(
                      key: ValueKey('res:ligne:${v['code']}'),
                      decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: JetonsShell.slate100))),
                      children: [
                        _cellule(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${_vrai(v['parent']) ? '↳ ' : ''}${v['libelle']}',
                                  style: styleLabo(14,
                                      couleur: _vrai(v['parent'])
                                          ? JetonsShell.slate600
                                          : JetonsShell.slate800,
                                      poids: _vrai(v['parent'])
                                          ? FontWeight.w400
                                          : FontWeight.w500)),
                              if (_vrai(v['accompagnement']))
                                Text(libellesTypeVariable['${v['type']}'] ?? '${v['type']}',
                                    style: styleLabo(12, couleur: JetonsShell.slate400)),
                            ])),
                        _cellule(_champ(v)),
                        _cellule(
                            Text(symbole(_c, v['unite']),
                                style: styleLabo(12,
                                    couleur: JetonsShell.slate500, police: 'monospace')),
                            droite: true),
                        _cellule(
                            Text(
                                // La référence affichée est celle du LOT en service à la date de la demande — pas forcément celle de la variable.
                                referenceALaDate(v, plages, _r['dateHeure'],
                                        aujourdhui: _c.aujourdhui)
                                    .ifEmpty('—'),
                                style: styleLabo(12,
                                    couleur: _vrai(v['aValider'])
                                        ? JetonsShell.warning700
                                        : JetonsShell.slate500)),
                            droite: true),
                        _cellule(KeyedSubtree(key: Key('res:ecart:${v['code']}'), child: _badgeEcart(v)), droite: true),
                      ]),
              ]))),
      const SizedBox(height: 12),
      // Le commentaire GÉNÉRAL porte sur l'échantillon, pas sur un examen : c'est là qu'on écrit « hémolysé — reprendre le prélèvement ».
      CarteSigh(
          titre: 'Commentaire général du compte rendu',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const NoteSigh(
                'À ne pas confondre avec le commentaire d’un examen : celui-ci porte sur l’échantillon et le compte rendu — « hémolysé, reprendre le prélèvement » — et non sur l’interprétation d’un résultat.'),
            const SizedBox(height: 8),
            InputDecorator(
                decoration: decorationChamp(),
                child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                        key: const Key('res:motif'),
                        isDense: true,
                        isExpanded: true,
                        value: _motif,
                        style: styleSaisie,
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('Aucun commentaire général')),
                          for (final x in motifsCommentaireGeneral)
                            DropdownMenuItem(value: x, child: Text(x)),
                        ],
                        onChanged: (x) => setState(() {
                              _motif = x ?? '';
                              if (_motif.isNotEmpty) _general.text = _motif;
                            })))),
            const SizedBox(height: 8),
            TextField(
                key: const Key('res:general'),
                controller: _general,
                minLines: 2,
                maxLines: 2,
                style: styleSaisie,
                decoration: decorationChamp(
                    indicatif: 'Commentaire libre sur l’échantillon ou le compte rendu')),
          ])),
      const SizedBox(height: 12),
      const LibelleChamp('Validé par'),
      InputDecorator(
          decoration: decorationChamp(),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                  key: const Key('res:valideur'),
                  isDense: true,
                  isExpanded: true,
                  value: _valideurs.contains(_valideur) ? _valideur : null,
                  style: styleSaisie,
                  items: [
                    for (final x in _valideurs) DropdownMenuItem(value: x, child: Text(x))
                  ],
                  onChanged: (x) => setState(() => _valideur = x ?? '')))),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        BoutonSigh(
            libelle: 'Annuler',
            variante: VarianteBouton.secondaire,
            onPressed: () => Navigator.of(context).pop()),
        const SizedBox(width: 8),
        BoutonSigh(
            key: const Key('res:enregistrer'),
            libelle: 'Enregistrer sans valider',
            icone: LucideIcons.save,
            variante: VarianteBouton.secondaire,
            onPressed: () => _enregistrer(false)),
        const SizedBox(width: 8),
        BoutonSigh(
            key: const Key('res:valider-resultat'),
            libelle: 'Valider le résultat',
            icone: LucideIcons.check,
            onPressed: () => _enregistrer(true)),
      ]),
    ]);
  }
}

extension on String {
  String ifEmpty(String autre) => isEmpty ? autre : this;
}
