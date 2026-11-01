import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/theme.dart';

/// Le pavé du code PIN : douze touches dans l'ordre de la page du simulateur (chiffres, un vide, 0, effacer), quatre points pleins au fur et à mesure.
class PavePin extends StatelessWidget {
  const PavePin({super.key, required this.points, required this.message, required this.touche, this.invite, this.activ = true});
  final int points;
  final String message;
  final String? invite;
  final bool activ;
  final void Function(String touche) touche;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline, size: 40, color: ThemeSigh.navy),
        const SizedBox(height: 12),
        if (invite != null) Text(invite!, key: const Key('pin-invite'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < mobPinLongueur; i++)
            Container(
              key: Key(i < points ? 'point-plein-$i' : 'point-vide-$i'),
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ThemeSigh.navy), color: i < points ? ThemeSigh.navy : null),
            ),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 24, child: Text(message, key: const Key('pin-message'), textAlign: TextAlign.center, style: TextStyle(color: ThemeSigh.danger))),
        const SizedBox(height: 8),
        SizedBox(
          width: 300,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final k in mobPinPave)
                if (k.isEmpty)
                  const SizedBox.shrink()
                else
                  OutlinedButton(
                    key: Key(k == '⌫' ? 'touche-effacer' : 'touche-$k'),
                    onPressed: activ ? () => touche(k) : null,
                    child: Text(k, style: const TextStyle(fontSize: 22)),
                  ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// L'écran « Code PIN ». La règle est celle de la page (`MobPin`) ; le code est vérifié par le coffre, jamais gardé ici.
class EcranPin extends StatefulWidget {
  const EcranPin({super.key, required this.pin, required this.ouvrir, this.horloge});
  final MobPin pin;
  final VoidCallback ouvrir;
  final DateTime Function()? horloge;

  @override
  State<EcranPin> createState() => _EcranPinState();
}

class _EcranPinState extends State<EcranPin> {
  Timer? _minuterie;
  MobPinEtat _etat = const MobPinEtat();

  DateTime _maintenant() => (widget.horloge ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(widget.pin.charger().then(_pose));
  }

  /// Retient l'état et, tant que le téléphone est bloqué, arme UNE échéance : le blocage de 30 s se lève de lui-même, sans quoi le message resterait
  /// affiché après l'échéance. Hors blocage aucune minuterie ne tourne.
  void _pose(MobPinEtat e) {
    if (!mounted) return;
    _minuterie?.cancel();
    if (e.bloque(_maintenant())) {
      _minuterie = Timer(Duration(seconds: e.secondesRestantes(_maintenant())) + const Duration(milliseconds: 100), () async => _pose(await widget.pin.actualiser()));
    }
    setState(() => _etat = e);
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _touche(String k) async {
    final e = await widget.pin.touche(k);
    _pose(e);
    if (e.deverrouille && mounted) widget.ouvrir();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(mobPinTitre)),
      body: Center(child: SingleChildScrollView(child: PavePin(points: _etat.points, message: _etat.message, invite: mobPinInvite, touche: _touche))),
    );
  }
}

/// Premier lancement : choisir le code, deux fois. Cet écran n'est PAS dans le simulateur (qui fixe 1234 pour la démonstration) : le texte est une
/// proposition (E1657).
class EcranDefinirPin extends StatefulWidget {
  const EcranDefinirPin({super.key, required this.coffre, required this.termine});
  final CoffrePin coffre;
  final VoidCallback termine;

  @override
  State<EcranDefinirPin> createState() => _EcranDefinirPinState();
}

class _EcranDefinirPinState extends State<EcranDefinirPin> {
  String _saisie = '', _premier = '', _message = '';

  Future<void> _touche(String k) async {
    var s = _saisie;
    if (k == '⌫') {
      s = s.isEmpty ? '' : s.substring(0, s.length - 1);
    } else if (RegExp(r'^\d$').hasMatch(k) && s.length < mobPinLongueur) {
      s += k;
    }
    if (s.length < mobPinLongueur) {
      setState(() => _saisie = s);
      return;
    }
    if (_premier.isEmpty) {
      setState(() {
        _premier = s;
        _saisie = '';
        _message = '';
      });
      return;
    }
    try {
      await MobPin.definir(widget.coffre, _premier, s);
    } on RefusMobile catch (r) {
      setState(() {
        _premier = '';
        _saisie = '';
        _message = '${r.motif} ${r.geste}.';
      });
      return;
    }
    widget.termine();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(mobPinTitre)),
      body: Center(
        child: SingleChildScrollView(
          child: PavePin(points: _saisie.length, message: _message, invite: _premier.isEmpty ? 'Choisissez un code à 4 chiffres.' : 'Saisissez le même code une seconde fois.', touche: _touche),
        ),
      ),
    );
  }
}

/// Garde du verrou : le téléphone démarre VERROUILLÉ, se reverrouille après le délai d'inactivité de la page des réglages (5 minutes) et au retour de
/// l'arrière-plan passé ce délai. L'écran en dessous reste monté (la saisie en cours n'est pas perdue). Sans [coffre], aucun verrou : c'est le cas des
/// tests d'écran, jamais celui de l'application (`main`).
class GardeVerrou extends StatefulWidget {
  const GardeVerrou({super.key, required this.coffre, required this.child, this.delai, this.horloge});
  final CoffrePin? coffre;
  final Widget child;
  final Duration? delai;
  final DateTime Function()? horloge;

  @override
  State<GardeVerrou> createState() => _GardeVerrouState();
}

class _GardeVerrouState extends State<GardeVerrou> with WidgetsBindingObserver {
  Timer? _inactivite;
  bool _verrouille = true;
  bool? _aCode;
  DateTime? _quitteLe;
  late MobPin _pin = MobPin(widget.coffre ?? CoffrePinMemoire(), horloge: widget.horloge);

  Duration get _delai => widget.delai ?? mobDelaiVerrouInactivite;
  DateTime _maintenant() => (widget.horloge ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.coffre == null) {
      _verrouille = false;
    } else {
      unawaited(widget.coffre!.aUnCode().then((a) {
        if (mounted) setState(() => _aCode = a);
      }));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivite?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (widget.coffre == null) return;
    if (etat == AppLifecycleState.paused || etat == AppLifecycleState.inactive) {
      _quitteLe ??= _maintenant();
    } else if (etat == AppLifecycleState.resumed) {
      final parti = _quitteLe;
      _quitteLe = null;
      if (parti != null && _maintenant().difference(parti) >= _delai) _verrouiller();
    }
  }

  void _verrouiller() {
    if (!mounted || widget.coffre == null) return;
    _inactivite?.cancel();
    setState(() {
      _pin = MobPin(widget.coffre!, horloge: widget.horloge);
      _verrouille = true;
    });
  }

  void _activite() {
    if (widget.coffre == null || _verrouille) return;
    _inactivite?.cancel();
    _inactivite = Timer(_delai, _verrouiller);
  }

  void _ouvrir() {
    setState(() => _verrouille = false);
    _activite();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coffre == null) return widget.child;
    final Widget verrou;
    if (_aCode == null) {
      verrou = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (!_aCode!) {
      verrou = EcranDefinirPin(
          coffre: widget.coffre!,
          termine: () => setState(() {
                _aCode = true;
                _verrouille = false;
                _activite();
              }));
    } else {
      verrou = EcranPin(key: ValueKey(_pin), pin: _pin, ouvrir: _ouvrir, horloge: widget.horloge);
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activite(),
      onPointerMove: (_) => _activite(),
      child: Stack(children: [
        Offstage(offstage: _verrouille, child: TickerMode(enabled: !_verrouille, child: widget.child)),
        if (_verrouille) Positioned.fill(child: verrou),
      ]),
    );
  }
}
