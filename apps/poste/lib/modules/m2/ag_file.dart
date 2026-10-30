import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'ag_commun.dart';

// --- m2-file-attente -----------------------------------------------------------------------------------------------------------------------

/// `m2-file-attente` — la file par poste : l'ordre d'ARRIVÉE gouverne, SAUF urgence. Le rang est calculé, jamais saisi : faire passer un patient devant se
/// fait en changeant sa priorité (avec un motif), ce qui est tracé. Le poste affiché est RETENU d'un geste à l'autre (E326).
class EcranFileAttente extends StatefulWidget with EcranMaquette {
  const EcranFileAttente({super.key});

  @override
  String get titre => 'File d’attente';

  @override
  String get description =>
      'Gestion des files par poste : ordre d’arrivée tempéré par la priorité de triage.';

  @override
  String get regle =>
      'L’ordre d’arrivée gouverne, sauf urgence. Le rang est calculé, jamais saisi : le saisir permettrait de faire passer quelqu’un devant sans que rien ne le trace. À priorité égale, c’est l’heure d’arrivée qui départage.';

  @override
  State<EcranFileAttente> createState() => _EtatFile();
}

class _EtatFile extends State<EcranFileAttente> {
  String _poste = agPostes.first.$1;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('fileAttente');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final tous = col.actives;
          final k = agKpisFile(tous, c.aujourdhui);
          final urgences = k[1].valeur != '0';
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              kpiAg(k[0], LucideIcons.users, TonSigh.navy),
              kpiAg(k[1], LucideIcons.siren, urgences ? TonSigh.danger : TonSigh.succes),
              kpiAg(k[2], LucideIcons.checkCheck, TonSigh.succes),
              kpiAg(k[3], LucideIcons.clock, TonSigh.info),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'Le rang affiché n’est pas un champ : il découle de la priorité et de l’heure d’arrivée. Faire passer un patient devant se fait en changeant sa priorité, ce qui est tracé — et non en réécrivant un numéro.',
                icone: LucideIcons.listOrdered),
            const SizedBox(height: 16),
            OngletsSigh(
                ancre: _poste,
                alChangement: (id) => _poste = id,
                onglets: [
                  for (final (code, libelle) in agPostes)
                    OngletDef(
                        id: code,
                        libelle: libelle,
                        compte: agFileTriee(tous, code).length,
                        construire: (_) => _panneau(context, c, code, agFileTriee(tous, code))),
                ]),
          ]);
        });
  }

  Widget _panneau(BuildContext ecran, ContexteEcran c, String poste, List<Fiche> f) {
    final lignes = [for (final (i, t) in f.indexed) {...t, 'rang': i + 1}];
    return TableauSigh(
      lignes: lignes,
      nomExport: 'fileAttente',
      messageVide: 'Personne n’attend à ce poste.',
      actions: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Inscrire un patient',
              icone: LucideIcons.userPlus,
              taille: TailleBouton.sm,
              onPressed: () => _inscrire(ecran, c, poste)),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'rang',
            libelle: 'Rang',
            rendu: (_, r) => Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration:
                    const BoxDecoration(color: JetonsShell.navy900, shape: BoxShape.circle),
                child: Text('${r['rang']}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)))),
        ColonneTableau(
            cle: 'numero',
            libelle: 'N° d’appel',
            rendu: (_, r) => Text('${r['numero']}',
                style: const TextStyle(
                    fontFamily: 'LiberationMono',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: JetonsShell.slate900))),
        const ColonneTableau(cle: 'patient', libelle: 'Patient'),
        ColonneTableau(
            cle: 'priorite',
            libelle: 'Priorité',
            texte: (r) => agPriorite(r['priorite']).libelle,
            rendu: (_, r) {
              final p = agPriorite(r['priorite']);
              return BadgeSigh(p.libelle, ton: tonAg(p.ton));
            }),
        ColonneTableau(
            cle: 'arriveeLe',
            libelle: 'Arrivé à',
            texte: (r) {
              final d = agDate(r['arriveeLe']);
              return d == null ? 'NaNhNaN' : heure(d);
            }),
        ColonneTableau(
            cle: 'attente',
            libelle: 'Attente',
            droite: true,
            valeur: (r) => agAttenteMinutes(r, c.aujourdhui),
            texte: (r) => '${agAttenteMinutes(r, c.aujourdhui)} min',
            rendu: (_, r) {
              final mn = agAttenteMinutes(r, c.aujourdhui);
              return Text('$mn min',
                  style: TextStyle(
                      color: mn > 45 ? JetonsShell.warning700 : JetonsShell.slate700,
                      fontWeight: mn > 45 ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14));
            }),
        const ColonneTableau(cle: 'motif', libelle: 'Motif'),
      ],
      actionsLigne: (ctx, r) => [
        if (c.droit.editer) ...[
          BoutonSigh(
              libelle: 'Appeler',
              icone: LucideIcons.megaphone,
              taille: TailleBouton.sm,
              onPressed: () => _appeler(ecran, c, r)),
          BoutonIcone(
              icone: LucideIcons.arrowUp,
              libelle: 'Modifier la priorité',
              onPressed: () => _priorite(ecran, c, r)),
        ]
      ],
    );
  }

  void _appeler(BuildContext ecran, ContexteEcran c, Fiche r) {
    c.magasin
        .collection('fileAttente')
        .mettreAJour(r['id'], agPatchAppel(c.utilisateur, c.aujourdhui));
    ToastsSigh.afficher(ecran, 'Patient appelé — ${r['numero']}.',
        type: TypeToast.succes, detail: '${r['patient']}');
  }

  void _inscrire(BuildContext ecran, ContexteEcran c, String poste) {
    final liste = <ChampDef>[
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient',
          type: TypeChamp.select,
          requis: true,
          options: optionsPatientsAg(c)),
      ChampDef(
          nom: 'priorite',
          libelle: 'Priorité de triage',
          type: TypeChamp.select,
          requis: true,
          options: [for (final p in agPriorites) OptionChamp(p.code, p.libelle)]),
      const ChampDef(nom: 'motif', libelle: 'Motif', requis: true),
      if (poste == 'consultation')
        ChampDef(
            nom: 'praticien',
            libelle: 'Praticien attendu',
            type: TypeChamp.select,
            options: [
              const OptionChamp('', '— File commune —'),
              for (final s in c.magasin.collection('soignants').actives)
                if (agVrai(s['prescrit'])) OptionChamp('${s['nomComplet']}')
            ],
            aide:
                'À renseigner seulement si le patient est adressé à un praticien précis (rendez-vous nominatif, suivi en cours). Sinon, laisser en file commune.'),
    ];
    final ctl = ControleurFormulaire(liste, {'priorite': 'ordre_arrivee', 'praticien': ''});
    afficherModale<void>(ecran,
        titre: 'Inscrire un patient — ${agLibellePoste(poste)}',
        sousTitre: 'Le rang sera calculé : priorité d’abord, heure d’arrivée ensuite.',
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Inscrire',
                  icone: LucideIcons.userPlus,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final col = c.magasin.collection('fileAttente');
                    final t = agTicket(
                        poste: poste,
                        patientCode: '${v['patientCode']}',
                        priorite: '${v['priorite']}',
                        motif: '${v['motif']}',
                        praticien: v['praticien'] as String?,
                        patients: patientsAg(c),
                        tous: col.toutes,
                        maintenant: c.aujourdhui);
                    final ins = col.inserer(t, prefixe: 'FIL');
                    fermer();
                    ToastsSigh.afficher(ecran, 'Patient inscrit — numéro ${t['numero']}.',
                        type: TypeToast.succes,
                        detail: '${t['patient']} — ${agPriorite(t['priorite']).libelle}',
                        messageAnnulation: 'Inscription annulée.',
                        annuler: ins.annuler);
                  }),
            ]);
  }

  void _priorite(BuildContext ecran, ContexteEcran c, Fiche r) {
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'priorite',
          libelle: 'Nouvelle priorité',
          type: TypeChamp.select,
          requis: true,
          options: [for (final p in agPriorites) OptionChamp(p.code, p.libelle)]),
      const ChampDef(
          nom: 'motifChangement',
          libelle: 'Motif du changement',
          requis: true,
          aide: 'Obligatoire : faire passer un patient devant un autre doit s’expliquer.'),
    ], {'priorite': '${r['priorite']}'});
    afficherModale<void>(ecran,
        titre: 'Modifier la priorité — ${r['patient']}',
        sousTitre: 'Le rang se recalcule ; le changement est journalisé (RG-12).',
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Appliquer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    c.magasin.collection('fileAttente').mettreAJour(
                        r['id'], agPatchPriorite('${v['priorite']}', '${v['motifChangement']}'));
                    fermer();
                    ToastsSigh.afficher(ecran, 'Priorité modifiée.',
                        type: TypeToast.succes,
                        detail: '${r['patient']} — ${agPriorite(v['priorite']).libelle}');
                  }),
            ]);
  }
}

// --- m2-affichage --------------------------------------------------------------------------------------------------------------------------

/// `m2-affichage` — l'écran de la salle d'attente : des NUMÉROS, jamais un nom ni un motif. Il se rafraîchit seul toutes les 15 secondes.
class EcranAffichage extends StatefulWidget with EcranMaquette {
  const EcranAffichage({super.key});

  @override
  String get titre => 'Écran d’appel des patients';

  @override
  String get description =>
      'Affichage de salle d’attente : numéros appelés et numéros suivants, sans aucune donnée médicale.';

  @override
  String get regle =>
      'Cet écran est destiné à la salle d’attente. Il n’affiche que des numéros — jamais le nom du patient ni son motif. Une salle d’attente n’est pas un lieu où l’on annonce publiquement pourquoi quelqu’un consulte.';

  @override
  State<EcranAffichage> createState() => _EtatAffichage();
}

class _EtatAffichage extends State<EcranAffichage> {
  Timer? _minuteur;
  DateTime? _derniere;

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _derniere = null);
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('fileAttente');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          _derniere ??= c.aujourdhui;
          final cartes = agCartesAffichage(col.actives);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LayoutBuilder(builder: (_, w) {
              final n = w.maxWidth >= 1024 ? 3 : (w.maxWidth >= 640 ? 2 : 1);
              final l = (w.maxWidth - 16 * (n - 1)) / n;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final p in cartes)
                  SizedBox(
                      width: l - 0.01,
                      child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: JetonsShell.slate200)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.libelle.toUpperCase(),
                                style: const TextStyle(
                                    color: JetonsShell.slate400,
                                    fontSize: 12,
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            const Text('Numéro appelé',
                                style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                            Text(p.appele ?? '—',
                                style: const TextStyle(
                                    color: JetonsShell.navy900,
                                    fontSize: 36,
                                    height: 40 / 36,
                                    letterSpacing: -0.9,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            const Text('Prochains numéros',
                                style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                            Text(p.prochains.isEmpty ? '—' : p.prochains.join('   ·   '),
                                style: const TextStyle(
                                    color: JetonsShell.slate700,
                                    fontSize: 18,
                                    height: 28 / 18,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            Text('${p.enAttente} patient(s) en attente',
                                style: const TextStyle(
                                    color: JetonsShell.slate400, fontSize: 12)),
                          ])))
              ]);
            }),
            const SizedBox(height: 16),
            Center(
                child: Text(
                    'Actualisé automatiquement toutes les 15 secondes — dernière actualisation à ${heure(_derniere!)}',
                    style: const TextStyle(color: JetonsShell.slate400, fontSize: 12))),
          ]);
        });
  }
}

// --- m2-file-cabinet -----------------------------------------------------------------------------------------------------------------------

/// `m2-file-cabinet` — DEUX listes, jamais fondues : ceux qui attendent NOMMÉMENT un praticien (un cabinet chacun), et le vivier commun. Chacune suit le
/// classement de la file : urgences en tête (E325).
class EcranFileCabinet extends StatelessWidget with EcranMaquette {
  const EcranFileCabinet({super.key});

  @override
  String get titre => 'File par cabinet';

  @override
  String get description =>
      'Qui attend quel praticien — et le vivier commun, que personne ne doit perdre de vue.';

  @override
  String get regle =>
      'DEUX listes, jamais fondues (doctrine de la vague 35) : les patients qui attendent nommément un praticien, et le vivier commun — la file de consultation est souvent commune dans une clinique de cette taille, et n’afficher que « ses » patients ferait manquer la charge du service. Le rang n’est jamais saisi.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('fileAttente');
    Widget table(List<Fiche> l) => MiniTableauSigh(colonnes: [
          ColonneMini('Patient', (t) => agLigneCabinet(t)[0]),
          ColonneMini('Priorité', (t) => agLigneCabinet(t)[1]),
          ColonneMini('Arrivé à', (t) => agLigneCabinet(t)[2]),
        ], lignes: l);
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final cab = agCabinets(col.actives);
          final k = agKpisCabinets(cab);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              kpiAg(k[0], LucideIcons.listOrdered, TonSigh.navy),
              kpiAg(k[1], LucideIcons.userCheck, TonSigh.info),
              kpiAg(k[2], LucideIcons.users,
                  cab.vivier.isNotEmpty ? TonSigh.attention : TonSigh.neutre),
              kpiAg(k[3], LucideIcons.doorOpen, TonSigh.neutre),
            ]),
            for (final (nom, l) in cab.parPraticien) ...[
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Cabinet — $nom (${l.length})',
                  sansRemplissage: true,
                  child: table(l)),
            ],
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Vivier commun — par ordre d’arrivée, urgences en tête',
                sansRemplissage: cab.vivier.isNotEmpty,
                child: cab.vivier.isEmpty
                    ? const VideSigh('Vivier vide — personne n’attend sans praticien désigné.',
                        icone: LucideIcons.users)
                    : table(cab.vivier)),
          ]);
        });
  }
}
