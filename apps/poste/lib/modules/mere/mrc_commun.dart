import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/controleur_poste.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../mere/client_mere.dart';
import '../../shell/contexte_ecran.dart';
import 'mrc_sources.dart';

/// Socle des huit écrans de la console du poste mère (lot MERE c). Un écran ne contient AUCUNE règle et ne devine rien : il affiche ce que la
/// source (le moteur, le système, la spécification) fournit, et dit « non disponible » avec le motif pour le reste.

/// Le branchement des écrans : le client du service de la mère et le contrôleur du poste, posés par `ecransPortes`. Un test pose [fabrique] pour
/// fournir une source fausse (sans réseau, sans service Windows).
class Mrc {
  Mrc._();
  static ClientMere? client;
  static ControleurPoste? controleur;
  static MrcSources Function(Magasin)? fabrique;

  static void brancher({ClientMere? client, ControleurPoste? controleur}) {
    Mrc.client = client;
    Mrc.controleur = controleur;
  }

  static MrcSources sources(Magasin m) =>
      (fabrique ?? (mg) => MrcSourcesReelles(client: client, controleur: controleur, magasin: mg))(m);
}

/// Les droits d'agir sur la console : réservée à l'administrateur et à la DAF, et aux droits d'écriture de l'écran. Une commande interdite est ABSENTE.
bool mrcPeutAgir(ContexteEcran c) => mrcRolesAdmin.contains(c.role) && c.droit.editer;

/// Colonne d'un tableau de la console : en-tête et valeur.
class MrcColonne {
  const MrcColonne(this.libelle, this.valeur, {this.rendu});
  final String libelle;
  final String Function(Map<String, Object?>) valeur;
  final Widget Function(Map<String, Object?>)? rendu;
}

/// Tableau de lecture dont les EN-TÊTES s'affichent toujours, même sans ligne : un tableau vide qui perd ses colonnes ne dit plus ce qu'il attend.
class MrcTableau extends StatelessWidget {
  const MrcTableau({super.key, required this.colonnes, required this.lignes, this.vide = 'Aucune ligne.'});
  final List<MrcColonne> colonnes;
  final List<Map<String, Object?>> lignes;
  final String vide;

  @override
  Widget build(BuildContext context) {
    Widget cel(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: w);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {for (var i = 0; i < colonnes.length; i++) i: const FlexColumnWidth()},
          children: [
            TableRow(
                decoration: const BoxDecoration(color: JetonsShell.slate50, border: Border(bottom: BorderSide(color: JetonsShell.slate200))),
                children: [
                  for (final c in colonnes)
                    cel(Text(c.libelle.toUpperCase(),
                        style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)))
                ]),
            for (final r in lignes)
              TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate100))),
                  children: [
                    for (final c in colonnes)
                      cel(c.rendu != null
                          ? c.rendu!(r)
                          : Text(c.valeur(r), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)))
                  ]),
          ]),
      if (lignes.isEmpty)
        Padding(
            padding: const EdgeInsets.all(20),
            child: Center(child: Text(vide, textAlign: TextAlign.center, style: const TextStyle(color: JetonsShell.slate500, fontSize: 14)))),
    ]);
  }
}

/// Texte de motif posé sous une valeur « non disponible » : l'écran dit POURQUOI.
class MrcMotif extends StatelessWidget {
  const MrcMotif(this.texte, {super.key});
  final String texte;
  @override
  Widget build(BuildContext context) =>
      Text(texte, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12));
}

/// KPI d'une valeur sourcée ou « non disponible » (le motif va en indice).
KpiSigh mrcKpi<T>(String libelle, MrcValeur<T>? v, {String Function(T)? forme, IconData? icone, TonSigh ton = TonSigh.navy, String? indice}) {
  final dispo = v != null && v.disponible;
  return KpiSigh(
      libelle: libelle,
      valeur: v == null ? '…' : v.texte(forme),
      icone: icone,
      ton: dispo ? ton : TonSigh.neutre,
      indice: dispo ? indice : v?.motif);
}

/// Bandeau de panne : le service de la mère ne répond pas (cause nommée).
Widget mrcBandeauPanne(String? panne) => panne == null
    ? const SizedBox.shrink()
    : Padding(padding: const EdgeInsets.only(bottom: 12), child: NoteSigh(panne, ton: TonSigh.attention, icone: LucideIcons.triangleAlert));

/// Refus pour un rôle qui n'administre pas la mère : l'écran ne montre rien de la mère.
class MrcAccesRefuse extends StatelessWidget {
  const MrcAccesRefuse({super.key, required this.role});
  final String role;
  @override
  Widget build(BuildContext context) => NoteSigh(
      'Accès refusé : la console du poste mère est réservée à l’administrateur système et à la Directrice Administrative. Le rôle « $role » n’y a pas accès (RG-13).',
      ton: TonSigh.danger,
      icone: LucideIcons.shieldAlert);
}

/// Base d'un écran de la console : charge à l'ouverture, garde l'instantané, restitue les pannes en les nommant.
abstract class MrcEtatEcran<W extends StatefulWidget> extends State<W> {
  late MrcSources src;
  late ContexteEcran c;
  bool _initialise = false;
  bool charge = false;
  String? panne;

  /// Lit les sources de l'écran. Lève pour dire pourquoi une lecture a échoué : le message devient le bandeau de panne.
  Future<void> lire();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    c = ContexteEcran.of(context);
    if (!_initialise) {
      _initialise = true;
      src = Mrc.sources(c.magasin);
      // Un rôle qui n'administre pas la mère n'obtient AUCUNE lecture du service (RG-13) : l'écran se contente de refuser.
      if (mrcRolesAdmin.contains(c.role)) {
        actualiser();
      } else {
        charge = true;
      }
    }
  }

  Future<void> actualiser() async {
    String? p;
    try {
      await lire();
    } catch (e) {
      p = 'Le service de la mère ne répond pas ou refuse la lecture : $e';
    }
    if (!mounted) return;
    setState(() {
      panne = p;
      charge = true;
    });
  }

  void annoncer(String message, {TypeToast type = TypeToast.succes, String? detail}) {
    if (mounted) ToastsSigh.afficher(context, message, type: type, detail: detail);
  }

  /// Rend un [MrcResultat] à l'agent : un refus se NOMME, un succès se dit.
  void annoncerResultat(MrcResultat r) {
    if (r.ok) {
      annoncer(r.message);
    } else {
      annoncer('Refusé : ${r.message}', type: TypeToast.erreur);
    }
  }

  Widget boutonActualiser() => BoutonSigh(
      libelle: 'Actualiser', icone: LucideIcons.refreshCw, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: actualiser);
}

/// Confirmation NOMMÉE : l'agent doit saisir la phrase exacte avant un geste qui engage le serveur. Renvoie `ok` si, et seulement si, la phrase est exacte ;
/// [libelleSecret] ajoute un champ masqué (ex. le secret de la mère), rendu dans `secret`.
Future<({bool ok, String secret})> mrcConfirmerNommee(BuildContext context,
    {required String titre,
    required String message,
    required String phrase,
    String libelleOk = 'Confirmer',
    bool dangereux = true,
    String? libelleSecret}) async {
  final t = TextEditingController();
  final secret = TextEditingController();
  final exacte = ValueNotifier(false);
  final r = await afficherModale<bool>(context,
      titre: titre,
      taille: TailleModale.sm,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(message, style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
        const SizedBox(height: 12),
        Text('Pour confirmer, saisir exactement : $phrase',
            style: const TextStyle(color: JetonsShell.slate700, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
            key: const Key('mrc-phrase'),
            controller: t,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Confirmation'),
            onChanged: (v) => exacte.value = mrcPhraseExacte(phrase, v)),
        if (libelleSecret != null) ...[
          const SizedBox(height: 10),
          TextField(
              key: const Key('mrc-secret'),
              controller: secret,
              obscureText: true,
              decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: libelleSecret)),
        ],
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            ValueListenableBuilder<bool>(
                valueListenable: exacte,
                builder: (_, ok, __) => BoutonSigh(
                    libelle: libelleOk,
                    variante: dangereux ? VarianteBouton.danger : VarianteBouton.primaire,
                    onPressed: ok ? () => Navigator.of(context, rootNavigator: true).pop(true) : null)),
          ]);
  final res = (ok: r == true, secret: secret.text);
  return res;
}
