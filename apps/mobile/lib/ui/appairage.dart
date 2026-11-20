import 'package:flutter/material.dart';

import '../moteur/moteur_mobile.dart';

/// Appairage : code à usage unique + clé de clinique (scannée par QR sur le vrai téléphone, collée ici) + nom de l'agent. Le profil et la fonction viennent du code.
class EcranAppairage extends StatefulWidget {
  const EcranAppairage({super.key, required this.moteur, required this.apres});
  final MoteurMobile moteur;
  final VoidCallback apres;

  @override
  State<EcranAppairage> createState() => _EcranAppairageState();
}

class _EcranAppairageState extends State<EcranAppairage> {
  final _code = TextEditingController();
  final _cle = TextEditingController();
  final _agent = TextEditingController();
  String? _erreur;
  bool _en = false;

  Future<void> _valider() async {
    if (_code.text.trim().isEmpty || _cle.text.trim().isEmpty) {
      setState(() => _erreur = 'Le code d’appairage et la clé de clinique sont obligatoires.');
      return;
    }
    if (_agent.text.trim().isEmpty) {
      setState(() => _erreur = 'Le nom de l’agent est obligatoire : aucune action anonyme (RG-12).');
      return;
    }
    setState(() {
      _en = true;
      _erreur = null;
    });
    try {
      await widget.moteur.appairer(code: _code.text.trim().toUpperCase(), cleClinique: _cle.text.trim(), agent: _agent.text.trim());
      widget.apres();
    } catch (e) {
      if (mounted) setState(() => _erreur = 'Appairage refusé : $e');
    } finally {
      if (mounted) setState(() => _en = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SIGH-CNT, appairage')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Demandez un code à la mère (DAF / administrateur) : il ne sert qu’une fois. Le profil du téléphone et la fonction du soignant sont fixés par ce code : ils ne se choisissent pas ici.'),
        const SizedBox(height: 12),
        TextField(key: const Key('code'), controller: _code, decoration: const InputDecoration(labelText: 'Code d’appairage')),
        const SizedBox(height: 12),
        TextField(key: const Key('cle'), controller: _cle, decoration: const InputDecoration(labelText: 'Clé de clinique (QR)'), obscureText: true),
        const SizedBox(height: 12),
        TextField(key: const Key('agent'), controller: _agent, decoration: const InputDecoration(labelText: 'Nom de l’agent')),
        ValueListenableBuilder<EtatMobile>(
          valueListenable: widget.moteur.etat,
          builder: (_, e, __) => e.enAttenteClinique
              ? const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Téléphone appairé. En attente de la clinique : elle vous attribue votre profil et votre fonction dès qu’elle est joignable (proposition à valider).',
                      key: Key('attente-clinique')))
              : const SizedBox.shrink(),
        ),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_erreur!, key: const Key('erreur'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(key: const Key('appairer'), onPressed: _en ? null : _valider, child: Text(_en ? 'Appairage…' : 'Appairer ce téléphone')),
      ]),
    );
  }
}
