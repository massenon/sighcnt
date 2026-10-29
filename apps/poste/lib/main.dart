import 'package:flutter/material.dart';

/// Mode de l'application : fileul (défaut) ou mère. Fixé à la compilation.
const String modeSigh = String.fromEnvironment('SIGH_MODE', defaultValue: 'fileul');

void main() => runApp(const SighPoste());

class SighPoste extends StatelessWidget {
  const SighPoste({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIGH-CNT',
      debugShowCheckedModeBanner: false,
      // Le thème viendra des jetons de la maquette (tailwind.config.js, src/input.css) :
      // aucune couleur en dur hors du thème (PRD Flutter, P0-3).
      home: Scaffold(
        body: Center(child: Text('SIGH-CNT — poste ($modeSigh)')),
      ),
    );
  }
}
