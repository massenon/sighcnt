import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/flux_commun.dart' show modaleSaisie;
import 'qual_commun.dart';
import 'qual_publique.dart';
import 'qual_qr.dart';

/// L'adresse du serveur qui sert la page publique d'une enquête. Le poste ne connaît pas l'adresse de la clinique sur le réseau : en exploitation, c'est
/// celle du serveur de la clinique ou du relais qui doit être communiquée (E574). Remplaçable par la configuration du poste.
String adresseDesLiens = 'http://serveur-clinique';

/// `lienDuJeton(code)` : l'adresse de la page publique — le jeton, jamais l'identifiant de l'enquête.
String lienDuJeton(String code) => '$adresseDesLiens/enquete-publique.php?jeton=${Uri.encodeQueryComponent(code)}';

/// `adm-enquetes` — « Enquêtes & questionnaires » : le générateur de questionnaires. Le questionnaire est une DONNÉE : le formulaire de
/// saisie naît du modèle (comme sur KoboCollect), ajouter une question au modèle suffit à la faire paraître à la prochaine saisie ; les réponses déjà
/// recueillies gardent leur forme. Le modèle de satisfaction amorcé est une proposition validée par la Direction le 01/09/2026.
///
/// Le partage à un tiers : un lien suppose d'être JOIGNABLE — le serveur de la clinique n'a aucun port ouvert sur Internet ; le lien et le QR couvrent le
/// tiers DANS la clinique et la tablette en mode kiosque. L'adresse porte un JETON daté et révocable, jamais l'identifiant de l'enquête. Les commandes
/// d'écriture (Nouveau modèle, Recueillir, Modifier, Partager) sont ABSENTES sans le droit d'écrire ; Révoquer sans le droit d'annuler.
class EcranEnquetes extends StatelessWidget with EcranMaquette {
  const EcranEnquetes({super.key});

  @override
  String get titre => 'Enquêtes & questionnaires';

  @override
  String get description =>
      'Le générateur de questionnaires : le formulaire de saisie naît du modèle, comme sur KoboCollect.';

  @override
  String get regle =>
      'Le questionnaire est une donnée : ajouter une question au modèle suffit à la faire paraître à la prochaine saisie — rien n’est codé. Les réponses déjà recueillies gardent leur forme. Le modèle de satisfaction amorcé est une proposition : aucun document de cadrage ne fixe de questionnaire.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final enquetes = colEnquetes(m), reponses = colReponses(m), jetons = colJetons(m);
    return ListenableBuilder(
        listenable: Listenable.merge([enquetes, reponses, jetons]),
        builder: (context, _) {
          final rows = enquetes.actives;
          final reps = reponses.actives;
          final liens = jetons.actives;
          final jour = jourIso(c);
          final ouverts = liens.where((j) => qualJetonOuvert(j, aLaDate: jour)).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(
                  libelle: 'Modèles d’enquête',
                  valeur: nombre(rows.length),
                  icone: LucideIcons.clipboardList,
                  ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Réponses recueillies',
                  valeur: nombre(reps.length),
                  icone: LucideIcons.messagesSquare,
                  ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Dont par lien partagé',
                  valeur: nombre(reps.where((x) => x['canal'] == qualCanalPublic).length),
                  icone: LucideIcons.link,
                  ton: TonSigh.neutre,
                  indice: 'Canal « $qualCanalPublic »'),
              KpiSigh(
                  libelle: 'Liens ouverts',
                  valeur: nombre(ouverts),
                  icone: LucideIcons.share2,
                  ton: ouverts > 0 ? TonSigh.attention : TonSigh.neutre,
                  indice: 'Datés et révocables'),
              KpiSigh(
                  libelle: 'Modèles à valider',
                  valeur: nombre(rows.where((r) => r['aValider'] == true).length),
                  icone: LucideIcons.circleHelp,
                  ton: TonSigh.attention,
                  indice: 'Propositions — aucun document ne les fixe'),
            ]),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(
                  id: 'modeles',
                  libelle: 'Modèles (${rows.length})',
                  construire: (ctx) => _tableModeles(context, c, rows, reps)),
              OngletDef(
                  id: 'partage',
                  libelle: 'Liens de partage (${liens.length})',
                  construire: (ctx) => _tablePartage(context, c, liens, reps, jour)),
            ]),
          ]);
        });
  }

  // ------------------------------------------------------------------------------------------------------------------------------------------
  // Modèles
  // ------------------------------------------------------------------------------------------------------------------------------------------
  Widget _tableModeles(BuildContext ecran, ContexteEcran c, List<Fiche> rows, List<Fiche> reps) => TableauSigh(
        titre: 'Modèles',
        lignes: rows,
        taillePage: 8,
        nomExport: 'enquetes',
        messageVide: 'Aucun modèle d’enquête.',
        actions: [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Nouveau modèle',
                icone: LucideIcons.plus,
                taille: TailleBouton.sm,
                onPressed: () => _editerModele(ecran, null)),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'titre',
              libelle: 'Enquête',
              texte: (r) => '${r['titre']} ${r['description'] ?? ''}',
              rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['titre']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: JetonsShell.slate800,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w500)),
                    Text('${r['description'] ?? ''}',
                        style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                  ])),
          ColonneTableau(
              cle: 'questions',
              libelle: 'Questions',
              droite: true,
              valeur: (r) => (r['questions'] as List? ?? const []).length,
              texte: (r) => '${(r['questions'] as List? ?? const []).length}'),
          ColonneTableau(
              cle: 'reponses',
              libelle: 'Réponses',
              droite: true,
              valeur: (r) => reps.where((x) => x['enqueteId'] == r['id']).length,
              texte: (r) => '${reps.where((x) => x['enqueteId'] == r['id']).length}'),
          ColonneTableau(
              cle: 'aValider',
              libelle: 'Statut',
              texte: (r) => r['aValider'] == true ? 'Proposition à valider' : 'Validé',
              rendu: (_, r) => r['aValider'] == true
                  ? const BadgeSigh('Proposition à valider', ton: TonSigh.attention)
                  : const BadgeSigh('Validé', ton: TonSigh.succes)),
        ],
        actionsLigne: (ctx, r) => [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Recueillir',
                icone: LucideIcons.plus,
                taille: TailleBouton.sm,
                onPressed: () => _saisirReponse(ecran, r)),
          BoutonIcone(
              icone: LucideIcons.eye,
              libelle: 'Voir les réponses',
              onPressed: () => _voirReponses(ecran, r)),
          if (c.droit.editer)
            BoutonIcone(
                icone: LucideIcons.share2,
                libelle: 'Partager à un tiers',
                onPressed: () => _ouvrirPartage(ecran, r)),
          if (c.droit.editer)
            BoutonIcone(
                icone: LucideIcons.pencil,
                libelle: 'Modifier le modèle',
                onPressed: () => _editerModele(ecran, r)),
        ],
      );

  /// Recueillir une réponse : le formulaire NAÎT du modèle. Un canal, puis une question = un champ.
  void _saisirReponse(BuildContext ecran, Fiche enq) {
    final c = ContexteEcran.of(ecran);
    modaleSaisie(ecran,
        titre: 'Recueillir une réponse — ${enq['titre']}',
        sousTitre: 'Le formulaire est engendré depuis le modèle : modifier le modèle suffit à le changer.',
        taille: TailleModale.lg,
        libelleOk: 'Enregistrer la réponse',
        icone: LucideIcons.check,
        champs: [
          ChampDef(
              nom: '_canal',
              libelle: 'Canal de recueil',
              type: TypeChamp.select,
              requis: true,
              options: [for (final x in qualCanaux) OptionChamp(x)]),
          ...champsDeModele(enq['questions']),
        ],
        surValider: (v) {
          final valeurs = {...v}..remove('_canal');
          final fiche = qualReponse(enq, valeurs,
              aujourdhui: c.aujourdhui, canal: '${v['_canal']}', saisiPar: c.utilisateur);
          colReponses(c.magasin).inserer(fiche, prefixe: 'REP');
          ToastsSigh.afficher(ecran, 'Réponse recueillie.', type: TypeToast.succes);
          return true;
        });
  }

  void _voirReponses(BuildContext ecran, Fiche r) {
    final c = ContexteEcran.of(ecran);
    final reps = [
      for (final x in colReponses(c.magasin).actives)
        if (x['enqueteId'] == r['id']) x
    ];
    afficherTiroir<void>(ecran,
        titre: '${r['titre']}',
        sousTitre: '${nombre(reps.length)} réponse(s)',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final x in reps.take(30)) ...[
            CarteSigh(
                titre: '${dateJj(x['date'])} — ${x['canal'] ?? ''}',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Question', (l) => '${l['q']}'),
                  ColonneMini('Réponse', (l) => '${l['r']}'),
                ], lignes: [
                  for (final q in (r['questions'] as List? ?? const []).cast<Map>())
                    {
                      'q': '${q['libelle']}',
                      'r': () {
                        final v = (x['reponses'] as Map?)?[q['code']];
                        return v == null || v == '' ? '—' : '$v';
                      }()
                    }
                ])),
            const SizedBox(height: 12),
          ]
        ]));
  }

  // ------------------------------------------------------------------------------------------------------------------------------------------
  // Créer ou modifier un modèle
  // ------------------------------------------------------------------------------------------------------------------------------------------
  void _editerModele(BuildContext ecran, Fiche? r) {
    final c = ContexteEcran.of(ecran);
    final creation = r == null;
    final ctl = ControleurFormulaire(const [
      ChampDef(nom: 'titre', libelle: 'Titre de l’enquête', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'description', libelle: 'Description', col: ColChamp.plein),
    ], {
      'titre': r?['titre'],
      'description': r?['description']
    });
    final questions = <Fiche>[
      for (final q in (r?['questions'] as List? ?? const []).cast<Map>()) {...q.cast<String, Object?>()}
    ];
    afficherModale<void>(ecran,
        titre: creation ? 'Nouveau modèle d’enquête' : 'Modifier — ${r['titre']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          CarteSigh(titre: 'Questions', child: _EditeurQuestions(ecran, questions)),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: creation ? 'Créer le modèle' : 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    if (questions.isEmpty) {
                      ToastsSigh.afficher(ecran, 'Un questionnaire sans question ne recueille rien.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final col = colEnquetes(c.magasin);
                    if (creation) {
                      col.inserer({
                        ...v,
                        'statut': 'actif',
                        'reference': _prochaineReference(col),
                        'questions': [for (final q in questions) {...q}],
                        'aValider': true,
                        'creeLe': jourIso(c),
                        'source': 'Créé dans l’application — à valider',
                      }, prefixe: 'ENQ');
                    } else {
                      col.mettreAJour(r['id'], {...v, 'questions': [for (final q in questions) {...q}]});
                    }
                    fermer();
                    ToastsSigh.afficher(ecran, creation ? 'Modèle créé.' : 'Modèle enregistré.', type: TypeToast.succes);
                  }),
            ]);
  }

  /// `ENQ-NNN` : le numéro suit le registre (le plus grand déjà attribué + 1), non un compteur de page (E573).
  String _prochaineReference(CollectionMagasin col) {
    var max = 0;
    for (final f in col.toutes) {
      final m = RegExp(r'^ENQ-(\d+)$').firstMatch('${f['reference']}');
      if (m != null) max = max < int.parse(m.group(1)!) ? int.parse(m.group(1)!) : max;
    }
    return 'ENQ-${(max + 1).toString().padLeft(3, '0')}';
  }

  // ------------------------------------------------------------------------------------------------------------------------------------------
  // Partage à un tiers
  // ------------------------------------------------------------------------------------------------------------------------------------------
  Widget _tablePartage(BuildContext ecran, ContexteEcran c, List<Fiche> liens, List<Fiche> reps, String jour) {
    final tries = trierPar(liens, (j) => j['creeLe']).reversed.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Un lien suppose d’être joignable. Le serveur de la clinique est local, sans port ouvert sur Internet : un lien fonctionne pour qui est dans la clinique — salle d’attente, Wi-Fi, ou tablette posée à la sortie, qui ne demande même pas de lien. Faire répondre un patient depuis chez lui exige une surface publique sur Internet : c’est un ré-arbitrage d’architecture, pas une option à cocher — et surtout pas l’ouverture du serveur de la clinique.',
          ton: TonSigh.attention,
          icone: LucideIcons.wifi),
      const SizedBox(height: 12),
      const NoteSigh(
          'Dans le prototype, chaque poste a son propre stockage : un lien ouvert sur une autre machine y afficherait bien le formulaire, mais ses réponses ne reviendraient jamais ici. Le geste se maquette — jeton, page publique, QR — la collecte réelle appartient à la version web.'),
      const SizedBox(height: 12),
      TableauSigh(
        titre: 'Liens de partage',
        lignes: tries,
        taillePage: 8,
        nomExport: 'liens-enquete',
        messageVide: 'Aucun lien de partage — en ouvrir un depuis l’onglet « Modèles ».',
        colonnes: [
          const ColonneTableau(cle: 'enqueteTitre', libelle: 'Enquête'),
          ColonneTableau(
              cle: 'jeton',
              libelle: 'Jeton',
              texte: (j) => '${'${j['jeton']}'.substring(0, min(8, '${j['jeton']}'.length))}…',
              rendu: (_, j) => mono('${'${j['jeton']}'.substring(0, min(8, '${j['jeton']}'.length))}…')),
          ColonneTableau(
              cle: 'anonyme',
              libelle: 'Recueil',
              texte: (j) => j['anonyme'] == true ? 'Anonyme' : 'Nominatif',
              rendu: (_, j) => j['anonyme'] == true
                  ? const BadgeSigh('Anonyme', ton: TonSigh.info)
                  : const BadgeSigh('Nominatif', ton: TonSigh.attention)),
          ColonneTableau(cle: 'expireLe', libelle: 'Expire le', texte: (j) => dateJj(j['expireLe'])),
          ColonneTableau(
              cle: 'reponses',
              libelle: 'Réponses',
              droite: true,
              valeur: (j) => reps.where((x) => x['jetonId'] == j['id']).length,
              texte: (j) => '${reps.where((x) => x['jetonId'] == j['id']).length}'),
          ColonneTableau(
              cle: 'etat',
              libelle: 'État',
              texte: (j) => qualEtatJeton(j, aLaDate: jour).libelle,
              rendu: (_, j) {
                final e = qualEtatJeton(j, aLaDate: jour);
                return BadgeSigh(e.libelle, ton: tonQual(e.ton));
              }),
        ],
        actionsLigne: (ctx, j) => [
          BoutonIcone(
              icone: LucideIcons.qrCode,
              libelle: 'Afficher le lien et le QR',
              onPressed: () => _montrerLien(ecran, j)),
          if (qualJetonOuvert(j, aLaDate: jour) && c.droit.annuler)
            BoutonIcone(icone: LucideIcons.ban, libelle: 'Révoquer le lien', onPressed: () => _revoquer(ecran, j)),
        ],
      ),
    ]);
  }

  void _ouvrirPartage(BuildContext ecran, Fiche enq) {
    final c = ContexteEcran.of(ecran);
    final ctl = ControleurFormulaire(const [
      ChampDef(
          nom: 'anonyme',
          libelle: 'Recueil',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            OptionChamp('oui', 'Anonyme — aucun lien vers un dossier patient'),
            OptionChamp('non', 'Nominatif — le répondant se nomme, et le formulaire le dit'),
          ],
          aide:
              'Décision explicite : si l’enquête est annoncée anonyme, on ne stocke ni identité ni lien vers le dossier — sinon « anonyme » est un mensonge.'),
      ChampDef(nom: 'usage', libelle: 'Où le tiers répond-il ?', type: TypeChamp.select, requis: true, options: [
        OptionChamp('salle', 'Dans la clinique — QR affiché ou imprimé'),
        OptionChamp('tablette', 'Sur une tablette de la clinique (mode kiosque)'),
        OptionChamp('reseau', 'Sur le réseau local — lien communiqué'),
      ]),
      ChampDef(
          nom: 'expireLe',
          libelle: 'Le lien expire le',
          type: TypeChamp.date,
          requis: true,
          aide: 'Un lien sans terme collecte des réponses des mois après la clôture.'),
      ChampDef(nom: 'note', libelle: 'Note interne', col: ColChamp.plein),
    ], {
      'anonyme': 'oui',
      'usage': 'salle',
      'expireLe': iso(c.aujourdhui.add(const Duration(days: 30)))
    });
    afficherModale<void>(ecran,
        titre: 'Partager — ${enq['titre']}',
        sousTitre: 'Le lien porte un jeton tiré au hasard, jamais l’identifiant de l’enquête.',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          const NoteSigh(
              'Aucune donnée médicale sur une page publique. Une enquête de satisfaction interroge l’accueil, l’attente, la propreté, la clarté des explications — jamais le diagnostic ni le motif de venue. Un formulaire qui rappellerait « votre consultation du 3 septembre en gynécologie » exposerait le patient à quiconque regarde son écran.',
              ton: TonSigh.danger,
              icone: LucideIcons.shieldAlert),
          const SizedBox(height: 12),
          const NoteSigh(
              'La page publique ne porte ni ruban, ni recherche, ni session, ni fil d’Ariane : une page d’enquête qui afficherait la coquille de l’application serait une porte.',
              icone: LucideIcons.lock),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Ouvrir le lien',
                  icone: LucideIcons.share2,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final alea = Random.secure();
                    final res = colJetons(c.magasin).inserer(
                        qualNouveauJeton(
                            enquete: enq,
                            jeton: qualGenererJeton(alea.nextInt),
                            anonyme: '${v['anonyme']}',
                            usage: '${v['usage']}',
                            expireLe: '${v['expireLe']}',
                            note: '${v['note'] ?? ''}',
                            aujourdhui: c.aujourdhui,
                            ouvertPar: c.utilisateur),
                        prefixe: 'JET');
                    fermer();
                    _montrerLien(ecran, res.fiche);
                  }),
            ]);
  }

  void _montrerLien(BuildContext ecran, Fiche j) {
    final c = ContexteEcran.of(ecran);
    final lien = lienDuJeton('${j['jeton']}');
    final e = qualEtatJeton(j, aLaDate: jourIso(c));
    final nb = colReponses(c.magasin).actives.where((x) => x['jetonId'] == j['id']).length;
    afficherTiroir<void>(ecran,
        titre: 'Lien de partage',
        sousTitre: '${j['enqueteTitre']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: Alignment.centerLeft, child: BadgeSigh(e.libelle, ton: tonQual(e.ton))),
          const SizedBox(height: 12),
          const LibelleChamp('Adresse à communiquer'),
          TextField(
              key: const Key('qual:adresse'),
              controller: TextEditingController(text: lien),
              readOnly: true,
              style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate900),
              decoration: decorationChamp()),
          const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'En exploitation, c’est l’adresse du serveur sur le réseau de la clinique qu’il faut communiquer (http://<serveur>/…) — celle-ci est celle du poste courant.',
                  style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
          const SizedBox(height: 12),
          CarteSigh(
              titre: 'À afficher en salle d’attente',
              child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                QrSigh(lien),
                ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text(
                          'Le patient scanne avec son téléphone et remplit sur place. C’est là qu’on obtient des réponses : à chaud, avant de partir.',
                          style: TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                      const SizedBox(height: 8),
                      Text(
                          j['anonyme'] == true
                              ? 'Recueil ANONYME : ni identité, ni adresse réseau, ni lien vers un dossier patient.'
                              : 'Recueil NOMINATIF : le formulaire demande le nom et l’annonce clairement.',
                          style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
                    ])),
              ])),
          const SizedBox(height: 12),
          DescListeSigh([
            ('Enquête', '${j['enqueteTitre']}'),
            ('Ouvert le', '${dateJj(j['creeLe'])} par ${j['ouvertPar'] ?? '—'}'),
            ('Expire le', dateJj(j['expireLe'])),
            ('Réponses reçues', nombre(nb)),
            ('Note interne', j['note'] == null ? '—' : '${j['note']}'),
          ]),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Ouvrir la page publique',
                  icone: LucideIcons.externalLink,
                  variante: VarianteBouton.secondaire,
                  onPressed: () {
                    fermer();
                    ouvrirPagePublique(ecran, c.magasin, '${j['jeton']}', horloge: () => c.aujourdhui);
                  }),
              BoutonSigh(
                  libelle: 'Copier l’adresse',
                  icone: LucideIcons.copy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: lien));
                    if (ecran.mounted) ToastsSigh.afficher(ecran, 'Adresse copiée.', type: TypeToast.succes);
                  }),
            ]);
  }

  Future<void> _revoquer(BuildContext ecran, Fiche j) async {
    final c = ContexteEcran.of(ecran);
    final ok = await confirmerSigh(ecran,
        titre: 'Révoquer ce lien ?',
        message:
            'Le formulaire cessera immédiatement de s’ouvrir. Les réponses déjà recueillies sont conservées : révoquer ferme la porte, cela n’efface rien.',
        libelleOk: 'Révoquer',
        dangereux: true);
    if (!ok || !ecran.mounted) return;
    final annuler = colJetons(c.magasin).mettreAJour(j['id'], {'revoqueLe': jourIso(c), 'revoquePar': c.utilisateur});
    ToastsSigh.afficher(ecran, 'Lien révoqué.',
        type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Révocation annulée.');
  }
}

// ----------------------------------------------------------------------------------------------------------------------------------------------
// L'éditeur de questions : une liste modifiable, comme les lignes d'une dépense
// ----------------------------------------------------------------------------------------------------------------------------------------------
class _EditeurQuestions extends StatefulWidget {
  const _EditeurQuestions(this.ecran, this.questions);
  final BuildContext ecran;
  final List<Fiche> questions;

  @override
  State<_EditeurQuestions> createState() => _EtatEditeur();
}

class _EtatEditeur extends State<_EditeurQuestions> {
  String _typeLibelle(Object? t) {
    for (final x in qualTypesQuestion) {
      if (x.$1 == t) return x.$2;
    }
    return '$t';
  }

  @override
  Widget build(BuildContext context) {
    final qs = widget.questions;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (qs.isEmpty)
        const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Aucune question — en ajouter au moins une.',
                style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
      for (final (i, q) in qs.indexed)
        Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
            child: Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ${q['libelle']}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14)),
                Text(
                    '${_typeLibelle(q['type'])}${(q['options'] as List? ?? const []).isNotEmpty ? ' — ${(q['options'] as List).join(' · ')}' : ''}',
                    style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
              ])),
              BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier la question', onPressed: () => _editer(q, i)),
              const SizedBox(width: 4),
              BoutonIcone(
                  icone: LucideIcons.trash2,
                  libelle: 'Retirer la question',
                  onPressed: () => setState(() => qs.removeAt(i))),
            ])),
      Align(
          alignment: Alignment.centerLeft,
          child: BoutonSigh(
              libelle: 'Ajouter une question',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () => _editer(null, -1))),
    ]);
  }

  void _editer(Fiche? q, int idx) {
    final qs = widget.questions;
    modaleSaisie(widget.ecran,
        titre: q != null ? 'Modifier la question' : 'Nouvelle question',
        taille: TailleModale.md,
        libelleOk: q != null ? 'Enregistrer' : 'Ajouter',
        icone: q != null ? LucideIcons.save : LucideIcons.plus,
        champs: [
          const ChampDef(nom: 'libelle', libelle: 'Question', requis: true, col: ColChamp.plein),
          ChampDef(
              nom: 'type',
              libelle: 'Type de réponse',
              type: TypeChamp.select,
              requis: true,
              options: [for (final x in qualTypesQuestion) OptionChamp(x.$1, x.$2)]),
          const ChampDef(
              nom: 'optionsTexte',
              libelle: 'Choix proposés (séparés par |)',
              col: ColChamp.plein,
              aide: 'Pour une question à choix seulement.'),
        ],
        initial: q != null
            ? {'libelle': q['libelle'], 'type': q['type'], 'optionsTexte': (q['options'] as List? ?? const []).join('|')}
            : {'type': 'note'},
        surValider: (v) {
          final optionsTexte = '${v['optionsTexte'] ?? ''}';
          if (v['type'] == 'choix' && optionsTexte.trim().isEmpty) {
            ToastsSigh.afficher(widget.ecran, 'Une question à choix a besoin de ses choix.', type: TypeToast.erreur);
            return false;
          }
          final neuf = <String, Object?>{
            'code': q != null ? q['code'] : _codeNeuf(qs),
            'libelle': v['libelle'],
            'type': v['type'],
            'options': v['type'] == 'choix'
                ? [for (final x in optionsTexte.split('|')) if (x.trim().isNotEmpty) x.trim()]
                : null,
          };
          setState(() {
            if (q != null) {
              qs[idx] = neuf;
            } else {
              qs.add(neuf);
            }
          });
          return true;
        });
  }

  /// `'Q' + Date.now().toString(36).toUpperCase()` : un code horodaté, rendu unique dans le modèle.
  String _codeNeuf(List<Fiche> qs) {
    var n = DateTime.now().millisecondsSinceEpoch;
    String code() => 'Q${n.toRadixString(36).toUpperCase()}';
    while (qs.any((q) => q['code'] == code())) {
      n++;
    }
    return code();
  }
}
