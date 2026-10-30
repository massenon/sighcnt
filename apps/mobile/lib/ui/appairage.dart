import 'package:flutter/material.dart';

import '../moteur/moteur_mobile.dart';

/// Appairage : code à usage unique + clé de clinique (scannée par QR sur le vrai téléphone, collée ici) + profil.
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
  ProfilMobile _profil = ProfilMobile.soignant;
  String? _erreur;
  bool _en = false;

  Future<void> _valider() async {
    if (_code.text.trim().isEmpty || _cle.text.trim().isEmpty) {
      setState(() => _erreur = 'Le code d’appairage et la clé de clinique sont obligatoires.');
      return;
    }
    setState(() {
      _en = true;
      _erreur = null;
    });
    try {
      await widget.moteur.appairer(code: _code.text.trim().toUpperCase(), cleClinique: _cle.text.trim(), profil: _profil);
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
      appBar: AppBar(title: const Text('SIGH-CNT — appairage')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Demandez un code à la mère (DAF / administrateur) : il ne sert qu’une fois.'),
        const SizedBox(height: 12),
        TextField(key: const Key('code'), controller: _code, decoration: const InputDecoration(labelText: 'Code d’appairage')),
        const SizedBox(height: 12),
        TextField(key: const Key('cle'), controller: _cle, decoration: const InputDecoration(labelText: 'Clé de clinique (QR)'), obscureText: true),
        const SizedBox(height: 16),
        SegmentedButton<ProfilMobile>(
          key: const Key('profil'),
          segments: const [
            ButtonSegment(value: ProfilMobile.soignant, label: Text('Soignant')),
            ButtonSegment(value: ProfilMobile.receptionSecours, label: Text('Réception de secours')),
          ],
          selected: {_profil},
          onSelectionChanged: (s) => setState(() => _profil = s.first),
        ),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_erreur!, key: const Key('erreur'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(key: const Key('appairer'), onPressed: _en ? null : _valider, child: Text(_en ? 'Appairage…' : 'Appairer ce téléphone')),
      ]),
    );
  }
}
