import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../mere/client_mere.dart';
import '../../shell/contexte_ecran.dart';
import '../mere/mrb_commun.dart';
import '../mere/mrb_source.dart';
import 'rls_commun.dart';

/// Les six premiers écrans du module RLS : tableau de bord, appareils, boîtes aux lettres, codes d'appairage, indicateurs reçus, alertes.
/// Libellés repris des fiches de la maquette (`docs/architecture/ecrans/rls-*.json`) ; données lues par la mère (voir `rls_commun.dart`).

abstract class EcranRls extends StatefulWidget with EcranMaquette {
  const EcranRls({super.key});
}

/// Libellé lisible d'un type d'alerte que la mère relève sur le relais (`Pont.alerter`).
String rlsLibelleAlerte(String type) => switch (type) {
      'revocation_relais_differee' => 'Révocation pas encore transmise au relais',
      'appareil_inconnu' => 'Appareil inconnu du relais',
      'profil_declare_different' => 'Profil déclaré différent de celui du code',
      'trou' => 'Trou dans les rangs d’une boîte',
      'authentification' => 'Échecs d’authentification d’un appareil',
      _ => type,
    };

String _nomAppareil(RlsLecture d, String uuid) {
  for (final a in d.etat.appareils) {
    if (a.uuid == uuid) return a.nom;
  }
  return uuid;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-tableau
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranRlsTableau extends EcranRls {
  const EcranRlsTableau({super.key});
  @override
  String get titre => 'Tableau de bord du relais';
  // Le tiret cadratin est celui de la maquette : la parité N1 compare les libellés (E1740).
  @override
  String get description => 'La mère est-elle vivante, à jour, sauvegardée ? Volumes et alertes \u2014 sans aucun nom de patient.';
  @override
  String get regle =>
      'Le relais lève une alerte « battement » si la mère se tait plus de 5 minutes. Les indicateurs sont le seul contenu en clair. '
      'Ici, la mère dit ce qu’elle sait de sa liaison ; le battement vu par le relais lui-même se lit sur le panneau web.';
  @override
  State<EcranRlsTableau> createState() => _EtatTableau();
}

class _EtatTableau extends RlsEtatEcran<EcranRlsTableau> {
  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final d = donnees;
    final liaison = d?.liaison;
    final alertes = <Ligne>[];
    if (d != null) {
      for (final (i, a) in d.etat.alertes.indexed) {
        final quand = a['quand'] is num ? DateTime.fromMillisecondsSinceEpoch((a['quand']! as num).toInt()) : null;
        final uuid = a['appareil'] == null ? null : '${a['appareil']}';
        alertes.add({
          'id': 'a$i',
          'quand': quand == null ? rlsNd : rlsIlYa(quand, c.aujourdhui),
          'alerte': '${rlsLibelleAlerte('${a['type']}')}${uuid == null ? '' : ' : ${_nomAppareil(d, uuid)}'}',
          'duree': rlsNd,
        });
      }
      for (final u in d.etat.bloques) {
        alertes.add({'id': 'b$u', 'quand': rlsNd, 'alerte': 'Appareil bloqué : ${_nomAppareil(d, u)}', 'duree': 'en cours'});
      }
    }
    return rlsPage(context, ecran: 'rls-tableau', panne: panne, lecture: d, blocs: [
      mrbGrilleKpi([
        mrbKpi('Mère', d == null ? null : 'Vivante',
            indice: d == null
                ? null
                : 'Le service de la mère répond à ce poste. Liaison avec le relais : ${liaison == null ? rlsNd : '${mrbLibelleEtat(liaison.etat)}, ${liaison.detail}'}',
            ton: liaison == null ? TonSigh.neutre : mrbTon(liaison.etat),
            icone: LucideIcons.heartPulse),
        mrbKpi('Appareils actifs', d == null ? null : '${d.actifs}', indice: d == null ? null : 'appairés, ni révoqués ni bloqués', icone: LucideIcons.monitorSmartphone),
        mrbKpi('Enveloppes stockées', d?.etat.repN == null ? null : nombre(d!.etat.repN),
            indice: d?.etat.repN == null
                ? 'Compteur non fourni par le service de la mère.'
                : 'enveloppes de journal déposées par la mère ; les boîtes des mobiles se lisent sur le panneau web',
            icone: LucideIcons.mails),
        mrbKpi('Alertes', d == null ? null : '${alertes.length}',
            ton: alertes.isEmpty ? TonSigh.succes : TonSigh.attention, indice: d == null ? null : 'relevées par la mère sur le relais', icone: LucideIcons.bellRing),
      ]),
      rlsCarteTableau(
          'Dernières alertes',
          rlsTableau(colonnes: [rlsCol('quand', 'Quand'), rlsCol('alerte', 'Alerte'), rlsCol('duree', 'Durée')], lignes: alertes, messageVide: d == null ? 'Alertes non lues : le service de la mère ne répond pas.' : 'Aucune alerte relevée par la mère.')),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-appareils
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranRlsAppareils extends EcranRls {
  const EcranRlsAppareils({super.key});
  @override
  String get titre => 'Appareils';
  @override
  String get description => 'Les appareils appairés : état, dernier contact, boîte aux lettres. Révocation.';
  @override
  String get regle =>
      'Un appareil révoqué est effacé à son prochain contact s’il s’agit d’un mobile ; sa fiche reste (RG-14). Le jeton n’est jamais conservé en clair '
      '(seule son empreinte l’est). La révocation passe par la mère, qui la transmet au relais.';
  @override
  State<EcranRlsAppareils> createState() => _EtatAppareils();
}

class _EtatAppareils extends RlsEtatEcran<EcranRlsAppareils> {
  Future<void> _revoquer(BuildContext contexte, String uuid, String nom) async {
    final s = source;
    if (s == null) return;
    final ok = await confirmerSigh(contexte,
        titre: 'Révoquer $nom ?',
        message: 'Action journalisée. L’appareil perd l’accès dès son prochain contact ; sa fiche reste au registre (RG-14).',
        libelleOk: 'Révoquer',
        dangereux: true);
    if (ok && contexte.mounted) await geste(contexte, () => s.revoquer(uuid), ok: 'Appareil révoqué : $nom.');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final d = donnees;
    final detail = {for (final a in d?.appareils ?? const <Appareil>[]) a.uuid: a};
    final lignes = <Ligne>[
      for (final a in d?.etat.appareils ?? const <MrbAppareil>[])
        {
          'id': a.uuid,
          'appareil': a.nom,
          'identifiant': a.uuid,
          'etat': a.etat == 'revoque' ? 'révoqué' : (d!.etat.bloques.contains(a.uuid) ? 'bloqué' : 'actif'),
          'contact': detail[a.uuid]?.dernierContact == null ? rlsNd : rlsIlYa(detail[a.uuid]!.dernierContact!, c.aujourdhui),
          'attente': detail[a.uuid] == null ? rlsNd : '${(d!.etat.seqMax - detail[a.uuid]!.derniereSeq).clamp(0, 1 << 31)}',
          'revoque': a.etat == 'revoque',
        }
    ];
    return rlsPage(context, ecran: 'rls-appareils', panne: panne, lecture: d, blocs: [
      rlsCarteTableau(
          'Appareils',
          rlsTableau(
            colonnes: [
              rlsCol('appareil', 'Appareil'),
              rlsCol('identifiant', 'Identifiant'),
              ColonneTableau(
                  cle: 'etat',
                  libelle: 'État',
                  triable: false,
                  rendu: (_, l) => BadgeSigh('${l['etat']}',
                      ton: switch (l['etat']) { 'actif' => TonSigh.succes, 'bloqué' => TonSigh.danger, _ => TonSigh.neutre }),
                  texte: (l) => '${l['etat']}'),
              rlsCol('contact', 'Dernier contact'),
              rlsCol('attente', 'En attente'),
            ],
            lignes: lignes,
            messageVide: d == null ? 'Appareils non lus : le service de la mère ne répond pas.' : 'Aucun appareil appairé.',
            actionsLigne: c.peutEcrire
                ? (ctx, l) => [
                      if (l['revoque'] != true)
                        BoutonSigh(
                            libelle: 'Révoquer',
                            icone: LucideIcons.ban,
                            taille: TailleBouton.sm,
                            variante: VarianteBouton.danger,
                            onPressed: () => _revoquer(ctx, '${l['id']}', '${l['appareil']}')),
                    ]
                : null,
          )),
      const NoteSigh(
          'En attente : opérations de la mère que l’appareil n’a pas encore acquittées (rang de la mère moins dernier rang de l’appareil). '
          'Les enveloppes qui l’attendent dans sa boîte au relais se lisent sur le panneau web.',
          ton: TonSigh.neutre,
          icone: LucideIcons.info),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-boites
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranRlsBoites extends EcranRls {
  const EcranRlsBoites({super.key});
  @override
  String get titre => 'Boîtes aux lettres';
  @override
  String get description => 'Pour chaque mobile : enveloppes déposées par la mère, enveloppes envoyées par le mobile, rangs, tailles.';
  @override
  String get regle =>
      'Chaque boîte est une suite contiguë (appareil, sens, rang). Un trou est détecté par la mère et bloque l’appareil : le relais ne supprime donc jamais une enveloppe seul. '
      'Les volumes, rangs et tailles sont tenus par le relais ; la mère n’en publie aucun.';
  @override
  State<EcranRlsBoites> createState() => _EtatBoites();
}

class _EtatBoites extends RlsEtatEcran<EcranRlsBoites> {
  @override
  Widget build(BuildContext context) {
    final d = donnees;
    final mobiles = d?.mobiles;
    final lignes = <Ligne>[
      for (final m in mobiles ?? const <MrbAppareil>[])
        {'id': m.uuid, 'mobile': m.nom, 'vers': rlsNd, 'depuis': rlsNd, 'rang': rlsNd, 'taille': rlsNd, 'ancienne': rlsNd}
    ];
    return rlsPage(context, ecran: 'rls-boites', panne: panne, lecture: d, blocs: [
      mrbGrilleKpi([
        mrbKpi('Boîtes', mobiles == null ? null : '${mobiles.length}', indice: mobiles == null ? null : 'une par mobile appairé non révoqué', icone: LucideIcons.inbox),
        mrbKpi('Vers les mobiles', null, indice: 'Volume tenu par le relais ; la mère ne le publie pas.', icone: LucideIcons.arrowDownToLine),
        mrbKpi('Depuis les mobiles', null, indice: 'Volume tenu par le relais ; la mère ne le publie pas.', icone: LucideIcons.arrowUpFromLine),
      ]),
      rlsCarteTableau(
          'Boîtes',
          rlsTableau(
            colonnes: [
              rlsCol('mobile', 'Mobile'),
              rlsCol('vers', 'Vers le mobile'),
              rlsCol('depuis', 'Depuis le mobile'),
              rlsCol('rang', 'Dernier rang reçu'),
              rlsCol('taille', 'Taille'),
              rlsCol('ancienne', 'Plus ancienne'),
            ],
            lignes: lignes,
            messageVide: d == null ? 'Boîtes non lues : le service de la mère ne répond pas.' : 'Aucun mobile appairé : aucune boîte aux lettres.',
            indiceVide: rlsMotifRelais,
          )),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-codes
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranRlsCodes extends EcranRls {
  const EcranRlsCodes({super.key});
  @override
  String get titre => 'Codes d’appairage';
  @override
  String get description => 'Codes à usage unique créés par la mère : ils expirent, ne servent qu’une fois, ne sont jamais conservés en clair.';
  @override
  String get regle =>
      'Le relais ne stocke que l’empreinte d’un code. Un code utilisé ou expiré est refusé avec la même réponse. '
      'L’état des codes (valides, utilisés, expirés) est tenu par le relais ; la mère les crée, elle ne relit pas leur état.';
  @override
  State<EcranRlsCodes> createState() => _EtatCodes();
}

class _EtatCodes extends RlsEtatEcran<EcranRlsCodes> {
  /// Les codes émis depuis cet écran pendant la séance : empreinte absente (le code n'est jamais conservé), heure d'émission seulement.
  final List<({String etiquette, DateTime quand})> _emis = [];

  Future<void> _emettre(BuildContext contexte, ContexteEcran c) async {
    final s = source;
    final client = mrbClientMere;
    if (s == null) return;
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'etiquette', libelle: 'Nom du poste à appairer', type: TypeChamp.texte, requis: true),
    ]);
    final v = await afficherModale<Map<String, Object?>>(contexte,
        titre: 'Émettre un code d’appairage',
        sousTitre: 'Code à usage unique pour un poste fileul. Un mobile s’appaire depuis « Appareils et appairage » de la mère (QR).',
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Émettre le code',
                  onPressed: () {
                    final x = ctl.valider();
                    if (x != null) Navigator.of(contexte, rootNavigator: true).pop(x);
                  }),
            ]);
    if (v == null || !contexte.mounted) return;
    final etiquette = '${v['etiquette']}'.trim();
    try {
      if (client == null) throw MrbIndisponible('Aucune liaison avec le service de la mère sur ce poste.');
      final code = await client.codeAppareil(etiquette);
      _emis.insert(0, (etiquette: etiquette, quand: c.aujourdhui));
      if (!contexte.mounted) return;
      await afficherModale<void>(contexte,
          titre: 'Code d’appairage émis',
          sousTitre: etiquette,
          taille: TailleModale.sm,
          corps: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            SelectableText(code, key: const Key('rls:code-emis'), style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('À saisir sur le poste à appairer. Ce code n’est affiché qu’une fois, ne sert qu’une fois et expire ; il n’est conservé nulle part en clair.',
                style: TextStyle(fontSize: 12, height: 16 / 12)),
          ]),
          pied: (fermer) => [BoutonSigh(libelle: 'Fermer', onPressed: fermer)]);
    } catch (e) {
      if (contexte.mounted) ToastsSigh.afficher(contexte, 'Code non émis : ${e is MrbIndisponible ? e.motif : mrbCause(e)}', type: TypeToast.erreur);
    }
    await actualiser();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final lignes = <Ligne>[
      for (final (i, e) in _emis.indexed)
        {'id': 'e$i', 'empreinte': 'non conservée (${e.etiquette})', 'cree': rlsIlYa(e.quand, c.aujourdhui), 'expire': rlsNd, 'etat': 'Émis depuis ce poste'}
    ];
    return rlsPage(context, ecran: 'rls-codes', panne: panne, lecture: donnees, blocs: [
      mrbGrilleKpi([
        mrbKpi('Codes valides', null, indice: 'État tenu par le relais ; la mère ne le relit pas.', icone: LucideIcons.ticket),
        mrbKpi('Utilisés (30 j)', null, indice: 'État tenu par le relais ; la mère ne le relit pas.', icone: LucideIcons.check),
        mrbKpi('Expirés', null, indice: 'État tenu par le relais ; la mère ne le relit pas.', icone: LucideIcons.clock),
      ]),
      if (c.peutEcrire)
        Wrap(spacing: 8, runSpacing: 8, children: [
          BoutonSigh(libelle: 'Émettre un code d’appairage', icone: LucideIcons.ticketPlus, onPressed: () => _emettre(context, c)),
        ]),
      rlsCarteTableau(
          'Codes',
          rlsTableau(
            colonnes: [rlsCol('empreinte', 'Empreinte'), rlsCol('cree', 'Créé'), rlsCol('expire', 'Expire'), rlsCol('etat', 'État')],
            lignes: lignes,
            messageVide: 'Liste des codes non disponible : le relais seul connaît les empreintes, les dates d’expiration et l’usage.',
            indiceVide: rlsMotifRelais,
          )),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-indicateurs
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranRlsIndicateurs extends EcranRls {
  const EcranRlsIndicateurs({super.key});
  @override
  String get titre => 'Indicateurs reçus';
  @override
  String get description => 'Les compteurs publiés par la mère à chaque battement. Aucun nom, aucun motif.';
  @override
  String get regle =>
      'Tout champ qui ressemblerait à une donnée de santé est refusé à la réception : le relais ne l’enregistre pas. '
      'Le relais ne renvoie pas ce qu’il a reçu : l’aperçu est celui que la mère enverrait à l’instant.';
  @override
  State<EcranRlsIndicateurs> createState() => _EtatIndicateurs();
}

class _EtatIndicateurs extends RlsEtatEcran<EcranRlsIndicateurs> {
  @override
  Widget build(BuildContext context) {
    final d = donnees;
    final valeurs = <String, Object?>{
      if (d?.patients != null) 'patients_actifs': d!.patients,
      if (d != null) 'seq_max': d.etat.seqMax,
      if (d != null) 'retard_replication': d.etat.retardRelais,
    };
    final verdict = d == null ? null : mrbVerifierIndicateurs(valeurs);
    return rlsPage(context, ecran: 'rls-indicateurs', panne: panne, lecture: d, blocs: [
      CarteSigh(
          titre: 'Dernier envoi',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(
              [
                '{ "indicateurs": {',
                for (final (i, k) in mrbChampsPublies.indexed) '    "$k": ${valeurs[k] ?? rlsNd}${i < mrbChampsPublies.length - 1 ? ',' : ''}',
                '} }',
              ].join('\n'),
              key: const Key('rls:apercu-indicateurs'),
              style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 13, height: 20 / 13),
            ),
            const SizedBox(height: 8),
            Text(
                verdict == null
                    ? 'Aperçu non calculé : le service de la mère ne répond pas.'
                    : (verdict.sansDonneeDeSante
                        ? 'Aperçu calculé à l’instant avec les lectures de l’envoi : champs en liste fermée, valeurs numériques seulement.'
                        : 'À vérifier : hors liste ${verdict.horsListe.join(', ')} ; non numériques ${verdict.nonNumeriques.join(', ')}.'),
                style: const TextStyle(fontSize: 12, height: 16 / 12)),
          ])),
      rlsCarteTableau(
          'Historique (24 h)',
          rlsTableau(
            colonnes: [rlsCol('heure', 'Heure'), rlsCol('seq', 'Séquence'), rlsCol('actifs', 'Appareils actifs'), rlsCol('conflits', 'Conflits'), rlsCol('bloques', 'Bloqués')],
            lignes: const [],
            messageVide: 'Historique non disponible : le relais seul conserve les envois reçus pendant 48 heures.',
            indiceVide: rlsMotifRelais,
          )),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// rls-alertes
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les quatre règles d'alerte du relais, telles que `docs/architecture/PARITE-RLS.md` les décrit (`App\Relais\Surveillance`). Seuils, canal et activation
/// sont dans la configuration du relais : la mère ne les publie pas.
const List<String> rlsReglesAlerte = ['Battement manquant', 'Appareil bloqué', 'Espace disque faible', 'Tâche cron non exécutée'];

class EcranRlsAlertes extends EcranRls {
  const EcranRlsAlertes({super.key});
  @override
  String get titre => 'Alertes et notifications';
  @override
  String get description => 'Règles d’alerte du relais et canaux de notification du superadmin (courriel).';
  @override
  String get regle =>
      'Une alerte porte un type, un appareil, une heure, jamais un contenu métier. Le courriel du superadmin ne contient aucun nom de patient. '
      'Les seuils et les canaux sont dans la configuration du relais.';
  @override
  State<EcranRlsAlertes> createState() => _EtatAlertes();
}

class _EtatAlertes extends RlsEtatEcran<EcranRlsAlertes> {
  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return rlsPage(context, ecran: 'rls-alertes', panne: panne, lecture: donnees, blocs: [
      rlsCarteTableau(
          'Règles',
          rlsTableau(
            colonnes: [rlsCol('alerte', 'Alerte'), rlsCol('seuil', 'Seuil'), rlsCol('canal', 'Canal'), rlsCol('active', 'Active')],
            lignes: [
              for (final r in rlsReglesAlerte) {'id': r, 'alerte': r, 'seuil': rlsNd, 'canal': rlsNd, 'active': rlsNd}
            ],
            messageVide: 'Aucune règle.',
          )),
      const NoteSigh(
          'Les quatre types d’alerte sont ceux que définit le relais. Leur seuil, leur canal et leur activation sont lus dans sa configuration : '
          'ils ne se consultent et ne se changent que sur le panneau web.',
          ton: TonSigh.neutre,
          icone: LucideIcons.info),
      if (c.peutEcrire)
        Wrap(spacing: 8, runSpacing: 8, children: [
          BoutonSigh(
              libelle: 'Envoyer un courriel de test',
              icone: LucideIcons.mail,
              onPressed: () => rlsRefuser(context,
                  geste: 'envoi d’un courriel de test',
                  motif: 'Le courriel part du relais, que la mère n’appelle pas pour cela. À faire depuis l’écran « Alertes et notifications » du panneau web.')),
        ]),
    ]);
  }
}
