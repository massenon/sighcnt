import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'client_mere.dart';

/// CONSOLE DU POSTE MÈRE — DAF / administrateur (spec §13). Elle ne décide de rien : elle montre l'état que la mère
/// annonce et appelle les gestes que la mère accepte ; tout refus s'affiche avec la cause nommée par la mère.
/// Les conflits (qui contiennent des données de santé) s'arbitrent ICI et nulle part ailleurs : le panneau en ligne
/// n'en montre que le nombre.
class ConsoleMere extends StatefulWidget {
  const ConsoleMere({super.key, required this.client, this.intervalle = const Duration(seconds: 3), this.maintenant});
  final ClientMere client;
  final Duration intervalle;
  final DateTime Function()? maintenant;

  @override
  State<ConsoleMere> createState() => _ConsoleMereState();
}

class _ConsoleMereState extends State<ConsoleMere> {
  EtatMere? _etat;
  List<Conflit> _conflits = const [];
  Supervision? _sante;
  List<EvenementJournal> _journal = const [];
  String? _panne;
  Timer? _minuterie;
  // Les champs de la maintenance vivent dans l'état : la console se rafraîchit toutes les 3 s et ne doit pas vider la saisie.
  final TextEditingController _confirmation = TextEditingController();
  final TextEditingController _secondProfil = TextEditingController();

  DateTime _maintenant() => (widget.maintenant ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _actualiser();
    _minuterie = Timer.periodic(widget.intervalle, (_) => _actualiser());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    _confirmation.dispose();
    _secondProfil.dispose();
    super.dispose();
  }

  Future<void> _actualiser() async {
    try {
      final e = await widget.client.etat();
      final c = await widget.client.conflits();
      final sante = await widget.client.supervision();
      final j = await widget.client.journal();
      if (!mounted) return;
      setState(() {
        _etat = e;
        _conflits = c;
        _sante = sante;
        _journal = j;
        _panne = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _panne = 'Le service de la mère ne répond pas : $e');
    }
  }

  Future<void> _geste(Future<void> Function() f, {String? ok}) async {
    try {
      await f();
      if (ok != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: ThemeSigh.danger));
    }
    await _actualiser();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SIGH-CNT — Poste mère'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Supervision'),
            Tab(text: 'Appareils'),
            Tab(text: 'Conflits'),
            Tab(text: 'Journal'),
            Tab(text: 'Maintenance'),
          ]),
        ),
        body: Column(children: [
          if (_panne != null) MaterialBanner(content: Text(_panne!), backgroundColor: ThemeSigh.dangerFond, actions: const [SizedBox.shrink()]),
          Expanded(
            child: _etat == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [_supervision(_etat!), _appareils(_etat!), _conflitsVue(), _journalVue(), _maintenance(_etat!)]),
          ),
        ]),
      ),
    );
  }

  // --- Supervision ----------------------------------------------------------------------------------------------
  Widget _kpi(String titre, String valeur, {Color? couleur}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(titre.toUpperCase(), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(valeur, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: couleur)),
          ]),
        ),
      );

  Widget _supervision(EtatMere e) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 200, child: _kpi('Époque', '${e.epoch}')),
        SizedBox(width: 200, child: _kpi('Opérations', '${e.seqMax}')),
        SizedBox(width: 200, child: _kpi('Retard vers le relais', '${e.retardRelais}', couleur: e.retardRelais > 0 ? ThemeSigh.attention : ThemeSigh.succes)),
        SizedBox(width: 200, child: _kpi('Conflits ouverts', '${e.conflitsOuverts}', couleur: e.conflitsOuverts > 0 ? ThemeSigh.attention : ThemeSigh.succes)),
      ]),
      const SizedBox(height: 12),
      if (_sante != null) ..._santeVue(_sante!),
      if (e.restauration != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Restauration : ${e.restauration}')),
      const SizedBox(height: 20),
      Text('Alertes', style: Theme.of(context).textTheme.titleMedium),
      if (e.alertes.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucune alerte.')) else ...e.alertes.reversed.take(50).map((a) => ListTile(dense: true, leading: Icon(Icons.warning_amber, color: ThemeSigh.attention), title: Text(_libelleAlerte(a)), subtitle: Text('${a['appareil'] ?? ''}'))),
      const SizedBox(height: 12),
      if (e.derives.isNotEmpty) Text('Horloge à vérifier (dérive > 2 min) : ${e.derives.length} appareil(s)'),
      if (e.bloques.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Appareils bloqués', style: Theme.of(context).textTheme.titleMedium),
        ...e.bloques.map((u) => ListTile(dense: true, title: Text(u), trailing: TextButton(onPressed: () => _geste(() => widget.client.debloquer(u), ok: 'Appareil débloqué.'), child: const Text('Débloquer')))),
      ],
    ]);
  }

  Color _couleurEtat(String etat) => switch (etat) {
        'ok' => ThemeSigh.succes,
        'attention' => ThemeSigh.attention,
        'alerte' => ThemeSigh.danger,
        _ => Colors.grey,
      };

  String _libelleEtat(String etat) => switch (etat) {
        'ok' => 'OK',
        'attention' => 'À surveiller',
        'alerte' => 'ALERTE',
        _ => 'Inconnu',
      };

  List<Widget> _santeVue(Supervision s) => [
        Row(children: [
          Icon(Icons.circle, size: 14, color: _couleurEtat(s.etat), key: const Key('sante-globale')),
          const SizedBox(width: 8),
          Text('Santé de la mère : ${_libelleEtat(s.etat)}', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton.icon(
            key: const Key('sauvegarder'),
            onPressed: () => _geste(widget.client.sauvegarderMaintenant, ok: 'Sauvegarde chiffrée effectuée.'),
            icon: const Icon(Icons.save_alt),
            label: const Text('Sauvegarder maintenant'),
          ),
        ]),
        ...s.controles.map((c) => ListTile(
              dense: true,
              leading: Icon(Icons.circle, size: 12, color: _couleurEtat(c.etat)),
              title: Text(c.nom),
              subtitle: Text(c.detail),
              trailing: Text(_libelleEtat(c.etat)),
            )),
      ];

  Widget _journalVue() {
    if (_journal.isEmpty) return const Center(child: Text('Aucun évènement enregistré.'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _journal
          .map((x) => ListTile(
                dense: true,
                leading: Icon(x.niveau == 'erreur' ? Icons.error_outline : x.niveau == 'alerte' ? Icons.warning_amber : Icons.info_outline,
                    color: x.niveau == 'erreur' ? ThemeSigh.danger : x.niveau == 'alerte' ? ThemeSigh.attention : null),
                title: Text(x.message),
                subtitle: Text('${x.source} · ${x.quand.toLocal().toString().substring(0, 19)}'),
              ))
          .toList(),
    );
  }

  String _libelleAlerte(Map<String, Object?> a) => switch (a['type']) {
        'authentification' => 'Enveloppe altérée : authentification échouée (rang ${a['n']})',
        'trou' => 'Enveloppe manquante : attendu le rang ${a['attendu']}, reçu ${a['recu']}',
        'appareil_inconnu' => 'Appareil inconnu ou code invalide',
        'revocation_relais_differee' => 'Révocation à répercuter au relais',
        final t => '$t',
      };

  // --- Appareils --------------------------------------------------------------------------------------------------
  String _depuis(DateTime? d) {
    if (d == null) return 'jamais';
    final s = _maintenant().difference(d).inSeconds;
    if (s < 60) return 'il y a $s s';
    if (s < 3600) return 'il y a ${s ~/ 60} min';
    return 'il y a ${s ~/ 3600} h';
  }

  Widget _appareils(EtatMere e) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, children: [
        FilledButton.icon(onPressed: () => _appairer(mobile: false), icon: const Icon(Icons.computer), label: const Text('Appairer un poste')),
        OutlinedButton.icon(onPressed: () => _appairer(mobile: true), icon: const Icon(Icons.phone_android), label: const Text('Appairer un mobile')),
      ]),
      const SizedBox(height: 12),
      if (e.appareils.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aucun appareil appairé.')),
      ...e.appareils.map((a) => Card(
            child: ListTile(
              leading: Icon(a.role == 'mobile' ? Icons.phone_android : Icons.computer),
              title: Text(a.etiquette.isEmpty ? a.uuid : a.etiquette),
              subtitle: Text('${a.role} · dernier contact ${_depuis(a.dernierContact)} · retard : ${e.seqMax - a.derniereSeq} op.${e.derives.contains(a.uuid) ? ' · HORLOGE À VÉRIFIER' : ''}'),
              trailing: a.revoque
                  ? Chip(label: const Text('Révoqué'), backgroundColor: ThemeSigh.dangerFond)
                  : TextButton(onPressed: () => _revoquer(a), child: Text('Révoquer', style: TextStyle(color: ThemeSigh.danger))),
            ),
          )),
    ]);
  }

  Future<void> _revoquer(Appareil a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Révoquer cet appareil ?'),
        content: Text('« ${a.etiquette.isEmpty ? a.uuid : a.etiquette} » ne pourra plus synchroniser. Ses données locales sont conservées (poste) ou effacées à son prochain contact (mobile).'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Révoquer'))],
      ),
    );
    if (ok == true) await _geste(() => widget.client.revoquer(a.uuid), ok: 'Appareil révoqué.');
  }

  Future<void> _appairer({required bool mobile}) async {
    final nom = TextEditingController();
    final etiquette = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(mobile ? 'Appairer un mobile' : 'Appairer un poste'),
        content: TextField(controller: nom, autofocus: true, decoration: const InputDecoration(labelText: 'Nom de l’appareil (ex. Réception, Dr Yeni)')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(c, nom.text.trim()), child: const Text('Générer le code'))],
      ),
    );
    if (etiquette == null || etiquette.isEmpty) return;
    try {
      final String code;
      String? cle;
      if (mobile) {
        final r = await widget.client.codeMobile(etiquette);
        code = r.code;
        cle = r.cle;
      } else {
        code = await widget.client.codeAppareil(etiquette);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Code d’appairage'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 4)),
            const Text('À usage unique, valable 15 minutes.'),
            if (cle != null) ...[
              const SizedBox(height: 12),
              const Text('Clé de la clinique à saisir sur le téléphone (ne jamais l’envoyer par messagerie) :'),
              SelectableText(cle, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))],
        ),
      );
      await _actualiser();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: ThemeSigh.danger));
    }
  }

  // --- Conflits ----------------------------------------------------------------------------------------------------
  Widget _conflitsVue() {
    if (_conflits.isEmpty) return const Center(child: Text('Aucun conflit à régulariser.'));
    return ListView(padding: const EdgeInsets.all(16), children: _conflits.map((c) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.estDoublon ? 'Doublon possible — ${c.collection}' : 'Conflit — ${c.collection} · champ « ${c.champ} »', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (c.estDoublon) Text('Fiche existante : ${c.a}\nFiche créée : ${c.b}\nLe code patient attribué ne change jamais (RG-01) ; une fusion se fait par une nouvelle opération.')
            else Text('Version A (déjà enregistrée) : ${c.a}\nVersion B (proposée) : ${c.b}'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => _geste(() => widget.client.trancher(c.id, 'a'), ok: c.estDoublon ? 'Classé sans fusion.' : 'Version A conservée.'), child: Text(c.estDoublon ? 'Classer sans fusion' : 'Garder A')),
              if (!c.estDoublon) FilledButton(onPressed: () => _geste(() => widget.client.trancher(c.id, 'b'), ok: 'Version B retenue.'), child: const Text('Garder B')),
            ]),
          ]),
        ),
      );
    }).toList());
  }

  // --- Maintenance ------------------------------------------------------------------------------------------------------
  Widget _maintenance(EtatMere e) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: ListTile(
          title: const Text('Renvoyer vers tous les postes'),
          subtitle: const Text('Chaque poste fait un tirage complet de son périmètre et l’acquitte ; un poste éteint acquittera à sa reconnexion.'),
          trailing: FilledButton(onPressed: () => _geste(widget.client.renvoyerATous, ok: 'Demande déposée.'), child: const Text('Renvoyer')),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Réinitialiser les données de test', style: Theme.of(context).textTheme.titleMedium),
            const Text('Vide l’activité (patients, factures, stocks mouvementés…) et conserve ce qui fait fonctionner le logiciel (référentiels, comptes, droits, tarifs). Une sauvegarde préalable est toujours faite. La commande n’est disponible que pendant une fenêtre ouverte par l’administrateur.'),
            SwitchListTile(value: e.reinitOuverte, onChanged: (v) => _geste(() => widget.client.ouvrirFenetreReinit(v)), title: const Text('Fenêtre de réinitialisation ouverte')),
            if (e.reinitOuverte) ...[
              TextField(controller: _confirmation, decoration: const InputDecoration(labelText: 'Tapez le nom de la clinique pour confirmer')),
              TextField(controller: _secondProfil, decoration: const InputDecoration(labelText: 'Second profil confirmant (DAF ou Direction)')),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: ThemeSigh.danger),
                onPressed: () => _geste(() async {
                  final sauv = await widget.client.reinitialiser(confirmation: _confirmation.text, second: _secondProfil.text);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Réinitialisé. Sauvegarde : $sauv')));
                }),
                child: const Text('Réinitialiser'),
              ),
            ] else
              const Text('Fenêtre fermée : la commande est absente, pas grisée.', style: TextStyle(fontStyle: FontStyle.italic)),
          ]),
        ),
      ),
    ]);
  }
}
