import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../mere/mrb_commun.dart';
import 'rls_commun.dart';
import 'rls_ecrans_a.dart';

/// Les six derniers écrans du module RLS : journal d'audit, comptes superadmin, paramètres, hébergement cPanel, sauvegarde du relais, preuve d'opacité.
/// Ce que la mère n'a pas (comptes du panneau Laravel, hébergement, exports de la base du relais) se dit « non disponible » avec le motif et le lien.

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-journal
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les sources du journal technique de la mère qui parlent du relais : la liaison (`relais`) et les gestes d'administration (`administration`).
const Set<String> rlsSourcesJournal = {'relais', 'administration'};

class EcranRlsJournal extends EcranRls {
  const EcranRlsJournal({super.key});
  @override
  String get titre => 'Journal d’audit du relais';
  @override
  String get description => 'Qui a fait quoi sur le panneau : connexions, révocations, codes, changements de paramètres.';
  @override
  String get regle =>
      'Aucune action anonyme (RG-12). Conservation 365 jours (30 au minimum) ; la purge ne touche jamais aux enveloppes. '
      'Le journal du panneau (connexions, paramètres) n’est lisible que sur le panneau web ; ici, les évènements de la mère qui concernent le relais.';
  @override
  State<EcranRlsJournal> createState() => _EtatJournalRls();
}

class _EtatJournalRls extends RlsEtatEcran<EcranRlsJournal> {
  @override
  bool get avecJournal => true;

  @override
  Widget build(BuildContext context) {
    final d = donnees;
    final lignes = <Ligne>[
      for (final (i, l) in (d?.journal ?? const <MrbLigneJournal>[]).where((x) => rlsSourcesJournal.contains(x.source)).indexed)
        {
          'id': i,
          'quand': l.quand,
          'acteur': 'mère (${l.source})',
          'action': l.message,
          'detail': switch (l.niveau) { 'alerte' => 'Alerte', 'erreur' => 'Erreur', _ => 'Information' },
        }
    ];
    return rlsPage(context, ecran: 'rls-journal', panne: panne, lecture: d, blocs: [
      rlsCarteTableau(
          'Journal',
          rlsTableau(
            colonnes: [
              ColonneTableau(cle: 'quand', libelle: 'Quand', sansCoupure: true, valeur: (l) => l['quand'], texte: (l) => mrbDateHeureMs(l['quand']! as int)),
              rlsCol('acteur', 'Acteur'),
              rlsCol('action', 'Action'),
              rlsCol('detail', 'Détail'),
            ],
            lignes: lignes,
            messageVide: d == null
                ? 'Journal non lu : le service de la mère ne répond pas.'
                : (d.journal == null ? 'Journal technique de la mère non disponible.' : 'Aucun évènement de la mère concernant le relais.'),
          )),
      const NoteSigh(
          'Ces lignes viennent du journal technique de la mère (sources « relais » et « administration »), pas du journal d’audit du panneau. '
          'Les connexions au panneau et les changements de paramètres du relais n’y figurent pas.',
          ton: TonSigh.neutre,
          icone: LucideIcons.info),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-superadmin
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranRlsSuperadmin extends EcranRls {
  const EcranRlsSuperadmin({super.key});
  @override
  String get titre => 'Comptes superadmin';
  @override
  String get description => 'Les comptes qui administrent le relais : création par commande, mot de passe, sessions, double facteur.';
  @override
  String get regle =>
      'Un compte se crée par commande (relais:superadmin, tâche cron à usage unique sur cPanel) : pas d’inscription publique. Mot de passe de 12 caractères au moins. '
      'Les comptes du panneau appartiennent au relais : ils ne sont pas lisibles depuis la mère.';
  @override
  State<EcranRlsSuperadmin> createState() => _EtatSuperadmin();
}

class _EtatSuperadmin extends RlsEtatEcran<EcranRlsSuperadmin> {
  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return rlsPage(context, ecran: 'rls-superadmin', panne: panne, lecture: donnees, blocs: [
      rlsCarteTableau(
          'Comptes',
          rlsTableau(
            colonnes: [rlsCol('courriel', 'Courriel'), rlsCol('cree', 'Créé'), rlsCol('connexion', 'Dernière connexion'), rlsCol('double', 'Double facteur')],
            lignes: const [],
            messageVide: 'Comptes non disponibles : ils sont tenus par le panneau Laravel du relais.',
            indiceVide: rlsMotifRelais,
          )),
      rlsCarteTableau(
          'Sessions ouvertes',
          rlsTableau(
            colonnes: [rlsCol('appareil', 'Appareil'), rlsCol('adresse', 'Adresse'), rlsCol('depuis', 'Depuis')],
            lignes: const [],
            messageVide: 'Sessions non disponibles : elles sont tenues par le panneau Laravel du relais.',
            indiceVide: rlsMotifRelais,
          )),
      if (c.peutEcrire)
        Wrap(spacing: 8, runSpacing: 8, children: [
          BoutonSigh(
              libelle: 'Changer le mot de passe',
              icone: LucideIcons.keyRound,
              onPressed: () => rlsRefuser(context,
                  geste: 'changement du mot de passe superadmin',
                  motif: 'Le compte appartient au panneau du relais, qui vérifie l’ancien mot de passe. À faire sur l’écran « Comptes superadmin » du panneau web.')),
        ]),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-parametres
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranRlsParametres extends EcranRls {
  const EcranRlsParametres({super.key});
  @override
  String get titre => 'Paramètres du relais';
  @override
  String get description => 'Secret de la mère, seuil de battement, rétention de l’audit, crochets du banc d’essai (fermés).';
  @override
  String get regle =>
      'Le secret de la mère se pose dans le .env du relais (jamais en base). Les crochets du banc d’essai sont fermés en production. '
      'Faire tourner le secret : le changer dans le .env du relais et dans la configuration de la mère, dans la même minute.';
  @override
  State<EcranRlsParametres> createState() => _EtatParametres();
}

class _EtatParametres extends RlsEtatEcran<EcranRlsParametres> {
  @override
  Widget build(BuildContext context) {
    final d = donnees;
    final adresse = d?.adresseRelais;
    final lignes = <Ligne>[
      {
        'id': 'adresse',
        'parametre': 'Adresse du relais (réglée sur ce poste)',
        'valeur': adresse == null ? rlsNd : (adresse.isEmpty ? 'aucun relais configuré' : adresse),
        'ou': 'Réglages du poste',
      },
      {'id': 'battement', 'parametre': 'Seuil de battement', 'valeur': rlsNd, 'ou': 'RELAIS_SEUIL_BATTEMENT_MS'},
      {'id': 'secret', 'parametre': 'Secret de la mère', 'valeur': 'jamais affiché', 'ou': 'RELAIS_SECRET_MERE'},
      {'id': 'audit', 'parametre': 'Rétention de l’audit', 'valeur': rlsNd, 'ou': 'relais:purger'},
      {'id': 'banc', 'parametre': 'Crochets du banc', 'valeur': rlsNd, 'ou': 'RELAIS_BANC'},
    ];
    return rlsPage(context, ecran: 'rls-parametres', panne: panne, lecture: d, blocs: [
      rlsCarteTableau(
          'Paramètres',
          rlsTableau(
            colonnes: [rlsCol('parametre', 'Paramètre'), rlsCol('valeur', 'Valeur'), rlsCol('ou', 'Où')],
            lignes: lignes,
            messageVide: 'Aucun paramètre.',
          )),
      const NoteSigh('Faire tourner le secret : le changer dans le .env du relais et dans la configuration de la mère, dans la même minute.',
          ton: TonSigh.attention, icone: LucideIcons.keyRound),
      const NoteSigh(
          'Seule l’adresse du relais est connue de ce poste. Les autres valeurs sont dans le .env du relais, jamais lues par la mère : elles se consultent sur le panneau web. '
          'Le secret de la mère n’est affiché nulle part.',
          ton: TonSigh.neutre,
          icone: LucideIcons.info),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-hebergement
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les contrôles de l'hébergement que mesure le relais (`App\Relais\...`), nommés comme le panneau les nomme. La mère n'en reçoit aucun.
const List<String> rlsControlesHebergement = ['Cron schedule:run', 'Certificat TLS', 'Dossier storage/', 'Extension pdo_pgsql'];

class EcranRlsHebergement extends EcranRls {
  const EcranRlsHebergement({super.key});
  @override
  String get titre => 'Hébergement';
  @override
  String get description => 'Santé de l’hébergement mutualisé : PHP, base, cron, disque, certificat.';
  @override
  String get regle =>
      'Contraintes connues : PHP 8.2 ou plus, PostgreSQL, cron toutes les minutes, pas de SSH, pas de Redis, pas de WebSocket (la mère interroge, le relais n’appelle jamais). '
      'La santé de l’hébergement est mesurée par le relais lui-même ; ce poste n’en reçoit rien.';
  @override
  State<EcranRlsHebergement> createState() => _EtatHebergement();
}

class _EtatHebergement extends RlsEtatEcran<EcranRlsHebergement> {
  @override
  Widget build(BuildContext context) {
    final d = donnees;
    final liaison = d?.liaison;
    const motif = 'Mesure faite par le relais sur son hébergement ; elle se lit sur le panneau web.';
    return rlsPage(context, ecran: 'rls-hebergement', panne: panne, lecture: d, blocs: [
      mrbGrilleKpi([
        mrbKpi('PHP', null, indice: motif, icone: LucideIcons.code),
        mrbKpi('Base', null, indice: motif, icone: LucideIcons.database),
        mrbKpi('Cron', null, indice: motif, icone: LucideIcons.timer),
        mrbKpi('Disque', null, indice: motif, icone: LucideIcons.hardDrive),
      ]),
      rlsCarteTableau(
          'Contrôles',
          rlsTableau(
            colonnes: [
              rlsCol('controle', 'Contrôle'),
              ColonneTableau(
                  cle: 'etat',
                  libelle: 'État',
                  triable: false,
                  rendu: (_, l) => BadgeSigh('${l['etat']}', ton: switch (l['code']) { 'ok' => TonSigh.succes, 'attention' => TonSigh.attention, 'alerte' => TonSigh.danger, _ => TonSigh.neutre }),
                  texte: (l) => '${l['etat']}'),
              rlsCol('detail', 'Détail'),
            ],
            lignes: [
              if (liaison != null)
                {'id': 'liaison', 'controle': 'Liaison de la mère avec le relais', 'code': liaison.etat, 'etat': mrbLibelleEtat(liaison.etat), 'detail': liaison.detail},
              for (final n in rlsControlesHebergement)
                {'id': n, 'controle': n, 'code': 'inconnu', 'etat': rlsNd, 'detail': 'Mesuré par le relais, lisible sur le panneau web.'},
            ],
            messageVide: d == null ? 'Contrôles non lus : le service de la mère ne répond pas.' : 'Aucun contrôle.',
          )),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-sauvegarde
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranRlsSauvegarde extends EcranRls {
  const EcranRlsSauvegarde({super.key});
  @override
  String get titre => 'Sauvegarde du relais';
  @override
  String get description => 'Export de la base du relais avant toute migration ; le journal chiffré qu’elle contient sert à restaurer la mère.';
  @override
  String get regle =>
      'Avant chaque migrate : export de la base (phpPgAdmin ou pg_dump par cron). Le contenu est déjà chiffré : un export ne contient aucune donnée lisible. '
      'La sauvegarde de la mère est un autre sujet : elle se pilote depuis « Sauvegardes et restauration » du poste mère.';
  @override
  State<EcranRlsSauvegarde> createState() => _EtatSauvegardeRls();
}

class _EtatSauvegardeRls extends RlsEtatEcran<EcranRlsSauvegarde> {
  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    const motif = 'Export de la base du relais : tenu par le relais, lisible sur le panneau web.';
    return rlsPage(context, ecran: 'rls-sauvegarde', panne: panne, lecture: donnees, blocs: [
      mrbGrilleKpi([
        mrbKpi('Dernier export', null, indice: motif, icone: LucideIcons.databaseBackup),
        mrbKpi('Taille', null, indice: motif, icone: LucideIcons.fileArchive),
      ]),
      rlsCarteTableau(
          'Exports',
          rlsTableau(
            colonnes: [rlsCol('date', 'Date'), rlsCol('taille', 'Taille'), rlsCol('migration', 'Avant migration')],
            lignes: const [],
            messageVide: 'Exports non disponibles : la liste est tenue par le relais.',
            indiceVide: rlsMotifRelais,
          )),
      if (c.peutEcrire)
        Wrap(spacing: 8, runSpacing: 8, children: [
          BoutonSigh(
              libelle: 'Exporter maintenant',
              icone: LucideIcons.download,
              onPressed: () => rlsRefuser(context,
                  geste: 'export de la base du relais',
                  motif: 'Seul le relais peut exporter sa base (commande relais:exporter). À lancer depuis l’écran « Sauvegarde du relais » du panneau web.')),
        ]),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-opacite
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce que le relais voit et ne voit pas : la CONCEPTION du protocole (spec de synchronisation, §12), pas une mesure. La mesure (entropie des 200 dernières
/// enveloppes) est faite par le relais.
const List<({String information, String visible, bool ouvert})> rlsVisibilite = [
  (information: 'Identifiant et état de l’appareil', visible: 'oui', ouvert: true),
  (information: 'Sens, rang, taille, date d’une enveloppe', visible: 'oui', ouvert: true),
  (information: 'Contenu d’une enveloppe', visible: 'non (chiffré)', ouvert: false),
  (information: 'Nom d’une collection ou d’un champ', visible: 'non', ouvert: false),
  (information: 'La clé de clinique', visible: 'non', ouvert: false),
];

class EcranRlsOpacite extends EcranRls {
  const EcranRlsOpacite({super.key});
  @override
  String get titre => 'Preuve d’opacité';
  @override
  String get description => 'Ce que le relais détient et ne détient pas : la démonstration que l’hébergeur ne peut rien lire.';
  @override
  String get regle =>
      'Le relais n’a aucun code de chiffrement ni clé. Un test d’opacité décode les enveloppes et mesure leur entropie (plus de 7 bits par octet). '
      'Le tableau ci-dessous décrit la conception du protocole ; la mesure se fait sur le relais.';
  @override
  State<EcranRlsOpacite> createState() => _EtatOpacite();
}

class _EtatOpacite extends RlsEtatEcran<EcranRlsOpacite> {
  @override
  Widget build(BuildContext context) {
    const mesure = 'Mesure faite par le relais sur ses 200 dernières enveloppes ; elle se lit sur le panneau web.';
    return rlsPage(context, ecran: 'rls-opacite', panne: panne, lecture: donnees, blocs: [
      mrbGrilleKpi([
        mrbKpi('Clé de clinique au relais', 'Aucune',
            indice: 'Par conception : la mère ne dépose jamais la clé. Non mesuré depuis ce poste.', ton: TonSigh.succes, icone: LucideIcons.keyRound),
        mrbKpi('Entropie moyenne', null, indice: mesure, icone: LucideIcons.binary),
        mrbKpi('Noms de collection lisibles', null, indice: mesure, icone: LucideIcons.eyeOff),
      ]),
      rlsCarteTableau(
          'Ce que le relais voit',
          rlsTableau(
            colonnes: [
              rlsCol('information', 'Information'),
              ColonneTableau(
                  cle: 'visible',
                  libelle: 'Visible ?',
                  triable: false,
                  rendu: (_, l) => l['ouvert'] == true ? Text('${l['visible']}') : BadgeSigh('${l['visible']}', ton: TonSigh.succes),
                  texte: (l) => '${l['visible']}'),
            ],
            lignes: [
              for (final (i, v) in rlsVisibilite.indexed) {'id': i, 'information': v.information, 'visible': v.visible, 'ouvert': v.ouvert}
            ],
            messageVide: 'Aucune information.',
          )),
    ]);
  }
}
