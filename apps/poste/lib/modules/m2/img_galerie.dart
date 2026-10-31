import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'img_commun.dart';

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

/// Un cliché est conservé en `data:` URL (comme la maquette : aucun fichier hors du magasin, rien à perdre à la coupure).
Uint8List? octetsDuCliche(Object? dataUrl) {
  final s = '${dataUrl ?? ''}';
  final i = s.indexOf(',');
  if (!s.startsWith('data:') || i < 0) return null;
  try {
    return base64Decode(s.substring(i + 1));
  } catch (_) {
    return null;
  }
}

const _typesImage = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp'
};

/// `m2-echographie-galerie` — « Galerie des clichés » : les clichés conservés au poste, rattachés au patient et au compte rendu. L'archivage est
/// logique (RG-14) : rien ne s'efface. Conservation locale, mêmes précautions de taille que les documents du dossier (deux mégaoctets).
class EcranGalerieClichesImagerie extends StatelessWidget with EcranMaquette {
  const EcranGalerieClichesImagerie({super.key});

  @override
  String get titre => 'Galerie des clichés';

  @override
  String get description =>
      'Les clichés d’échographie conservés au poste, rattachés au patient et au compte rendu.';

  @override
  String get regle =>
      'Un cliché se rattache à un patient et, si possible, à son compte rendu : une image orpheline ne se retrouve plus. Conservation locale, mêmes précautions de taille que les documents du dossier — au-delà de deux mégaoctets, le stockage du navigateur sature vite. L’archivage est logique (RG-14) : rien ne s’efface.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('clichesImagerie');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final s = statsGalerie(rows);
        final tries = clichesRecentsDabord(rows);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Clichés conservés',
                    valeur: nombre(s.conserves),
                    icone: LucideIcons.images),
                KpiSigh(
                    libelle: 'Patients concernés',
                    valeur: nombre(s.patients),
                    icone: LucideIcons.users,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Liés à un compte rendu',
                    valeur: nombre(s.lies),
                    icone: LucideIcons.fileCheck2,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Sans compte rendu lié',
                    valeur: nombre(s.sansLien),
                    icone: LucideIcons.circleHelp,
                    ton: TonSigh.neutre),
              ]),
              const SizedBox(height: 16),
              if (c.droit.editer) ...[
                Container(
                    decoration: decorationCarte(),
                    padding: const EdgeInsets.all(20),
                    child: Row(children: [
                      BoutonSigh(
                          libelle: 'Ajouter un cliché',
                          icone: LucideIcons.imagePlus,
                          taille: TailleBouton.sm,
                          onPressed: () => _ajouter(context, c)),
                    ])),
                const SizedBox(height: 16),
              ],
              if (tries.isEmpty)
                const CarteSigh(
                    titre: 'Galerie',
                    child: VideSigh(
                        'Aucun cliché conservé. Les images s’ajoutent depuis ce poste, rattachées au patient.',
                        icone: LucideIcons.images))
              else
                LayoutBuilder(builder: (_, k) {
                  final n = k.maxWidth >= 1024 ? 3 : (k.maxWidth >= 640 ? 2 : 1);
                  final l = (k.maxWidth - 16 * (n - 1)) / n;
                  return Wrap(spacing: 16, runSpacing: 16, children: [
                    for (final r in tries)
                      SizedBox(
                          width: l,
                          child: _CarteCliche(
                              cliche: r,
                              archiver: c.droit.editer
                                  ? () => _archiver(context, col, r)
                                  : null)),
                  ]);
                }),
            ]);
      },
    );
  }

  Future<void> _archiver(
      BuildContext ctx, CollectionMagasin col, Fiche r) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Archiver ce cliché ?',
        message:
            'Archivage logique (RG-14) : le cliché reste restaurable depuis la Corbeille.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    col.archiver(r['id']);
    ToastsSigh.afficher(ctx, 'Cliché archivé.', type: TypeToast.succes);
  }

  void _ajouter(BuildContext ctx, ContexteEcran c) => afficherModale<void>(ctx,
      titre: 'Ajouter un cliché',
      taille: TailleModale.lg,
      corps: _ModaleCliche(contexte: c, ecran: ctx),
      pied: null);
}

class _CarteCliche extends StatelessWidget {
  const _CarteCliche({required this.cliche, this.archiver});
  final Fiche cliche;
  final VoidCallback? archiver;

  @override
  Widget build(BuildContext context) {
    final r = cliche;
    final octets = octetsDuCliche(r['fichier']);
    return Container(
      key: Key('img:cliche:${r['id']}'),
      decoration: decorationCarte(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            height: 176,
            color: JetonsShell.slate100,
            child: octets == null
                ? null
                : Image.memory(octets,
                    fit: BoxFit.contain,
                    semanticLabel: 'Cliché — ${r['examen']}',
                    errorBuilder: (_, __, ___) => const SizedBox())),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['patient']}',
                    style: const TextStyle(
                        color: JetonsShell.slate800,
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('${r['examen']} — ${texteDate(r['date'])}',
                    style: const TextStyle(
                        color: JetonsShell.slate500,
                        fontSize: 12,
                        height: 16 / 12)),
                if (_vrai(r['legende'])) ...[
                  const SizedBox(height: 4),
                  Text('${r['legende']}',
                      style: const TextStyle(
                          color: JetonsShell.slate600,
                          fontSize: 12,
                          height: 16 / 12)),
                ],
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _vrai(r['crReference'])
                            ? Text('${r['crReference']}',
                                style: const TextStyle(
                                    fontFamily: 'LiberationMono',
                                    fontSize: 10,
                                    color: JetonsShell.navy700))
                            : const Text('sans CR lié',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: JetonsShell.slate400)),
                        if (archiver != null)
                          BoutonIcone(
                              icone: LucideIcons.archive,
                              libelle: 'Archiver le cliché',
                              onPressed: archiver),
                      ]),
                ),
              ]),
        ),
      ]),
    );
  }
}

class _ModaleCliche extends StatefulWidget {
  const _ModaleCliche({required this.contexte, required this.ecran});
  final ContexteEcran contexte;

  /// Le contexte de l'ÉCRAN : une modale vit au-dessus de la coque, hors du `ContexteEcran`.
  final BuildContext ecran;
  @override
  State<_ModaleCliche> createState() => _EtatModaleCliche();
}

class _EtatModaleCliche extends State<_ModaleCliche> {
  late final ControleurFormulaire _f;
  final _chemin = TextEditingController();
  String? _fichier;
  String? _avertissement;
  Uint8List? _apercu;

  @override
  void initState() {
    super.initState();
    final m = widget.contexte.magasin;
    _f = ControleurFormulaire([
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: optionsPatientsImagerie(m)),
      ChampDef(
          nom: 'crReference',
          libelle: 'Compte rendu lié',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: [
            const OptionChamp('', '— aucun —'),
            for (final r in m.collection('resultatsImagerie').actives)
              OptionChamp('${r['reference']}',
                  '${r['reference']} — ${r['examen']} — ${r['patient']}')
          ]),
      ChampDef(
          nom: 'examen',
          libelle: 'Examen',
          type: TypeChamp.select,
          requis: true,
          options: [
            for (final x in catalogueExamens(m))
              OptionChamp('${x['label']}', '${x['label']}')
          ]),
      const ChampDef(
          nom: 'legende',
          libelle: 'Légende',
          col: ColChamp.plein,
          aide: 'Ce que montre le cliché — coupe, mesure, structure visée.'),
    ]);
  }

  @override
  void dispose() {
    _f.dispose();
    _chemin.dispose();
    super.dispose();
  }

  /// Lit l'image choisie : PNG, JPEG ou WEBP ; au-delà de deux mégaoctets, la conservation locale sature vite — on le DIT.
  Future<void> _charger() async {
    final chemin = _chemin.text.trim();
    setState(() {
      _fichier = null;
      _apercu = null;
      _avertissement = null;
    });
    if (chemin.isEmpty) return;
    final ext = chemin.split('.').last.toLowerCase();
    final type = _typesImage[ext];
    final f = File(chemin);
    if (type == null || !f.existsSync()) {
      ToastsSigh.afficher(
          widget.ecran,
          type == null
              ? 'Format non reconnu : PNG, JPEG ou WEBP.'
              : 'Fichier introuvable.',
          type: TypeToast.erreur);
      return;
    }
    // Lecture synchrone : une image de cliché pèse quelques centaines de Ko, et l'interface ne doit pas se repeindre à mi-chemin.
    final octets = f.readAsBytesSync();
    if (!mounted) return;
    setState(() {
      if (octets.length > 2 * 1024 * 1024) {
        _avertissement =
            'Fichier de ${(octets.length / 1024).round()} Ko — au-delà de deux mégaoctets, le stockage local sature vite. Exporter le cliché en résolution plus basse.';
      }
      _fichier = 'data:$type;base64,${base64Encode(octets)}';
      _apercu = octets;
    });
  }

  void _conserver() {
    final c = widget.contexte;
    final v = _f.valider();
    if (v == null) {
      ToastsSigh.afficher(widget.ecran, 'Le formulaire comporte des erreurs.',
          type: TypeToast.erreur);
      return;
    }
    if (_fichier == null) {
      ToastsSigh.afficher(widget.ecran, 'Choisir une image.',
          type: TypeToast.erreur,
          detail: 'Un cliché sans image n’est qu’une légende.');
      return;
    }
    final pt = c.magasin
        .collection('patients')
        .actives
        .where((x) => x['code'] == v['patientCode'])
        .firstOrNull;
    c.magasin.collection('clichesImagerie').inserer({
      'date': c.aujourdhui.toIso8601String(),
      'patientId': pt?['id'],
      'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : v['patientCode'],
      'patientCode': v['patientCode'],
      'examen': v['examen'],
      'legende': _vrai(v['legende']) ? v['legende'] : '',
      'crReference': _vrai(v['crReference']) ? v['crReference'] : null,
      'fichier': _fichier,
      'deposePar': c.utilisateur,
      'statut': 'actif',
    }, prefixe: 'CLI');
    Navigator.of(context).pop();
    ToastsSigh.afficher(widget.ecran, 'Cliché conservé.', type: TypeToast.succes);
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormulaireSigh(controleur: _f),
        const SizedBox(height: 12),
        const LibelleChamp('Image * — PNG, JPEG ou WEBP'),
        Row(children: [
          Expanded(
              child: TextField(
                  key: const Key('img:chemin'),
                  controller: _chemin,
                  style: styleSaisie,
                  decoration: decorationChamp(
                      indicatif: 'Chemin du fichier image sur ce poste'),
                  onSubmitted: (_) => _charger())),
          const SizedBox(width: 8),
          BoutonSigh(
              libelle: 'Charger',
              icone: LucideIcons.imagePlus,
              variante: VarianteBouton.secondaire,
              onPressed: _charger),
        ]),
        if (_avertissement != null) ...[
          const SizedBox(height: 8),
          NoteSigh(_avertissement!,
              ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
        ],
        if (_apercu != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_apercu!,
                              fit: BoxFit.contain,
                              semanticLabel: 'Aperçu du cliché',
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox()))))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          BoutonSigh(
              libelle: 'Annuler',
              variante: VarianteBouton.secondaire,
              onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          BoutonSigh(
              libelle: 'Conserver le cliché',
              icone: LucideIcons.imagePlus,
              onPressed: _conserver),
        ]),
      ]);
}
