import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';

/// Le CANAL sonore du poste (`SIGH.notifications.audioDisponible` / `tester`). Le poste n'a pas de moteur de notification : ce sont les deux seules
/// questions que l'écran pose à la plateforme, et elles s'injectent (un test ne joue pas de son). Par défaut : Windows et macOS savent émettre le bip du
/// système ; ailleurs le canal est déclaré INDISPONIBLE — l'alerte visuelle demeure entière, le son n'est jamais un point de défaillance.
class CfbAudio {
  const CfbAudio._();
  static bool Function() disponible = () => Platform.isWindows || Platform.isMacOS;
  static Future<({bool joue, String? motif})> Function() tester = () async {
    if (!disponible()) return (joue: false, motif: 'Aucun périphérique audio détecté.');
    try {
      await SystemSound.play(SystemSoundType.alert);
      return (joue: true, motif: null);
    } catch (_) {
      return (joue: false, motif: 'Le système a refusé la lecture — réessayer.');
    }
  };
}

const _idParams = 'notificationsSon';
const _idCanaux = 'notificationsCanaux';

/// `cfg-notifications` — « Notifications » : le CANAL (visuel, son, profil sonore, temporisation) et la matrice des événements par canal. Ces réglages ne
/// touchent ni seuil, ni destinataire, ni priorité : COUPER LE SON NE COUPE PAS L'ALERTE (cloche, badge, message et historique continuent).
class EcranNotifications extends StatefulWidget with EcranMaquette {
  const EcranNotifications({super.key});
  @override
  String get titre => 'Notifications';
  @override
  String get description => 'Paramétrage des alertes adressées au personnel, par événement et par canal.';

  @override
  State<EcranNotifications> createState() => _EtatNotifications();
}

class _EtatNotifications extends State<EcranNotifications> {
  ControleurFormulaire? _ctlProfil, _ctlTempo;
  late Map<String, Map<String, bool>> _cases;
  bool _pret = false;

  Map<String, Object?> _params(ContexteEcran c) {
    final brut = cfbReglage(c.magasin, _idParams);
    return cfbParamsNotif(brut is Map ? brut.cast<String, Object?>() : null);
  }

  Map<String, Object?>? _canauxEnregistres(ContexteEcran c) {
    final b = cfbReglage(c.magasin, _idCanaux);
    return b is Map ? b.cast<String, Object?>() : null;
  }

  void _poser(ContexteEcran c, Map<String, Object?> patch) => cfbPoserReglage(c.magasin, _idParams, {..._params(c), ...patch});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    _pret = true;
    final c = ContexteEcran.of(context);
    final p = _params(c);
    _cases = {
      for (final n in cfbNotifications) n.id: cfbCanaux(n, _canauxEnregistres(c)),
    };
    _ctlProfil = ControleurFormulaire(
        [ChampDef(nom: 'profil', libelle: 'Profil sonore', type: TypeChamp.select, col: ColChamp.plein, options: [for (final x in cfbProfilsAudio) OptionChamp(x.$1, x.$2)])],
        {'profil': '${p['profil']}'});
    _ctlTempo = ControleurFormulaire(
        [ChampDef(nom: 'temporisation', libelle: 'Ne pas resonner la même alerte avant', type: TypeChamp.select, col: ColChamp.plein, options: [for (final t in cfbTemporisations) OptionChamp('${t.$1}', t.$2)])],
        {'temporisation': '${p['temporisation']}'});
    _ctlProfil!.addListener(() {
      final profil = '${_ctlProfil!['profil']}';
      if (profil != _params(c)['profil']) _poser(c, {'profil': profil});
    });
    _ctlTempo!.addListener(() {
      final tempo = int.tryParse('${_ctlTempo!['temporisation']}');
      if (tempo != null && tempo != _params(c)['temporisation']) _poser(c, {'temporisation': tempo});
    });
  }

  @override
  void dispose() {
    _ctlProfil?.dispose();
    _ctlTempo?.dispose();
    super.dispose();
  }

  Widget _bascule(ContexteEcran c, String cle, String libelle, String aide, bool valeur) => Tooltip(
        message: '$libelle$aide',
        child: InkWell(
            key: Key('cfb:notif:$cle'),
            onTap: () => _poser(c, {cle: !valeur}),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(value: valeur, onChanged: (v) => _poser(c, {cle: v == true}), activeColor: JetonsShell.navy900, visualDensity: VisualDensity.compact)),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(libelle, style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate800)),
                Text(aide, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
              ])),
            ])),
      );

  Widget _carteSon(BuildContext ctx, ContexteEcran c) {
    final p = _params(c);
    final dispo = CfbAudio.disponible();
    final son = p['son'] == true;
    final attente = 0; // le poste n'a pas de moteur d'alertes : la cloche reste à zéro (voir E887)
    return Container(
      decoration: decorationCarte(),
      padding: const EdgeInsets.all(20),
      child: cfaPile([
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Notifications & son', style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
            Text('Ces réglages gouvernent la façon dont une alerte se manifeste sur CE poste. Ils ne modifient ni les seuils, ni les destinataires, ni les priorités.',
                style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
          ])),
          const SizedBox(width: 12),
          dispo ? const BadgeSigh('Sonorisation disponible', ton: TonSigh.succes) : const BadgeSigh('Sonorisation indisponible', ton: TonSigh.attention),
        ]),
        if (!dispo)
          cfbNote(
              'Aucun périphérique audio n’a répondu. L’application continue normalement : la cloche, le badge, les messages et l’historique fonctionnent. La sonorisation est un canal secondaire, jamais un point de défaillance.',
              icone: LucideIcons.volumeX),
        LayoutBuilder(builder: (_, k) {
          final deux = k.maxWidth >= 768;
          final a = _bascule(c, 'visuel', 'Notifications visuelles',
              'Message à l’écran lorsqu’une alerte nouvelle apparaît. La cloche et le badge restent actifs même sans cette option.', p['visuel'] == true);
          final b = _bascule(c, 'son', 'Sons d’alerte', 'DÉSACTIVER LE SON NE DÉSACTIVE PAS L’ALERTE : cloche, badge, message et historique continuent de fonctionner.', son);
          return deux ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]) : cfaPile([a, b], espace: 12);
        }),
        // Sans son, le profil et la temporisation sont désactivés — ils ne gouvernent plus rien.
        IgnorePointer(
            key: const Key('cfb:notif:reglages-son'),
            ignoring: !son,
            child: Opacity(
                opacity: son ? 1 : 0.5,
                child: LayoutBuilder(builder: (_, k) {
                  final a = cfaPile([
                    FormulaireSigh(controleur: _ctlProfil!),
                    Text(cfbProfilAudio(p['profil']).$5, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
                  ], espace: 4);
                  final b = cfaPile([
                    FormulaireSigh(controleur: _ctlTempo!),
                    const Text('Une alerte persistante — un stock sous son seuil le reste des jours — ne doit pas sonner à chaque passage. L’alerte, elle, demeure entière.',
                        style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
                  ], espace: 4);
                  return k.maxWidth >= 768
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
                      : cfaPile([a, b], espace: 12);
                }))),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          BoutonSigh(
              libelle: 'Tester la sonorisation',
              icone: LucideIcons.volume2,
              variante: VarianteBouton.secondaire,
              onPressed: () async {
                final r = await CfbAudio.tester();
                if (!ctx.mounted) return;
                ToastsSigh.afficher(ctx, r.joue ? 'Son de test émis.' : 'Son de test non émis.',
                    type: r.joue ? TypeToast.succes : TypeToast.attention,
                    detail: r.joue ? 'Aucune alerte n’a été créée : ce test ne touche ni les données ni les workflows.' : r.motif);
              }),
          const Text('Ce test ne crée aucune notification métier et ne modifie aucune donnée.', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
        ]),
        cfbNote(cfbNoteAttente(attente), ton: attente > 0 ? 'warning' : 'success', icone: LucideIcons.bell),
      ]),
    );
  }

  Widget _matrice(BuildContext ctx, ContexteEcran c) {
    const tete = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: JetonsShell.slate500);
    Widget cel(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: w);
    Widget case_(Map<String, bool> etat, String canal, String id) => Center(
        child: Checkbox(
            key: Key('cfb:canal:$id:$canal'),
            value: etat[canal],
            activeColor: JetonsShell.navy900,
            onChanged: (v) => setState(() => etat[canal] = v == true)));
    return Table(
      columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2.2), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(1), 4: FlexColumnWidth(1.2)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50, border: Border(bottom: BorderSide(color: JetonsShell.slate200))), children: [
          cel(const Text('ÉVÉNEMENT DÉCLENCHEUR', style: tete)),
          cel(const Text('DESTINATAIRES', style: tete)),
          cel(const Center(child: Text('DANS L’APPLICATION', style: tete))),
          cel(const Center(child: Text('SMS', style: tete))),
          cel(const Center(child: Text('COURRIEL', style: tete))),
        ]),
        for (final n in cfbNotifications)
          TableRow(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate100))), children: [
            cel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.libelle, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
              Text(n.detail, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
            ])),
            cel(Text(n.destinataires, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate600))),
            case_(_cases[n.id]!, 'app', n.id),
            case_(_cases[n.id]!, 'sms', n.id),
            case_(_cases[n.id]!, 'mail', n.id),
          ]),
      ],
    );
  }

  void _enregistrer(BuildContext ctx, ContexteEcran c) {
    final actifs = cfbCanauxActifs(_cases.values);
    cfbPoserReglage(c.magasin, _idCanaux, {for (final e in _cases.entries) e.key: {...e.value}});
    c.magasin.journaliser('Modification', 'CFG', 'ParametrageNotifications', 'NOTIF', null, {'canauxActifs': actifs});
    ToastsSigh.afficher(ctx, 'Paramétrage enregistré.', type: TypeToast.succes, detail: '$actifs canal(aux) actif(s).');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: c.magasin.collection('reglages'),
        builder: (ctx, _) => cfaPile([
              _carteSon(ctx, c),
              cfaKpis(cfbKpisNotifications([for (final n in cfbNotifications) cfbCanaux(n, _canauxEnregistres(c))])),
              CarteSigh(
                  titre: 'Matrice des notifications',
                  sansRemplissage: true,
                  actions: [
                    if (c.droit.editer)
                      BoutonSigh(libelle: 'Enregistrer le paramétrage', icone: LucideIcons.save, taille: TailleBouton.sm, onPressed: () => _enregistrer(ctx, c)),
                  ],
                  child: _matrice(ctx, c)),
              cfbNote(
                  'Les envois par SMS et par courriel nécessitent une connexion Internet. En son absence, les notifications restent disponibles dans l’application et sont transmises dès le rétablissement de la liaison.',
                  ton: 'warning',
                  icone: LucideIcons.wifiOff),
            ]));
  }
}
