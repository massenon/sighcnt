import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../mere/client_mere.dart';
import '../../shell/contexte_ecran.dart';
import 'mrb_source.dart';

/// Pièces communes des sept écrans de la console mère, lot (b).

const String mrbNonDisponible = 'non disponible';

/// Les trois états d'une lecture auprès du service de la mère. « Inconnu » n'est jamais « ok ».
String mrbLibelleEtat(String etat) => switch (etat) {
      'ok' => 'OK',
      'attention' => 'À surveiller',
      'alerte' => 'ALERTE',
      _ => 'Inconnu',
    };

TonSigh mrbTon(String etat) => switch (etat) {
      'ok' => TonSigh.succes,
      'attention' => TonSigh.attention,
      'alerte' => TonSigh.danger,
      _ => TonSigh.neutre,
    };

String _deux(int n) => n.toString().padLeft(2, '0');

String mrbDateHeure(DateTime d) {
  final l = d.toLocal();
  return '${_deux(l.day)}/${_deux(l.month)}/${l.year} ${_deux(l.hour)}:${_deux(l.minute)}';
}

String mrbDateHeureMs(int ms) => mrbDateHeure(DateTime.fromMillisecondsSinceEpoch(ms));

String mrbTaille(int octets) {
  if (octets >= 1 << 30) return '${(octets / (1 << 30)).toStringAsFixed(1)} Go';
  if (octets >= 1 << 20) return '${(octets / (1 << 20)).toStringAsFixed(1)} Mo';
  if (octets >= 1 << 10) return '${(octets / (1 << 10)).toStringAsFixed(0)} Ko';
  return '$octets o';
}

/// Dit POURQUOI une lecture manque : la cause nommée par la mère, ou l'absence de réponse. Jamais un écran vide muet.
String mrbCause(Object e) => e is ErreurMere ? e.motif.isEmpty ? e.code : '${e.code} : ${e.motif}' : '$e';

/// Un indicateur : la valeur ou « non disponible », jamais un zéro de substitution.
Widget mrbKpi(String libelle, String? valeur, {String? indice, TonSigh ton = TonSigh.navy, IconData? icone}) => KpiSigh(
      libelle: libelle,
      valeur: valeur ?? mrbNonDisponible,
      indice: indice,
      ton: valeur == null ? TonSigh.neutre : ton,
      icone: icone,
    );

/// Grille d'indicateurs : jusqu'à quatre colonnes selon la largeur, espace 12.
Widget mrbGrilleKpi(List<Widget> kpis) => LayoutBuilder(builder: (_, c) {
      final n = c.maxWidth >= 1024 ? kpis.length.clamp(1, 4) : (c.maxWidth >= 640 ? 2 : 1);
      final l = (c.maxWidth - 12 * (n - 1)) / n;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final k in kpis) SizedBox(width: l, child: k)]);
    });

/// Bandeau d'indisponibilité du service : la cause, et ce que l'écran montre en attendant (rien d'inventé).
Widget mrbBandeauPanne(String? panne) => panne == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: NoteSigh('Le service de la mère ne répond pas correctement : $panne. Les valeurs ci-dessous sont affichées « $mrbNonDisponible » '
            'tant qu’elles ne sont pas lues.', ton: TonSigh.danger, icone: LucideIcons.triangleAlert),
      );

/// Tableau du kit, avec ses en-têtes visibles même VIDE : le kit ne dessine pas les en-têtes d'un tableau sans ligne (comme la maquette), or
/// l'agent doit lire ce que le tableau contiendra et dans quel ordre. Une cellule sans valeur dit « non disponible », jamais un trait.
class MrbTableau extends StatelessWidget {
  const MrbTableau({
    super.key,
    required this.colonnes,
    required this.lignes,
    required this.messageVide,
    this.titre,
    this.indiceVide,
    this.filtres = const [],
    this.alExporter,
    this.nomExport = 'export',
    this.actionsLigne,
    this.recherche = true,
  });
  final List<ColonneTableau> colonnes;
  final List<Ligne> lignes;
  final String messageVide;
  final String? indiceVide;
  final String? titre;
  final List<FiltreTableau> filtres;
  final void Function(String nom, String csv)? alExporter;
  final String nomExport;
  final List<Widget> Function(BuildContext, Ligne)? actionsLigne;
  final bool recherche;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TableauSigh(
          colonnes: colonnes,
          lignes: lignes,
          titre: titre,
          messageVide: messageVide,
          indiceVide: indiceVide,
          filtres: filtres,
          alExporter: alExporter,
          nomExport: nomExport,
          actionsLigne: actionsLigne,
          recherche: recherche,
        ),
        if (lignes.isEmpty)
          Container(
            key: const Key('mrb:entetes-vides'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
            child: Wrap(spacing: 24, runSpacing: 4, children: [
              for (final c in colonnes)
                Text(c.libelle,
                    style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]);
}

/// Base commune des écrans : lit la source, rafraîchit à intervalle régulier, garde la dernière lecture réussie et NOMME la panne. Un écran n'efface
/// jamais ce qu'il sait parce qu'une lecture a échoué : il le garde et dit que le service ne répond plus.
abstract class MrbEtatEcran<W extends StatefulWidget, T> extends State<W> {
  T? donnees;
  String? panne;
  bool enCours = true;
  Timer? _minuterie;

  /// Une lecture complète de l'écran. Lève en cas de panne.
  Future<T> charger(MrbSource source);

  MrbSource? get source => mrbSourceCourante();

  @override
  void initState() {
    super.initState();
    actualiser();
    _minuterie = Timer.periodic(mrbIntervalle, (_) => actualiser());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> actualiser() async {
    final s = source;
    if (s == null) {
      if (!mounted) return;
      setState(() {
        panne = 'aucune liaison avec le service de la mère sur ce poste';
        enCours = false;
      });
      return;
    }
    try {
      final d = await charger(s);
      if (!mounted) return;
      setState(() {
        donnees = d;
        panne = null;
        enCours = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        panne = mrbCause(e);
        enCours = false;
      });
    }
  }

  /// Un geste d'écriture : exécute, annonce le résultat ou le refus NOMMÉ, puis relit. Le contexte est celui de l'écran (jamais celui d'une modale).
  Future<bool> geste(BuildContext contexte, Future<void> Function() f, {String? ok}) async {
    try {
      await f();
      if (ok != null && contexte.mounted) ToastsSigh.afficher(contexte, ok, type: TypeToast.succes);
      await actualiser();
      return true;
    } catch (e) {
      if (contexte.mounted) {
        ToastsSigh.afficher(contexte, e is MrbIndisponible ? 'Non disponible : ${e.motif}' : 'Refusé : ${mrbCause(e)}', type: TypeToast.erreur);
      }
      await actualiser();
      return false;
    }
  }
}

/// Les droits de l'écran, en une ligne : une commande sans le droit n'est PAS dessinée (pas de bouton grisé).
extension MrbDroits on ContexteEcran {
  bool get peutEcrire => droit.editer;
  bool get peutAnnuler => droit.annuler;
}
