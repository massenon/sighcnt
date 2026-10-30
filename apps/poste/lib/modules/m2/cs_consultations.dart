import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cs_commun.dart';
import 'cs_modale.dart';

const _statuts = [
  OptionChamp('planifiee', 'Planifiée'),
  OptionChamp('en_cours', 'En cours'),
  OptionChamp('terminee', 'Terminée'),
];

/// `m2-consultations` — « Consultations » : le registre des consultations, diagnostics et actes réalisés, avec édition du compte rendu.
/// (`K.crud` de la maquette : tableau trié / filtré / paginé, création et modification en modale, archivage annulable, fiche, impression.)
class EcranConsultations extends StatelessWidget with EcranMaquette {
  const EcranConsultations({super.key});

  @override
  String get titre => 'Consultations';

  @override
  String get description =>
      'Enregistrement des consultations, diagnostics et actes réalisés, avec édition du compte rendu.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('consultations');
    return ListenableBuilder(
        listenable: col, builder: (ctx, _) => _Corps(c: c, col: col, ecran: ctx));
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.c, required this.col, required this.ecran});
  final ContexteEcran c;
  final CollectionMagasin col;
  final BuildContext ecran;

  List<ChampDef> _champs() => [
        const ChampDef.section('Patient et praticien'),
        ChampDef(
            nom: 'patientCode',
            libelle: 'Dossier patient',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: optionsPatientsCs(c.magasin)),
        ChampDef(
            nom: 'medecin',
            libelle: 'Praticien',
            type: TypeChamp.select,
            requis: true,
            options: optionsMedecinsCs(c.magasin)),
        const ChampDef(
            nom: 'type',
            libelle: 'Type',
            type: TypeChamp.select,
            requis: true,
            options: [
              OptionChamp('Consultation'),
              OptionChamp('Contrôle'),
              OptionChamp('Urgence'),
              OptionChamp('Domicile')
            ]),
        const ChampDef.section('Rendez-vous'),
        const ChampDef(
            nom: 'date',
            libelle: 'Date et heure',
            requis: true,
            indicatif: 'AAAA-MM-JJThh:mm'),
        const ChampDef(
            nom: 'motif', libelle: 'Motif', requis: true, col: ColChamp.plein),
        const ChampDef(
            nom: 'diagnostic',
            libelle: 'Diagnostic',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein),
        const ChampDef(nom: 'tarif', libelle: 'Tarif (FCFA)', type: TypeChamp.nombre),
        const ChampDef(
            nom: 'statut',
            libelle: 'Statut',
            type: TypeChamp.select,
            requis: true,
            options: _statuts),
      ];

  /// `completerPatient` : le patient (identifiant et nom) se déduit du code ; la référence suit le registre.
  String? _ecrire(Fiche? existante, Map<String, Object?> v) {
    final p = c.magasin
        .collection('patients')
        .actives
        .where((x) => x['code'] == v['patientCode'])
        .firstOrNull;
    final date = '${v['date']}'.replaceFirst(' ', 'T');
    if (DateTime.tryParse(date) == null) {
      return 'Date et heure invalides : saisir AAAA-MM-JJThh:mm.';
    }
    final tarif = '${v['tarif'] ?? ''}'.isEmpty ? null : num.tryParse('${v['tarif']}');
    final fiche = <String, Object?>{
      ...v,
      'date': date,
      'tarif': tarif,
      if (p != null) 'patientId': p['id'],
      if (p != null) 'patient': '${p['nom']} ${p['prenom']}',
    };
    if (existante != null) {
      col.mettreAJour(existante['id'], fiche);
      ToastsSigh.afficher(ecran, 'Consultation modifiée.', type: TypeToast.succes);
    } else {
      col.inserer({
        'statut': 'actif',
        ...fiche,
        'reference': referenceSerie('C', 5, col.toutes),
      }, prefixe: 'CON');
      ToastsSigh.afficher(ecran, 'Consultation créée.', type: TypeToast.succes);
    }
    return null;
  }

  void _ouvrir(Fiche? r) {
    final m = c.magasin;
    modaleFormulaire(ecran,
        titre: r == null ? 'Nouvelle consultation' : 'Modifier la consultation',
        champs: _champs(),
        libelleOk: r == null ? 'Créer' : 'Enregistrer',
        initial: r == null
            ? {
                'statut': 'en_cours',
                'type': 'Consultation',
                'tarif': '3000',
                'date': c.aujourdhui.toUtc().toIso8601String().substring(0, 16),
              }
            : {
                ...r,
                'tarif': r['tarif'] == null ? '' : '${r['tarif']}',
              },
        valider: (v) {
          if (m.collection('patients').actives.every((x) => x['code'] != v['patientCode'])) {
            return 'Patient introuvable au répertoire.';
          }
          return _ecrire(r, v);
        });
  }

  void _archiver(Fiche r) async {
    final ok = await confirmerSigh(ecran,
        titre: 'Archiver cet enregistrement ?',
        message:
            'Archivage logique : les données restent consultables dans l’onglet « Archivés » et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (!ok || !ecran.mounted) return;
    final u = col.archiver(r['id']);
    ToastsSigh.afficher(ecran, 'Enregistrement archivé.',
        type: TypeToast.succes, annuler: u);
  }

  Widget _detail(Fiche r) {
    final p = c.magasin.collection('patients').actives.where((x) => x['id'] == r['patientId']).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DescListeSigh([
        ('Référence', vrai(r['reference']) ? r['reference'] : r['id']),
        ('Date', '${texteDateCs(r['date'])} à ${_heure(r['date'])}'),
        ('Patient', '${r['patient']}'),
        ('Dossier', '${r['patientCode']}'),
        ('Praticien', '${r['medecin']}'),
        ('Type', '${r['type']}'),
        ('Statut', statutBadge(r['statut'])),
        ('Tarif', money(r['tarif'] ?? 0)),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Motif et diagnostic',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Motif de consultation',
                style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
            Text(vrai(r['motif']) ? '${r['motif']}' : '—',
                style: const TextStyle(color: JetonsShell.slate800, fontSize: 14)),
            const SizedBox(height: 12),
            const Text('Diagnostic',
                style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
            Text(vrai(r['diagnostic']) ? '${r['diagnostic']}' : 'Non renseigné',
                style: const TextStyle(color: JetonsShell.slate800, fontSize: 14)),
          ])),
      if (p != null && vrai(p['assureur'])) ...[
        const SizedBox(height: 16),
        NoteSigh(
            'Patient couvert par ${p['assureurNom'] ?? p['assureur']} à hauteur de ${p['tauxPriseEnCharge']} %. La facturation appliquera la répartition patient / assureur (RG-09).',
            icone: LucideIcons.shieldCheck),
      ],
    ]);
  }

  static String _heure(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
    return d == null ? '' : heure(d);
  }

  void _consulter(Fiche r) => afficherTiroir<void>(ecran,
      titre: '${vrai(r['reference']) ? r['reference'] : r['id']}',
      largeurMax: 672,
      corps: _detail(r),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Imprimer',
                icone: LucideIcons.printer,
                variante: VarianteBouton.secondaire,
                onPressed: () => _etat(r)),
            if (c.droit.annuler)
              BoutonSigh(
                  libelle: 'Archiver',
                  icone: LucideIcons.archive,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    fermer();
                    _archiver(r);
                  }),
          ]);

  /// `etatConsultation` : le compte rendu de consultation.
  void _etat(Fiche r) {
    final p = c.magasin.collection('patients').actives.where((x) => x['id'] == r['patientId']).firstOrNull;
    final nais = DateTime.tryParse('${p?['dateNaissance'] ?? ''}');
    afficherApercu(
        ecran,
        PieceA4(
          titre: 'Compte rendu de consultation',
          sousTitre: '${r['type']} du ${texteDateCs(r['date'])}',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Patient', '${r['patient']}'),
            ('Dossier', '${r['patientCode']}'),
            ('Âge', nais != null ? '${(c.aujourdhui.difference(nais).inDays / 365.25).floor()} ans' : '—'),
            ('Praticien', '${r['medecin']}'),
            ('Référence', '${vrai(r['reference']) ? r['reference'] : r['id']}'),
            ('Type', '${r['type']}'),
          ],
          blocs: [
            BlocTexte('Motif de consultation : ${vrai(r['motif']) ? r['motif'] : '—'}'),
            BlocTexte('Diagnostic retenu : ${vrai(r['diagnostic']) ? r['diagnostic'] : '—'}'),
            const BlocTexte('Observations et conduite à tenir', gras: true),
            const BlocTexte('(Espace réservé à la rédaction manuscrite ou à la saisie)',
                italique: true),
          ],
          signatures: [Signature('Le Médecin traitant', nom: '${r['medecin']}')],
        ));
  }

  TableauSigh _tableau(bool archive) {
    final lignes = archive ? col.archivees : col.actives;
    final medecins = optionsMedecinsCs(c.magasin);
    return TableauSigh(
      colonnes: [
        ColonneTableau(
            cle: 'date',
            libelle: 'Date',
            sansCoupure: true,
            valeur: (r) =>
                DateTime.tryParse('${r['date']}')?.millisecondsSinceEpoch ?? 0,
            texte: (r) => '${texteDateCs(r['date'])} ${_heure(r['date'])}',
            rendu: (_, r) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(texteDateCs(r['date']),
                          style: const TextStyle(
                              color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                      Text(_heure(r['date']),
                          style: const TextStyle(
                              color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                    ])),
        colPatientCs(),
        const ColonneTableau(cle: 'motif', libelle: 'Motif'),
        const ColonneTableau(cle: 'diagnostic', libelle: 'Diagnostic'),
        const ColonneTableau(cle: 'medecin', libelle: 'Praticien'),
        ColonneTableau(
            cle: 'tarif',
            libelle: 'Tarif',
            droite: true,
            texte: (r) => money(r['tarif'] ?? 0, avecDevise: false)),
        ColonneTableau(
            cle: 'statut',
            libelle: 'Statut',
            texte: (r) => '${r['statut']}',
            rendu: (_, r) => statutBadge(r['statut'])),
      ],
      lignes: lignes,
      filtres: [
        const FiltreTableau(nom: 'statut', libelle: 'Statut', options: _statuts),
        FiltreTableau(nom: 'medecin', libelle: 'Praticien', options: medecins),
      ],
      taillePage: 12,
      selectionnable: !archive,
      nomExport: 'consultations',
      triInitial: 'date',
      sensInitial: 'desc',
      libelleRecherche: 'Rechercher un consultation…',
      messageVide: archive
          ? 'Aucun enregistrement archivé.'
          : 'Aucun consultation enregistré.',
      indiceVide: archive
          ? null
          : 'Utiliser le bouton « Nouveau » pour créer le premier enregistrement.',
      alClicLigne: _consulter,
      actions: [
        if (!archive && c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => _ouvrir(null)),
      ],
      actionsLigne: (context, r) => archive
          ? [
              if (c.droit.annuler)
                BoutonIcone(
                    icone: LucideIcons.archiveRestore,
                    libelle: 'Restaurer',
                    onPressed: () {
                      col.restaurer(r['id']);
                      ToastsSigh.afficher(ecran, 'Enregistrement restauré.',
                          type: TypeToast.succes);
                    }),
            ]
          : [
              BoutonIcone(
                  icone: LucideIcons.eye,
                  libelle: 'Consulter',
                  onPressed: () => _consulter(r)),
              BoutonIcone(
                  icone: LucideIcons.printer,
                  libelle: 'Imprimer l’état',
                  onPressed: () => _etat(r)),
              if (c.droit.editer)
                BoutonIcone(
                    icone: LucideIcons.pencil,
                    libelle: 'Modifier',
                    onPressed: () => _ouvrir(r)),
              if (c.droit.annuler)
                BoutonIcone(
                    icone: LucideIcons.archive,
                    libelle: 'Archiver',
                    onPressed: () => _archiver(r)),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final actives = col.actives;
    final mois = actives.where((r) {
      final d = DateTime.tryParse('${r['date']}')?.toLocal();
      return d != null && d.year == c.aujourdhui.year && d.month == c.aujourdhui.month;
    }).toList();
    double somme(Iterable<Fiche> l) =>
        l.fold(0.0, (a, r) => a + nombreOuZero(r['tarif']));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!c.droit.editer && c.droit.voir)
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NoteSigh(
                'Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
                ton: TonSigh.attention)),
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Consultations totales',
                valeur: nombre(actives.length),
                icone: LucideIcons.stethoscope,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Ce mois-ci',
                valeur: nombre(mois.length),
                icone: LucideIcons.calendarCheck,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Recette consultations',
                valeur: money(somme(actives)),
                icone: LucideIcons.coins,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Tarif moyen',
                valeur: money(actives.isEmpty ? 0 : somme(actives) / actives.length),
                icone: LucideIcons.trendingUp,
                ton: TonSigh.neutre),
          ])),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'liste',
            libelle: 'Tous les consultations',
            compte: actives.length,
            construire: (_) => _tableau(false)),
        OngletDef(
            id: 'archives',
            libelle: 'Archivés',
            compte: col.archivees.length,
            construire: (_) => _tableau(true)),
      ]),
    ]);
  }
}
