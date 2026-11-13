import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/fichiers_poste.dart';
import '../donnees/magasin.dart';
import '../import/selecteurs_import.dart' show FichierChoisi;
import '../shell/contexte_ecran.dart';
import 'bouton.dart';
import 'badge.dart';
import 'carte.dart';
import 'detail.dart';
import 'modale.dart';
import 'toast.dart';
import 'ton.dart';

/// LES COMPOSANTS DES FICHIERS NUMÉRISÉS (lot D5) : la carte « Pièce numérisée » d'une fiche (dépôt, aperçu, téléchargement sous le nom normalisé, retrait annulable, remplacement,
/// chemin sur ce poste, état « en cours de transfert » ou « non disponible hors ligne »), la visionneuse d'images écrite pour le projet (zoom, rotation, ajustement), le lecteur de
/// PDF derrière une interface, et le réglage de la taille maximale. Toutes les règles sont celles du domaine ; ces composants ne décident rien, ils montrent et enchaînent.

typedef ChoisirFichierNumerise = Future<FichierChoisi?> Function();
typedef EnregistrerPiece = Future<String?> Function(String nom, Uint8List octets);

/// Les sélecteurs de fichier, INJECTABLES : aucun test ne dépend d'une boîte de dialogue native. En exploitation ils ouvrent celles du système (`file_picker` pour choisir un scan,
/// `file_selector` pour enregistrer sous le nom normalisé) ; un test pose les siens.
class SelecteursFichiers {
  SelecteursFichiers._();

  static ChoisirFichierNumerise choisir = choisirNatif;
  static EnregistrerPiece enregistrer = enregistrerNatif;
  static LecteurPdf lecteurPdf = const LecteurPdfSysteme();

  static void reinitialiser() {
    choisir = choisirNatif;
    enregistrer = enregistrerNatif;
    lecteurPdf = const LecteurPdfSysteme();
  }

  static Future<FichierChoisi?> choisirNatif() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Fichier numérisé à déposer', type: FileType.custom, allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp']);
    if (f == null) return null;
    return FichierChoisi(f.name, await f.readAsBytes());
  }

  static Future<String?> enregistrerNatif(String nom, Uint8List octets) async {
    final ext = nom.contains('.') ? nom.split('.').last : '';
    final lieu = await fs.getSaveLocation(suggestedName: nom, acceptedTypeGroups: [fs.XTypeGroup(label: 'Pièce numérisée', extensions: [ext])]);
    if (lieu == null) return null;
    await File(lieu.path).writeAsBytes(octets);
    return lieu.path;
  }
}

/// LE LECTEUR DE PDF, derrière une interface. Un rendu natif (pdfium ou équivalent) ne se compile pas dans l'environnement de rédaction : l'interface permet de le brancher sans toucher aux
/// écrans, et les tests lisent un rendu factice. Le lecteur livré ouvre le fichier, dont l'empreinte vient d'être VÉRIFIÉE, dans l'application PDF du système (aucun service externe,
/// aucun envoi du document : il passe du disque du poste à l'application locale).
abstract class LecteurPdf {
  Widget construire(BuildContext context, {required Uint8List octets, required String nom, required String titre});
}

class LecteurPdfSysteme implements LecteurPdf {
  const LecteurPdfSysteme();

  /// Écrit les octets vérifiés sous un dossier temporaire propre à l'empreinte, puis les ouvre avec l'application du système.
  static Future<String> ouvrir(Uint8List octets, String nom) async {
    final d = Directory.systemTemp.createTempSync('sigh-pdf-');
    final f = File('${d.path}${Platform.pathSeparator}$nom');
    await f.writeAsBytes(octets, flush: true);
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', f.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [f.path]);
    } else {
      await Process.run('xdg-open', [f.path]);
    }
    // Le PDF a été déchiffré pour le lecteur du système : la copie en clair ne reste pas dans le dossier temporaire (suppression au mieux après dix minutes ; Windows refuse de supprimer
    // un fichier que le lecteur tient encore ouvert, la copie reste alors jusqu'au nettoyage du dossier temporaire par le système : limite dite, écart E2542).
    Timer(const Duration(minutes: 10), () {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    });
    return f.path;
  }

  @override
  Widget construire(BuildContext context, {required Uint8List octets, required String nom, required String titre}) => _PdfSysteme(octets: octets, nom: nom, titre: titre);
}

class _PdfSysteme extends StatefulWidget {
  const _PdfSysteme({required this.octets, required this.nom, required this.titre});
  final Uint8List octets;
  final String nom;
  final String titre;

  @override
  State<_PdfSysteme> createState() => _PdfSystemeState();
}

class _PdfSystemeState extends State<_PdfSysteme> {
  String? _erreur;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh('Le PDF s’ouvre dans l’application PDF de ce poste : le fichier a été vérifié (empreinte SHA-256) avant d’être ouvert, et il ne quitte pas le poste.', icone: LucideIcons.fileText),
        const SizedBox(height: 12),
        Align(
            alignment: Alignment.centerLeft,
            child: BoutonSigh(
                key: const Key('fichiers:ouvrir-pdf'),
                libelle: 'Ouvrir dans le lecteur PDF du poste',
                icone: LucideIcons.externalLink,
                onPressed: () async {
                  try {
                    await LecteurPdfSysteme.ouvrir(widget.octets, widget.nom);
                  } catch (e) {
                    if (mounted) setState(() => _erreur = 'Aucune application PDF n’a pu s’ouvrir sur ce poste ($e). Enregistrer la pièce (« Télécharger ») puis l’ouvrir à la main.');
                  }
                })),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 8), child: NoteSigh(_erreur!, ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
      ]);
}

/// Un refus nommé : le code, le motif, le geste (jamais un message muet).
Widget noteRefus(RefusFichier r, {Key? key}) => NoteSigh('${r.code} : ${r.motif} ${r.geste}', key: key ?? const Key('fichiers:refus'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// la visionneuse d'images
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// LA VISIONNEUSE D'IMAGES, écrite pour le projet (réponse Q3 de la Direction) : zoom (boutons et molette), rotation par quarts de tour, déplacement, ajustement à la fenêtre, taille
/// réelle. Aucune dépendance. L'état se lit à l'écran (« 125 % ») et aux lecteurs d'écran (`Semantics`).
class VisionneuseImage extends StatefulWidget {
  const VisionneuseImage({super.key, required this.octets, this.libelle = 'Pièce numérisée', this.hauteur = 420});
  final Uint8List octets;
  final String libelle;
  final double hauteur;

  @override
  State<VisionneuseImage> createState() => VisionneuseImageState();
}

class VisionneuseImageState extends State<VisionneuseImage> {
  double _zoom = 1;
  int _quarts = 0;
  Offset _decalage = Offset.zero;
  bool _ajuste = true;
  ui.Image? _image;

  /// Pour les tests : l'état lu comme l'agent le lit.
  double get zoom => _zoom;
  int get rotation => ((_quarts % 4) + 4) % 4 * 90;
  bool get ajuste => _ajuste;

  @override
  void initState() {
    super.initState();
    unawaited(_decoder());
  }

  Future<void> _decoder() async {
    try {
      final c = await ui.instantiateImageCodec(widget.octets);
      final f = await c.getNextFrame();
      if (mounted) setState(() => _image = f.image);
    } catch (_) {/* l'image ne se décode pas : Image.memory affichera son erreur */}
  }

  void _zoomer(double facteur) => setState(() {
        _zoom = (_zoom * facteur).clamp(0.1, 8.0);
        _ajuste = false;
      });

  void _tourner(int quarts) => setState(() => _quarts += quarts);

  void _ajuster() => setState(() {
        _zoom = 1;
        _decalage = Offset.zero;
        _ajuste = true;
      });

  /// Taille réelle : un pixel de l'image pour un pixel de l'écran (zoom = taille naturelle / taille affichée de l'ajustement).
  void _tailleReelle(double largeurBoite) {
    final img = _image;
    if (img == null) return;
    final aspect = img.width / img.height;
    final affichee = (widget.hauteur * aspect < largeurBoite) ? widget.hauteur * aspect : largeurBoite;
    setState(() {
      _zoom = (img.width / affichee).clamp(0.1, 8.0);
      _ajuste = false;
    });
  }

  Widget _bouton(String libelle, IconData icone, VoidCallback f) => BoutonIcone(icone: icone, libelle: libelle, onPressed: f);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${widget.libelle} : zoom ${(_zoom * 100).round()} %, rotation $rotation degrés${_ajuste ? ', ajustée à la fenêtre' : ''}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _bouton('Agrandir', LucideIcons.zoomIn, () => _zoomer(1.25)),
          _bouton('Réduire', LucideIcons.zoomOut, () => _zoomer(0.8)),
          SizedBox(
              width: 56,
              child: Text('${(_zoom * 100).round()} %', key: const Key('visionneuse:zoom'), textAlign: TextAlign.center, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12))),
          _bouton('Tourner à gauche', LucideIcons.rotateCcw, () => _tourner(-1)),
          _bouton('Tourner à droite', LucideIcons.rotateCw, () => _tourner(1)),
          _bouton('Ajuster à la fenêtre', LucideIcons.minimize, _ajuster),
          LayoutBuilder(builder: (_, c) => _bouton('Taille réelle', LucideIcons.maximize, () => _tailleReelle(c.maxWidth))),
        ]),
        const SizedBox(height: 8),
        Container(
          key: const Key('visionneuse:cadre'),
          height: widget.hauteur,
          decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
          clipBehavior: Clip.antiAlias,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _zoomer(e.scrollDelta.dy < 0 ? 1.1 : 0.9);
            },
            // Le déplacement se lit sur les événements du pointeur et non sur un geste d'arène : dans une fenêtre qui défile, un glissement vertical serait pris par le défilement.
            onPointerMove: (e) => setState(() {
              _decalage += e.delta;
              _ajuste = false;
            }),
            child: Center(
                  child: Transform.translate(
                      offset: _decalage,
                      child: Transform.rotate(
                          angle: _quarts * 3.141592653589793 / 2,
                          child: Transform.scale(
                              scale: _zoom,
                              child: Image.memory(widget.octets, fit: BoxFit.contain, height: widget.hauteur, semanticLabel: widget.libelle, errorBuilder: (_, __, ___) => const Text('Image illisible')))))),
          ),
        ),
      ]),
    );
  }
}

/// L'APERÇU d'une pièce (modale) : image dans la visionneuse, PDF dans le lecteur injecté. La pièce est lue avec son empreinte VÉRIFIÉE et la lecture est journalisée ; un refus nommé est
/// RENDU (jamais une fenêtre vide). `null` : la modale s'est ouverte.
Future<RefusFichier?> ouvrirApercuPiece(BuildContext context,
    {required String famille, required FicheDoc fiche, required String titre, required String role, required Droit droit, String? sousTitre}) async {
  final fp = FichiersPoste.de(ContexteEcran.of(context).magasin);
  if (fp == null) return const RefusFichier('FICHIERS_NON_ACTIVES', 'le stockage des fichiers numérisés n’est pas disponible sur ce poste', 'Redémarrer le poste.');
  final r = await fp.lire(famille: famille, fiche: fiche, role: role, droit: droit);
  if (!r.ok) return r.refus;
  if (!context.mounted) return null;
  final mime = '${r.fichier?['mime']}';
  await afficherModale<void>(context,
      titre: titre,
      sousTitre: sousTitre ?? r.nom,
      taille: TailleModale.lg,
      corps: mime == 'application/pdf'
          ? SelecteursFichiers.lecteurPdf.construire(context, octets: r.octets!, nom: r.nom!, titre: titre)
          : VisionneuseImage(octets: r.octets!, libelle: titre));
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// la carte « Pièce numérisée » d'une fiche
// ---------------------------------------------------------------------------------------------------------------------------------------------

String _formatLisible(Map<String, Object?> x) {
  final mime = '${x['mime'] ?? ''}'.replaceAll('application/', '').replaceAll('image/', '').toUpperCase();
  final pages = x['pages'];
  return '$mime · ${fichierPoids(x['taille'] as num?)}${pages != null ? ' · $pages page${(pages as num) > 1 ? 's' : ''}' : ''}';
}

/// La carte « Pièce numérisée » d'une fiche (`cartePiece` de la maquette) : la même pour un courrier (M13) et un document du patient (M1). Les commandes interdites sont ABSENTES, jamais
/// grisées ; une pièce que le profil ne lit pas n'est PAS montrée et le dit (RG-13).
class CartePieceNumerisee extends StatefulWidget {
  const CartePieceNumerisee(
      {super.key, required this.famille, required this.ficheId, required this.titre, required this.role, required this.droit, this.portee, this.motifLecture});
  final String famille;
  final Object ficheId;
  final String titre;
  final String role;
  final Droit droit;
  final bool Function(FicheDoc)? portee;
  final String? motifLecture;

  @override
  State<CartePieceNumerisee> createState() => _CartePieceState();
}

class _CartePieceState extends State<CartePieceNumerisee> {
  RefusFichier? _refus;
  bool _occupe = false;
  bool _remplacerOuvert = false;

  Magasin get _magasin => ContexteEcran.of(context).magasin;
  CollectionMagasin get _col => _magasin.collection(fichiersCollectionDe(widget.famille));

  String? get _type {
    final f = _col.parId(widget.ficheId);
    return widget.famille == 'patient' ? '${f?['type']}' : null;
  }

  bool get _peutVoir => widget.famille != 'patient' ? widget.droit.voir : (widget.droit.voir && docPeutVoir(_type, widget.role).autorise);
  bool get _peutDeposer => widget.droit.editer && _peutVoir && _col.parId(widget.ficheId)?['statut'] != 'archive';
  bool get _peutRetirer => widget.droit.annuler && _col.parId(widget.ficheId)?['statut'] != 'archive';

  Future<void> _choisirEtDeposer({required bool remplacer}) async {
    final fp = FichiersPoste.de(_magasin);
    if (fp == null) return;
    final choix = await SelecteursFichiers.choisir();
    if (choix == null || !mounted) return;
    setState(() {
      _occupe = true;
      _refus = null;
    });
    final r = await fp.deposer(
        famille: widget.famille,
        ficheId: widget.ficheId,
        nom: choix.nom,
        octets: choix.octets,
        role: widget.role,
        droit: widget.droit,
        remplacer: remplacer,
        portee: widget.portee,
        confirmerAutre: (autre) => confirmerSigh(context,
            titre: 'Ce fichier est déjà rattaché ailleurs',
            message: 'Le même fichier est déjà la pièce ${fichierNomPiece(autre)}. Le rattacher aussi à cette fiche ?',
            libelleOk: 'Rattacher quand même'));
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _refus = r.refus;
      if (r.ok) _remplacerOuvert = false;
    });
    if (r.ok) {
      ToastsSigh.afficher(context, remplacer ? 'Pièce remplacée.' : 'Pièce numérisée rattachée.',
          type: TypeToast.succes, detail: '${r.fichier?['nomNormalise']}', annuler: r.annuler, messageAnnulation: 'Dépôt annulé : la fiche est de nouveau sans pièce.');
    }
  }

  Future<void> _apercu(FicheDoc fiche) async {
    final refus = await ouvrirApercuPiece(context, famille: widget.famille, fiche: fiche, titre: widget.titre, role: widget.role, droit: widget.droit);
    if (!mounted) return;
    setState(() => _refus = refus);
  }

  Future<void> _telecharger(FicheDoc fiche) async {
    final fp = FichiersPoste.de(_magasin);
    if (fp == null) return;
    final r = await fp.lire(famille: widget.famille, fiche: fiche, role: widget.role, droit: widget.droit, usage: 'telechargement');
    if (!mounted) return;
    if (!r.ok) {
      ToastsSigh.afficher(context, 'Téléchargement refusé : ${r.refus!.code}', type: TypeToast.erreur, detail: '${r.refus!.motif} ${r.refus!.geste}');
      setState(() => _refus = r.refus);
      return;
    }
    final chemin = await SelecteursFichiers.enregistrer(r.nom!, r.octets!);
    if (!mounted) return;
    if (chemin != null) ToastsSigh.afficher(context, 'Pièce enregistrée sous ${r.nom}.', type: TypeToast.succes, detail: chemin);
  }

  Future<void> _retirer(FicheDoc fiche) async {
    final fp = FichiersPoste.de(_magasin);
    if (fp == null) return;
    final motif = await confirmerAvecMotif(context,
        titre: 'Retirer la pièce de la fiche ?',
        message: 'La pièce est retirée de la fiche, non supprimée (RG-14) : le fichier et son empreinte restent conservés, l’opération est journalisée et annulable.',
        libelleOk: 'Retirer',
        dangereux: true);
    if (motif == null || !mounted) return;
    final r = fp.retirer(famille: widget.famille, ficheId: widget.ficheId, motif: motif, role: widget.role, droit: widget.droit);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _refus = r.refus);
      return;
    }
    ToastsSigh.afficher(context, 'Pièce retirée de la fiche.', type: TypeToast.succes, annuler: r.annuler, messageAnnulation: 'Retrait annulé : la pièce est de nouveau rattachée.');
  }

  Widget _zoneDepot(String libelle, {required bool remplacer}) {
    final admis = [for (final f in fichierFormats) if (f.familles.contains(widget.famille)) f.libelle].join(', ');
    return Container(
        key: Key(remplacer ? 'fichiers:zone-remplacer' : 'fichiers:zone-depot'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate300)),
        child: Column(children: [
          Text('$libelle ($admis ; ${fichierPoids(FichiersPoste.de(_magasin)?.tailleMax())} au plus)', textAlign: TextAlign.center, style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
          const SizedBox(height: 8),
          BoutonSigh(
              key: Key(remplacer ? 'fichiers:choisir-remplacer' : 'fichiers:choisir'),
              libelle: 'Choisir un fichier',
              icone: LucideIcons.upload,
              taille: TailleBouton.sm,
              onPressed: _occupe ? null : () => _choisirEtDeposer(remplacer: remplacer)),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final fp = FichiersPoste.de(_magasin);
    return ListenableBuilder(
        listenable: Listenable.merge([_col, if (fp != null) fp]),
        builder: (context, _) {
          final fiche = _col.parId(widget.ficheId);
          final corps = <Widget>[];
          if (fiche == null) return const SizedBox.shrink();
          if (fp == null) {
            corps.add(const NoteSigh('Le stockage des fichiers numérisés n’est pas disponible sur ce poste.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert));
          } else if (!_peutVoir) {
            corps.add(NoteSigh('Pièce non affichée à votre profil : ${widget.motifLecture ?? 'les pièces médicales du dossier ne se lisent que par les profils cliniques (RG-13).'}', icone: LucideIcons.lock));
          } else {
            final x = fichierDe(fiche);
            if (x != null) {
              corps.add(DescListeSigh([
                ('Nom de téléchargement', Text(docNomNormalise(widget.famille, fiche, fichierExtDeMime('${x['mime']}')), key: const Key('fichiers:nom'), style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate800))),
                ('Fichier d’origine', '${x['nom'] ?? ''}'),
                ('Format', _formatLisible(x)),
                ('Empreinte SHA-256', Text('${docAbrege(x['sha256'])}…', key: const Key('fichiers:empreinte'), style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate800))),
                ('Recherche dans le texte', x['texteIndexe'] == true ? const BadgeSigh('Texte indexé', ton: TonSigh.succes) : const BadgeSigh('Texte non indexé', ton: TonSigh.neutre)),
                ('Déposé', '${x['deposePar'] ?? 'auteur inconnu'}, le ${_dateFr(x['deposeLe'])}'),
              ]));
              if (x['texteIndexe'] != true) {
                corps.add(const Text('Texte non indexé : la recherche par le contenu ne trouve pas cette pièce (image sans couche texte). Elle reste retrouvable par ses données de fiche.',
                    style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)));
              }
              corps.add(Wrap(spacing: 8, runSpacing: 8, children: [
                BoutonSigh(key: const Key('fichiers:apercu'), libelle: 'Aperçu', icone: LucideIcons.eye, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _apercu(fiche)),
                BoutonSigh(key: const Key('fichiers:telecharger'), libelle: 'Télécharger', icone: LucideIcons.download, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _telecharger(fiche)),
                if (_peutRetirer) BoutonSigh(key: const Key('fichiers:retirer'), libelle: 'Retirer la pièce', icone: LucideIcons.archive, taille: TailleBouton.sm, variante: VarianteBouton.danger, onPressed: () => _retirer(fiche)),
                if (_peutDeposer)
                  BoutonSigh(
                      key: const Key('fichiers:remplacer'),
                      libelle: _remplacerOuvert ? 'Garder la pièce actuelle' : 'Remplacer la pièce',
                      icone: LucideIcons.replace,
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.secondaire,
                      onPressed: () => setState(() => _remplacerOuvert = !_remplacerOuvert)),
              ]));
              if (_peutDeposer && _remplacerOuvert) corps.add(_zoneDepot('Choisir le nouveau scan', remplacer: true));
              corps.add(_EtatFichier(famille: widget.famille, fiche: fiche, role: widget.role, fp: fp));
            } else {
              corps.add(const Text('Aucune pièce numérisée rattachée à cette fiche.', style: TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)));
              corps.add(_peutDeposer
                  ? _zoneDepot('Choisir le scan à déposer', remplacer: false)
                  : const NoteSigh('Votre profil consulte cette fiche sans pouvoir y déposer de pièce.'));
            }
            final histo = (fiche['fichiersRetires'] as List? ?? const []);
            if (histo.isNotEmpty) {
              corps.add(DescListeSigh([
                for (var i = 0; i < histo.length; i++)
                  (
                    'Pièce retirée ${i + 1}',
                    '${(histo[i] as Map)['nomNormalise'] ?? (histo[i] as Map)['nom']} · empreinte ${docAbrege((histo[i] as Map)['sha256'])} · retirée par ${(histo[i] as Map)['retirePar'] ?? 'auteur inconnu'}, motif : ${(histo[i] as Map)['motif'] ?? 'non renseigné'}'
                  )
              ]));
            }
            if (_refus != null) corps.add(noteRefus(_refus!));
          }
          return CarteSigh(
              key: Key('fichiers:carte-${widget.famille}'),
              titre: 'Pièce numérisée',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < corps.length; i++) ...[if (i > 0) const SizedBox(height: 12), corps[i]]]));
        });
  }
}

String _dateFr(Object? iso) {
  final s = '${iso ?? ''}';
  if (s.length < 10) return '—';
  return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
}

/// L'état du fichier SUR CE POSTE et son chemin : « en cours de transfert », « non disponible hors ligne », altéré, présent (avec le chemin du fichier rangé).
class _EtatFichier extends StatelessWidget {
  const _EtatFichier({required this.famille, required this.fiche, required this.role, required this.fp});
  final String famille;
  final FicheDoc fiche;
  final String role;
  final FichiersPoste fp;

  Future<(EtatFichierPoste, String?)> _lire() async => (await fp.etat(famille: famille, fiche: fiche, role: role), await fp.chemin(fiche));

  @override
  Widget build(BuildContext context) => FutureBuilder<(EtatFichierPoste, String?)>(
        future: _lire(),
        builder: (context, s) {
          if (!s.hasData) return const Text('Chemin sur ce poste : recherche…', style: TextStyle(color: JetonsShell.slate600, fontSize: 12));
          final (etat, chemin) = s.data!;
          final sha = fichierDe(fiche)?['sha256'];
          if (etat == EtatFichierPoste.present) {
            return Container(
                key: const Key('fichiers:chemin'),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8)),
                child: Text('Chemin sur ce poste : ${chemin ?? '—'}', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12)));
          }
          return NoteSigh(fichierLibelleEtatPoste(etat, sha: '$sha'),
              key: Key('fichiers:etat-${etat.name}'), ton: etat == EtatFichierPoste.altere ? TonSigh.danger : TonSigh.attention, icone: LucideIcons.cloudOff);
        },
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// le réglage de la taille maximale
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le bouton « Taille maximale des fichiers » : ABSENT sans le droit de régler (administrateur et Directrice Administrative).
Widget? boutonTailleFichiers(BuildContext context, {required String role}) {
  final c = ContexteEcran.of(context);
  final fp = FichiersPoste.de(c.magasin);
  if (fp == null || !fp.peutRegler(role)) return null;
  return BoutonSigh(
      key: const Key('fichiers:bouton-taille'),
      libelle: 'Taille maximale des fichiers',
      icone: LucideIcons.slidersHorizontal,
      variante: VarianteBouton.secondaire,
      onPressed: () => _ouvrirReglage(context, fp, role));
}

Future<void> _ouvrirReglage(BuildContext context, FichiersPoste fp, String role) async {
  final taille = TextEditingController(text: '${(fp.tailleMax() / 104857.6).round() / 10}');
  final motif = TextEditingController();
  final refus = ValueNotifier<RefusFichier?>(null);
  await afficherModale<void>(context,
      titre: 'Taille maximale des fichiers numérisés',
      taille: TailleModale.sm,
      corps: ValueListenableBuilder<RefusFichier?>(
          valueListenable: refus,
          builder: (_, r, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                NoteSigh(
                    'Taille maximale d’UN fichier déposé (courrier ou document du dossier patient). ${fp.tailleMaxReglee ? 'Valeur réglée par la clinique.' : 'Valeur de départ de 10 Mo : à valider par la Direction.'} Au delà, le dépôt est refusé en le nommant. Ce réglage est propre à ce poste.'),
                const SizedBox(height: 12),
                const Text('Taille maximale (Mo)', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                TextField(key: const Key('fichiers:taille-mo'), controller: taille, keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                const Text('Motif (consigné dans le journal)', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                TextField(key: const Key('fichiers:taille-motif'), controller: motif, maxLines: 2),
                if (r != null) Padding(padding: const EdgeInsets.only(top: 8), child: noteRefus(r)),
              ])),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                key: const Key('fichiers:taille-enregistrer'),
                libelle: 'Enregistrer',
                icone: LucideIcons.check,
                onPressed: () {
                  final mo = double.tryParse(taille.text.trim().replaceAll(',', '.'));
                  final r = fp.definirTailleMax(role: role, octets: mo == null ? null : (mo * 1048576).round(), motif: motif.text);
                  if (!r.ok) {
                    refus.value = r.refus;
                    return;
                  }
                  fermer();
                  ToastsSigh.afficher(context, 'Taille maximale réglée à ${fichierPoids(r.fichier!['tailleMax'] as int)}.', type: TypeToast.succes, detail: 'Elle s’applique aux prochains dépôts.');
                }),
          ]);
}
