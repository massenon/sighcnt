import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';

/// Un écran du simulateur rendu depuis sa page : les champs, leur ordre, leurs cartes, leurs listes, leurs claviers et leurs exemples sont ceux que la
/// page a montrés dans Chrome (`mobChampsEcran`), jamais écrits ici. Sert la visite prénatale, la visite post-natale et la surveillance mère-bébé.
///
/// Le geste d'enregistrement est celui du service (`ServiceSuite`) : il refait le contrôle d'habilitation, refuse en nommant (code, motif, geste) et
/// écrit UNE opération. Un refus de champ s'affiche sous le champ ; un refus d'ensemble en carte de refus.
class FormulaireSuite extends StatefulWidget {
  const FormulaireSuite({super.key, required this.ecran, required this.enregistrer, this.sous, this.notes = const [], this.signalement});

  /// `cpn`, `cpon` ou `surveillance`.
  final String ecran;

  /// Le nom de la patiente (sous-titre de l'écran).
  final String? sous;

  /// Les notes posées en tête : âge à risque, grille unique de la surveillance.
  final List<String> notes;
  final Future<void> Function(Map<String, String> saisie) enregistrer;

  /// Un signalement à dire AVEC l'enregistrement (la grossesse à risque), ou `null`.
  final String? Function(Map<String, String> saisie)? signalement;

  @override
  State<FormulaireSuite> createState() => _FormulaireSuiteState();
}

class _FormulaireSuiteState extends State<FormulaireSuite> {
  late final List<MobChamp> _champs = mobChampsEcran(widget.ecran);
  late final Map<String, TextEditingController> _texte = {for (final c in _champs) if (!c.liste) c.id: TextEditingController()};
  late final Map<String, String> _choix = {for (final c in _champs) if (c.liste) c.id: c.options!.first};
  RefusMobile? _refus;

  Map<String, String> _saisie() => {for (final e in _texte.entries) e.key: e.value.text, ..._choix};

  Future<void> _enregistrer() async {
    final saisie = _saisie();
    try {
      await widget.enregistrer(saisie);
    } on RefusMobile catch (r) {
      setState(() => _refus = r);
      return;
    }
    if (!mounted) return;
    final signal = widget.signalement?.call(saisie);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(signal == null ? messageEnregistre : '$signal $messageEnregistre')));
    Navigator.of(context).pop();
  }

  Widget _champ(MobChamp c, Map<String, String> erreurs) {
    final libelle = c.requis ? '${c.libelle} *' : c.libelle;
    if (c.liste) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: Key('champ-${c.id}'),
          initialValue: _choix[c.id],
          isExpanded: true,
          decoration: InputDecoration(labelText: libelle, errorText: erreurs[c.id], border: const OutlineInputBorder()),
          items: [for (final o in c.options!) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => setState(() => _choix[c.id] = v ?? _choix[c.id]!),
        ),
      );
    }
    if (c.date) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: Key('champ-${c.id}'),
          controller: _texte[c.id],
          readOnly: true,
          decoration: InputDecoration(labelText: libelle, errorText: erreurs[c.id], border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.calendar_today_outlined)),
          onTap: () async {
            final maintenant = DateTime.now();
            final d = await showDatePicker(context: context, initialDate: maintenant, firstDate: maintenant.subtract(const Duration(days: 30)), lastDate: maintenant.add(const Duration(days: 730)));
            if (d != null) {
              _texte[c.id]!.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            }
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key('champ-${c.id}'),
        controller: _texte[c.id],
        keyboardType: c.decimal ? const TextInputType.numberWithOptions(decimal: true) : (c.numerique ? TextInputType.number : (c.saisie == 'tel' ? TextInputType.phone : null)),
        minLines: c.type == 'textarea' ? 3 : 1,
        maxLines: c.type == 'textarea' ? 3 : 1,
        decoration: InputDecoration(labelText: libelle, hintText: c.placeholder, errorText: erreurs[c.id], border: const OutlineInputBorder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final erreurs = _refus?.champs ?? const <String, String>{};
    // Les champs d'une même carte se suivent : la page les groupe sous le titre de la carte ; hors carte, ils sont posés tels quels.
    final corps = <Widget>[];
    String? section;
    var enCarte = <Widget>[];
    void fermer() {
      if (section != null && enCarte.isNotEmpty) corps.add(CarteTitre(titre: section, enfants: enCarte));
      enCarte = <Widget>[];
    }

    for (final c in _champs) {
      if (c.section != section) {
        fermer();
        section = c.section;
      }
      final w = _champ(c, erreurs);
      if (section == null) {
        corps.add(w);
      } else {
        enCarte.add(w);
      }
    }
    fermer();
    return Scaffold(
      appBar: AppBar(title: Text(mobTitreEcranSuite(widget.ecran)), bottom: widget.sous == null ? null : PreferredSize(preferredSize: const Size.fromHeight(24), child: Text(widget.sous!, style: const TextStyle(color: Colors.white)))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final n in widget.notes) NoteInfo(n),
        ...corps,
        if (_refus != null && _refus!.champs.isEmpty) CarteRefus(_refus!),
        const SizedBox(height: 8),
        FilledButton(key: const Key('enregistrer'), onPressed: _enregistrer, child: Text(mobBoutonEcran(widget.ecran))),
      ]),
    );
  }
}

/// Un écran fermé au profil : il se NOMME, il ne s'ouvre pas à moitié (le motif est celui de la page du simulateur).
class EcranFerme extends StatelessWidget {
  const EcranFerme({super.key, required this.ecran, required this.profil});
  final String ecran, profil;

  @override
  Widget build(BuildContext context) {
    final refus = mobRefusEcranFerme(profil, ecran);
    return Scaffold(
      appBar: AppBar(title: Text(mobLibelleEcran(ecran))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        CarteRefus(refus),
        const SizedBox(height: 12),
        OutlinedButton(key: const Key('retour-accueil'), onPressed: () => Navigator.of(context).pop(), child: const Text('Retour à l’accueil')),
      ]),
    );
  }
}
