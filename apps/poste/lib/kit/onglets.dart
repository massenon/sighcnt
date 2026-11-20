import 'package:flutter/material.dart';

import '../core/jetons_shell.dart';

class OngletDef {
  const OngletDef(
      {required this.id,
      required this.libelle,
      required this.construire,
      this.compte});
  final String id;
  final String libelle;
  final Widget Function(BuildContext) construire;
  final int? compte;
}

/// `U.tabs` : barre à filet bas (slate-200), onglet px 14 py 10, 14/20 en 500, filet de 2 px sous l'actif (navy-900) ;
/// le filet de l'onglet recouvre celui de la barre (`-mb-px`). L'ancre (`#onglet=`) devient `ancre`.
class OngletsSigh extends StatefulWidget {
  const OngletsSigh(
      {super.key, required this.onglets, this.ancre, this.alChangement});
  final List<OngletDef> onglets;
  final String? ancre;
  final ValueChanged<String>? alChangement;

  @override
  State<OngletsSigh> createState() => _OngletsSighState();
}

class _OngletsSighState extends State<OngletsSigh> {
  late String _actif;

  @override
  void initState() {
    super.initState();
    _actif = widget.onglets.any((o) => o.id == widget.ancre)
        ? widget.ancre!
        : widget.onglets.first.id;
  }

  void _choisir(String id) {
    if (id == _actif) return;
    setState(() => _actif = id);
    widget.alChangement?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final actif = widget.onglets.firstWhere((o) => o.id == _actif);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('kit:onglets-barre'),
            decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: JetonsShell.slate200))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final o in widget.onglets)
                  _Onglet(o, o.id == _actif, () => _choisir(o.id)),
              ]),
            ),
          ),
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: actif.construire(context)),
        ]);
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet(this.def, this.actif, this.surClic);
  final OngletDef def;
  final bool actif;
  final VoidCallback surClic;

  @override
  Widget build(BuildContext context) {
    final couleur = actif ? JetonsShell.navy900 : JetonsShell.slate500;
    return Semantics(
      selected: actif,
      button: true,
      label: def.libelle + (def.compte != null ? ', ${def.compte}' : ''),
      excludeSemantics: true,
      onTap: surClic,
      child: InkWell(
        key: Key('kit:onglet:${def.id}${actif ? ':actif' : ''}'),
        onTap: surClic,
        hoverColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: actif ? JetonsShell.navy900 : Colors.transparent,
                      width: 2))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(def.libelle,
                style: TextStyle(
                    color: couleur,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500)),
            if (def.compte != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: JetonsShell.slate100,
                    borderRadius: BorderRadius.circular(9999)),
                child: Text('${def.compte}',
                    style: const TextStyle(
                        color: JetonsShell.slate600,
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
