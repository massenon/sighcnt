import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';
import '../donnees/ocr_poste.dart';
import '../shell/contexte_ecran.dart';
import 'badge.dart';
import 'bouton.dart';
import 'carte.dart';
import 'modale.dart';
import 'toast.dart';
import 'ton.dart';

/// LES COMPOSANTS DE LA LECTURE OCR (lot OCR-prep) : l'état d'indexation d'une pièce (badge), le bloc de la carte « Pièce numérisée » (état en toutes lettres, marquage « lu par machine, à
/// vérifier », commande « Relancer la lecture » ABSENTE sans le droit et sans moteur prêt, historique des lectures), le petit mot des lignes de registre, et le réglage réservé à
/// l'administrateur et à la DAF. Toutes les règles sont celles du domaine ; ces composants ne décident rien, ils montrent et enchaînent. AUCUN moteur n'est livré : sans moteur, l'état dit
/// « aucun moteur d'OCR installé sur ce poste ».

TonSigh tonEtatOcr(EtatIndexation e) => switch (e) {
      EtatIndexation.indexe => TonSigh.succes,
      EtatIndexation.ocrIndexe => TonSigh.attention,
      EtatIndexation.ocrEnAttente || EtatIndexation.ocrEnCours => TonSigh.info,
      EtatIndexation.ocrEchec => TonSigh.danger,
      EtatIndexation.nonIndexe => TonSigh.neutre,
    };

String _majuscule(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// L'état d'indexation d'une pièce, sans le service de lecture : la couche texte ou rien (un poste sans service ne prétend rien de plus).
EtatIndexationOcr etatTexteSansService(Map<String, Object?> x) =>
    ocrEtatIndexation(
        natif: x['texteIndexe'] == true,
        versions: const [],
        moteurInstalle: false,
        actif: false,
        moteurActif: false);

/// L'état d'indexation de l'objet `fichier` d'une fiche (avec le service de lecture quand il existe).
EtatIndexationOcr etatTexte(Magasin m, Map<String, Object?> x) =>
    OcrPoste.de(m)?.etatDe(x) ?? etatTexteSansService(x);

/// Le petit mot d'une ligne de registre : « texte indexé », « texte lu par machine, à vérifier », « lecture OCR en attente », « texte non indexé »...
String motTexte(Magasin m, Map<String, Object?> x) => etatTexte(m, x).court;

/// Le badge d'état de la carte (clé `ocr:etat-<code>`).
Widget badgeEtatTexte(EtatIndexationOcr e) => BadgeSigh(_majuscule(e.court),
    key: Key('ocr:etat-${e.code}'), ton: tonEtatOcr(e.etat));

/// Le bloc de la carte « Pièce numérisée » sous les lignes : l'état en toutes lettres, le marquage, la relance, l'historique des lectures.
class BlocOcrPiece extends StatefulWidget {
  const BlocOcrPiece(
      {super.key,
      required this.famille,
      required this.fichier,
      required this.type,
      required this.peutDeposer});
  final String famille;
  final Map<String, Object?> fichier;
  final String? type;

  /// Le droit d'ÉCRIRE sur l'écran de la pièce (et la zone du document) : la relance n'existe que pour qui peut déposer.
  final bool peutDeposer;

  @override
  State<BlocOcrPiece> createState() => _BlocOcrPieceState();
}

class _BlocOcrPieceState extends State<BlocOcrPiece> {
  RefusFichier? _refus;

  @override
  Widget build(BuildContext context) {
    final m = ContexteEcran.of(context).magasin;
    final o = OcrPoste.de(m);
    if (o == null) return const SizedBox.shrink();
    return ListenableBuilder(
        listenable: Listenable.merge(
            [o, m.collection(ocrLectures), m.collection(ocrFile)]),
        builder: (context, _) {
          final x = widget.fichier;
          final e = o.etatDe(x);
          if (e.etat == EtatIndexation.indexe) return const SizedBox.shrink();
          final sha = '${x['sha256']}';
          final versions = o.versionsDe(sha);
          final courante = o.versionCourante(sha);
          final file =
              m.collection(ocrFile).parId('OCQ-${sha.substring(0, 16)}');
          final enfants = <Widget>[
            Text('${e.libelle}.',
                key: const Key('ocr:libelle'),
                style: const TextStyle(
                    color: JetonsShell.slate600,
                    fontSize: 12,
                    height: 16 / 12)),
          ];
          if (e.marque || courante != null) {
            enfants.add(const NoteSigh(
                'Texte lu par machine, à vérifier. La reconnaissance de caractères peut se tromper (accents, chiffres, mots coupés) : le texte sert à RETROUVER une pièce, jamais à la citer. Le scan reste la seule référence.',
                key: Key('ocr:marque'),
                ton: TonSigh.attention,
                icone: LucideIcons.scanText));
          }
          if (e.etat == EtatIndexation.ocrEchec) {
            enfants.add(Text('${file?['geste'] ?? ''}',
                key: Key('ocr:echec-${file?['code']}'),
                style: const TextStyle(
                    color: JetonsShell.danger700,
                    fontSize: 12,
                    height: 16 / 12)));
          }
          if (e.etat == EtatIndexation.nonIndexe) {
            enfants.add(const Text(
                'La recherche par le contenu ne lit pas cette pièce ; elle reste retrouvable par ses données de fiche.',
                style: TextStyle(
                    color: JetonsShell.slate500,
                    fontSize: 12,
                    height: 16 / 12)));
          }
          if (o.relancePossible(x, peutDeposer: widget.peutDeposer)) {
            enfants.add(Wrap(spacing: 8, children: [
              BoutonSigh(
                  key: const Key('ocr:relancer'),
                  libelle: 'Relancer la lecture',
                  icone: LucideIcons.refreshCw,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () async {
                    final r = o.relancer(x,
                        peutDeposer: widget.peutDeposer,
                        famille: widget.famille,
                        type: widget.type);
                    if (!r.ok) {
                      setState(() => _refus = r.refus);
                      return;
                    }
                    setState(() => _refus = null);
                    ToastsSigh.afficher(context, 'Lecture relancée.',
                        type: TypeToast.succes,
                        detail:
                            'Une nouvelle version sera ajoutée ; l’ancienne reste lisible.');
                    await o.vider(1);
                  })
            ]));
          }
          if (_refus != null) {
            enfants.add(NoteSigh(
                '${_refus!.code} : ${_refus!.motif} ${_refus!.geste}',
                key: const Key('ocr:refus'),
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert));
          }
          if (versions.isNotEmpty) {
            enfants.add(Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                    key: Key('ocr:historique-${versions.length}'),
                    tilePadding: EdgeInsets.zero,
                    title: Text('Lectures de ce scan (${versions.length})',
                        style: const TextStyle(
                            color: JetonsShell.slate700, fontSize: 14)),
                    children: [
                      for (var i = versions.length - 1; i >= 0; i--)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                                key: Key('ocr:version-${i + 1}'),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: JetonsShell.slate50,
                                    borderRadius: BorderRadius.circular(6)),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'Version ${i + 1}${courante != null && versions[i]['id'] == courante['id'] ? ' (courante)' : ''} : ${versions[i]['moteur']}${(versions[i]['moteurVersion'] ?? '') != '' ? ' ${versions[i]['moteurVersion']}' : ''}, langue ${versions[i]['langue']}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12)),
                                      Text(
                                          'Lue le ${_dateFr(versions[i]['ocrLe'])} par ${versions[i]['ocrPar'] ?? 'auteur inconnu'} · ${versions[i]['nbMots']} mots · confiance ${_confiance(versions[i]['confiance'])}${versions[i]['declencheur'] == 'relance' ? ' · relance' : ''}',
                                          style: const TextStyle(
                                              color: JetonsShell.slate500,
                                              fontSize: 12)),
                                      const SizedBox(height: 4),
                                      const Text(
                                          'Texte lu par machine, à vérifier',
                                          style: TextStyle(
                                              color: JetonsShell.slate600,
                                              fontSize: 12)),
                                      SelectableText(
                                          '${versions[i]['texteBrut'] ?? ''}',
                                          key: Key('ocr:texte-${i + 1}'),
                                          style: const TextStyle(
                                              color: JetonsShell.slate700,
                                              fontSize: 12)),
                                    ])))
                    ])));
          }
          return Column(
              key: Key('ocr:bloc-${e.code}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < enfants.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  enfants[i]
                ]
              ]);
        });
  }
}

String _dateFr(Object? iso) {
  final s = '${iso ?? ''}';
  if (s.length < 16) return '—';
  return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)} ${s.substring(11, 16)}';
}

String _confiance(Object? c) => c is num
    ? '${(c * 100).round()} % en moyenne'
    : 'non fournie par le moteur';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// le réglage
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le bouton « Lecture des scans (OCR) » : ABSENT sans le droit de régler (administrateur et Directrice Administrative).
Widget? boutonOcr(BuildContext context, {required String role}) {
  final c = ContexteEcran.of(context);
  final o = OcrPoste.de(c.magasin);
  if (o == null || !o.peutRegler(role)) return null;
  return BoutonSigh(
      key: const Key('ocr:bouton-reglage'),
      libelle: 'Lecture des scans (OCR)',
      icone: LucideIcons.scanText,
      variante: VarianteBouton.secondaire,
      onPressed: () => _ouvrirReglage(context, o, role));
}

Future<void> _ouvrirReglage(
    BuildContext context, OcrPoste o, String role) async {
  final r = o.reglage;
  var actif = r.actif;
  var moteur =
      r.moteur != null && o.moteurs.containsKey(r.moteur) ? r.moteur : null;
  final langue = TextEditingController(text: r.langue);
  final motif = TextEditingController();
  final refus = ValueNotifier<RefusFichier?>(null);
  await afficherModale<void>(context,
      titre: 'Lecture des scans (OCR)',
      taille: TailleModale.sm,
      corps: StatefulBuilder(
          builder: (_, setS) => ValueListenableBuilder<RefusFichier?>(
              valueListenable: refus,
              builder: (_, ref, __) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        NoteSigh(
                            o.moteurInstalle
                                ? 'La lecture des scans est désactivée par défaut (à valider par la Direction). Le texte lu par machine est toujours marqué « à vérifier ». Ce réglage est propre à ce poste.'
                                : '${ocrRaisonSansMoteur[0].toUpperCase()}${ocrRaisonSansMoteur.substring(1)}. Il n’y a rien à activer tant qu’un moteur n’est pas installé : la Direction a décidé de choisir le moteur après un essai sur trois vrais scans.',
                            key: const Key('ocr:reglage-note')),
                        const SizedBox(height: 12),
                        Row(children: [
                          Checkbox(
                              key: const Key('ocr:actif'),
                              value: actif,
                              onChanged: (v) => setS(() => actif = v ?? false)),
                          const Expanded(
                              child: Text(
                                  'Activer la lecture automatique des scans',
                                  style: TextStyle(fontSize: 14))),
                        ]),
                        const Text('Moteur d’OCR',
                            style: TextStyle(
                                color: JetonsShell.slate600, fontSize: 12)),
                        DropdownButtonFormField<String>(
                            key: const Key('ocr:moteur'),
                            initialValue: moteur,
                            hint: Text(o.moteurInstalle
                                ? 'Choisir un moteur'
                                : 'Aucun moteur installé'),
                            items: [
                              for (final m in o.moteurs.values)
                                DropdownMenuItem(
                                    value: m.id,
                                    child: Text(
                                        '${m.libelle}${m.version.isEmpty ? '' : ' ${m.version}'}'))
                            ],
                            onChanged: o.moteurInstalle
                                ? (v) => setS(() => moteur = v)
                                : null),
                        const SizedBox(height: 12),
                        const Text(
                            'Langue (code du moteur, « fra » pour le français)',
                            style: TextStyle(
                                color: JetonsShell.slate600, fontSize: 12)),
                        TextField(
                            key: const Key('ocr:langue'), controller: langue),
                        const SizedBox(height: 12),
                        const Text('Motif (consigné dans le journal)',
                            style: TextStyle(
                                color: JetonsShell.slate600, fontSize: 12)),
                        TextField(
                            key: const Key('ocr:motif'),
                            controller: motif,
                            maxLines: 2),
                        if (ref != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: NoteSigh(
                                  '${ref.code} : ${ref.motif} ${ref.geste}',
                                  key: const Key('ocr:reglage-refus'),
                                  ton: TonSigh.attention)),
                      ]))),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                key: const Key('ocr:enregistrer'),
                libelle: 'Enregistrer',
                icone: LucideIcons.check,
                onPressed: () {
                  final x = o.definirReglage(
                      role: role,
                      actif: actif,
                      moteur: moteur,
                      langue: langue.text.trim(),
                      motif: motif.text);
                  if (!x.ok) {
                    refus.value = x.refus;
                    return;
                  }
                  fermer();
                  ToastsSigh.afficher(
                      context,
                      actif
                          ? 'Lecture des scans activée.'
                          : 'Lecture des scans désactivée.',
                      type: TypeToast.succes);
                }),
          ]);
}
