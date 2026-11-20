import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/fichiers_poste.dart';
import '../../donnees/magasin.dart';
import '../../donnees/ocr_poste.dart';
import '../../impression/piece.dart';
import '../../import/selecteurs_import.dart' show FichierChoisi;
import '../../kit/fichiers_ui.dart';
import '../../kit/kit.dart';
import '../../kit/ocr_ui.dart';
import '../../shell/contexte_ecran.dart';
import '../m5/res_commun.dart' show profilLabo;
import 'commun_m1.dart';

String _t(Object? v, [String vide = '—']) => patVrai(v) ? '$v' : vide;

/// `m1-documents` : la bibliothèque documentaire du patient. Un document se DÉPOSE (PDF, PNG, JPEG ; WEBP admis ici) et reste rattaché au dossier ; le fichier est rangé sur le disque du poste,
/// hors du magasin, sous son empreinte SHA-256 (lot D5 : sélecteur de fichier injectable, visionneuse, téléchargement sous le nom normalisé, zones RG-13). RG-14 : retirer un document l'archive,
/// avec son motif ; retirer sa pièce la garde au journal.
///
/// LOT 8 : l'onglet « Pièces produites par le logiciel » (vue unifiée de renvois, élargie aux comptes rendus de maternité et aux fiches de consultation) est porté ; son vecteur est
/// `pieces_produites.json`. NON PORTÉ : le vecteur `m1.json` de la maquette DOCS-1 (non régénéré : la parité N1 de cet écran reste celle de la version d'avant).
class EcranDocuments extends StatelessWidget with EcranMaquette {
  const EcranDocuments({super.key});

  @override
  String get titre => 'Documents numérisés du patient';

  @override
  String get description =>
      'Ordonnances, résultats d’analyses, comptes rendus, consentements et imagerie rattachés au dossier patient.';

  @override
  String get regle =>
      'Un document se dépose depuis cet écran (PDF, PNG ou JPEG ; WEBP admis ici) et reste rattaché au dossier du patient. Le fichier est rangé hors du magasin, sous son empreinte SHA-256 : la fiche en garde le nom, la taille et l’empreinte. '
      'Zones (RG-13) : l’accueil dépose la pièce d’identité et la carte d’assurance, les pièces médicales ne se lisent que par les profils cliniques. '
      'RG-14 : retirer un document l’archive, retirer sa pièce la garde au journal ; tout reste restaurable.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      // Lot D5 : le réglage de la taille maximale d'un fichier, ABSENT sans le droit de régler (administrateur et Directrice Administrative).
      if (boutonTailleFichiers(context, role: c.role) case final b?) b,
      if (boutonOcr(context, role: c.role) case final b?) b,
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
            options: [for (final t in patTypesDocument) if (docPeutVoir(t, c.role).autorise) OptionChamp(t)]),
        const ChampDef(nom: 'date', libelle: 'Date du document', type: TypeChamp.date, requis: true),
        const ChampDef(
            nom: 'etat',
            libelle: 'Statut',
            type: TypeChamp.select,
            requis: true,
            options: [OptionChamp('en_attente', 'En attente de validation'), OptionChamp('valide', 'Validé')]),
        const ChampDef(nom: 'depose', libelle: 'Déposé par', requis: true),
      ];

  /// « Ajouter un document au dossier » : le fichier est choisi par le SÉLECTEUR injectable, contrôlé et rangé D'ABORD ; la fiche n'est créée que s'il l'est (un refus nommé ne laisse aucune
  /// fiche vide). Un fichier déjà rattaché à ce dossier est refusé en nommant la pièce ; déjà rattaché ailleurs, l'agent confirme.
  static void _deposer(BuildContext ctx, ContexteEcran c) {
    final fp = FichiersPoste.de(c.magasin);
    final defs = champs(c, null);
    final ctl = ControleurFormulaire(defs, {'date': iso(c.aujourdhui), 'etat': 'en_attente', 'depose': acteur(c).nom});
    FichierChoisi? choix;
    final refus = ValueNotifier<RefusFichier?>(null);
    afficherModale<void>(ctx,
        titre: 'Ajouter un document au dossier',
        taille: TailleModale.lg,
        corps: StatefulBuilder(
            builder: (cx, maj) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormulaireSigh(controleur: ctl),
                  const SizedBox(height: 12),
                  Text('Fichier numérisé * : ${[for (final f in fichierFormats) if (f.familles.contains('patient')) f.libelle].join(', ')}', style: styleM1(t: 12, c: JetonsShell.slate600)),
                  const SizedBox(height: 6),
                  Row(children: [
                    BoutonSigh(
                        key: const Key('doc:choisir'),
                        libelle: 'Choisir un fichier',
                        icone: LucideIcons.upload,
                        variante: VarianteBouton.secondaire,
                        onPressed: () async {
                          final f = await SelecteursFichiers.choisir();
                          if (f == null) return;
                          final v = fichierControler(nom: f.nom, mime: '', taille: f.octets.length, famille: 'patient', tailleMax: fp?.tailleMax() ?? fichierTailleDefaut);
                          maj(() => choix = v.refus == null ? f : null);
                          refus.value = v.refus;
                        }),
                    const SizedBox(width: 12),
                    if (choix != null) Expanded(child: Text('Fichier choisi : ${choix!.nom} (${fichierPoids(choix!.octets.length)})', key: const Key('doc:choisi'), style: styleM1(t: 12, c: JetonsShell.slate600))),
                  ]),
                  ValueListenableBuilder<RefusFichier?>(valueListenable: refus, builder: (_, r, __) => r == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 8), child: noteRefus(r))),
                  const SizedBox(height: 12),
                  const NoteSigh(
                      'Le fichier est rangé sur le disque de ce poste, hors du magasin, sous son empreinte SHA-256 (chiffré au repos). Un fichier déjà rattaché à ce dossier est refusé en nommant la pièce.'),
                ])),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('doc:rattacher'),
                  libelle: 'Rattacher au dossier',
                  icone: LucideIcons.upload,
                  onPressed: () async {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    if (choix == null) {
                      ToastsSigh.afficher(ctx, 'Choisir un fichier à déposer.', type: TypeToast.attention);
                      return;
                    }
                    if (fp == null) {
                      refus.value = const RefusFichier('FICHIERS_NON_ACTIVES', 'le stockage des fichiers numérisés n’est pas disponible sur ce poste', 'Redémarrer le poste.');
                      return;
                    }
                    final p = c.magasin.collection('patients').parId(v['patientId']);
                    final col = c.magasin.collection('documentsPatient');
                    final r = await fp.creerDocumentPatient(
                        fiche: {
                          ...v,
                          'reference': patReferenceDocument(col.toutes.length),
                          'code': p?['code'],
                          'patient': p != null ? '${p['nom']} ${p['prenom']}' : 'dossier introuvable',
                        },
                        nom: choix!.nom,
                        octets: choix!.octets,
                        role: c.role,
                        droit: c.droit,
                        confirmerAutre: (autre) => confirmerSigh(ctx,
                            titre: 'Ce fichier est déjà rattaché ailleurs',
                            message: 'Le même fichier est déjà la pièce ${fichierNomPiece(autre)}. Le rattacher aussi à ce dossier ?',
                            libelleOk: 'Rattacher quand même'));
                    if (!r.ok) {
                      refus.value = r.refus;
                      return;
                    }
                    fermer();
                    if (ctx.mounted) {
                      ToastsSigh.afficher(ctx, 'Document rattaché au dossier ${p?['code']}.',
                          type: TypeToast.succes, detail: '${v['type']} : ${r.fichier?['nomNormalise']}', annuler: r.annuler, messageAnnulation: 'Création annulée : la fiche est archivée.');
                    }
                  }),
            ]);
  }

  /// « Prévisualiser » : le fichier déposé s'ouvre (image dans la visionneuse, PDF dans le lecteur) ; une fiche référencée sans fichier le dit.
  static Future<void> _previsualiser(BuildContext ctx, Fiche r) async {
    final c = ContexteEcran.of(ctx);
    if (fichierDe(r) != null) {
      final refus = await ouvrirApercuPiece(ctx, famille: 'patient', fiche: r, titre: '${r['type']}', role: c.role, droit: c.droit, sousTitre: '${r['reference']} : ${r['patient']} (${r['code']})');
      if (refus != null && ctx.mounted) ToastsSigh.afficher(ctx, 'Aperçu refusé : ${refus.code}', type: TypeToast.erreur, detail: '${refus.motif} ${refus.geste}');
      return;
    }
    afficherModale<void>(ctx,
        titre: '${r['type']}',
        sousTitre: '${r['reference']} : ${r['patient']} (${r['code']})',
        taille: TailleModale.lg,
        corps: Container(
            height: 256,
            decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate300)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(LucideIcons.fileText, size: 40, color: JetonsShell.slate300),
              const SizedBox(height: 8),
              Text('Document référencé au dossier, fichier non encore déposé', style: styleM1(c: JetonsShell.slate500)),
              Text('Ouvrir la fiche pour y déposer le scan (enregistré le ${dateFrM1(r['date'])}).', style: styleM1(t: 12, c: JetonsShell.slate400)),
            ])),
        pied: (fermer) => [BoutonSigh(libelle: 'Imprimer la fiche', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _imprimerFiche(ctx, r))]);
  }

  static void _imprimerFiche(BuildContext ctx, Fiche r) {
    final x = fichierDe(r);
    imprimerM1(ctx,
        titre: '${r['type']}',
        sousTitre: '${r['reference']}',
        cartouche: [
          ('Patient', '${r['patient']}'),
          ('Dossier', '${r['code']}'),
          ('Date', dateFrM1(r['date'])),
          ('Nom du fichier', x != null ? docNomNormalise('patient', r, fichierExtDeMime('${x['mime']}')) : 'Aucun fichier rattaché'),
          ('Empreinte SHA-256', x != null ? docAbrege(x['sha256']) : 'Sans objet'),
          ('Taille', x != null ? fichierPoids(x['taille'] as num?) : 'Sans objet'),
          ('Déposé par', _t(r['depose'])),
        ],
        blocs: const [BlocTexte('Fiche du document numérisé rattaché au dossier patient. Le fichier d’origine se lit depuis le logiciel (aperçu) ; son empreinte permet de vérifier qu’une copie est identique.')]);
  }

  /// La fiche d'un document (tiroir) : le détail, la carte de la pièce numérisée (dépôt, aperçu, chemin), l'impression.
  static Widget _fiche(BuildContext ctx, Fiche r) {
    final c = ContexteEcran.of(ctx);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DescListeSigh([
        ('Référence', enMono('${r['reference']}')),
        ('Dossier', '${r['code'] ?? ''} : ${r['patient']}'),
        ('Type', '${r['type']}'),
        ('Date du document', dateFrM1(r['date'])),
        ('Statut', statutBadge(r['etat'])),
        ('Déposé par', '${r['depose'] ?? ''}'),
      ]),
      const SizedBox(height: 16),
      CartePieceNumerisee(
          famille: 'patient',
          ficheId: r['id']!,
          titre: '${r['type']}',
          role: c.role,
          droit: c.droit,
          portee: (f) => f['patientId'] == r['patientId'] && f['id'] != r['id']),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: BoutonSigh(libelle: 'Imprimer la fiche', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _imprimerFiche(ctx, r))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('documentsPatient');
    final fp = FichiersPoste.de(c.magasin);
    return ListenableBuilder(
        listenable: Listenable.merge([col, c.magasin.collection('fichiers'), c.magasin.collection(ocrLectures), c.magasin.collection(ocrFile)]),
        builder: (context, _) {
          // ZONES (RG-13) : les pièces que le profil ne lit pas ne sont ni montrées, ni comptées ; l'écran le DIT (une restriction muette ferait croire à une donnée manquante).
          final toutes = col.actives;
          final rows = [for (final r in toutes) if (docPeutVoir('${r['type']}', c.role).autorise) r];
          final cachees = toutes.length - rows.length;
          final k = patKpisDocuments(rows);
          final scans = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            if (cachees > 0)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: NoteSigh(
                      'Votre profil ne voit que les pièces administratives (pièce d’identité, carte d’assurance) : $cachees pièce${cachees > 1 ? 's médicales ne sont' : ' médicale n’est'} pas affichée${cachees > 1 ? 's' : ''} (RG-13). Les profils cliniques les lisent.',
                      icone: LucideIcons.lock)),
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
                  lignes: (cc, actives) => rows,
                  rechercheExtra: (r) => fp != null
                      ? fp.texteRecherche(r, famille: 'patient')
                      : fichierTexteRecherche(r, dateFr: dateFrM1(r['date']), texteIndexe: ''),
                  indiceRecherche: (_) => fp?.indiceNonIndexe(rows),
                  // Lot OCR-prep : un résultat trouvé par un texte lu par machine le DIT (la reconnaissance peut se tromper).
                  noteRecherche: (q, lignes) => OcrPoste.de(c.magasin)?.noteRecherche(q, lignes, famille: 'patient', role: c.role),
                  detail: _fiche,
                  titreDetail: (f) => '${f['type']}',
                  sousTitreDetail: (f) => '${f['reference']} : ${f['code'] ?? ''}',
                  champs: champs,
                  // Le dossier peut changer à l'édition : `code` et `patient` (posés à la création) suivent `patientId`, sinon les colonnes gardent l'ancien patient.
                  transformer: (cc, saisie, existante) {
                    if (existante == null) return saisie;
                    final p = cc.magasin.collection('patients').parId(saisie['patientId']);
                    return {
                      ...saisie,
                      'code': p?['code'],
                      'patient': p != null ? '${p['nom']} ${p['prenom']}' : '—',
                    };
                  },
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
                        options: const [OptionChamp('oui', 'Fichier déposé'), OptionChamp('non', 'Référencé seulement'), OptionChamp('sansTexte', 'Texte non indexé'), OptionChamp('lu', 'Texte lu par machine')],
                        correspond: (r, v) {
                          final x = fichierDe(r);
                          if (v == 'oui') return x != null;
                          if (v == 'non') return x == null;
                          if (v == 'lu') return x != null && etatTexte(c.magasin, x).etat == EtatIndexation.ocrIndexe;
                          return x != null && !etatTexte(c.magasin, x).disponible;
                        }),
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
                        texte: (r) {
                          final x = fichierDe(r);
                          if (x != null) return '${'${x['mime']}'.replaceAll('application/', '').replaceAll('image/', '').toUpperCase()} ${fichierPoids(x['taille'] as num?)}';
                          return patVrai(r['donnees']) ? '${r['format'] ?? ''} ${patPoidsDoc(r['taille'])}' : 'référencé';
                        },
                        rendu: (_, r) {
                          final x = fichierDe(r);
                          if (x == null) {
                            // Une fiche d'AVANT les fichiers porte encore son scan en base64 dans le magasin (`donnees`) : elle le dit, « migration en attente ». Sinon : référencée, fichier non déposé.
                            final ancien = patVrai(r['donnees']);
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(ancien ? '${r['format'] ?? ''} · ${patPoidsDoc(r['taille'])}' : 'référencé', style: styleM1(t: 12, c: JetonsShell.slate600)),
                              Text(ancien ? 'dans le magasin, migration en attente' : 'fichier non déposé', style: const TextStyle(color: JetonsShell.slate400, fontSize: 11, height: 15 / 11)),
                            ]);
                          }
                          final pages = x['pages'];
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text('${'${x['mime']}'.replaceAll('application/', '').replaceAll('image/', '').toUpperCase()} · ${fichierPoids(x['taille'] as num?)}${pages != null ? ' · $pages p.' : ''}',
                                style: styleM1(t: 12, c: JetonsShell.slate600)),
                            Text('déposé, ${motTexte(c.magasin, x)}',
                                key: Key('ocr:ligne-${etatTexte(c.magasin, x).code}'),
                                style: TextStyle(color: etatTexte(c.magasin, x).etat == EtatIndexation.ocrIndexe ? JetonsShell.warning700 : JetonsShell.success600, fontSize: 11, height: 15 / 11)),
                          ]);
                        }),
                    const ColonneTableau(cle: 'depose', libelle: 'Déposé par'),
                    ColonneTableau(cle: 'etat', libelle: 'Statut', texte: (r) => statutsMetier['${r['etat']}']?.$1 ?? '${r['etat']}', rendu: (_, r) => statutBadge(r['etat'])),
                  ],
                )),
          ]);
          // Lot 8 : la vue unifiée du dossier (des renvois, jamais des copies) est le second onglet, comme à la maquette.
          return OngletsSigh(onglets: [
            OngletDef(id: 'scans', libelle: 'Documents numérisés', compte: rows.length, construire: (_) => scans),
            OngletDef(id: 'produites', libelle: 'Pièces produites par le logiciel', construire: (_) => _VuePieces(c)),
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

/// LOT 8, « Pièces produites par le logiciel » : la vue unifiée du dossier. Des RENVOIS vers les pièces que le logiciel produit (ordonnances, résultats d'analyses rendus, comptes rendus
/// opératoires, d'imagerie et de maternité, fiches de consultation), JAMAIS des copies : la liste est relue à chaque affichage. La zone médicale (RG-13) ferme la vue ENTIÈRE à qui ne la lit
/// pas : ni choix de dossier, ni tableau, ni un seul renvoi. Le bouton « Ouvrir » n'existe que si le profil ouvre l'écran de la pièce. Ouvrir la vue d'un dossier se journalise (RG-12).
class _VuePieces extends StatefulWidget {
  const _VuePieces(this.c);
  final ContexteEcran c;
  @override
  State<_VuePieces> createState() => _VuePiecesEtat();
}

class _VuePiecesEtat extends State<_VuePieces> {
  late final ControleurFormulaire _choix;
  String? _journalise;

  @override
  void initState() {
    super.initState();
    final c = widget.c;
    _choix = ControleurFormulaire([
      ChampDef(
          nom: 'patientId',
          libelle: 'Dossier patient',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: [
            for (final p in trierPar(c.magasin.collection('patients').actives, (p) => p['code'])) OptionChamp('${p['id']}', '${p['code']} : ${p['nom']} ${p['prenom']}')
          ]),
    ], {});
  }

  @override
  void dispose() {
    _choix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    if (!docPeutVoir('Compte rendu médical', c.role).autorise) {
      return const Column(key: Key('pieces:zone-refusee'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        NoteSigh(
            'Les pièces produites par le logiciel (ordonnances, résultats, comptes rendus, imagerie) sont des pièces médicales : votre profil ne les lit pas (RG-13). Elles se lisent depuis le dossier par les profils cliniques.',
            ton: TonSigh.attention,
            icone: LucideIcons.lock),
      ]);
    }
    const noms = ['ordonnances', 'demandesAnalyses', 'crOperatoires', 'resultatsImagerie', 'crMaternite', 'dossiersConsultation'];
    return ListenableBuilder(
        listenable: Listenable.merge([_choix, for (final n in noms) c.magasin.collection(n)]),
        builder: (context, _) {
          final id = '${_choix['patientId'] ?? ''}';
          final p = id.isEmpty ? null : c.magasin.collection('patients').parId(id);
          final profil = profilLabo(c);
          final pieces = id.isEmpty
              ? <PatPieceProduite>[]
              : patPiecesProduites(
                  patientId: id,
                  collections: {for (final n in noms) n: c.magasin.collection(n).actives},
                  peutVoirResultat: (d) => peutVoirResultat(d, profil.session).autorise,
                  renvoi: (e) => c.donnees?.matrice.peutVoir(c.role, e) == true ? e : null);
          if (p != null && _journalise != id) {
            _journalise = id;
            WidgetsBinding.instance.addPostFrameCallback((_) => c.magasin.journaliser('Consultation du dossier documentaire du patient', 'M1', 'document', '${p['code'] ?? id}', null, {'ecran': 'm1-documents'}));
          }
          return Column(key: const Key('pieces:vue'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormulaireSigh(controleur: _choix),
            const SizedBox(height: 12),
            if (p != null)
              TableauSigh(
                  titre: 'Pièces produites par le logiciel (${pieces.length})',
                  lignes: [for (final x in pieces) {'famille': x.famille, 'reference': x.reference, 'date': x.date, 'resume': x.resume, 'ecran': x.ecran}],
                  taillePage: 10,
                  messageVide: 'Aucune pièce produite pour ce dossier.',
                  colonnes: [
                    ColonneTableau(cle: 'famille', libelle: 'Pièce', texte: (r) => '${r['famille']}', rendu: (_, r) => BadgeSigh('${r['famille']}', ton: TonSigh.neutre)),
                    ColonneTableau(cle: 'reference', libelle: 'Référence', sansCoupure: true, texte: (r) => '${r['reference']}', rendu: (_, r) => enMono('${r['reference']}')),
                    ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => dateFrM1(r['date'])),
                    const ColonneTableau(cle: 'resume', libelle: 'Objet'),
                  ],
                  actionsLigne: (ctx, r) => [
                        if (r['ecran'] != null)
                          BoutonSigh(
                              key: Key('pieces:ouvrir-${r['reference']}'),
                              libelle: 'Ouvrir',
                              icone: LucideIcons.externalLink,
                              taille: TailleBouton.sm,
                              variante: VarianteBouton.secondaire,
                              onPressed: () => c.aller('${r['ecran']}')),
                      ]),
            const SizedBox(height: 12),
            const NoteSigh('Les pièces produites par le logiciel ne sont jamais copiées ici : ce sont des renvois vers l’écran qui les tient, relus à chaque affichage.', icone: LucideIcons.info),
          ]);
        });
  }
}
