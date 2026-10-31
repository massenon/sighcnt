import 'package:flutter/material.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/controleur_poste.dart';
import '../core/theme.dart';
import '../kit/kit.dart';
import '../mere/activation.dart';
import '../shell/contexte_ecran.dart';

/// « Ce poste » : où l'on active le MODE MÈRE sur le serveur local, et où on le désactive. Réservé à l'administrateur
/// et à la DAF. Un seul poste peut être mère : le relais refuse la deuxième déclaration en nommant la première.
class ReglagesPoste extends StatefulWidget with EcranMaquette {
  const ReglagesPoste({super.key, required this.controleur});
  final ControleurPoste controleur;

  // L'en-tête de `cfg-poste` de la maquette (titre, description, règle) : le mode du poste se lit en deux indicateurs, puis la note de ce qu'il exige.
  @override
  String get titre => 'Ce poste';
  @override
  String get description => 'Mode du poste : fileul ou mère. La mère est le même logiciel avec ses modules complémentaires (synchronisation, supervision, sauvegardes).';
  @override
  String get regle =>
      'Il ne peut y avoir qu’un seul poste mère par clinique : le relais refuse une seconde déclaration en nommant la première. L’activation est atomique : si le service ne démarre pas, le poste reste fileul.';

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
      await widget.controleur.activer(
          relais: _relais.text,
          secretMere: _secret.text,
          cleClinique: _cle.text,
          nomPoste: _nom.text,
          remplacer: remplacer);
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
        return ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Mode de ce poste',
                valeur: c.estMere ? 'Mère' : 'Fileul',
                icone: c.estMere ? LucideIcons.server : LucideIcons.monitor,
                ton: c.estMere ? TonSigh.succes : TonSigh.navy),
            KpiSigh(libelle: 'Service de synchronisation', valeur: c.estMere ? 'En marche' : 'Arrêté', icone: LucideIcons.power, ton: c.estMere ? TonSigh.succes : TonSigh.neutre),
          ]),
          const SizedBox(height: 16),
          if (!c.estMere)
            const NoteSigh('À faire sur le serveur local uniquement. Exige l’adresse du relais, le secret de la mère et la clé de clinique.')
          else
            const NoteSigh('Les modules du groupe Poste mère sont maintenant disponibles pour l’administrateur et la DAF.', ton: TonSigh.succes, icone: LucideIcons.check),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(c.estMere ? Icons.dns : Icons.computer,
                  color: ThemeSigh.navy),
              title: Text(
                  c.estMere
                      ? 'Ce poste est la MÈRE de la clinique'
                      : 'Ce poste est un poste fileul',
                  key: const Key('mode-courant')),
              subtitle: Text(c.estMere
                  ? 'Il porte aussi le service de synchronisation et les modules « Poste mère ».'
                  : 'Il travaille avec la mère de la clinique ; il peut en devenir la mère (une seule par clinique).'),
            ),
          ),
          if (widget.controleur.avertissement != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(widget.controleur.avertissement!,
                    key: const Key('avertissement'),
                    style: TextStyle(color: ThemeSigh.attention))),
          const SizedBox(height: 12),
          if (!c.estMere) ...[
            Text('Activer le mode mère',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
                'Le relais déclare la mère : il exige le secret de la mère et la clé de clinique, saisis ici et jamais conservés dans le fichier des réglages.'),
            const SizedBox(height: 8),
            TextField(
                key: const Key('relais'),
                controller: _relais,
                decoration: const InputDecoration(
                    labelText: 'Adresse du relais',
                    hintText: 'https://relais.exemple.bj')),
            TextField(
                key: const Key('secret'),
                controller: _secret,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Secret de la mère')),
            TextField(
                key: const Key('cle'),
                controller: _cle,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Clé de clinique')),
            TextField(
                key: const Key('nom'),
                controller: _nom,
                decoration:
                    const InputDecoration(labelText: 'Nom de ce poste')),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erreur!,
                    key: const Key('erreur'),
                    style: TextStyle(color: ThemeSigh.danger)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                  key: const Key('activer'),
                  onPressed: _occupe ? null : _activer,
                  icon: const Icon(Icons.dns),
                  label:
                      Text(_occupe ? 'Activation…' : 'Activer le mode mère')),
              // Reprise après sinistre : proposée SEULEMENT quand le relais a dit « une mère existe » (jamais d'emblée).
              if (_codeErreur == 'mere_deja_active') ...[
                const SizedBox(width: 12),
                OutlinedButton(
                    key: const Key('remplacer'),
                    onPressed: _occupe ? null : () => _activer(remplacer: true),
                    child: const Text('Remplacer la mère silencieuse')),
              ],
            ]),
          ] else ...[
            Text('Désactiver le mode mère',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
                'Arrête le service de synchronisation, libère la place au relais, conserve toutes les données. Le secret de la mère est demandé.'),
            TextField(
                key: const Key('secret'),
                controller: _secret,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Secret de la mère')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                key: const Key('desactiver'),
                onPressed: _occupe ? null : _desactiver,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Désactiver le mode mère')),
          ],
        ]);
      },
    );
  }
}
