import 'package:flutter/material.dart';

import '../core/controleur_poste.dart';
import '../core/theme.dart';
import '../mere/activation.dart';

/// « Ce poste » : où l'on active le MODE MÈRE sur le serveur local, et où on le désactive. Réservé à l'administrateur
/// et à la DAF. Un seul poste peut être mère : le relais refuse la deuxième déclaration en nommant la première.
class ReglagesPoste extends StatefulWidget {
  const ReglagesPoste({super.key, required this.controleur});
  final ControleurPoste controleur;

  @override
  State<ReglagesPoste> createState() => _ReglagesPosteState();
}

class _ReglagesPosteState extends State<ReglagesPoste> {
  final _relais = TextEditingController();
  final _secret = TextEditingController();
  final _cle = TextEditingController();
  final _nom = TextEditingController(text: 'Serveur de la clinique');
  String? _erreur;
  String? _codeErreur;
  bool _occupe = false;

  Future<void> _activer({bool remplacer = false}) async {
    setState(() {
      _occupe = true;
      _erreur = null;
      _codeErreur = null;
    });
    try {
      await widget.controleur.activer(relais: _relais.text, secretMere: _secret.text, cleClinique: _cle.text, nomPoste: _nom.text, remplacer: remplacer);
      _secret.clear();
      _cle.clear();
    } on ActivationRefusee catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e.motif;
          _codeErreur = e.code;
        });
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _desactiver() async {
    setState(() => _occupe = true);
    try {
      await widget.controleur.desactiver(secretMere: _secret.text);
      _secret.clear();
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controleur,
      builder: (context, _) {
        final c = widget.controleur.config;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Ce poste', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(c.estMere ? Icons.dns : Icons.computer, color: ThemeSigh.navy),
              title: Text(c.estMere ? 'Ce poste est la MÈRE de la clinique' : 'Ce poste est un poste fileul', key: const Key('mode-courant')),
              subtitle: Text(c.estMere ? 'Il porte aussi le service de synchronisation et les modules « Poste mère ».' : 'Il travaille avec la mère de la clinique ; il peut en devenir la mère (une seule par clinique).'),
            ),
          ),
          if (widget.controleur.avertissement != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.controleur.avertissement!, key: const Key('avertissement'), style: TextStyle(color: ThemeSigh.attention))),
          const SizedBox(height: 12),
          if (!c.estMere) ...[
            Text('Activer le mode mère', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('À faire sur le SERVEUR local uniquement. Exige le secret de la mère (relais) et la clé de clinique.'),
            const SizedBox(height: 8),
            TextField(key: const Key('relais'), controller: _relais, decoration: const InputDecoration(labelText: 'Adresse du relais', hintText: 'https://relais.exemple.bj')),
            TextField(key: const Key('secret'), controller: _secret, obscureText: true, decoration: const InputDecoration(labelText: 'Secret de la mère')),
            TextField(key: const Key('cle'), controller: _cle, obscureText: true, decoration: const InputDecoration(labelText: 'Clé de clinique')),
            TextField(key: const Key('nom'), controller: _nom, decoration: const InputDecoration(labelText: 'Nom de ce poste')),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erreur!, key: const Key('erreur'), style: TextStyle(color: ThemeSigh.danger)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(key: const Key('activer'), onPressed: _occupe ? null : _activer, icon: const Icon(Icons.dns), label: Text(_occupe ? 'Activation…' : 'Activer le mode mère')),
              // Reprise après sinistre : proposée SEULEMENT quand le relais a dit « une mère existe » (jamais d'emblée).
              if (_codeErreur == 'mere_deja_active') ...[
                const SizedBox(width: 12),
                OutlinedButton(key: const Key('remplacer'), onPressed: _occupe ? null : () => _activer(remplacer: true), child: const Text('Remplacer la mère silencieuse')),
              ],
            ]),
          ] else ...[
            Text('Désactiver le mode mère', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Arrête le service de synchronisation, libère la place au relais, conserve toutes les données. Le secret de la mère est demandé.'),
            TextField(key: const Key('secret'), controller: _secret, obscureText: true, decoration: const InputDecoration(labelText: 'Secret de la mère')),
            const SizedBox(height: 12),
            OutlinedButton.icon(key: const Key('desactiver'), onPressed: _occupe ? null : _desactiver, icon: const Icon(Icons.power_settings_new), label: const Text('Désactiver le mode mère')),
          ],
        ]);
      },
    );
  }
}
