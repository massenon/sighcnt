import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'moteur/moteur_mobile.dart';
import 'ui/accueil.dart';
import 'ui/appairage.dart';

const String adresseRelais = String.fromEnvironment('SIGH_RELAIS', defaultValue: 'https://relais.exemple.bj');
const String cheminBase = String.fromEnvironment('SIGH_DB', defaultValue: 'sigh-mobile.db');

void main() => runApp(SighMobile(moteur: MoteurMobileSync.creer(dbChemin: cheminBase, relais: adresseRelais)));

class SighMobile extends StatefulWidget {
  const SighMobile({super.key, required this.moteur});
  final MoteurMobile moteur;

  @override
  State<SighMobile> createState() => _SighMobileState();
}

class _SighMobileState extends State<SighMobile> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIGH-CNT',
      debugShowCheckedModeBanner: false,
      theme: ThemeSigh.clair(),
      // Le profil vient de la mère (code d'appairage, E1600) : l'écran suit l'état du moteur, il ne devine pas.
      home: ValueListenableBuilder<EtatMobile>(
        valueListenable: widget.moteur.etat,
        builder: (c, _, __) => widget.moteur.profil == null ? EcranAppairage(moteur: widget.moteur, apres: () => setState(() {})) : Accueil(moteur: widget.moteur),
      ),
    );
  }
}
