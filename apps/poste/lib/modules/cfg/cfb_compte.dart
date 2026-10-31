import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/commun_m14.dart' show initiales, libelleRole;
import 'cfa_commun.dart';
import 'cfb_commun.dart';
import 'cfb_perimetre.dart';

/// `cfg-compte` — « Mon compte » : l'identité de l'agent connecté, la sécurité de SON compte (mot de passe, authentification à deux facteurs), son périmètre
/// d'accès (les modules que son rôle ouvre) et son activité récente. Le mot de passe est SAISI, il n'est jamais gardé : seul le geste est journalisé.
class EcranCompte extends StatefulWidget with EcranMaquette {
  const EcranCompte({super.key});
  @override
  String get titre => 'Mon compte';
  @override
  String get description => 'Informations personnelles, sécurité du compte et préférences d’affichage.';

  @override
  State<EcranCompte> createState() => _EtatCompte();
}

class _EtatCompte extends State<EcranCompte> {
  ControleurFormulaire? _identite, _contact, _securite;
  String _nom = '';
  bool _pret = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    _pret = true;
    final c = ContexteEcran.of(context);
    _nom = c.utilisateur;
    _identite = ControleurFormulaire(const [ChampDef(nom: 'nom', libelle: 'Nom et prénoms', requis: true, col: ColChamp.plein)], {'nom': _nom});
    _contact = ControleurFormulaire(const [
      ChampDef(nom: 'telephone', libelle: 'Téléphone', type: TypeChamp.tel),
      ChampDef(nom: 'email', libelle: 'Adresse électronique', type: TypeChamp.email),
    ]);
    _securite = ControleurFormulaire(const [
      ChampDef(nom: 'actuel', libelle: 'Mot de passe actuel', type: TypeChamp.motDePasse, requis: true),
      ChampDef(nom: 'nouveau', libelle: 'Nouveau mot de passe', type: TypeChamp.motDePasse, requis: true),
      ChampDef(nom: 'confirmation', libelle: 'Confirmer le nouveau mot de passe', type: TypeChamp.motDePasse, requis: true),
      ChampDef(nom: 'mfa', libelle: 'Activer l’authentification à deux facteurs', type: TypeChamp.case_, col: ColChamp.plein),
    ], {'mfa': cfbMfaParDefaut(c.role)});
  }

  @override
  void dispose() {
    _identite?.dispose();
    _contact?.dispose();
    _securite?.dispose();
    super.dispose();
  }

  /// L'identifiant de connexion : celui du compte qui porte ce rôle, « admin.systeme » à défaut (la maquette fait de même).
  String _identifiant(ContexteEcran c) {
    final u = c.magasin.collection('utilisateurs').actives.where((x) => x['role'] == c.role && cfaVrai(x['identifiant'])).firstOrNull;
    return u != null ? '${u['identifiant']}' : 'admin.systeme';
  }

  /// Un champ en LECTURE SEULE (`readonly: true` de la maquette) : sa valeur se lit, elle ne se saisit pas.
  Widget _champLecture(String libelle, String valeur) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(libelle, style: const TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600))),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate300)),
            child: Text(valeur, style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate500))),
      ]);

  void _enregistrer(BuildContext ctx, ContexteEcran c) {
    final v = _identite!.valider();
    if (v == null) return; // le formulaire dit lui-même quel champ manque (la maquette ne parle pas non plus)
    final avant = _nom;
    final nom = '${v['nom']}'.trim();
    c.magasin.utilisateur = nom;
    c.magasin.journaliser('Modification', 'CFG', 'Compte', _identifiant(c), {'nom': avant}, {'nom': nom});
    setState(() => _nom = nom);
    ToastsSigh.afficher(ctx, 'Informations enregistrées.', type: TypeToast.succes);
  }

  void _modifierMotDePasse(BuildContext ctx, ContexteEcran c) {
    final v = _securite!.valider();
    if (v == null) {
      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final refus = cfbRefusMotDePasse('${v['nouveau']}', '${v['confirmation']}');
    if (refus != null) {
      ToastsSigh.afficher(ctx, refus, type: TypeToast.erreur);
      return;
    }
    // Le secret n'entre jamais au magasin ni au journal : seule la MODIFICATION est tracée (RG-12).
    c.magasin.journaliser('Modification', 'M14', 'Utilisateur', _identifiant(c), null, {'motDePasse': 'modifié'});
    for (final k in const ['actuel', 'nouveau', 'confirmation']) {
      _securite!.poser(k, '');
    }
    ToastsSigh.afficher(ctx, 'Mot de passe modifié.', type: TypeToast.succes);
  }

  Widget _perimetre(ContexteEcran c) {
    Widget badges(List<CfbRangeeRoles> r) =>
        Wrap(spacing: 4, runSpacing: 4, children: [for (final code in cfbPerimetre(c.magasin, c.role, r)) BadgeSigh(code, ton: TonSigh.navy)]);
    final prete = cfbRangeesRolesChargees;
    if (prete != null) return badges(prete);
    return FutureBuilder<List<CfbRangeeRoles>>(
        future: cfbChargerRangeesRoles(),
        builder: (ctx, snap) => snap.hasData ? badges(snap.data!) : const SizedBox(height: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
  }

  Widget _chronologie(ContexteEcran c) {
    final lignes = [for (final a in c.magasin.collection('audit').toutes) if (a['utilisateur'] == _nom) a].take(6).toList();
    if (lignes.isEmpty) return const VideSigh('Aucun événement enregistré.', icone: LucideIcons.history);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final a in lignes)
        Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(margin: const EdgeInsets.only(top: 5, right: 10), width: 10, height: 10, decoration: const BoxDecoration(color: JetonsShell.navy500, shape: BoxShape.circle)),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['action']} — ${a['entite']}', style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
                Text('Module ${a['module']}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
                Text(secHorodatage(a['dateHeure']) == null ? '' : secIlYA(secHorodatage(a['dateHeure'])!, c.aujourdhui), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
              ])),
            ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: c.magasin.collection('audit'),
        builder: (ctx, _) {
          final principal = cfaPile([
            CarteSigh(
                titre: 'Informations personnelles',
                child: cfaPile([
                  FormulaireSigh(controleur: _identite!),
                  LayoutBuilder(builder: (_, k) {
                    final a = _champLecture('Identifiant de connexion', _identifiant(c));
                    final b = _champLecture('Poste', libelleRole(c.magasin, c.role));
                    return k.maxWidth >= 640
                        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)])
                        : cfaPile([a, b]);
                  }),
                  FormulaireSigh(controleur: _contact!),
                  Align(alignment: Alignment.centerLeft, child: BoutonSigh(libelle: 'Enregistrer', icone: LucideIcons.save, onPressed: () => _enregistrer(ctx, c))),
                ])),
            CarteSigh(
                titre: 'Sécurité du compte',
                child: cfaPile([
                  FormulaireSigh(controleur: _securite!),
                  cfbNote('Politique en vigueur : 12 caractères minimum, majuscules, minuscules, chiffre et caractère spécial, renouvellement tous les 90 jours, verrouillage après trois tentatives infructueuses.'),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: BoutonSigh(libelle: 'Modifier le mot de passe', icone: LucideIcons.keyRound, onPressed: () => _modifierMotDePasse(ctx, c))),
                ])),
          ]);
          final lateral = cfaPile([
            CarteSigh(
                child: Column(children: [
              Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: JetonsShell.navy900, shape: BoxShape.circle),
                  child: Text(initiales(_nom), style: const TextStyle(fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600, color: Colors.white))),
              const SizedBox(height: 12),
              Text(_nom, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate900)),
              Text(libelleRole(c.magasin, c.role), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
              const SizedBox(height: 12),
              const BadgeSigh('Compte actif', ton: TonSigh.succes),
            ])),
            CarteSigh(
                titre: 'Périmètre d’accès',
                actions: [cfbLien(c, 'm14-roles', 'Matrice RBAC')],
                child: _perimetre(c)),
            CarteSigh(titre: 'Activité récente', child: _chronologie(c)),
          ]);
          return LayoutBuilder(
              builder: (_, k) => k.maxWidth >= 1024
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 2, child: principal), const SizedBox(width: 16), Expanded(child: lateral)])
                  : cfaPile([principal, lateral]));
        });
  }
}
