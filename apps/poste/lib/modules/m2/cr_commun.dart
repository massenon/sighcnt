import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Ce que partagent les cinq tableaux d'imagerie et la page de compte rendu : lecture du magasin, tiroir « Consulter », pièce imprimée,
/// « Rendre au prescripteur ». Les règles (lignes lisibles, rubriques, indicateurs) sont dans `packages/domaine/lib/src/imagerie/`.

CollectionMagasin colCR(Magasin m) => m.collection('resultatsImagerie');
CollectionMagasin colDemandesImagerie(Magasin m) =>
    m.collection('demandesImagerie');

/// Le catalogue des examens (`imExamens`) : la modalité d'un examen se lit ICI, jamais sur le compte rendu.
List<Fiche> examensImagerie(Magasin m) =>
    m.collection('examensImagerie').actives;

/// Les variables d'un examen, lues AU MAGASIN (`imVariablesDe`) : la mécanique n'en connaît aucune.
List<Fiche> variablesDe(Magasin m, Object? codeExamen) =>
    variablesDeExamen(m.collection('variablesImagerie').actives, '$codeExamen');

List<RubriqueLibre> libresDe(Magasin m, Object? codeExamen) =>
    rubriquesLibresDe(examensImagerie(m), codeExamen);

String modaliteDe(Magasin m, Object? codeExamen) =>
    modaliteDeCodeExamen(examensImagerie(m), codeExamen);

/// `nomSoignant2(id)`.
String nomSoignant(Magasin m, Object? id) {
  final s =
      m.collection('soignants').actives.where((x) => x['id'] == id).firstOrNull;
  return s == null ? '—' : '${s['nomComplet']}';
}

/// `C.dateHeure(r.date)` : l'heure LOCALE du poste.
String dateHeureDe(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateHeure(d.toLocal());
}

TonSigh tonDe(String t) => switch (t) {
      'navy' => TonSigh.navy,
      'success' => TonSigh.succes,
      'warning' => TonSigh.attention,
      'danger' => TonSigh.danger,
      'info' => TonSigh.info,
      _ => TonSigh.neutre,
    };

IconData iconeDe(String nom) => switch (nom) {
      'scan-line' => LucideIcons.scanLine,
      'bone' => LucideIcons.bone,
      'ribbon' => LucideIcons.ribbon,
      'radiation' => LucideIcons.radiation,
      'magnet' => LucideIcons.magnet,
      'send' => LucideIcons.send,
      'pencil' => LucideIcons.pencil,
      'baby' => LucideIcons.baby,
      'alert-triangle' => LucideIcons.triangleAlert,
      'syringe' => LucideIcons.syringe,
      'droplets' => LucideIcons.droplets,
      'wallet' => LucideIcons.wallet,
      _ => LucideIcons.scanLine,
    };

/// L'adresse de la page de compte rendu : la maquette passe `{id | nouveau, modalite, retour}` dans l'ancre et l'en-tête dans `sessionStorage` ;
/// le poste les dépose ici avant `aller('m2-imagerie-cr')`, la page les consomme UNE fois à son ouverture (on ne rouvre pas deux saisies dessus).
class AdresseCompteRendu {
  const AdresseCompteRendu(
      {this.id, this.nouveau = false, this.modalite, this.retour, this.entete});
  final String? id;
  final bool nouveau;
  final String? modalite;
  final String? retour;

  /// L'en-tête relevé par la modale : il ne crée RIEN, la fiche naît à l'enregistrement.
  final Map<String, Object?>? entete;

  static AdresseCompteRendu? enAttente;
  static AdresseCompteRendu consommer() {
    final a = enAttente ?? const AdresseCompteRendu();
    enAttente = null;
    return a;
  }
}

/// `saisirCR(rec)` : la saisie a quitté les modales pour la page — détourné EN UN POINT.
void saisirCR(ContexteEcran c, Fiche r, {String? retour}) {
  AdresseCompteRendu.enAttente =
      AdresseCompteRendu(id: '${r['id']}', retour: retour);
  c.aller('m2-imagerie-cr');
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le tiroir « Consulter »
// ---------------------------------------------------------------------------------------------------------------------------------------------

Widget detailCR(Magasin m, Fiche r) {
  final vars = variablesDe(m, r['examenCode']);
  final libres = libresDe(m, r['examenCode']);
  final lignes = <Fiche>[
    for (final g in groupesCR(r, vars))
      for (final l in g.lignes)
        {
          'rubrique': g.titre,
          'variable': '${l.variable['libelle']}',
          'valeur': l.lu
        }
  ];
  final anciennes = annexesAnterieures(r, libres);
  Widget texte(String t, {bool fort = false}) => Padding(
      padding: const EdgeInsets.all(20),
      child: Text(t,
          style: TextStyle(
              color: fort ? JetonsShell.slate800 : JetonsShell.slate600,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: fort ? FontWeight.w500 : FontWeight.w400)));
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DescListeSigh([for (final p in pairesDetailCR(r)) (p.$1, p.$2)]),
    const SizedBox(height: 16),
    SectionSigh(
        titre: 'Résultats',
        child: MiniTableauSigh(colonnes: [
          ColonneMini('Rubrique', (l) => '${l['rubrique']}'),
          ColonneMini('Variable', (l) => '${l['variable']}'),
          ColonneMini('Valeur', (l) => '${l['valeur']}'),
        ], lignes: lignes)),
    for (final lib in libres)
      if (r[lib.code] != null && r[lib.code] != '') ...[
        const SizedBox(height: 16),
        SectionSigh(
            titre: lib.label,
            child: texte('${r[lib.code]}', fort: lib.code == 'conclusion')),
      ],
    if (anciennes != null) ...[
      const SizedBox(height: 16),
      SectionSigh(
          titre: 'Annexes (saisie antérieure au 14/09/2026)',
          child: texte(anciennes)),
    ],
  ]);
}

void consulterCR(BuildContext ctx, Fiche r) {
  final c = ContexteEcran.of(ctx);
  afficherTiroir<void>(ctx,
      titre: '${r['reference']} — ${r['examen']}',
      sousTitre: '',
      largeurMax: 672,
      corps: detailCR(c.magasin, r));
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La pièce imprimée
// ---------------------------------------------------------------------------------------------------------------------------------------------

PieceA4 pieceCR(Magasin m, Fiche r,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final vars = variablesDe(m, r['examenCode']);
  final libres = libresDe(m, r['examenCode']);
  final mod = modaliteDe(m, r['examenCode']);
  return PieceA4(
    titre: '${r['examen'] ?? ''}'.toUpperCase(),
    sousTitre: '${r['reference']} — ${r['patient']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: cartoucheCR(r, mod),
    blocs: [
      for (final l in contenuImpressionCR(r, vars, libres))
        BlocTexte(l.texte, gras: l.gras),
    ],
    signatures: [Signature('Réalisé par', nom: '${r['realisateur'] ?? ''}')],
  );
}

Future<void> imprimerCR(BuildContext ctx, Fiche r) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(
      ctx,
      pieceCR(c.magasin, r,
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          reference: PieceA4.reference_(
              c.aujourdhui, ImpressionPoste.prochainNumero())));
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// « Rendre au prescripteur »
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `rendreCR(r, apres)` : la conclusion est obligatoire ; la confirmation nomme la pièce et le prescripteur ; le compte rendu passe « rendu », la
/// demande « validée », et le poste de consultation est AVISÉ (une notification de poste, pas un message à écrire à la main).
Future<void> rendreCR(BuildContext ctx, Fiche r) async {
  final refus = refusRendreCR(r);
  if (refus != null) {
    ToastsSigh.afficher(ctx, refus, type: TypeToast.erreur);
    return;
  }
  final ok = await confirmerSigh(ctx,
      titre: 'Rendre le compte rendu au prescripteur ?',
      message: messageRendreCR(r),
      libelleOk: 'Rendre');
  if (!ok || !ctx.mounted) return;
  final c = ContexteEcran.of(ctx);
  final m = c.magasin;
  final maintenant = c.aujourdhui.toUtc().toIso8601String();
  colCR(m).mettreAJour(r['id'], {'statut': 'rendu', 'renduLe': maintenant});
  final dem = r['demandeImagerieId'];
  if (dem != null && dem != '') {
    colDemandesImagerie(m)
        .mettreAJour(dem, {'statut': 'validee', 'valideLe': maintenant});
  }
  m.collection('notifications').inserer({
    ...notificationRenduCR(r, maintenant),
    'statut': 'actif',
  }, prefixe: 'NOT');
  ToastsSigh.afficher(ctx, 'Compte rendu rendu au prescripteur.',
      type: TypeToast.succes, detail: '${r['reference']}');
}

/// `K.actionsLigne` — « Archiver » : le motif est demandé et gardé (E47) ; l'archivage est ANNULABLE (RG-14).
Future<void> archiverCR(BuildContext ctx, Fiche r) async {
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Archiver cet enregistrement ?',
      message:
          'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
      libelleOk: 'Archiver',
      dangereux: true);
  if (motif == null || !ctx.mounted) return;
  final col = colCR(ContexteEcran.of(ctx).magasin);
  col.mettreAJour(r['id'], {'_motifArchivage': motif});
  final annuler = col.archiver(r['id']);
  ToastsSigh.afficher(ctx, 'Enregistrement archivé.',
      type: TypeToast.succes,
      annuler: annuler,
      messageAnnulation: 'Archivage annulé.');
}
