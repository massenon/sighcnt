import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show CodeMaj, RefusMaj;

import '../donnees/persistance.dart';

/// LA CLÉ DE CHIFFREMENT AU PREMIER DÉMARRAGE (lot MAJ, PRD-MISE-A-JOUR, exigence 10) : un poste dont le fichier de clé est ABSENT ne la fabrique pas en silence. Il demande : « premier poste de
/// la clinique, créer la clé » ou « restaurer la clé d'une clinique existante » (fichier de sauvegarde de clé et phrase de passe). Sans cela un poste neuf ou remplacé créerait une clé NEUVE, et
/// les données et les exports de la clinique resteraient illisibles. Refus nommés, rien n'est écrasé. La restauration n'est jamais offerte quand une clé existe (elle la remplacerait).
RefusMaj refusCle(Object e) {
  final m = e is StateError ? e.message : '$e';
  if (m.contains('Phrase de passe incorrecte')) {
    return const RefusMaj('CLE_PHRASE_INCORRECTE', 'La phrase de passe est incorrecte, ou la sauvegarde de clé est altérée.', 'Ressaisir la phrase de passe ; sans elle la clé ne se restaure pas (copie papier de la clinique sous scellé)');
  }
  if (m.contains('pas une sauvegarde de clé')) {
    return const RefusMaj('CLE_FICHIER_INVALIDE', 'Ce fichier n’est pas une sauvegarde de clé SIGH.', 'Choisir le fichier .cle exporté par « Sauvegarder la clé de chiffrement »');
  }
  return RefusMaj('CLE_RESTAURATION_REFUSEE', m, 'Aucune clé n’a été écrite ; vérifier le fichier et la phrase de passe');
}

/// Le fichier de clé existe-t-il ? Sinon, l'écran ci-dessous doit être passé AVANT d'obtenir la clé.
bool cleAbsente(String chemin) => !CleLocale(chemin).existe();

class EcranDemarrageCle extends StatefulWidget {
  const EcranDemarrageCle({super.key, required this.cle, required this.choisirFichier, required this.termine});
  final CleLocale cle;
  final Future<String?> Function() choisirFichier;

  /// Appelé quand la clé existe (créée ou restaurée) : le démarrage reprend.
  final VoidCallback termine;

  @override
  State<EcranDemarrageCle> createState() => _EtatDemarrageCle();
}

class _EtatDemarrageCle extends State<EcranDemarrageCle> {
  bool _restaurer = false;
  String? _fichier;
  final _phrase = TextEditingController();
  RefusMaj? _refus;
  bool _occupe = false;

  Future<void> _choisir() async {
    final f = await widget.choisirFichier();
    if (f != null && mounted) setState(() => _fichier = f);
  }

  Future<void> _restaurer_() async {
    if (_fichier == null) {
      setState(() => _refus = const RefusMaj(CodeMaj.importSansCle, 'Aucun fichier de clé choisi.', 'Choisir le fichier .cle de la clinique'));
      return;
    }
    setState(() {
      _occupe = true;
      _refus = null;
    });
    try {
      await widget.cle.importer(_fichier!, _phrase.text);
      widget.termine();
    } catch (e) {
      if (mounted) setState(() => _refus = refusCle(e));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('SIGH-CNT : clé de chiffrement de la clinique', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const Text(
                    'Ce poste n’a pas encore de clé. Les données et les exports de la clinique sont chiffrés par une clé unique : sur un poste neuf ou remplacé, restaurez la clé de la clinique au lieu d’en créer une nouvelle.'),
                const SizedBox(height: 16),
                if (!_restaurer) ...[
                  ElevatedButton(key: const Key('cle:restaurer'), onPressed: () => setState(() => _restaurer = true), child: const Text('Restaurer la clé de la clinique')),
                  const SizedBox(height: 8),
                  OutlinedButton(key: const Key('cle:creer'), onPressed: _occupe ? null : () async {
                    await widget.cle.obtenir();
                    widget.termine();
                  }, child: const Text('Premier poste de la clinique : créer la clé')),
                ] else ...[
                  Row(children: [
                    OutlinedButton(key: const Key('cle:choisir'), onPressed: _occupe ? null : _choisir, child: const Text('Choisir le fichier de clé (.cle)')),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_fichier ?? 'Aucun fichier choisi', overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(key: const Key('cle:phrase'), controller: _phrase, obscureText: true, decoration: const InputDecoration(labelText: 'Phrase de passe de la sauvegarde de clé')),
                  const SizedBox(height: 12),
                  ElevatedButton(key: const Key('cle:confirmer'), onPressed: _occupe ? null : _restaurer_, child: const Text('Restaurer la clé')),
                  TextButton(onPressed: _occupe ? null : () => setState(() => _restaurer = false), child: const Text('Retour')),
                ],
                if (_refus != null) ...[
                  const SizedBox(height: 12),
                  Text('${_refus!.code} : ${_refus!.motif}\nGeste : ${_refus!.geste}.', key: const Key('cle:refus'), style: const TextStyle(color: Color(0xFFB42318))),
                ],
              ])),
        )),
      );
}
