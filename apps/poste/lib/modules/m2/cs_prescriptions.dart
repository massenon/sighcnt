import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cs_commun.dart';
import 'cs_modale.dart';

List<Fiche> _lignes(Object? v) => [
      for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()
    ];

/// `m2-prescriptions` — « Prescriptions » : le registre unique des prescriptions d'ordonnance et de soins, quelle qu'en soit l'origine. Deux
/// prescriptions distinctes : l'ORDONNANCE porte des médicaments et sort du stock ; la prescription de SOINS porte des actes et s'adresse à un
/// secteur. Seuls médecins et sages-femmes prescrivent — le contrôle est au moteur, pas à l'écran. Une prescription non réglée reste visible
/// mais non exécutable : l'encaissement la débloque.
class EcranPrescriptions extends StatelessWidget with EcranMaquette {
  const EcranPrescriptions({super.key});

  @override
  String get titre => 'Prescriptions';

  @override
  String get description =>
      'Registre unique des prescriptions d’ordonnance et de soins, quelle qu’en soit l’origine.';

  @override
  String get regle =>
      'Deux prescriptions distinctes : l’ordonnance porte des médicaments et sort du stock ; la prescription de soins porte des actes et s’adresse à un secteur. Quatre origines : consultation, hospitalisation, bloc et maternité. Seuls médecins et sages-femmes prescrivent — le contrôle est au moteur, pas à l’écran.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('prescriptions');
    return ListenableBuilder(
        listenable: Listenable.merge([col, c.magasin.collection('administrations')]),
        builder: (ctx, _) => _Corps(c: c, ecran: ctx, col: col));
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.c, required this.ecran, required this.col});
  final ContexteEcran c;
  final BuildContext ecran;
  final CollectionMagasin col;

  List<ChampDef> _champs() {
    final m = c.magasin;
    final catalogue = [
      for (final t in m.collection('catalogueTarifs').actives)
        if (t['famille'] == 'AMI') t
    ];
    return [
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient',
          type: TypeChamp.select,
          requis: true,
          options: optionsPatientsCs(m)),
      ChampDef(
          nom: 'prescripteurId',
          libelle: 'Prescripteur',
          type: TypeChamp.select,
          requis: true,
          aide: 'Médecins et sages-femmes seulement : l’infirmier n’est pas habilité à prescrire.',
          options: [
            for (final x in m.collection('soignants').actives)
              if (vrai(x['prescrit'])) OptionChamp('${x['id']}', '${x['nomComplet']} — ${x['poste']}')
          ]),
      ChampDef(
          nom: 'origine',
          libelle: 'Origine de la prescription',
          type: TypeChamp.select,
          requis: true,
          options: [
            for (final o in csOriginesPrescription) OptionChamp('${o['code']}', '${o['label']}')
          ]),
      ChampDef(
          nom: 'secteurDestinataire',
          libelle: 'Secteur destinataire',
          type: TypeChamp.select,
          requis: true,
          aide: 'Sans destinataire, la prescription n’apparaîtrait sur aucun poste.',
          options: [
            for (final o in csSecteursSoins) OptionChamp('${o['code']}', '${o['label']}')
          ]),
      ChampDef(
          nom: 'modalite',
          libelle: 'Modalité de traitement',
          type: TypeChamp.select,
          requis: true,
          aide:
              'Ambulatoire : salle de soins seule. Hospitalisation : première administration en salle de soins, les suivantes en hospitalisation.',
          options: [
            for (final o in csModalitesTraitement) OptionChamp('${o['code']}', '${o['label']}')
          ]),
      const ChampDef(
          nom: 'indication', libelle: 'Indication', type: TypeChamp.textarea, lignes: 2),
      ChampDef(
          nom: 'actes',
          libelle: 'Actes prescrits',
          type: TypeChamp.multiselect,
          requis: true,
          options: [
            for (final a in catalogue)
              OptionChamp('${a['code']}',
                  '${a['code']} — ${a['libelle']} — ${a['prixNonAssure'] == null ? 'tarif non renseigné au document' : '${money(a['prixNonAssure'])} non assuré · ${money(a['prixAssure'])} assuré'}')
          ]),
      const ChampDef(
          nom: 'nbAdministrations',
          libelle: 'Nombre d’administrations par acte',
          type: TypeChamp.nombre,
          aide:
              'C’est ce nombre qui fait vivre le relais : une administration unique ne quitte jamais la salle de soins.'),
    ];
  }

  void _nouvelle() => modaleFormulaire(ecran,
      titre: 'Prescrire des soins',
      sousTitre: 'Les champs marqués d’un astérisque sont obligatoires.',
      champs: _champs(),
      initial: const {'modalite': 'ambulatoire', 'nbAdministrations': '1'},
      libelleOk: 'Prescrire',
      valider: (v) {
        final FicheCs pres;
        try {
          final nb = num.tryParse('${v['nbAdministrations'] ?? ''}');
          pres = csPrescrireSoins(stockDe(c), {
            'patientCode': v['patientCode'],
            'prescripteurId': v['prescripteurId'],
            'origine': v['origine'],
            'secteurDestinataire': v['secteurDestinataire'],
            'modalite': v['modalite'],
            'indication': v['indication'],
            'actes': [
              for (final code in (v['actes'] as List))
                {'code': code, 'nbAdministrations': (nb == null || nb == 0) ? 1 : nb}
            ],
            'date': c.aujourdhui.toUtc().toIso8601String(),
          });
        } on RefusCs catch (e) {
          return e.message;
        }
        ToastsSigh.afficher(ecran, 'Prescription ${pres['reference']} enregistrée.',
            type: TypeToast.succes,
            detail:
                '${csLibelleSecteur(pres['secteurDestinataire'])} — première administration : ${csLibelleSecteur(pres['premierAdministrateur'])}',
            annuler: () => col.archiver(pres['id']),
            messageAnnulation: 'Prescription annulée — la fiche est archivée.');
        return null;
      });

  void _archiver(Fiche r) async {
    final ok = await confirmerSigh(ecran,
        titre: 'Archiver cet enregistrement ?',
        message:
            'Archivage logique : les données restent consultables dans l’onglet « Archivés » et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (!ok || !ecran.mounted) return;
    ToastsSigh.afficher(ecran, 'Enregistrement archivé.',
        type: TypeToast.succes, annuler: col.archiver(r['id']));
  }

  void _detail(Fiche r) {
    final s = stockDe(c);
    final lignes = _lignes(r['lignes']);
    afficherTiroir<void>(ecran,
        titre: '${r['reference']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Référence', '${r['reference']}'),
            ('Date', texteDateHeureCs(r['date'])),
            ('Patient', '${r['patient']} — ${r['patientCode']}'),
            ('Type', r['type'] == 'soins' ? 'Prescription de soins' : 'Ordonnance'),
            ('Origine', csLibelleOrigine(r['origine'])),
            ('Prescripteur', '${r['prescripteur']}'),
            ('Secteur destinataire', csLibelleSecteur(r['secteurDestinataire'])),
            ('Modalité', r['modalite'] == 'ambulatoire' ? 'Ambulatoire' : 'En hospitalisation'),
            ('Tarif appliqué', vrai(r['assure']) ? 'Assuré (carte valide à la date)' : 'Non assuré'),
            ('Règlement', r['statutPaiement'] == 'payee' ? 'Réglée' : 'Non réglée'),
          ]),
          if (vrai(r['indication'])) ...[
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Indication',
                child: Text('${r['indication']}',
                    style: const TextStyle(color: JetonsShell.slate600, fontSize: 14))),
          ],
          const SizedBox(height: 16),
          SectionSigh(
              titre: 'Lignes et avancement des administrations',
              child: miniPaires(
                  ['Acte', 'Qté', 'Administré', 'Prochain secteur', 'Prix'], [
                for (var i = 0; i < lignes.length; i++)
                  () {
                    final l = lignes[i];
                    final rang = csRangSuivant(s, r['id'], i);
                    final att = csSecteurAdministrateur(r['modalite'], rang);
                    return [
                      '${l['libelle']}',
                      '${l['quantite'] ?? 1}',
                      '${rang - 1} / ${l['nbAdministrations'] ?? 1}',
                      csLibelleSecteur(att.secteur),
                      l['prix'] == null ? 'tarif non renseigné' : money(l['prix']),
                    ];
                  }()
              ])),
          const SizedBox(height: 16),
          const NoteSigh(
              'Le prochain secteur n’est pas un choix d’organisation : il découle du rang. Traitement ambulatoire, la salle de soins administre du premier au dernier passage ; traitement hospitalier, la première administration revient à la salle de soins et les suivantes à l’hospitalisation.',
              icone: LucideIcons.route),
        ]));
  }

  Widget _tableau(List<Fiche> rows) {
    final tries = trierPar(rows, (r) => r['date']).reversed.toList();
    return TableauSigh(
      lignes: tries,
      messageVide: 'Aucune prescription enregistrée.',
      nomExport: 'prescriptions',
      colonnes: [
        const ColonneTableau(cle: 'reference', libelle: 'Référence'),
        ColonneTableau(
            cle: 'date', libelle: 'Date', texte: (r) => texteDateHeureCs(r['date'])),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Patient',
            texte: (r) => '${r['patient']} — ${r['patientCode']}'),
        ColonneTableau(
            cle: 'type',
            libelle: 'Type',
            texte: (r) => r['type'] == 'soins' ? 'Soins' : 'Ordonnance',
            rendu: (_, r) => BadgeSigh(r['type'] == 'soins' ? 'Soins' : 'Ordonnance',
                ton: r['type'] == 'soins' ? TonSigh.succes : TonSigh.info)),
        ColonneTableau(
            cle: 'origine', libelle: 'Origine', texte: (r) => csLibelleOrigine(r['origine'])),
        ColonneTableau(
            cle: 'secteurDestinataire',
            libelle: 'Destinataire',
            texte: (r) => csLibelleSecteur(r['secteurDestinataire'])),
        const ColonneTableau(cle: 'prescripteur', libelle: 'Prescripteur'),
        ColonneTableau(
            cle: 'montant',
            libelle: 'Montant',
            droite: true,
            texte: (r) => money(r['montant'] ?? 0)),
        ColonneTableau(
            cle: 'statutPaiement',
            libelle: 'Règlement',
            texte: (r) => r['statutPaiement'] == 'payee' ? 'Réglée' : 'Non réglée',
            rendu: (_, r) => r['statutPaiement'] == 'payee'
                ? const BadgeSigh('Réglée', ton: TonSigh.succes)
                : const BadgeSigh('Non réglée', ton: TonSigh.attention)),
      ],
      alClicLigne: _detail,
      actions: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Nouvelle prescription de soins',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: _nouvelle),
      ],
      actionsLigne: (context, r) => [
        BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _detail(r)),
        if (c.droit.annuler)
          BoutonIcone(
              icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(r)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = col.actives;
    final k = csKpisPrescriptions(rows);
    final soins = rows.where((r) => r['type'] == 'soins').toList();
    final ordo = rows.where((r) => r['type'] == 'ordonnance').toList();
    final enCours = rows.where((r) => r['statut'] == 'en_cours').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Prescriptions',
            valeur: nombre(k.total),
            icone: LucideIcons.clipboardPlus,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Ordonnances',
            valeur: nombre(k.ordonnances),
            icone: LucideIcons.scrollText,
            ton: TonSigh.info,
            indice: 'médicaments — vers la pharmacie'),
        KpiSigh(
            libelle: 'Prescriptions de soins',
            valeur: nombre(k.soins),
            icone: LucideIcons.handHeart,
            ton: TonSigh.succes,
            indice: 'actes — vers un secteur d’exécution'),
        KpiSigh(
            libelle: 'En attente de règlement',
            valeur: nombre(k.attenteReglement),
            icone: LucideIcons.lock,
            ton: k.attenteReglement > 0 ? TonSigh.attention : TonSigh.neutre,
            indice: 'exécution bloquée'),
      ]),
      const SizedBox(height: 16),
      const NoteSigh(
          'Une prescription non réglée reste visible mais non exécutable : l’encaissement la débloque. C’est la même règle que pour la délivrance en pharmacie et pour le laboratoire — le poste voit ce qui l’attend sans pouvoir le servir avant paiement.',
          icone: LucideIcons.lock),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'toutes',
            libelle: 'Toutes',
            compte: rows.length,
            construire: (_) => _tableau(rows)),
        OngletDef(
            id: 'soins',
            libelle: 'Prescriptions de soins',
            compte: soins.length,
            construire: (_) => _tableau(soins)),
        OngletDef(
            id: 'ordonnances',
            libelle: 'Ordonnances',
            compte: ordo.length,
            construire: (_) => _tableau(ordo)),
        OngletDef(
            id: 'encours',
            libelle: 'En cours',
            compte: enCours.length,
            construire: (_) => _tableau(enCours)),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m2-salle-soins
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `m2-salle-soins` — « Salle de soins » : les administrations dues à ce poste, ambulatoires et premières administrations des hospitalisés. Le
/// RANG décide du secteur (règle de relais), le règlement de l'exécutabilité ; un poste qui prend ce qui ne lui revient pas est refusé EN LE NOMMANT.
class EcranSalleSoins extends StatelessWidget with EcranMaquette {
  const EcranSalleSoins({super.key});

  static const _regle =
      'La salle de soins administre tous les traitements ambulatoires, du premier au dernier passage, et la première administration des traitements hospitaliers. Le relais passe ensuite à l’hospitalisation — c’est le circuit décrit par la Direction, appliqué par le moteur et non laissé à l’usage.';

  @override
  String get titre => 'Salle de soins';

  @override
  String get description =>
      'Administrations dues à la salle de soins : ambulatoires et premières administrations des hospitalisés.';

  @override
  String get regle => _regle;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge(
            [m.collection('prescriptions'), m.collection('administrations')]),
        builder: (ctx, _) => _Salle(c: c, ecran: ctx));
  }
}

class _Salle extends StatelessWidget {
  const _Salle({required this.c, required this.ecran});
  final ContexteEcran c;
  final BuildContext ecran;
  static const secteur = 'salle_soins';

  void _administrer(Fiche r, SoinDu l, Fiche pres) {
    final m = c.magasin;
    final exs = [
      for (final x in m.collection('soignants').actives)
        if (vrai(x['execute']) && ((x['secteurs'] as List?) ?? const []).contains(secteur))
          OptionChamp('${x['id']}', '${x['nomComplet']} — ${x['poste']}')
    ];
    modaleFormulaire(ecran,
        titre: 'Administrer — ${l.ligne['libelle']}',
        sousTitre: '${pres['patient']} — passage ${l.rang} sur ${l.total}',
        taille: TailleModale.md,
        libelleOk: 'Confirmer l’administration',
        avant: NoteSigh(l.motif, icone: LucideIcons.route),
        champs: [
          ChampDef(
              nom: 'executantId',
              libelle: 'Exécutant',
              type: TypeChamp.select,
              requis: true,
              col: ColChamp.plein,
              aide: 'Infirmiers et sages-femmes. Le médecin prescrit, il n’exécute pas les soins.',
              options: exs),
          const ChampDef(
              nom: 'observation',
              libelle: 'Observation',
              type: TypeChamp.textarea,
              lignes: 2,
              col: ColChamp.plein),
        ],
        valider: (v) {
          final ResultatAdministration res;
          try {
            res = csAdministrer(stockDe(c), pres['id'],
                ligneIndex: l.index,
                secteur: secteur,
                executantId: v['executantId'],
                observation: v['observation'] as String?);
          } on RefusCs catch (e) {
            return e.message;
          }
          if (!res.ok) return res.motif;
          ToastsSigh.afficher(ecran, 'Administration n° ${res.rang} enregistrée.',
              type: TypeToast.succes, detail: '${l.ligne['libelle']} — ${pres['patient']}');
          return null;
        });
  }

  @override
  Widget build(BuildContext context) {
    final dus = csSoinsDuSecteur(stockDe(c), secteur);
    final lignes = dus.fold<int>(0, (n, d) => n + d.lignes.length);
    final bloquees = dus.fold<int>(0, (n, d) => n + d.lignes.where((l) => l.bloque).length);
    final premieres = dus.fold<int>(0, (n, d) => n + d.lignes.where((l) => l.rang == 1).length);
    final rows = <Fiche>[
      for (final d in dus)
        for (final l in d.lignes)
          {
            'id': '${d.prescription['id']}:${l.index}',
            'reference': d.prescription['reference'],
            'patient': d.prescription['patient'],
            'patientCode': d.prescription['patientCode'],
            'libelle': l.ligne['libelle'],
            'rang': l.rang,
            'total': l.total,
            'motif': l.motif,
            'bloque': l.bloque,
            '_pres': d.prescription,
            '_ligne': l,
          }
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Patients concernés',
            valeur: nombre(dus.length),
            icone: LucideIcons.users,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Administrations dues',
            valeur: nombre(lignes),
            icone: LucideIcons.syringe,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Premières administrations',
            valeur: nombre(premieres),
            icone: LucideIcons.flag,
            ton: TonSigh.succes),
        KpiSigh(
            libelle: 'Bloquées faute de règlement',
            valeur: nombre(bloquees),
            icone: LucideIcons.lock,
            ton: bloquees > 0 ? TonSigh.attention : TonSigh.neutre),
      ]),
      const SizedBox(height: 16),
      const NoteSigh(EcranSalleSoins._regle, icone: LucideIcons.route),
      const SizedBox(height: 16),
      TableauSigh(
        lignes: rows,
        messageVide: 'Aucune administration due à ce poste pour l’instant.',
        nomExport: 'salle-de-soins',
        colonnes: [
          const ColonneTableau(cle: 'reference', libelle: 'Prescription'),
          ColonneTableau(
              cle: 'patient',
              libelle: 'Patient',
              texte: (r) => '${r['patient']} — ${r['patientCode']}'),
          const ColonneTableau(cle: 'libelle', libelle: 'Acte ou produit'),
          ColonneTableau(
              cle: 'rang',
              libelle: 'Passage',
              texte: (r) => '${r['rang']} / ${r['total']}'),
          ColonneTableau(
              cle: 'motif',
              libelle: 'Pourquoi ce poste',
              rendu: (_, r) => Text('${r['motif']}',
                  style: const TextStyle(color: JetonsShell.slate500, fontSize: 12))),
          ColonneTableau(
              cle: 'bloque',
              libelle: 'État',
              texte: (r) => r['bloque'] == true ? 'Non réglée' : 'Exécutable',
              rendu: (_, r) => r['bloque'] == true
                  ? const BadgeSigh('Non réglée', ton: TonSigh.attention)
                  : const BadgeSigh('Exécutable', ton: TonSigh.succes)),
        ],
        actionsLigne: (context, r) {
          if (r['bloque'] == true) {
            return [
              BoutonIcone(
                  icone: LucideIcons.lock,
                  libelle: 'Bloquée : la prescription n’est pas réglée',
                  onPressed: () => ToastsSigh.afficher(ecran,
                      'Administration bloquée — la prescription ${r['reference']} n’est pas réglée.',
                      type: TypeToast.attention)),
            ];
          }
          // Les droits de l'ÉCRAN (la salle de soins est un écran de M2) : interroger M3 donnait le droit d'administrer à l'aide-soignante.
          if (!c.droit.editer) return const [];
          return [
            BoutonSigh(
                libelle: 'Administrer',
                icone: LucideIcons.check,
                taille: TailleBouton.sm,
                onPressed: () => _administrer(
                    r, r['_ligne'] as SoinDu, (r['_pres'] as Map).cast<String, Object?>())),
          ];
        },
      ),
    ]);
  }
}
