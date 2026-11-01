import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../mere/client_mere.dart';
import '../../shell/contexte_ecran.dart';
import '../mere/mrb_commun.dart';
import '../mere/mrb_source.dart';
import '../mere/mrc_commun.dart' show Mrc;

/// Pièces communes des douze écrans du module RLS (« Relais en ligne »), portés dans le poste le 1er novembre 2026.
///
/// CE QUE CES ÉCRANS SONT : le poste ne parle JAMAIS au relais (il est opaque et n'appelle personne : la mère l'interroge, ADR-0005). Ces écrans lisent
/// donc le relais PAR LA MÈRE : ce que la mère publie, ce qu'elle sait de ses appareils, de ses alertes et de sa liaison. Tout ce que seul le relais
/// connaît (hébergement cPanel, exports de sa base, comptes du panneau Laravel, boîtes aux lettres, codes déclarés, historique des indicateurs reçus)
/// se dit « non disponible » avec le motif et le lien vers le panneau web : jamais un zéro, jamais une valeur inventée.

/// Les pages du panneau web (`apps/web`, routes de `routes/web.php`), par écran : le lien que chaque écran donne vers la source de vérité.
const Map<String, String> rlsPagesPanneau = {
  'rls-tableau': '',
  'rls-appareils': 'appareils',
  'rls-boites': 'boites',
  'rls-codes': 'codes',
  'rls-indicateurs': 'indicateurs',
  'rls-alertes': 'alertes',
  'rls-journal': 'journal',
  'rls-superadmin': 'superadmin',
  'rls-parametres': 'parametres',
  'rls-hebergement': 'hebergement',
  'rls-sauvegarde': 'sauvegarde',
  'rls-opacite': 'opacite',
};

/// Adresse du panneau web d'un écran : `<adresse du relais>/panneau/<page>`. Vide si le poste n'a pas d'adresse de relais.
String rlsAdressePanneau(String relais, String ecran) {
  final base = relais.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) return '';
  final page = rlsPagesPanneau[ecran] ?? '';
  return page.isEmpty ? '$base/panneau' : '$base/panneau/$page';
}

/// Ouvre une adresse dans le navigateur du système. Posé par les tests pour ne rien lancer. Rend `false` si le système n'a pas pu l'ouvrir.
Future<bool> Function(String url) rlsOuvreur = (url) async {
  try {
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
    return true;
  } catch (_) {
    return false;
  }
};

/// L'adresse du relais configurée sur CE poste (réglages du poste). `null` : le poste ne la connaît pas (pas de contrôleur, lecture impossible).
Future<String?> rlsAdresseRelais() async {
  try {
    final p = await Mrc.controleur?.activation.parametres();
    return p?.relais;
  } catch (_) {
    return null;
  }
}

/// Une lecture complète du relais, par la mère.
class RlsLecture {
  const RlsLecture({required this.sante, required this.etat, this.appareils, this.patients, this.journal, this.adresseRelais});
  final MrbSante sante;
  final MrbEtat etat;

  /// Les appareils AVEC dernier contact et curseur (`GET /admin/etat` complet) ; `null` si cette lecture seule a échoué.
  final List<Appareil>? appareils;
  final int? patients;
  final List<MrbLigneJournal>? journal;
  final String? adresseRelais;

  MrbControle? get liaison => sante.controle('Relais en ligne');

  /// Les appareils actifs : appairés, non révoqués, non bloqués.
  int get actifs => etat.appareils.where((a) => a.etat != 'revoque' && !etat.bloques.contains(a.uuid)).length;

  List<MrbAppareil> get mobiles => etat.appareils.where((a) => a.role == 'mobile' && a.etat != 'revoque').toList();
}

/// Lit la mère : la santé et l'état sont OBLIGATOIRES (sans eux, l'écran dit la panne) ; le reste est facultatif et ne fait jamais échouer l'écran.
Future<RlsLecture> rlsCharger(MrbSource s, {bool journal = false}) async {
  final sante = await s.supervision();
  final etat = await s.etat();
  List<Appareil>? appareils;
  final client = mrbClientMere;
  if (client != null) {
    try {
      appareils = (await client.etat()).appareils;
    } catch (_) {
      appareils = null;
    }
  }
  int? patients;
  try {
    patients = await s.patientsActifs();
  } catch (_) {
    patients = null;
  }
  List<MrbLigneJournal>? lignes;
  if (journal) {
    try {
      lignes = await s.journal(limite: 500);
    } catch (_) {
      lignes = null;
    }
  }
  return RlsLecture(
      sante: sante, etat: etat, appareils: appareils, patients: patients, journal: lignes, adresseRelais: await rlsAdresseRelais());
}

/// Base des douze écrans : la lecture de la mère, rafraîchie, avec la panne nommée.
abstract class RlsEtatEcran<W extends StatefulWidget> extends MrbEtatEcran<W, RlsLecture> {
  /// Lire aussi le journal technique de la mère (écran du journal d'audit).
  bool get avecJournal => false;

  @override
  Future<RlsLecture> charger(MrbSource s) => rlsCharger(s, journal: avecJournal);
}

/// `il y a 40 s`, `il y a 12 min`, `il y a 3 h`, `il y a 2 j` : comme la maquette.
String rlsIlYa(DateTime quand, DateTime maintenant) {
  final s = maintenant.difference(quand).inSeconds;
  if (s < 0) return 'à l’instant';
  if (s < 60) return 'il y a $s s';
  if (s < 3600) return 'il y a ${s ~/ 60} min';
  if (s < 86400) return 'il y a ${s ~/ 3600} h';
  return 'il y a ${s ~/ 86400} j';
}

const String rlsNd = mrbNonDisponible;

/// Le motif commun à tout ce que seul le relais connaît.
const String rlsMotifRelais =
    'Cette mesure appartient au relais lui-même. La mère ne l’interroge pas et le poste n’appelle jamais le relais : elle se lit sur le panneau web.';

/// Cadre commun d'un écran : la panne nommée, la note de lecture, puis les blocs, puis le lien vers le panneau web.
Widget rlsPage(BuildContext contexte, {required String ecran, required String? panne, required RlsLecture? lecture, required List<Widget> blocs}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      mrbBandeauPanne(panne),
      const NoteSigh(
          'Ce poste lit le relais à travers la mère : ce que la mère publie et sait de sa liaison. Le relais ne contient aucune donnée de patient lisible. '
          'Ce que seul le relais connaît s’affiche « $mrbNonDisponible », avec le lien vers le panneau web.',
          ton: TonSigh.neutre,
          icone: LucideIcons.cloud),
      const SizedBox(height: 12),
      for (final b in blocs) ...[b, const SizedBox(height: 16)],
      RlsLienPanneau(ecran: ecran, adresse: lecture?.adresseRelais),
    ]);

/// Le lien vers la source de vérité : l'écran jumeau du panneau web (Laravel + Livewire). Ouvrir le navigateur ou copier l'adresse.
class RlsLienPanneau extends StatelessWidget {
  const RlsLienPanneau({super.key, required this.ecran, required this.adresse});
  final String ecran;

  /// L'adresse du relais configurée sur ce poste ; `null` ou vide : non configurée.
  final String? adresse;

  @override
  Widget build(BuildContext context) {
    final url = rlsAdressePanneau(adresse ?? '', ecran);
    return Container(
      key: const Key('rls:lien-panneau'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Icon(LucideIcons.externalLink, size: 16, color: JetonsShell.slate500),
        Text('Panneau web du relais',
            style: const TextStyle(fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w600, color: JetonsShell.slate700)),
        if (url.isEmpty)
          const Text('Adresse du relais non configurée sur ce poste (réglages du poste, champ « Relais »).',
              style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))
        else ...[
          SelectableText(url, key: const Key('rls:adresse-panneau'), style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate700)),
          BoutonSigh(
              libelle: 'Ouvrir le panneau web',
              icone: LucideIcons.externalLink,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () async {
                final ok = await rlsOuvreur(url);
                if (!ok && context.mounted) {
                  ToastsSigh.afficher(context, 'Le système n’a pas pu ouvrir le navigateur. Copier l’adresse et la coller dans un navigateur.', type: TypeToast.attention);
                }
              }),
          BoutonSigh(
              libelle: 'Copier le lien',
              icone: LucideIcons.copy,
              taille: TailleBouton.sm,
              variante: VarianteBouton.fantome,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) ToastsSigh.afficher(context, 'Adresse du panneau copiée.', type: TypeToast.succes);
              }),
        ],
      ]),
    );
  }
}

/// Refus NOMMÉ d'un geste que la mère n'expose pas : la cause, et où le faire (panneau web).
Future<void> rlsRefuser(BuildContext contexte, {required String geste, required String motif}) async {
  ToastsSigh.afficher(contexte, 'Non disponible depuis ce poste : $geste. $motif', type: TypeToast.attention);
}

/// Colonne simple : l'en-tête est le libellé de la fiche de la maquette.
ColonneTableau rlsCol(String cle, String libelle, {bool triable = false, bool sansCoupure = false}) =>
    ColonneTableau(cle: cle, libelle: libelle, triable: triable, sansCoupure: sansCoupure);

/// Tableau dont les en-têtes s'affichent même vide, sans recherche ni pagination (ce sont de petites listes de lecture).
Widget rlsTableau({required List<ColonneTableau> colonnes, required List<Ligne> lignes, required String messageVide, String? indiceVide, List<Widget> Function(BuildContext, Ligne)? actionsLigne}) =>
    MrbTableau(colonnes: colonnes, lignes: lignes, messageVide: messageVide, indiceVide: indiceVide, recherche: false, actionsLigne: actionsLigne);

/// Une carte sans remplissage portant un tableau.
Widget rlsCarteTableau(String titre, Widget tableau, {List<Widget> actions = const []}) =>
    CarteSigh(titre: titre, sansRemplissage: true, actions: actions, child: tableau);

/// Droit d'écrire sur l'écran : la commande interdite est ABSENTE.
bool rlsPeutEcrire(BuildContext c) => ContexteEcran.of(c).peutEcrire;
