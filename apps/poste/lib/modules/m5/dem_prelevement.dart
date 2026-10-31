import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'dem_commun.dart';

enum _Mode { attente, transmettre, labo }

/// `m5-prelevement` — « Salle de prélèvement » : trois états qui se suivent (à prélever, prélevé, reçu au laboratoire). Le prélèvement ne s'effectue
/// qu'APRÈS encaissement : une demande impayée reste visible, non exécutable, et le verrou le dit. Le laboratoire ne saisit un résultat que sur un
/// échantillon REÇU. Les règles sont dans `packages/domaine` (`dem_regles.dart`), rejouées sur les vecteurs de l'écran réel.
class EcranPrelevement extends StatelessWidget with EcranMaquette {
  const EcranPrelevement({super.key});

  @override
  String get titre => 'Salle de prélèvement';

  @override
  String get description =>
      'Prélèvement des échantillons après encaissement, et transmission au laboratoire avec le bon d’analyse.';

  @override
  String get regle =>
      'Le prélèvement ne s’effectue qu’après encaissement : une demande impayée reste visible mais non exécutable. Une fois prélevé, le patient peut partir — c’est la salle qui transmet l’échantillon au laboratoire, accompagné du bon d’analyse. Le laboratoire ne saisit un résultat que sur un échantillon reçu.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('demandesAnalyses');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final actives = col.actives;
        final attente = demAPrelever(actives);
        final preleves = demPreleves(actives);
        final recus = demRecus(actives);
        final k = demKpisPrelevement(actives);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'À prélever',
                    valeur: nombre(k.aPrelever),
                    icone: LucideIcons.syringe,
                    ton: TonSigh.attention,
                    indice: 'Demandes réglées, patient attendu'),
                KpiSigh(
                    libelle: 'En attente de règlement',
                    valeur: nombre(k.attenteReglement),
                    icone: LucideIcons.lock,
                    ton: k.attenteReglement > 0 ? TonSigh.danger : TonSigh.neutre,
                    indice: 'Prélèvement impossible'),
                KpiSigh(
                    libelle: 'Prélevés, à transmettre',
                    valeur: nombre(k.aTransmettre),
                    icone: LucideIcons.package,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Reçus au laboratoire',
                    valeur: nombre(k.recus),
                    icone: LucideIcons.flaskConical,
                    ton: TonSigh.succes),
              ]),
              const SizedBox(height: 16),
              const NoteSigh(
                  'Le patient peut partir dès le prélèvement fait : c’est la salle qui achemine l’échantillon au laboratoire avec le bon d’analyse. Le laboratoire ne saisit un résultat que sur un échantillon reçu — sans quoi un résultat pourrait être rendu pour un prélèvement qui n’a jamais eu lieu.',
                  icone: LucideIcons.route),
              const SizedBox(height: 16),
              OngletsSigh(onglets: [
                OngletDef(
                    id: 'attente',
                    libelle: 'À prélever',
                    compte: attente.length,
                    construire: (ctx) => _table(context, attente, _Mode.attente)),
                OngletDef(
                    id: 'transmettre',
                    libelle: 'À transmettre',
                    compte: preleves.length,
                    construire: (ctx) =>
                        _table(context, preleves, _Mode.transmettre)),
                OngletDef(
                    id: 'labo',
                    libelle: 'Reçus au laboratoire',
                    compte: recus.length,
                    construire: (ctx) => _table(context, recus, _Mode.labo)),
              ]),
            ]);
      },
    );
  }

  Widget _table(BuildContext ctx, List<Fiche> rows, _Mode mode) {
    final c = ContexteEcran.of(ctx);
    return TableauSigh(
      titre: switch (mode) {
        _Mode.attente => 'Patients attendus en salle de prélèvement',
        _Mode.transmettre => 'Échantillons prélevés, à acheminer',
        _Mode.labo => 'Échantillons reçus au laboratoire',
      },
      lignes: rows,
      nomExport: 'prelevements',
      taillePage: 15,
      messageVide: mode == _Mode.attente
          ? 'Aucun prélèvement en attente.'
          : 'Aucun échantillon à ce stade.',
      colonnes: [
        ColonneTableau(
            cle: 'reference',
            libelle: 'N°',
            sansCoupure: true,
            texte: (r) => '${r['reference'] ?? ''}',
            rendu: (_, r) => monoTexte('${r['reference'] ?? ''}')),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Patient',
            texte: (r) => '${r['patient'] ?? ''}',
            rendu: (_, r) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${r['patient'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: JetonsShell.slate800,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w500)),
                      Text(
                          '${r['patientCode'] ?? ''}${r['origineDemande'] == 'externe' ? ' · externe' : ''}',
                          style: const TextStyle(
                              color: JetonsShell.slate400,
                              fontSize: 12,
                              height: 16 / 12)),
                    ])),
        const ColonneTableau(cle: 'analyse', libelle: 'Examen'),
        const ColonneTableau(
            cle: 'echantillon', libelle: 'Échantillon', sansCoupure: true),
        ColonneTableau(
            cle: 'urgence',
            libelle: 'Priorité',
            sansCoupure: true,
            valeur: (r) => vrai(r['urgent']) ? 'urgent' : 'courant',
            rendu: (_, r) => vrai(r['urgent'])
                ? const BadgeSigh('Urgent', ton: TonSigh.danger)
                : const BadgeSigh('Courant')),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            droite: true,
            valeur: (r) => demReglee(r) ? 'réglée' : 'impayée',
            rendu: (_, r) {
              if (mode == _Mode.attente) {
                return demReglee(r)
                    ? const BadgeSigh('Réglée — à prélever', ton: TonSigh.succes)
                    : const BadgeSigh('En attente de caisse', ton: TonSigh.danger);
              }
              final transmettre = mode == _Mode.transmettre;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    transmettre
                        ? const BadgeSigh('Prélevé', ton: TonSigh.info)
                        : const BadgeSigh('Reçu', ton: TonSigh.succes),
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                            dateHeureDe(r[transmettre ? 'preleveLe' : 'recuLaboLe']),
                            style: const TextStyle(
                                color: JetonsShell.slate400,
                                fontSize: 12,
                                height: 16 / 12))),
                  ]);
            }),
      ],
      actionsLigne: (context, r) {
        final actes = <Widget>[
          BoutonIcone(
              icone: LucideIcons.printer,
              libelle: 'Imprimer le bon d’analyse',
              onPressed: () => imprimerBonAnalyse(ctx, r)),
        ];
        if (!c.droit.editer) return actes;
        switch (mode) {
          case _Mode.attente:
            if (!demReglee(r)) {
              // Le verrou est VISIBLE et DIT pourquoi : retirer la commande ferait croire que la demande n'existe pas.
              actes.add(BoutonIcone(
                  icone: LucideIcons.lock,
                  libelle: 'Règlement requis avant prélèvement',
                  onPressed: () => ToastsSigh.afficher(ctx, 'Prélèvement impossible.',
                      type: TypeToast.erreur,
                      detail:
                          'La demande n’est pas réglée. Le patient doit d’abord passer à la caisse.')));
            } else {
              actes.add(BoutonIcone(
                  icone: LucideIcons.syringe,
                  libelle: 'Enregistrer le prélèvement',
                  onPressed: () => _prelever(ctx, r)));
            }
          case _Mode.transmettre:
            actes.add(BoutonIcone(
                icone: LucideIcons.send,
                libelle: 'Transmettre au laboratoire',
                onPressed: () => _transmettre(ctx, r)));
          case _Mode.labo:
            actes.add(BoutonIcone(
                icone: LucideIcons.filePenLine,
                libelle: 'Saisir le résultat',
                onPressed: () => c.aller('m5-resultats')));
        }
        return actes;
      },
    );
  }

  void _prelever(BuildContext ctx, Fiche r) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    String deux(int n) => n.toString().padLeft(2, '0');
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'preleveur',
          libelle: 'Prélevé par',
          type: TypeChamp.select,
          requis: true,
          options: laborantins(m)),
      ChampDef(
          nom: 'heurePrelevement',
          libelle: 'Heure du prélèvement',
          requis: true,
          indicatif: 'HH:MM',
          valider: (v, _) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('$v')
              ? null
              : 'Heure attendue au format HH:MM.'),
      const ChampDef(
          nom: 'natureEchantillon',
          libelle: 'Nature de l’échantillon',
          requis: true,
          aide: 'Reprise de la demande ; corrigeable si le prélèvement a différé.'),
      const ChampDef(
          nom: 'observationPrelevement',
          libelle: 'Observation',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein,
          aide:
              'Difficulté de prélèvement, patient à jeun ou non, tout ce que le laboratoire doit savoir.'),
    ], {
      'heurePrelevement':
          '${deux(c.aujourdhui.hour)}:${deux(c.aujourdhui.minute)}',
      'natureEchantillon': r['echantillon'] ?? '',
    });
    afficherModale<void>(ctx,
        titre: 'Enregistrer le prélèvement',
        sousTitre: '${r['patient']} — ${r['analyse']}',
        taille: TailleModale.md,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Patient', r['patient']),
            ('Dossier', r['patientCode']),
            ('Examen', r['analyse']),
            ('Prescripteur', vrai(r['prescripteur']) ? r['prescripteur'] : '—'),
          ]),
          const SizedBox(height: 12),
          const NoteSigh(
              'Une fois le prélèvement enregistré, le patient peut partir. L’échantillon reste à acheminer au laboratoire avec son bon.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Prélèvement effectué',
                  icone: LucideIcons.syringe,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final col = m.collection('demandesAnalyses');
                    final annuler = col.mettreAJour(
                        r['id'],
                        demPatchPrelevement(v,
                            demande: r, maintenant: c.aujourdhui));
                    m.journaliser('Prélèvement effectué', 'M5', 'DemandeAnalyse',
                        '${r['reference']}', null, {'preleveur': v['preleveur']});
                    fermer();
                    ToastsSigh.afficher(ctx, 'Prélèvement enregistré.',
                        type: TypeToast.succes,
                        detail:
                            'Le patient peut partir ; l’échantillon est à transmettre au laboratoire.',
                        annuler: annuler);
                  }),
            ]);
  }

  Future<void> _transmettre(BuildContext ctx, Fiche r) async {
    final c = ContexteEcran.of(ctx);
    final ok = await confirmerSigh(ctx,
        titre: 'Transmettre l’échantillon au laboratoire ?',
        message:
            'L’échantillon de ${r['patient']} (${r['analyse']}) est remis au laboratoire avec son bon d’analyse.\n\nÀ compter de cette remise, le laboratoire peut saisir le résultat — et pas avant : un résultat rendu sur un échantillon non reçu serait invérifiable.',
        libelleOk: 'Transmettre');
    if (!ok || !ctx.mounted) return;
    final m = c.magasin;
    final annuler = m.collection('demandesAnalyses').mettreAJour(
        r['id'],
        demPatchTransmission(
            maintenant: c.aujourdhui, utilisateur: c.utilisateur));
    m.journaliser('Échantillon reçu au laboratoire', 'M5', 'DemandeAnalyse',
        '${r['reference']}', null, {});
    ToastsSigh.afficher(ctx, 'Échantillon transmis au laboratoire.',
        type: TypeToast.succes,
        detail: 'Le résultat peut désormais être saisi.',
        annuler: annuler);
  }
}
