import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show CoffrePin;

import 'core/coffre_pin_securise.dart';
import 'core/theme.dart';
import 'moteur/moteur_mobile.dart';
import 'ui/accueil.dart';
import 'ui/appairage.dart';
import 'ui/pin.dart';

const String adresseRelais = String.fromEnvironment('SIGH_RELAIS', defaultValue: 'https://relais.exemple.bj');
const String cheminBase = String.fromEnvironment('SIGH_DB', defaultValue: 'sigh-mobile.db');

/// Sur un téléphone, le code PIN est OBLIGATOIRE (spec §11) : le coffre est celui du système (`flutter_secure_storage`), jamais éprouvé ici faute de
/// chaîne native (ECARTS-MAQUETTE E1658).
void main() => runApp(SighMobile(
      moteur: MoteurMobileSync.creer(dbChemin: cheminBase, relais: adresseRelais),
      coffre: CoffrePinSecurise(StockageFlutterSecure()),
    ));

class SighMobile extends StatefulWidget {
  /// [coffre] absent : aucun verrou. C'est le cas des tests d'écran, jamais celui de l'application (`main` le fournit toujours).
  const SighMobile({super.key, required this.moteur, this.coffre, this.horlogeVerrou});
  final MoteurMobile moteur;
  final CoffrePin? coffre;

  /// L'horloge du verrou (le blocage de 30 s se compte avec elle) ; absente, l'heure du téléphone. Les tests la déplacent.
  final DateTime Function()? horlogeVerrou;

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
      builder: (context, child) => GardeVerrou(coffre: widget.coffre, horloge: widget.horlogeVerrou, child: child ?? const SizedBox.shrink()),
      // Le profil vient de la mère (code d'appairage, E1600) : l'écran suit l'état du moteur, il ne devine pas.
      home: ValueListenableBuilder<EtatMobile>(
        valueListenable: widget.moteur.etat,
        builder: (c, _, __) => widget.moteur.profil == null ? EcranAppairage(moteur: widget.moteur, apres: () => setState(() {})) : Accueil(moteur: widget.moteur, coffreActif: widget.coffre != null, apresReinitialisation: () => setState(() {})),
      ),
    );
  }
}
