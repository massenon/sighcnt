import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// Un acte du catalogue tarifaire par son code (`D.tarif(code)`).
Fiche? _tarif(Magasin m, Object? code) {
  for (final r in m.collection('catalogueTarifs').actives) {
    if (r['code'] == code) return r;
  }
  return null;
}

// =============================================================================================================================================
// cfg-types-piece
// =============================================================================================================================================

/// `cfg-types-piece` — « Types de pièces certifiantes » : les quatorze gabarits officiels relevés sur les documents réels, chacun avec son sigle de
/// référence et sa direction émettrice (numérotation « SIGLE n°/n°/CNT/direction/année »). DEUX COLLISIONS DE SIGLES existent dans les sources — CMA
/// (accouchement / aptitude), CMD (décès / genre de mort) : elles sont CONSERVÉES et signalées, renuméroter romprait la correspondance avec les registres
/// papier tenus depuis des années.
class EcranTypesPiece extends StatelessWidget with EcranMaquette {
  const EcranTypesPiece({super.key});
  @override
  String get titre => 'Types de pièces certifiantes';
  @override
  String get description => 'Les quatorze certificats et attestations que la clinique délivre.';
  @override
  String get regle =>
      'Chaque pièce porte son sigle de référence et sa direction émettrice ; toutes s’impriment sous l’en-tête officiel unifié. Les certificats ne sont couverts par aucune assurance à l’exception de SOS — la grille tarifaire le porte en toutes lettres.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('typesPiece');
    final catalogue = c.magasin.collection('catalogueTarifs');
    final pieces = c.magasin.collection('pieces');
    return ListenableBuilder(
        listenable: Listenable.merge([col, catalogue, pieces]),
        builder: (ctx, _) {
          final rows = col.actives;
          final collisions = rows.where((r) => cfaVrai(r['collision'])).length;
          final tarifs = [for (final r in catalogue.actives) if (r['famille'] == 'CERTIFICAT') r];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis(cfaKpisTypesPiece(types: rows.length, tarifes: rows.where((r) => cfaVrai(r['tarifCode'])).length, collisions: collisions, delivrees: pieces.actives.length)),
            if (collisions > 0) ...[
              const SizedBox(height: 16),
              const NoteSigh(
                  'Deux sigles servent chacun à deux pièces dans les documents sources : CMA pour l’accouchement et pour l’aptitude, CMD pour le décès et pour le genre de mort. Les sigles sont conservés tels quels — renuméroter d’office romprait la correspondance avec les registres papier tenus depuis des années. Trancher appartient à la Direction.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.triangleAlert),
            ],
            const SizedBox(height: 16),
            CfaTableau(
              collection: 'typesPiece',
              entite: 'Type de pièce',
              libelleNouveau: 'Nouveau type de pièce',
              titreCreation: 'Type de pièce certifiante',
              prefixeId: 'TPC',
              messageVide: 'Aucun type de pièce enregistré.',
              nomExport: 'types-piece',
              lignes: (a) => trierPar(a, (r) => r['libelle']),
              colonnes: [
                ColonneTableau(
                    cle: 'sigle',
                    libelle: 'Sigle',
                    texte: (r) => '${r['sigle'] ?? ''}${cfaVrai(r['collision']) ? ' collision' : ''}',
                    rendu: (_, r) => Row(mainAxisSize: MainAxisSize.min, children: [
                          cfaCode(r['sigle']),
                          if (cfaVrai(r['collision'])) ...[const SizedBox(width: 8), const BadgeSigh('collision', ton: TonSigh.attention)],
                        ])),
                const ColonneTableau(cle: 'libelle', libelle: 'Pièce'),
                const ColonneTableau(cle: 'direction', libelle: 'Direction'),
                ColonneTableau(
                    cle: 'tarifCode',
                    libelle: 'Tarif',
                    droite: true,
                    texte: (r) {
                      final t = cfaVrai(r['tarifCode']) ? _tarif(c.magasin, r['tarifCode']) : null;
                      return t == null ? '—' : cfaMoney(t['prixNonAssure'], devise: true);
                    }),
              ],
              champs: (e) => [
                const ChampDef(nom: 'sigle', libelle: 'Sigle de référence', requis: true),
                const ChampDef(nom: 'libelle', libelle: 'Intitulé de la pièce', requis: true),
                const ChampDef(nom: 'direction', libelle: 'Direction émettrice', requis: true, aide: 'Le segment du numéro de référence : DG/DE, DA, CN, DM/DA…'),
                ChampDef(nom: 'tarifCode', libelle: 'Acte du catalogue', type: TypeChamp.select, options: [
                  const OptionChamp('', '— non tarifé —'),
                  for (final t in tarifs) OptionChamp('${t['code']}', '${t['libelle']} — ${cfaMoney(t['prixNonAssure'], devise: true)}'),
                ]),
              ],
              detail: (ctx2, r) {
                final t = cfaVrai(r['tarifCode']) ? _tarif(c.magasin, r['tarifCode']) : null;
                final examens = r['examens'] is List ? (r['examens'] as List) : null;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DescListeSigh([
                    ('Sigle', '${r['sigle'] ?? ''}'),
                    ('Pièce', '${r['libelle'] ?? ''}'),
                    ('Direction émettrice', '${r['direction'] ?? ''}'),
                    ('Numérotation', cfaNumerotationPiece(r, c.aujourdhui.year)),
                    ('Tarif', t != null ? cfaMoney(t['prixNonAssure'], devise: true) : 'non tarifé'),
                    ('Couverture', t != null ? (t['assurable'] == 'sos' ? 'SOS seule' : 'aucune') : '—'),
                  ]),
                  if (cfaVrai(r['collision'])) ...[
                    const SizedBox(height: 16),
                    NoteSigh('${r['collision']} Le sigle est conservé tel quel : la correspondance avec les registres papier prime sur la cohérence apparente.',
                        ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
                  ],
                  if (examens != null) ...[
                    const SizedBox(height: 16),
                    NoteSigh(
                        'Cette pièce se remplit depuis les résultats validés biologiquement du patient — ${examens.length} examens : ${examens.map((x) => _tarif(c.magasin, x)?['libelle'] ?? '$x').join(', ')}. Un examen non validé ne peut pas y être coché.',
                        icone: LucideIcons.flaskConical),
                  ],
                ]);
              },
              titreDetail: (r) => '${r['libelle']}',
            ),
          ]);
        });
  }
}

// =============================================================================================================================================
// cfg-certificats
// =============================================================================================================================================

/// `cfg-certificats` — « Certificats médicaux » : génération, numérotation et archivage des certificats délivrés. Un certificat est un acte engageant : en-tête
/// officielle, nom du praticien signataire, numéro unique, archivé au dossier. Le modèle fournit la trame, le praticien la complète et la signe. RG-14 — un
/// certificat délivré s'ANNULE par archivage motivé, il ne s'efface pas.
///
/// Écarts portés fidèlement (consignés E842, E843) : l'année du numéro est écrite « 2026 » en dur ; « délivrés ce mois » ne compare que le numéro du mois.
class EcranCertificats extends StatelessWidget with EcranMaquette {
  const EcranCertificats({super.key});
  @override
  String get titre => 'Certificats médicaux';
  @override
  String get description => 'Génération, numérotation et archivage des certificats délivrés par la clinique.';
  @override
  String get regle =>
      'Un certificat est un acte engageant : il porte l’en-tête officielle, le nom du praticien signataire, un numéro unique et reste archivé au dossier du patient. Le modèle fournit la trame — le praticien la complète et la signe. RG-14 — un certificat délivré s’annule par archivage motivé, il ne s’efface pas.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('certificats');
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final rows = col.actives;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis(cfaKpisCertificats(
                delivres: rows.length,
                types: cfaTypesCertificat.length,
                ceMois: cfaDelivresCeMois(rows, c.aujourdhui),
                praticiens: cfaDistincts(rows, 'praticien').length)),
            const SizedBox(height: 16),
            CarteSigh(titre: 'Types de certificats — cliquer pour rédiger', child: _grille(ctx, c, rows)),
            const SizedBox(height: 16),
            _registre(ctx, c, col, rows),
          ]);
        });
  }

  Widget _grille(BuildContext ctx, ContexteEcran c, List<Fiche> rows) => LayoutBuilder(builder: (_, k) {
        final colonnes = k.maxWidth >= 1024 ? 4 : (k.maxWidth >= 640 ? 2 : 1);
        final l = (k.maxWidth - 12 * (colonnes - 1)) / colonnes - 0.001;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final t in cfaTypesCertificat)
            SizedBox(width: l, child: _carte(ctx, c, t, rows.where((r) => r['type'] == t.id).length)),
        ]);
      });

  /// La carte d'un type : libellé et compte sur deux lignes. Le texte lu par l'infobulle est celui du bouton de la maquette (libellé suivi du compte).
  Widget _carte(BuildContext ctx, ContexteEcran c, CfaTypeCertificat t, int n) {
    final sous = n > 0 ? '${nombre(n)} délivré(s)' : 'Aucun délivré';
    return Tooltip(
      message: '${t.libelle}$sous',
      child: InkWell(
        key: Key('cfa:type:${t.id}'),
        borderRadius: BorderRadius.circular(12),
        // Rédiger délivre un certificat : l'écriture est ABSENTE sans le droit (la carte reste lisible, elle ne s'ouvre pas).
        onTap: c.droit.editer ? () => _rediger(ctx, c, t) : null,
        child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: JetonsShell.slate200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(LucideIcons.fileBadge, size: 16, color: JetonsShell.navy700)),
              const SizedBox(height: 8),
              Text(t.libelle, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
              const SizedBox(height: 4),
              Text(sous, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
            ])),
      ),
    );
  }

  Widget _registre(BuildContext ctx, ContexteEcran c, CollectionMagasin col, List<Fiche> rows) {
    String libelleType(Object? id) => cfaTypeCertificat(id)?.libelle ?? '$id';
    return TableauSigh(
      titre: 'Registre des certificats délivrés',
      lignes: rows,
      triInitial: 'date',
      sensInitial: 'desc',
      taillePage: 15,
      nomExport: 'certificats',
      messageVide: 'Aucun certificat délivré.',
      filtres: [FiltreTableau(nom: 'type', libelle: 'Type', options: [for (final t in cfaTypesCertificat) OptionChamp(t.id, t.libelle)])],
      colonnes: [
        ColonneTableau(cle: 'numero', libelle: 'N°', sansCoupure: true, texte: (r) => '${r['numero'] ?? ''}', rendu: (_, r) => cfaCode(r['numero'])),
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => dateFR(DateTime.parse('${r['date']}'))),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Patient',
            texte: (r) => '${r['patient'] ?? ''} ${r['patientCode'] ?? ''}',
            rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${r['patient'] ?? ''}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate800)),
                  cfaCode(r['patientCode']),
                ])),
        ColonneTableau(cle: 'type', libelle: 'Type', texte: (r) => libelleType(r['type']), rendu: (_, r) => BadgeSigh(libelleType(r['type']), ton: TonSigh.navy)),
        const ColonneTableau(cle: 'praticien', libelle: 'Praticien signataire'),
      ],
      actionsLigne: (ctx2, r) => [
        BoutonIcone(icone: LucideIcons.printer, libelle: 'Rééditer', onPressed: () => _imprimer(ctx2, c, r)),
        if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Annuler le certificat', onPressed: () => _annuler(ctx2, col, r)),
      ],
    );
  }

  Future<void> _annuler(BuildContext ctx, CollectionMagasin col, Fiche r) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Annuler le certificat ${r['numero']} ?',
        message:
            'Le certificat est archivé, non supprimé (RG-14) : il reste au registre et restaurable. Un certificat déjà remis au patient garde sa valeur — l’annulation doit être motivée.',
        libelleOk: 'Annuler le certificat',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = col.archiver(r['id']);
    ToastsSigh.afficher(ctx, 'Certificat annulé.', type: TypeToast.succes, annuler: annuler);
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, Fiche r) {
    final t = cfaTypeCertificat(r['type']);
    final p = c.magasin.collection('patients').parId(r['patientId']);
    cfaImprimer(ctx,
        titre: (t?.libelle ?? 'CERTIFICAT MÉDICAL').toUpperCase(),
        sousTitre: '${r['numero']}',
        cartouche: [
          ('Patient', '${r['patient']}'),
          ('Dossier', '${r['patientCode']}'),
          ('Âge', ageTexte(p, c.aujourdhui)),
          ('Date de délivrance', dateFR(DateTime.parse('${r['date']}'))),
          ('Praticien', '${r['praticien']}'),
          ('N° du certificat', '${r['numero']}'),
        ],
        blocs: [
          BlocTexte('${r['texte'] ?? cfaComposerCertificat(t?.trame ?? '', r)}'),
          const BlocTexte('Certificat établi à la demande de l’intéressé(e) et remis en main propre pour servir et valoir ce que de droit.', italique: true),
        ],
        signatures: [Signature('Le praticien', nom: '${r['praticien']}', mention: 'Signature et cachet')]);
  }

  /// La rédaction : le texte se compose au fil de la saisie ; « Délivrer » numérote, archive au dossier, journalise (RG-12) puis imprime la pièce.
  void _rediger(BuildContext ctx, ContexteEcran c, CfaTypeCertificat t) {
    final patients = trierPar(c.magasin.collection('patients').actives, (p) => p['code']);
    final praticiens = [
      for (final e in c.magasin.collection('personnel').actives)
        if (e['fonction'] == 'medecin' || e['fonction'] == 'sage_femme') '${e['nomComplet']}'
    ];
    final champs = <ChampDef>[
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [for (final p in patients) OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')]),
      ChampDef(nom: 'praticien', libelle: 'Praticien signataire', type: TypeChamp.select, requis: true, options: [for (final p in praticiens) OptionChamp(p)]),
      const ChampDef(nom: 'date', libelle: 'Date de délivrance', type: TypeChamp.date, requis: true),
      for (final k in t.champs) _champ(k),
    ];
    final ctl = ControleurFormulaire(champs, {'date': iso(c.aujourdhui)});

    Map<String, Object?> valeurs() {
      final v = <String, Object?>{for (final ch in champs) ch.nom: ctl[ch.nom]};
      final p = patients.where((x) => x['code'] == v['patientCode']).firstOrNull;
      v['patient'] = p != null ? '${p['nom']} ${p['prenom']}' : '……………';
      return v;
    }

    afficherModale<void>(ctx,
        titre: t.libelle,
        sousTitre: 'Le texte se compose au fil de la saisie',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          const Text('APERÇU DU TEXTE', style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: JetonsShell.slate500)),
          const SizedBox(height: 4),
          ListenableBuilder(
              listenable: ctl,
              builder: (_, __) => Container(
                  key: const Key('cfa:apercu-certificat'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
                  child: Text(cfaComposerCertificat(t.trame, valeurs()), style: const TextStyle(fontSize: 14, height: 1.625, color: JetonsShell.slate700)))),
          const SizedBox(height: 12),
          const NoteSigh('Le certificat sera numéroté, archivé au dossier du patient et journalisé (RG-12). Il porte l’en-tête officielle et la signature du praticien.'),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Délivrer le certificat',
                  icone: LucideIcons.fileBadge,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final col = c.magasin.collection('certificats');
                    final p = patients.where((x) => x['code'] == v['patientCode']).firstOrNull;
                    final fiche = <String, Object?>{
                      for (final e in v.entries) e.key: cfaChampsCertificat[e.key]?.type == 'nombre' ? cfaNombre(e.value) : e.value,
                    };
                    fiche['type'] = t.id;
                    fiche['numero'] = cfaNumeroCertificat(col.toutes.length);
                    fiche['patientId'] = p?['id'];
                    fiche['patient'] = p != null ? '${p['nom']} ${p['prenom']}' : '—';
                    fiche['texte'] = cfaComposerCertificat(t.trame, fiche);
                    final r = col.inserer({'statut': 'actif', ...fiche, '_creePar': c.utilisateur, '_creeLe': c.aujourdhui.toIso8601String()}, prefixe: 'CERT');
                    c.magasin.journaliser('Délivrance de certificat', 'CFG', t.libelle, '${fiche['numero']}', null, {'patient': fiche['patient']});
                    fermer();
                    ToastsSigh.afficher(ctx, 'Certificat ${fiche['numero']} délivré.',
                        type: TypeToast.succes, detail: '${t.libelle} — ${fiche['patient']}', annuler: r.annuler);
                    _imprimer(ctx, c, r.fiche);
                  }),
            ]);
  }

  static ChampDef _champ(String k) {
    final d = cfaChampsCertificat[k]!;
    return ChampDef(
        nom: k,
        libelle: d.libelle,
        requis: true,
        type: switch (d.type) {
          'nombre' => TypeChamp.nombre,
          'date' => TypeChamp.date,
          'select' => TypeChamp.select,
          'zone' => TypeChamp.textarea,
          _ => TypeChamp.texte,
        },
        options: [for (final o in d.options) OptionChamp(o)],
        lignes: d.lignes ?? 3,
        col: d.plein ? ColChamp.plein : ColChamp.demi);
  }
}
