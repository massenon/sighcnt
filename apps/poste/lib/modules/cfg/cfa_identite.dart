import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';
import 'cfb_configuration_fiscale.dart';

/// `cfg-entetes` : « Papier à en-tête officiel », l'en-tête RÉSULTANT : la version de l'identité légale EN FORCE À LA DATE DU JOUR (lue au magasin,
/// `identiteLegale`, jamais la constante) et son état de validation. Il n'écrit rien : l'identité se corrige à « Identité & papier à en-tête » et à
/// « Paramètres fiscaux », se valide, et chaque pièce imprimée la reprend à SA date (E2277).
class EcranEntetes extends StatefulWidget with EcranMaquette {
  const EcranEntetes({super.key});
  @override
  String get titre => 'Papier à en-tête officiel';
  @override
  String get description => 'L’unique identité légale imprimée sur tous les états de la clinique.';
  @override
  String get regle =>
      'Depuis l’arbitrage de la Direction du 31/08/2026, tous les états portent le même en-tête : celui de la version de l’identité légale en force à la date de la pièce. L’identité se corrige en un seul endroit (Identité & papier à en-tête, Paramètres fiscaux), se valide, et chaque pièce imprimée la reprend.';

  @override
  State<EcranEntetes> createState() => _EtatEntetes();
}

class _EtatEntetes extends State<EcranEntetes> {
  bool _amorce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    ConfigurationFiscalePoste.amorcer(ContexteEcran.of(context).magasin);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final cf = ConfigurationFiscalePoste(c);
    return ListenableBuilder(
        listenable: cf.versions,
        builder: (context, _) {
          final f = cf.identiteEnForce();
          final b = cf.identiteImprimee();
          final futures = cfbNoteVersionsAVenir(cf);
          return cfaPile([
            cfbBandeauEtat(cf, identite: true, libelle: 'identité légale'),
            if (futures != null) futures,
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'IFU imprimé', valeur: '1', icone: LucideIcons.hash, ton: TonSigh.succes, indice: b.ifu),
              KpiSigh(libelle: 'RCCM imprimé', valeur: '1', icone: LucideIcons.scale, ton: TonSigh.succes, indice: b.rccm),
              KpiSigh(
                  libelle: 'Version en force',
                  valeur: 'v${b.version ?? 1}',
                  icone: LucideIcons.history,
                  ton: TonSigh.navy,
                  indice: b.debut != null ? 'depuis le ${dateFR(DateTime.parse(isoJour(b.debut)))}' : 'depuis l’ouverture du dossier'),
              const KpiSigh(libelle: 'États alimentés', valeur: 'Tous', icone: LucideIcons.printer, ton: TonSigh.navy),
            ]),
            CarteSigh(
                titre: 'Identité légale imprimée sur chaque état',
                child: DescListeSigh([
                  ('Dénomination', '${b.nom}${b.forme.isNotEmpty ? ' : ${b.forme}' : ''}'),
                  ('Devise de l’établissement', b.slogan),
                  ('Adresse', '${b.adresse} · ${b.bp}'),
                  ('Téléphones', b.telephones.join(' / ')),
                  ('Ligne rendez-vous', b.telephoneRdv.isEmpty ? '—' : b.telephoneRdv),
                  ('Courriel', b.email),
                  ('IFU', b.ifu),
                  ('RCCM', b.rccm),
                  ('Autorisation d’ouverture', b.autorisation),
                  ('Autorisation d’exercice', b.autorisationExercice ?? 'Non imprimée : ${b.autorisationExerciceMotif}'),
                  ('Régime de TVA affiché', b.regimeTva.isEmpty ? '—' : b.regimeTva),
                  ('Validation', f?['valideLe'] != null ? 'Validée le ${dateHeure(DateTime.parse('${f!['valideLe']}').toLocal())} par ${f['validePar']}' : 'À valider (écran Paramètres fiscaux)'),
                ])),
            Wrap(spacing: 8, runSpacing: 8, children: [
              BoutonSigh(libelle: 'Paramètres fiscaux et validation', icone: LucideIcons.landmark, variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: () => c.aller('cfg-fiscalite')),
              BoutonSigh(libelle: 'Identité & papier à en-tête', icone: LucideIcons.image, variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: () => c.aller('cfg-branding')),
            ]),
            const NoteSigh(cfaNoteAnciennesPieces, icone: LucideIcons.archive),
          ]);
        });
  }
}

/// `cfg-branding` : « Identité & papier à en-tête ». CFG-BRANDING ÉCRIT VRAIMENT (E2270 corrigé dans la maquette, porté ici : E2277). « Enregistrer » ne
/// faisait que journaliser et annoncer ; l'identité vit désormais dans la collection `identiteLegale`, par versions datées, et cet écran en écrit la part
/// VISIBLE (dénomination, sigle, slogan, logo, adresse, pays, téléphones, courriel). Les mentions FISCALES (forme, IFU, RCCM, autorisation, adresse fiscale,
/// devise, TVA) se saisissent et se VALIDENT à « Paramètres fiscaux » : c'est la MÊME fiche, chaque écran ses champs. Les options d'impression sont des
/// RÉGLAGES d'exploitation (`impression.doubleLogo`, `impression.filigrane`) lus par l'impression ; la case « pied de page normalisé » est retirée : le
/// pied est obligatoire (RG-12).
class EcranBranding extends StatefulWidget with EcranMaquette {
  const EcranBranding({super.key});
  @override
  String get titre => 'Identité & papier à en-tête';
  @override
  String get description => 'Paramétrage de l’identité visuelle et des coordonnées reprises sur tous les documents édités.';
  @override
  String get regle =>
      'Ces paramètres alimentent automatiquement tous les états imprimables : facture, ordonnance, bulletin de paie, bon de sortie, état comptable. Aucune mention légale n’est saisie document par document. L’identité est une donnée de référence datée : après validation, toute modification crée une version avec sa date d’effet.';

  @override
  State<EcranBranding> createState() => _EtatBranding();
}

class _EtatBranding extends State<EcranBranding> {
  bool _amorce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    ConfigurationFiscalePoste.amorcer(ContexteEcran.of(context).magasin);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final cf = ConfigurationFiscalePoste(c);
    return ListenableBuilder(
        listenable: Listenable.merge([cf.versions, c.magasin.collection('reglages')]),
        builder: (context, _) {
          final futures = cfbNoteVersionsAVenir(cf);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfbBandeauEtat(cf, identite: true, libelle: 'identité légale'),
            if (futures != null) ...[const SizedBox(height: 16), futures],
            const SizedBox(height: 16),
            LayoutBuilder(builder: (ctx, k) {
              final deux = k.maxWidth >= 1024;
              final gauche = cfaPile([
                _CarteIdentite(key: ValueKey('identite:${cf.identiteImprimee().version}'), cf: cf),
                const NoteSigh(
                    'Les mentions fiscales (forme juridique, IFU, RCCM, autorisation d’ouverture, adresse fiscale, devise, régime de TVA) se saisissent et se valident à l’écran Paramètres fiscaux : c’est la même fiche, chaque écran y écrit ses champs.',
                    icone: LucideIcons.landmark),
                Align(
                    alignment: Alignment.centerLeft,
                    child: BoutonSigh(
                        libelle: 'Paramètres fiscaux (IFU / RCCM) et validation',
                        icone: LucideIcons.arrowRight,
                        variante: VarianteBouton.secondaire,
                        taille: TailleBouton.sm,
                        onPressed: () => c.aller('cfg-fiscalite'))),
              ]);
              final droite = cfaPile([
                _CarteApercu(cf: cf),
                const _CarteRessources(),
                const NoteSigh('Les états produits reprennent la version de l’identité en force à la date de la pièce.', ton: TonSigh.succes, icone: LucideIcons.circleCheck)
              ]);
              if (!deux) return cfaPile([gauche, droite]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: gauche), const SizedBox(width: 16), Expanded(child: droite)]);
            }),
          ]);
        });
  }
}

/// Les champs que `cfg-branding` écrit (`CHAMPS_BRANDING`).
const List<String> champsBranding = ['nom', 'sigle', 'slogan', 'logo', 'adresse', 'pays', 'telephones', 'telephoneRdv', 'email'];

class _CarteIdentite extends StatefulWidget {
  const _CarteIdentite({super.key, required this.cf});
  final ConfigurationFiscalePoste cf;
  @override
  State<_CarteIdentite> createState() => _CarteIdentiteState();
}

class _CarteIdentiteState extends State<_CarteIdentite> {
  late final IdentiteImprimee _i = widget.cf.identiteImprimee();
  late final ControleurFormulaire _ctl = ControleurFormulaire([
    const ChampDef.section('Dénomination'),
    const ChampDef(nom: 'nom', libelle: 'Dénomination sociale', requis: true, col: ColChamp.plein),
    const ChampDef(nom: 'sigle', libelle: 'Sigle'),
    const ChampDef(nom: 'logo', libelle: 'Logo (chemin de la ressource)', aide: 'Un chemin de ressource, pas un fichier : le fichier se dépose dans « Ressources graphiques ».'),
    const ChampDef(nom: 'slogan', libelle: 'Devise ou slogan', col: ColChamp.plein),
    const ChampDef.section('Coordonnées'),
    const ChampDef(nom: 'adresse', libelle: 'Adresse géographique', col: ColChamp.plein),
    const ChampDef(nom: 'pays', libelle: 'Pays'),
    const ChampDef(nom: 'email', libelle: 'Adresse électronique', type: TypeChamp.email),
    const ChampDef(nom: 'telephones', libelle: 'Téléphones (séparés par « / »)', requis: true),
    const ChampDef(nom: 'telephoneRdv', libelle: 'Ligne rendez-vous'),
    const ChampDef.section('Options d’impression (réglages d’exploitation, lus par le moteur d’impression)'),
    const ChampDef(nom: 'doubleLogo', libelle: 'Logo de part et d’autre de la dénomination', type: TypeChamp.case_, col: ColChamp.plein),
    const ChampDef(nom: 'filigrane', libelle: 'Filigrane par défaut', type: TypeChamp.select, options: [OptionChamp('', ''), OptionChamp('Document officiel'), OptionChamp('Confidentiel')]),
  ], {
    'nom': _i.nom,
    'sigle': _i.sigle,
    'logo': _i.logo,
    'slogan': _i.slogan,
    'adresse': _i.adresse,
    'pays': _i.pays,
    'email': _i.email,
    'telephones': _i.telephones.join(' / '),
    'telephoneRdv': _i.telephoneRdv,
    'doubleLogo': cfbReglage(widget.cf.m, 'impression.doubleLogo', true) != false,
    'filigrane': '${cfbReglage(widget.cf.m, 'impression.filigrane', '') ?? ''}',
  });

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _enregistrer(BuildContext context) {
    final v = _ctl.valider();
    if (v == null) {
      ToastsSigh.afficher(context, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final cf = widget.cf;
    // Les options d'impression ne sont pas des champs de l'identité : des réglages, lus par l'impression. Un fileul ne les écrit pas non plus (garde du magasin).
    if (cfbRefuseSiGarde(context, () {
      cfbPoserReglage(cf.m, 'impression.doubleLogo', v['doubleLogo'] == true);
      cfbPoserReglage(cf.m, 'impression.filigrane', '${v['filigrane'] ?? ''}');
    })) return;
    cfbEnregistrerIdentiteDepuis(context, cf, 'cfg-branding', {for (final k in champsBranding) k: v[k]});
  }

  void _previsualiser(BuildContext context) {
    final j = widget.cf.identiteImprimee();
    cfaImprimer(context,
        titre: 'Aperçu du papier à en-tête',
        sousTitre: 'Modèle appliqué à tous les documents édités',
        blocs: [
          const BlocTexte(
              'Ce document illustre le gabarit officiel appliqué automatiquement à l’ensemble des états produits par le système : factures normalisées, ordonnances, bulletins de paie, bons de commande et de sortie, résultats de laboratoire, états comptables et rapports de direction.'),
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Mention', valeur: (l) => l['k']),
            ColonneEtat(libelle: 'Valeur', valeur: (l) => l['v']),
          ], lignes: [
            {'k': 'Dénomination', 'v': j.nom},
            {'k': 'Adresse postale', 'v': j.bp},
            {'k': 'Téléphones', 'v': j.telephones.join(' / ')},
            {'k': 'Adresse électronique', 'v': j.email},
            {'k': 'Autorisation d’ouverture', 'v': j.autorisation},
            {'k': 'IFU', 'v': j.ifu},
            {'k': 'RCCM', 'v': j.rccm},
          ])),
        ],
        signatures: const [Signature('La Directrice Administrative', nom: 'TAKI Alimatou')]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return CarteSigh(
        titre: 'Paramètres de l’identité (part visible)',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: _ctl),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            // Écrire l'identité est une écriture : la commande est ABSENTE sans le droit (la prévisualisation reste ouverte).
            if (c.droit.editer) BoutonSigh(key: const Key('cfa:branding:enregistrer'), libelle: 'Enregistrer', icone: LucideIcons.save, onPressed: () => _enregistrer(context)),
            BoutonSigh(libelle: 'Prévisualiser un état', icone: LucideIcons.eye, variante: VarianteBouton.secondaire, onPressed: () => _previsualiser(context)),
          ]),
        ]));
  }
}

class _CarteApercu extends StatelessWidget {
  const _CarteApercu({required this.cf});
  final ConfigurationFiscalePoste cf;

  Widget _logo() => Image.asset(CfaIdentite.logo, width: 48, height: 48, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 48));

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final i = cf.identiteImprimee();
    final doubleLogo = cfbReglage(cf.m, 'impression.doubleLogo', true) != false;
    const t = TextStyle(color: JetonsShell.slate700);
    return CarteSigh(
        titre: 'Aperçu du papier à en-tête (version ${i.version ?? 1} en force)',
        child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _logo(),
                const SizedBox(width: 16),
                Flexible(
                    child: Column(children: [
                  Text(i.nomCourt, key: const Key('cfa:apercu:nom'), style: const TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700, color: JetonsShell.navy950)),
                  Text('${i.bp} TÉL. : ${i.telephones.join(' / ')}', textAlign: TextAlign.center, style: t.copyWith(fontSize: 9)),
                  Text('AUTORISATION D’OUVERTURE ${i.autorisation}', textAlign: TextAlign.center, style: t.copyWith(fontSize: 8)),
                  Text('IFU : ${i.ifu}   RCCM : ${i.rccm}', textAlign: TextAlign.center, style: t.copyWith(fontSize: 8, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
                  Text('E-mail : ${i.email}', textAlign: TextAlign.center, style: t.copyWith(fontSize: 8)),
                  Text(i.slogan, key: const Key('cfa:apercu:slogan'), textAlign: TextAlign.center, style: t.copyWith(fontSize: 8, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: JetonsShell.navy800)),
                ])),
                const SizedBox(width: 16),
                if (doubleLogo) _logo() else const SizedBox(width: 48, height: 48),
              ]),
              const SizedBox(height: 8),
              Container(height: 2, color: JetonsShell.navy900),
              const SizedBox(height: 16),
              const Text('(corps du document)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic, color: JetonsShell.slate400)),
              const SizedBox(height: 16),
              Container(
                  padding: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate300))),
                  child: Text('${i.nom} : ${i.rccm} : IFU ${i.ifu} · Document généré par ${acteur(c).nom} le ${dateHeure(c.aujourdhui)} · Réf. CNT-XXXXXXXX-0001',
                      style: const TextStyle(fontSize: 8, color: JetonsShell.slate500))),
            ])));
  }
}

class _CarteRessources extends StatelessWidget {
  const _CarteRessources();

  static Widget _vignette(Fiche? f, String nom, bool fourni) {
    final donnees = f == null ? null : f['donnees'];
    if (fourni && donnees is String && donnees.startsWith('data:') && donnees.contains(',')) {
      try {
        return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(base64Decode(donnees.substring(donnees.indexOf(',') + 1)), width: 36, height: 36, fit: BoxFit.cover, semanticLabel: nom, errorBuilder: (_, __, ___) => const SizedBox(width: 36, height: 36)));
      } catch (_) {/* une donnée illisible n'empêche pas d'afficher la ligne */}
    }
    return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: fourni ? JetonsShell.success50 : JetonsShell.slate100, borderRadius: BorderRadius.circular(8)),
        child: Icon(fourni ? LucideIcons.image : LucideIcons.imageOff, size: 16, color: fourni ? JetonsShell.success600 : JetonsShell.slate400));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('ressources');
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final deposees = col.actives;
          final attendues = {for (final r in cfaRessourcesAttendues) r.$1};
          final lignes = <Widget>[];
          for (final r in cfaRessourcesAttendues) {
            lignes.add(_ligne(ctx, c, col, r.$1, r.$2, r.$3, [for (final x in deposees) if (x['type'] == r.$1) x]));
          }
          for (final x in deposees) {
            if (!attendues.contains(x['type'])) lignes.add(_ligne(ctx, c, col, '${x['type']}', '${x['libelle']}', 'Ressource ajoutée par la clinique', [x]));
          }
          return CarteSigh(
              titre: 'Ressources graphiques',
              actions: [
                if (c.droit.editer) BoutonSigh(libelle: 'Déposer une ressource', icone: LucideIcons.upload, taille: TailleBouton.sm, onPressed: () => _deposer(context, c, col, null, null)),
              ],
              child: cfaPile(lignes, espace: 8));
        });
  }

  Widget _ligne(BuildContext ctx, ContexteEcran c, CollectionMagasin col, String type, String nom, String usage, List<Fiche> fichiers) {
    final fourni = fichiers.isNotEmpty;
    final f = fourni ? fichiers.first : null;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
        child: Row(children: [
          _vignette(f, nom, fourni),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
            Text(fourni ? '${f!['fichier']} · ${cfaPoids(cfaNombre(f['taille']))} · déposé le ${cfaVrai(f['_creeLe']) ? dateFR(DateTime.parse('${f['_creeLe']}').toLocal()) : '—'}' : usage,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
          ])),
          if (fourni) ...[
            if (fichiers.length > 1) BadgeSigh('${fichiers.length} fichiers', ton: TonSigh.info),
            const SizedBox(width: 4),
            const BadgeSigh('Déposé', ton: TonSigh.succes),
            if (c.droit.editer) BoutonIcone(icone: LucideIcons.replace, libelle: 'Remplacer', onPressed: () => _deposer(ctx, c, col, type, f)),
            if (c.droit.annuler) BoutonIcone(icone: LucideIcons.trash2, libelle: 'Retirer', onPressed: () => _retirer(ctx, col, f!)),
          ] else ...[
            const BadgeSigh('À fournir', ton: TonSigh.attention),
            if (c.droit.editer) BoutonIcone(icone: LucideIcons.upload, libelle: 'Déposer', onPressed: () => _deposer(ctx, c, col, type, null)),
          ],
        ]));
  }

  Future<void> _retirer(BuildContext ctx, CollectionMagasin col, Fiche f) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Retirer « ${f['libelle']} » ?',
        message:
            'La ressource est archivée, non supprimée (RG-14) : elle reste restaurable depuis la corbeille. Les états édités après ce retrait ne la reprendront plus.',
        libelleOk: 'Retirer',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    final annuler = col.archiver(f['id']);
    ToastsSigh.afficher(ctx, 'Ressource retirée.', type: TypeToast.succes, annuler: annuler);
  }

  static const _extensions = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'webp': 'image/webp', 'svg': 'image/svg+xml'};

  /// Le dépôt : le fichier image est lu sur le poste et CONSERVÉ avec les données (aucune requête réseau). Le sélecteur de fichier natif n'est pas encore
  /// branché (écart E847) : le chemin du fichier se saisit.
  void _deposer(BuildContext ctx, ContexteEcran c, CollectionMagasin col, String? type, Fiche? remplace) {
    final attendue = cfaRessourcesAttendues.where((r) => r.$1 == type).firstOrNull;
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'libelle', libelle: 'Intitulé', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'type', libelle: 'Emploi', type: TypeChamp.select, requis: true, options: [for (final r in cfaRessourcesAttendues) OptionChamp(r.$1, r.$2), const OptionChamp('autre', 'Autre usage')]),
      const ChampDef(nom: 'usage', libelle: 'Où elle apparaît', col: ColChamp.plein),
      const ChampDef(
          nom: 'chemin',
          libelle: 'Fichier image',
          requis: true,
          col: ColChamp.plein,
          indicatif: '/chemin/vers/le/fichier.png',
          aide: 'PNG, JPEG, WebP ou SVG. Le chemin du fichier sur ce poste.'),
    ], {'libelle': attendue?.$2 ?? '', 'type': type ?? 'autre', 'usage': attendue?.$3 ?? ''});
    afficherModale<void>(ctx,
        titre: remplace != null ? 'Remplacer la ressource' : 'Déposer une ressource graphique',
        sousTitre: attendue?.$2,
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          const NoteSigh('Le fichier est conservé dans le poste, avec le reste des données : aucune requête réseau, conformément à la contrainte hors ligne de la clinique.'),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: remplace != null ? 'Remplacer' : 'Déposer',
                  icone: LucideIcons.upload,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final chemin = '${v['chemin']}'.trim();
                    final ext = chemin.contains('.') ? chemin.split('.').last.toLowerCase() : '';
                    final fichier = File(chemin);
                    // Refus nommés : un fichier qui n'existe pas, ou qui n'est pas une image, ne devient jamais une ressource.
                    if (!_extensions.containsKey(ext)) {
                      ToastsSigh.afficher(ctx, 'Choisir un fichier image (PNG, JPEG, WebP ou SVG).', type: TypeToast.attention);
                      return;
                    }
                    if (!fichier.existsSync()) {
                      ToastsSigh.afficher(ctx, 'Fichier introuvable : $chemin', type: TypeToast.attention);
                      return;
                    }
                    final octets = fichier.readAsBytesSync();
                    final fiche = <String, Object?>{
                      'libelle': v['libelle'],
                      'type': v['type'],
                      'usage': v['usage'],
                      'donnees': 'data:${_extensions[ext]};base64,${base64Encode(octets)}',
                      'fichier': chemin.split(Platform.pathSeparator).last,
                      'taille': octets.length,
                    };
                    if (remplace != null) col.archiver(remplace['id']);
                    col.inserer({'statut': 'actif', ...fiche, '_creePar': acteur(c).nom, '_creeLe': c.aujourdhui.toIso8601String()}, prefixe: 'RES');
                    fermer();
                    ToastsSigh.afficher(ctx, 'Ressource « ${v['libelle']} » enregistrée.', type: TypeToast.succes, detail: 'Elle alimentera les états imprimables.');
                  }),
            ]);
  }
}
