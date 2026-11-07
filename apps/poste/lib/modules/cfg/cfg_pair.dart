import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../sync/config_pair.dart';
import '../../sync/etat_pair.dart';
import '../../sync/recuperation_cle.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';

/// `cfg-pair` : le réglage de CE poste pour échanger ses opérations avec les autres par le relais (ADR-0006). Il écrit `pair.json` (adresse du relais, nom du
/// poste, code d'appairage à usage unique, activation) et porte la clé unique de la clinique : générée ici, affichée UNE SEULE FOIS, jamais relue. La
/// récupération de la clé par courriel est un réglage fermé par défaut, protégé par une phrase secrète que le poste ne garde pas.
class EcranPair extends StatefulWidget with EcranMaquette {
  const EcranPair({super.key});
  @override
  String get titre => 'Échanges entre postes (mode pair)';
  @override
  String get description => 'Réglage de ce poste pour échanger ses opérations avec les autres postes par le relais, sans passer par la mère.';
  @override
  String get regle =>
      'Les opérations sont chiffrées de bout en bout avec la clé unique de la clinique : le relais ne voit que des enveloppes. La clé ne s’affiche qu’une seule fois, à sa génération, et ne voyage jamais.';

  @override
  State<EcranPair> createState() => _EtatPair();
}

class _EtatPair extends State<EcranPair> {
  ControleurFormulaire? _config, _recup;
  String? _cleMontree;
  Map<String, Object?> _fichier = {};
  bool _pret = false;

  String? get _dossier => EtatPairPoste.dossier;

  void _relire() => _fichier = _dossier == null ? {} : ConfigPairPoste.lireBrut(_dossier!);

  ControleurFormulaire _formConfig() => ControleurFormulaire(const [
        ChampDef(nom: 'relais', libelle: 'Adresse du relais', requis: true, col: ColChamp.plein, aide: 'Exemple : https://relais.exemple.bj'),
        ChampDef(nom: 'nom', libelle: 'Nom de ce poste', requis: true),
        ChampDef(nom: 'code', libelle: 'Code d’appairage (usage unique)', aide: 'Délivré par le relais. Consommé au premier lancement, jamais gardé.'),
        ChampDef(nom: 'actif', libelle: 'Activer le mode pair sur ce poste', type: TypeChamp.case_, col: ColChamp.plein),
      ], {'relais': _fichier['relais'] ?? '', 'nom': _fichier['nom'] ?? '', 'actif': _fichier['actif'] == true});

  ControleurFormulaire _formRecup() {
    final c = ControleurFormulaire(const [
      ChampDef(nom: 'recuperation', libelle: 'Permettre la récupération de la clé par courriel', type: TypeChamp.case_, col: ColChamp.plein),
      ChampDef(nom: 'courriel', libelle: 'Adresse de courriel de récupération', type: TypeChamp.email, requis: true, condition: (controle: 'recuperation', quand: ['true'])),
      ChampDef(
          nom: 'phrase',
          libelle: 'Phrase secrète',
          type: TypeChamp.motDePasse,
          requis: true,
          aide: 'Chiffre la clé avant l’envoi. Le système ne la garde pas : la perdre rend la clé irrécupérable.',
          condition: (controle: 'recuperation', quand: ['true'])),
    ], {'recuperation': _fichier['recuperation'] == true, 'courriel': _fichier['courriel'] ?? ''});
    bool avant = c['recuperation'] == true;
    c.addListener(() {
      final maintenant = c['recuperation'] == true;
      if (maintenant == avant) return;
      avant = maintenant;
      if (_dossier != null) ConfigPairPoste.ecrire(_dossier!, recuperation: maintenant);
      _relire();
    });
    return c;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    _pret = true;
    _relire();
    _config = _formConfig();
    _recup = _formRecup();
  }

  @override
  void dispose() {
    _config?.dispose();
    _recup?.dispose();
    super.dispose();
  }

  bool get _cleGeneree => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch('${_fichier['cle'] ?? ''}');

  void _enregistrer(BuildContext ctx, ContexteEcran c) {
    final v = _config!.valider();
    if (v == null) {
      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final d = _dossier;
    if (d == null) {
      ToastsSigh.afficher(ctx, 'Le dossier des données de ce poste est inconnu : le réglage ne peut pas être enregistré.', type: TypeToast.erreur);
      return;
    }
    final relais = '${v['relais']}'.trim();
    if (!RegExp(r'^https?://[^\s/]+').hasMatch(relais)) {
      ToastsSigh.afficher(ctx, 'L’adresse du relais doit commencer par http:// ou https://.', type: TypeToast.erreur);
      return;
    }
    final actif = v['actif'] == true;
    if (actif && !_cleGeneree) {
      ToastsSigh.afficher(ctx, 'Générer d’abord la clé unique de la clinique : sans elle, aucune opération ne peut être chiffrée.', type: TypeToast.erreur);
      return;
    }
    final avant = _fichier['actif'] == true;
    final code = '${v['code'] ?? ''}'.trim();
    try {
      ConfigPairPoste.ecrire(d, actif: actif, relais: relais.replaceAll(RegExp(r'/+$'), ''), nom: '${v['nom']}'.trim(), code: code.isEmpty ? null : code);
    } on FormatException catch (e) {
      ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur);
      return;
    }
    c.magasin.journaliser('Modification', 'CFG', 'Mode pair', '${v['nom']}', {'actif': avant}, {'actif': actif, 'relais': relais});
    setState(_relire);
    ToastsSigh.afficher(ctx, 'Configuration enregistrée.', type: TypeToast.succes, detail: 'Elle prend effet au prochain lancement du poste.');
  }

  Future<void> _genererCle(BuildContext ctx, ContexteEcran c) async {
    final d = _dossier;
    if (d == null) {
      ToastsSigh.afficher(ctx, 'Le dossier des données de ce poste est inconnu : la clé ne peut pas être générée.', type: TypeToast.erreur);
      return;
    }
    if (_cleGeneree) {
      final ok = await confirmerSigh(ctx,
          titre: 'Générer une nouvelle clé ?',
          message: 'Les enveloppes déjà déposées au relais resteront chiffrées avec l’ancienne clé : tous les postes devront recevoir la nouvelle. Cette action ne peut pas être annulée.',
          libelleOk: 'Générer une nouvelle clé',
          dangereux: true);
      if (!ok || !ctx.mounted) return;
    }
    final cle = ConfigPairPoste.genererCle();
    final j = DateTime.now();
    ConfigPairPoste.ecrire(d, cleHex: cle, cleLe: '${j.year}-${j.month.toString().padLeft(2, '0')}-${j.day.toString().padLeft(2, '0')}');
    c.magasin.journaliser('Création', 'CFG', 'Clé du mode pair', 'clé de la clinique', null, {'generee': true});
    setState(() {
      _relire();
      _cleMontree = cle;
    });
  }

  Future<void> _envoyerCle(BuildContext ctx, ContexteEcran c) async {
    final v = _recup!.valider();
    if (v == null) {
      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final phrase = '${v['phrase']}';
    if (phrase.length < RecuperationCle.longueurMinimaleDePhrase) {
      ToastsSigh.afficher(ctx, 'La phrase secrète doit comporter au moins ${RecuperationCle.longueurMinimaleDePhrase} caractères.', type: TypeToast.erreur);
      return;
    }
    if (!_cleGeneree) {
      ToastsSigh.afficher(ctx, 'Aucune clé à envoyer : la générer d’abord.', type: TypeToast.erreur);
      return;
    }
    final courriel = '${v['courriel']}'.trim();
    if (_dossier != null) ConfigPairPoste.ecrire(_dossier!, courriel: courriel);
    final jeton = EtatPairPoste.jeton?.call();
    final relais = '${_fichier['relais'] ?? ''}';
    if (jeton == null || relais.isEmpty) {
      ToastsSigh.afficher(ctx, 'Adresse de récupération enregistrée, mais rien n’a été envoyé.',
          type: TypeToast.attention, detail: 'L’envoi passe par le relais : activer le mode pair et appairer ce poste d’abord (au prochain lancement).');
      return;
    }
    try {
      final coffre = await RecuperationCle.fabriquerCoffre('${_fichier['cle']}', phrase);
      await RecuperationCle.envoyer(relais: relais, jeton: jeton, courriel: courriel, coffre: coffre);
    } on StateError catch (e) {
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Le coffre n’a pas été envoyé.', type: TypeToast.erreur, detail: e.message);
      return;
    }
    c.magasin.journaliser('Modification', 'CFG', 'Récupération de la clé', courriel, null, {'envoi': 'coffre envoyé'});
    _recup!.poser('phrase', '');
    if (ctx.mounted) {
      ToastsSigh.afficher(ctx, 'Coffre envoyé par courriel.', type: TypeToast.succes, detail: 'Il est inutilisable sans votre phrase secrète, que ce poste ne garde pas.');
    }
  }

  Widget _carteCle(BuildContext ctx, ContexteEcran c) {
    final cle = _cleMontree;
    return CarteSigh(
        titre: 'Clé unique de la clinique',
        child: cfaPile([
          cfbNote('La clé est unique pour toute la clinique : tous les postes doivent porter la même. Notez-la ou copiez-la maintenant, elle ne sera plus affichée.',
              ton: 'warning', icone: LucideIcons.keyRound),
          if (cle != null) ...[
            SelectableText(cle, key: const Key('pair:cle'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              BoutonSigh(
                  libelle: 'Copier la clé',
                  icone: LucideIcons.copy,
                  variante: VarianteBouton.secondaire,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: cle));
                    if (ctx.mounted) ToastsSigh.afficher(ctx, 'Clé copiée.', type: TypeToast.succes);
                  }),
              BoutonSigh(libelle: 'J’ai noté la clé', icone: LucideIcons.check, onPressed: () => setState(() => _cleMontree = null)),
            ]),
          ] else ...[
            Text(
                _fichier['cle_illisible'] == true
                    ? 'La clé de la clinique est ILLISIBLE dans pair.json (fichier altéré, ou chiffré par un autre poste ou une autre session Windows). Restaurer le fichier ou générer une nouvelle clé.'
                    : _cleGeneree
                    ? 'La clé a été générée${_fichier['cle_le'] != null ? ' le ${_dateFr('${_fichier['cle_le']}')}' : ''}. Elle n’est plus affichée.'
                    : 'Aucune clé n’a encore été générée sur ce poste.',
                style: const TextStyle(fontSize: 14)),
            Align(
                alignment: Alignment.centerLeft,
                child: BoutonSigh(
                    key: const Key('pair:generer'),
                    libelle: _cleGeneree ? 'Générer une nouvelle clé' : 'Générer la clé',
                    icone: LucideIcons.keyRound,
                    variante: _cleGeneree ? VarianteBouton.danger : VarianteBouton.primaire,
                    onPressed: () => _genererCle(ctx, c))),
          ],
        ]));
  }

  static String _dateFr(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final source = EtatPairPoste.source;
    return ListenableBuilder(
        listenable: Listenable.merge([c.magasin.collection('conflitsPair'), _config!, _recup!, if (source != null) source]),
        builder: (ctx, _) {
          final inst = source?.value ?? const InstantanePair();
          final actif = _fichier['actif'] == true;
          final conflits = c.magasin.collection('conflitsPair').actives.length;
          final recup = _recup!['recuperation'] == true;
          final echanges = source == null
              ? 'Aucun (moteur non démarré)'
              : inst.cycles == 0
                  ? 'Aucun'
                  : '${inst.cycles} cycle(s), ${inst.horsLigne ? 'hors ligne' : 'en ligne'}';
          return cfaPile([
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Mode pair', valeur: actif ? 'Activé' : 'Désactivé', icone: LucideIcons.gitCompareArrows, ton: actif ? TonSigh.succes : TonSigh.neutre),
              KpiSigh(libelle: 'Appairage', valeur: inst.appaire ? 'Appairé' : 'Non appairé', icone: LucideIcons.link, ton: inst.appaire ? TonSigh.succes : TonSigh.attention),
              KpiSigh(libelle: 'Conflits à trancher', valeur: '$conflits', icone: LucideIcons.gitMerge, ton: conflits > 0 ? TonSigh.attention : TonSigh.neutre),
              KpiSigh(libelle: 'Opérations en attente', valeur: '${inst.enAttente}', icone: LucideIcons.cloudUpload, ton: TonSigh.neutre),
            ]),
            CarteSigh(
                titre: 'Configuration du mode pair',
                child: cfaPile([
                  FormulaireSigh(controleur: _config!),
                  if (c.droit.editer)
                    Align(alignment: Alignment.centerLeft, child: BoutonSigh(libelle: 'Enregistrer la configuration', icone: LucideIcons.save, onPressed: () => _enregistrer(ctx, c))),
                ])),
            if (c.droit.editer) _carteCle(ctx, c),
            CarteSigh(
                titre: 'Récupération de la clé par courriel',
                child: cfaPile([
                  cfbNote('Réglage fermé par défaut : tant qu’il l’est, la perte de la clé ne se rattrape que sur un autre poste de la clinique.', icone: LucideIcons.mail),
                  FormulaireSigh(controleur: _recup!),
                  if (recup && c.droit.editer) Align(alignment: Alignment.centerLeft, child: BoutonSigh(libelle: 'Envoyer la clé par courriel', icone: LucideIcons.send, onPressed: () => _envoyerCle(ctx, c))),
                ])),
            CarteSigh(
                titre: 'État du mode pair',
                child: DescListeSigh([
                  ('Relais', _fichier['relais'] ?? 'Non renseigné'),
                  ('Nom de ce poste', _fichier['nom'] ?? 'Non renseigné'),
                  ('Clé de la clinique', _fichier['cle_illisible'] == true ? 'Illisible' : (_cleGeneree ? 'Générée' : 'Absente')),
                  ('Derniers échanges', echanges),
                ])),
          ]);
        });
  }
}
