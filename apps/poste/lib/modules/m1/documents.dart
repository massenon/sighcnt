import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m1.dart';

String _t(Object? v, [String vide = '—']) => patVrai(v) ? '$v' : vide;

/// `m1-documents` — la bibliothèque documentaire du patient. Un document se DÉPOSE (PDF, PNG ou JPEG) et reste rattaché au dossier ; le fichier est
/// conservé dans le poste, sans requête réseau. RG-14 : retirer un document l'archive, avec son motif.
///
/// Limite dite : le poste n'a pas de sélecteur natif de fichier (aucune dépendance de plateforme dans le projet) — comme la galerie d'imagerie, le dépôt
/// demande le CHEMIN du fichier sur le poste.
class EcranDocuments extends StatelessWidget with EcranMaquette {
  const EcranDocuments({super.key});

  @override
  String get titre => 'Documents numérisés du patient';

  @override
  String get description =>
      'Ordonnances, résultats d’analyses, comptes rendus, consentements et imagerie rattachés au dossier patient.';

  @override
  String get regle =>
      'Un document se dépose depuis cet écran — PDF, PNG ou JPEG — et reste rattaché au dossier du patient. Le fichier est conservé dans le poste, sans requête réseau. RG-14 — retirer un document l’archive : il reste restaurable depuis la corbeille.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Répertoire des patients',
          icone: LucideIcons.users,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m1-patients')),
      BoutonSigh(
          libelle: 'Plan de numérisation',
          icone: LucideIcons.scanLine,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m1-numerisation')),
    ];
  }

  static List<ChampDef> champs(ContexteEcran c, Fiche? e) => [
        ChampDef(
            nom: 'patientId',
            libelle: 'Dossier patient',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [
              for (final p in trierPar(c.magasin.collection('patients').actives, (p) => p['code']))
                OptionChamp('${p['id']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
            ]),
        ChampDef(
            nom: 'type',
            libelle: 'Type de document',
            type: TypeChamp.select,
            requis: true,
            options: [for (final t in patTypesDocument) OptionChamp(t)]),
        const ChampDef(nom: 'date', libelle: 'Date du document', type: TypeChamp.date, requis: true),
        const ChampDef(
            nom: 'etat',
            libelle: 'Statut',
            type: TypeChamp.select,
            requis: true,
            options: [OptionChamp('en_attente', 'En attente de validation'), OptionChamp('valide', 'Validé')]),
        const ChampDef(nom: 'depose', libelle: 'Déposé par', requis: true),
      ];

  static void _deposer(BuildContext ctx, ContexteEcran c) {
    final defs = champs(c, null);
    final ctl = ControleurFormulaire(defs, {'date': iso(c.aujourdhui), 'etat': 'en_attente', 'depose': c.utilisateur});
    final chemin = TextEditingController();
    String? data, nom, format;
    int taille = 0;
    Uint8List? apercu;
    String? avertissement;
    afficherModale<void>(ctx,
        titre: 'Ajouter un document au dossier',
        taille: TailleModale.lg,
        corps: StatefulBuilder(
            builder: (cx, maj) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormulaireSigh(controleur: ctl),
                  const SizedBox(height: 12),
                  const LibelleChamp('Fichier numérisé * — PDF, PNG ou JPEG'),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            key: const Key('doc:chemin'),
                            controller: chemin,
                            style: styleSaisie,
                            decoration: decorationChamp(indicatif: 'Chemin du fichier sur ce poste'))),
                    const SizedBox(width: 8),
                    BoutonSigh(
                        libelle: 'Charger',
                        icone: LucideIcons.upload,
                        variante: VarianteBouton.secondaire,
                        onPressed: () {
                          final f = File(chemin.text.trim());
                          final n = f.path.toLowerCase();
                          final type = n.endsWith('.pdf')
                              ? 'application/pdf'
                              : n.endsWith('.png')
                                  ? 'image/png'
                                  : (n.endsWith('.jpg') || n.endsWith('.jpeg'))
                                      ? 'image/jpeg'
                                      : n.endsWith('.webp')
                                          ? 'image/webp'
                                          : null;
                          if (type == null || !f.existsSync()) {
                            ToastsSigh.afficher(ctx, type == null ? 'Format non reconnu : PDF, PNG ou JPEG.' : 'Fichier introuvable.',
                                type: TypeToast.erreur);
                            return;
                          }
                          final octets = f.readAsBytesSync();
                          maj(() {
                            nom = f.path.split(Platform.pathSeparator).last;
                            taille = octets.length;
                            format = patFormatDocument(nom);
                            data = 'data:$type;base64,${base64Encode(octets)}';
                            apercu = type == 'application/pdf' ? null : octets;
                            avertissement = octets.length > 2 * 1024 * 1024
                                ? 'Fichier de ${patPoidsDoc(octets.length)} — au-delà de deux mégaoctets, le stockage local sature vite. Numériser en résolution plus basse.'
                                : null;
                          });
                        }),
                  ]),
                  if (avertissement != null) Padding(padding: const EdgeInsets.only(top: 8), child: NoteSigh(avertissement!, ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
                  if (nom != null && apercu == null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('$nom — ${patPoidsDoc(taille)} (PDF prêt à être rattaché)', style: styleM1(t: 12, c: JetonsShell.slate500))),
                  if (apercu != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 160),
                                child: Image.memory(apercu!, fit: BoxFit.contain, semanticLabel: 'Aperçu du document', errorBuilder: (_, __, ___) => const SizedBox())))),
                  const SizedBox(height: 12),
                  const NoteSigh(
                      'Le fichier est conservé dans le poste, avec le reste des données : aucune requête réseau, même contrainte hors ligne que le reste du logiciel.'),
                ])),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Rattacher au dossier',
                  icone: LucideIcons.upload,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    if (data == null) {
                      ToastsSigh.afficher(ctx, 'Choisir un fichier à déposer.', type: TypeToast.attention);
                      return;
                    }
                    final p = c.magasin.collection('patients').parId(v['patientId']);
                    final col = c.magasin.collection('documentsPatient');
                    final r = col.inserer({
                      ...v,
                      'statut': 'actif',
                      'reference': patReferenceDocument(col.toutes.length),
                      'code': p?['code'],
                      'patient': p != null ? '${p['nom']} ${p['prenom']}' : '—',
                      'donnees': data,
                      'fichier': nom,
                      'taille': taille,
                      'format': format,
                    }, prefixe: 'DOC');
                    fermer();
                    ToastsSigh.afficher(ctx, 'Document rattaché au dossier ${r.fiche['code']}.',
                        type: TypeToast.succes, detail: '${v['type']} — $nom', annuler: r.annuler, messageAnnulation: 'Création annulée — la fiche est archivée.');
                  }),
            ]);
  }

  static void _previsualiser(BuildContext ctx, Fiche r) {
    Widget corps;
    final d = '${r['donnees'] ?? ''}';
    if (d.isNotEmpty && r['format'] != 'PDF') {
      Uint8List? octets;
      try {
        octets = base64Decode(d.substring(d.indexOf(',') + 1));
      } catch (_) {}
      corps = octets == null
          ? const SizedBox()
          : Image.memory(octets, fit: BoxFit.contain, semanticLabel: '${r['type']}', errorBuilder: (_, __, ___) => const SizedBox());
    } else if (d.isNotEmpty) {
      corps = Container(
          height: 160,
          alignment: Alignment.center,
          child: Text('Fichier PDF conservé au dossier — ${patPoidsDoc(r['taille'])}', style: styleM1(c: JetonsShell.slate500)));
    } else {
      corps = Container(
          height: 256,
          decoration: BoxDecoration(
              color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate300)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(LucideIcons.fileText, size: 40, color: JetonsShell.slate300),
            const SizedBox(height: 8),
            Text('Document référencé au dossier, fichier non encore déposé', style: styleM1(c: JetonsShell.slate500)),
            Text('${patPoidsDoc(r['taille'])} — enregistré le ${dateFrM1(r['date'])}', style: styleM1(t: 12, c: JetonsShell.slate400)),
          ]));
    }
    afficherModale<void>(ctx,
        titre: '${r['type']}',
        sousTitre: '${r['reference']} — ${r['patient']} (${r['code']})',
        taille: TailleModale.lg,
        corps: corps,
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Imprimer',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => imprimerM1(ctx,
                      titre: '${r['type']}',
                      sousTitre: '${r['reference']}',
                      cartouche: [
                        ('Patient', '${r['patient']}'),
                        ('Dossier', '${r['code']}'),
                        ('Date', dateFrM1(r['date'])),
                        ('Format', _t(r['format'])),
                        ('Taille', patPoidsDoc(r['taille'])),
                        ('Déposé par', _t(r['depose'])),
                      ],
                      blocs: const [BlocTexte('Reproduction du document numérisé rattaché au dossier patient.')])),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('documentsPatient');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final k = patKpisDocuments(rows);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Documents numérisés', valeur: nombre(k.total), icone: LucideIcons.files),
              KpiSigh(libelle: 'Validés', valeur: nombre(k.valides), icone: LucideIcons.fileCheck2, ton: TonSigh.succes),
              KpiSigh(libelle: 'En attente de validation', valeur: nombre(k.enAttente), icone: LucideIcons.fileClock, ton: TonSigh.attention),
              KpiSigh(libelle: 'Dossiers couverts', valeur: nombre(k.dossiers), icone: LucideIcons.folderOpen, ton: TonSigh.info),
            ]),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Bibliothèque documentaire du patient',
                sansRemplissage: true,
                child: RegistreM1(
                  collection: col,
                  entite: 'Document',
                  triInitial: 'date',
                  sensInitial: 'desc',
                  taillePage: 15,
                  messageVide: 'Aucun enregistrement.',
                  champs: champs,
                  libelleArchiver: 'Retirer du dossier',
                  messageArchive: 'Document retiré du dossier.',
                  titreArchivage: (f) => 'Retirer « ${f['type']} » du dossier ?',
                  actionsBarre: [
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Ajouter un document',
                          icone: LucideIcons.upload,
                          taille: TailleBouton.sm,
                          onPressed: () => _deposer(context, c)),
                  ],
                  actionsSup: (ctx, r) => [
                    BoutonIcone(icone: LucideIcons.eye, libelle: 'Prévisualiser', onPressed: () => _previsualiser(ctx, r)),
                  ],
                  filtres: [
                    FiltreTableau(nom: 'type', libelle: 'Type de document', options: [for (final t in patTypesDocument) OptionChamp(t)]),
                    FiltreTableau(
                        nom: 'fichier',
                        libelle: 'Fichier',
                        options: const [OptionChamp('oui', 'Fichier déposé'), OptionChamp('non', 'Référencé seulement')],
                        correspond: (r, v) => v == 'oui' ? patVrai(r['donnees']) : !patVrai(r['donnees'])),
                  ],
                  colonnes: [
                    ColonneTableau(cle: 'reference', libelle: 'Référence', sansCoupure: true, rendu: (_, r) => enMono('${r['reference']}'), texte: (r) => '${r['reference']}'),
                    const ColonneTableau(cle: 'code', libelle: 'Dossier', sansCoupure: true),
                    const ColonneTableau(cle: 'patient', libelle: 'Patient'),
                    ColonneTableau(cle: 'type', libelle: 'Type', texte: (r) => '${r['type']}', rendu: (_, r) => BadgeSigh('${r['type']}', ton: TonSigh.navy)),
                    ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => dateFrM1(r['date']), valeur: (r) => r['date']),
                    ColonneTableau(
                        cle: 'format',
                        libelle: 'Fichier',
                        sansCoupure: true,
                        texte: (r) => '${r['format'] ?? '—'} · ${patPoidsDoc(r['taille'])} ${patVrai(r['donnees']) ? 'déposé' : 'référencé'}',
                        rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text('${r['format'] ?? '—'} · ${patPoidsDoc(r['taille'])}', style: styleM1(t: 12, c: JetonsShell.slate600)),
                              Text(patVrai(r['donnees']) ? 'déposé' : 'référencé',
                                  style: TextStyle(color: patVrai(r['donnees']) ? JetonsShell.success600 : JetonsShell.slate400, fontSize: 10, height: 15 / 10)),
                            ])),
                    const ColonneTableau(cle: 'depose', libelle: 'Déposé par'),
                    ColonneTableau(cle: 'etat', libelle: 'Statut', texte: (r) => statutsMetier['${r['etat']}']?.$1 ?? '${r['etat']}', rendu: (_, r) => statutBadge(r['etat'])),
                  ],
                )),
          ]);
        });
  }
}

/// `m1-numerisation` — le plan de reprise des dossiers papier (CDCT §24). Les chiffres sont ceux du rapport de cadrage (environ 18 000 dossiers
/// recensés) : des valeurs de la maquette, non des mesures du magasin.
class EcranNumerisation extends StatelessWidget with EcranMaquette {
  const EcranNumerisation({super.key});

  @override
  String get titre => 'Plan de numérisation des dossiers';

  @override
  String get description => 'Suivi de la reprise progressive et priorisée des dossiers patients papier (CDCT §24).';

  @override
  String get regle =>
      'Le périmètre exclut la migration rétroactive intégrale : seuls les dossiers actifs sont numérisés en priorité, les dossiers inactifs restant numérisables à la demande.';

  static const _total = 18000;
  static const _traites = 4230;
  static const _lots = <(String, int, int)>[
    ('Lot 1 — Hospitalisations en cours', 320, 320),
    ('Lot 2 — Patients suivis (chroniques)', 1450, 1450),
    ('Lot 3 — Maternité et suivis prénataux', 980, 860),
    ('Lot 4 — Patients assurés', 2300, 1600),
    ('Lot 5 — Consultations 2025-2026', 1150, 0),
    ('Lot 6 — Fonds inactif (à la demande)', 11800, 0),
  ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final mois = parMois(const [], 'x', ref: c.aujourdhui);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Dossiers papier recensés', valeur: nombre(_total), icone: LucideIcons.archive, ton: TonSigh.neutre),
        KpiSigh(
            libelle: 'Dossiers numérisés',
            valeur: nombre(_traites),
            icone: LucideIcons.scanLine,
            ton: TonSigh.succes,
            indice: '${pourcent(_traites / _total * 100)} du fonds'),
        KpiSigh(libelle: 'Dossiers actifs prioritaires', valeur: nombre(6200), icone: LucideIcons.star, indice: 'Vus au cours des 24 derniers mois'),
        KpiSigh(libelle: 'Reste à traiter (prioritaires)', valeur: nombre(6200 - _traites), icone: LucideIcons.clock, ton: TonSigh.attention),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Avancement par lot de reprise',
          actions: [
            BoutonSigh(
                libelle: 'Éditer l’état d’avancement',
                icone: LucideIcons.printer,
                taille: TailleBouton.sm,
                onPressed: () => imprimerM1(context,
                    titre: 'État d’avancement de la numérisation',
                    sousTitre: 'Reprise des dossiers patients — CDCT §24',
                    cartouche: [
                      ('Fonds total', '${nombre(_total)} dossiers'),
                      ('Numérisés', nombre(_traites)),
                      ('Avancement', pourcent(_traites / _total * 100)),
                      ('Date d’édition', dateFR(c.aujourdhui)),
                    ],
                    blocs: [
                      BlocTableau(TableauEtat(colonnes: [
                        ColonneEtat(libelle: 'Lot de reprise', valeur: (l) => l['lot']),
                        ColonneEtat(libelle: 'Total', valeur: (l) => l['total'], droite: true, somme: (l) => l['total'] as num),
                        ColonneEtat(libelle: 'Numérisés', valeur: (l) => l['fait'], droite: true, somme: (l) => l['fait'] as num),
                        ColonneEtat(libelle: 'Avancement', valeur: (l) => '${((l['fait'] as int) / (l['total'] as int) * 100).round()} %', droite: true),
                      ], lignes: [
                        for (final l in _lots) {'lot': l.$1, 'total': l.$2, 'fait': l.$3}
                      ])),
                    ],
                    signatures: const [Signature('Le Secrétaire Médical'), Signature('La Directrice Administrative', nom: 'TAKI Alimatou')]))
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final l in _lots)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(l.$1, style: styleM1(p: FontWeight.w500))),
                      Text('${nombre(l.$3)} / ${nombre(l.$2)} (${(l.$3 / l.$2 * 100).round()} %)', style: styleM1(t: 12, c: JetonsShell.slate500)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                            value: (l.$3 / l.$2).clamp(0.01, 1.0).toDouble(),
                            minHeight: 8,
                            backgroundColor: JetonsShell.slate100,
                            valueColor: AlwaysStoppedAnimation(l.$3 == l.$2
                                ? JetonsShell.success500
                                : (l.$3 > 0 ? JetonsShell.navy500 : JetonsShell.slate300)))),
                  ])),
          ])),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (_, w) {
        final barres = CarteSigh(
            titre: 'Cadence de numérisation (12 derniers mois)',
            child: GraphiqueBarres(etiquettes: mois.etiquettes, series: const [
              SerieGraphique('Dossiers numérisés', [0, 0, 120, 310, 480, 520, 610, 430, 380, 520, 460, 400])
            ]));
        final anneau = CarteSigh(
            titre: 'Répartition du fonds',
            child: GraphiqueAnneau(
                etiquettes: const ['Numérisés', 'Prioritaires restants', 'Fonds inactif'],
                valeurs: [_traites, 6200 - _traites, _total - 6200]));
        return w.maxWidth >= 1024
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: barres), const SizedBox(width: 16), Expanded(child: anneau)])
            : Column(children: [barres, const SizedBox(height: 16), anneau]);
      }),
      const SizedBox(height: 12),
      const Text('Source : Rapport de cadrage — environ 18 000 dossiers patients recensés.',
          style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
    ]);
  }
}

/// Les pages-renvoi hors ruban (`m1-dossier-medical`, `m1-dossier-etendu`, `m1-certificats-externes`) : elles se portent comme la maquette — elles
/// RENVOIENT. Retirer l'entrée du manifeste n'est jamais la bonne façon de fermer un écran : elle casserait tout lien qui la vise.
class EcranRenvoiM1 extends StatelessWidget with EcranMaquette {
  const EcranRenvoiM1._(this.titre, this.description, this._note, this._boutons, {this.regleTexte});

  const EcranRenvoiM1.dossierMedical({Key? key})
      : this._('Dossier médical informatisé',
            'Fusionné dans le répertoire des patients — un seul point d’entrée du dossier (Bug 1).',
            'Le dossier médical informatisé est fusionné dans le répertoire des patients : la fiche de chaque patient y agrège consultations, hospitalisations, analyses, ordonnances et documents — et les épisodes de soins se tiennent dans Consultations (M2), leur écran d’origine.',
            const [
              ('Ouvrir le répertoire des patients', 'm1-patients', LucideIcons.users, true),
              ('Consultations', 'm2-consultations', LucideIcons.stethoscope, false)
            ]);

  const EcranRenvoiM1.dossierEtendu({Key? key})
      : this._('Dossier de consultation étendu',
            'Page de renvoi : le dossier de consultation vit désormais dans son propre écran.',
            'Le dossier de consultation a déménagé dans son propre écran — « Soins › Consultations & prescriptions › Dossiers de consultation » (14/09/2026). Le dossier s’y enregistre d’abord (anamnèse, antécédents, examen clinique IPPOA) ; la fiche de consultation en fait ensuite le récapitulatif et porte seule la prescription.',
            const [('Ouvrir les dossiers de consultation', 'm2-dossiers-consultation', LucideIcons.folderHeart, true)]);

  const EcranRenvoiM1.certificatsExternes({Key? key})
      : this._('Certificats — patients externes',
            'Page de renvoi : les pièces des patients externes figurent au registre unique.',
            'Les certificats des patients adressés de l’extérieur ont rejoint le registre unique — « Certificats & attestations », onglet Patients externes (22/09/2026). La délivrance y ouvre au besoin le dossier du patient, et la pièce passe par la caisse comme celle d’un patient de la clinique.',
            const [('Ouvrir le registre des certificats', 'm1-pieces', LucideIcons.stamp, true)]);

  @override
  final String titre;
  @override
  final String description;
  final String _note;
  final List<(String, String, IconData, bool)> _boutons;
  final String? regleTexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 576),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  NoteSigh(_note, icone: LucideIcons.merge),
                  const SizedBox(height: 16),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    for (final b in _boutons)
                      BoutonSigh(
                          libelle: b.$1,
                          icone: b.$3,
                          variante: b.$4 ? VarianteBouton.primaire : VarianteBouton.secondaire,
                          onPressed: () => c.aller(b.$2)),
                  ]),
                ]))));
  }
}
