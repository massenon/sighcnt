import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../mere/client_mere.dart';
import 'mra_affectation.dart';
import 'mra_commun.dart';

/// Les trois écrans « santé et appareils » de la console mère : supervision (M-01), appareils et appairage (M-02), conflits et doublons (M-03).
/// Ils ajoutent à la console existante (`lib/mere/console.dart`) la mise en page de la coque, les en-têtes de la fiche de parité et la
/// distinction entre « rien à signaler » et « la mère ne le dit pas ».

Widget sectionMra(String titre, Widget corps) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(titre,
              style: const TextStyle(
                  color: JetonsShell.slate900,
                  fontSize: 16,
                  height: 24 / 16,
                  fontWeight: FontWeight.w600))),
      corps,
    ]);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-supervision
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranMraSupervision extends EcranMra {
  const EcranMraSupervision({super.key, super.source, super.intervalle, super.maintenant});
  @override
  String get titre => 'Supervision';
  @override
  String get description =>
      'Santé de la mère d’un coup d’œil : base, disque, sauvegarde, relais, postes, horloges, intégrité.';
  @override
  List<(String, String)> get voisins => const [
        ('mere-appareils', 'Appareils et appairage'),
        ('mere-conflits', 'Conflits et doublons'),
      ];
  @override
  State<EcranMraSupervision> createState() => _EtatSupervision();
}

class _EtatSupervision extends EtatEcranMra<EcranMraSupervision> {
  LectureMra<EtatMere> _etat = const LectureMra(null);
  LectureMra<Supervision> _sante = const LectureMra(null);

  @override
  Future<void> charger() async {
    _etat = await lire((s) => s.etat());
    _sante = await lire((s) => s.supervision());
  }

  String _libelleAlerte(Map<String, Object?> a) => switch (a['type']) {
        'authentification' => 'Enveloppe altérée : authentification échouée (rang ${a['n']})',
        'trou' => 'Enveloppe manquante : attendu le rang ${a['attendu']}, reçu ${a['recu']}',
        'appareil_inconnu' => 'Appareil inconnu ou code invalide',
        'revocation_relais_differee' => 'Révocation à répercuter au relais',
        final t => '$t',
      };

  @override
  Widget build(BuildContext context) {
    final e = _etat.valeur;
    final s = _sante.valeur;
    final (tonSante, libSante) = switch (s?.etat) {
      'ok' => (TonSigh.succes, 'OK'),
      'attention' => (TonSigh.attention, 'À surveiller'),
      'alerte' => (TonSigh.danger, 'ALERTE'),
      null => (TonSigh.neutre, null),
      _ => (TonSigh.neutre, 'Inconnu'),
    };
    final retard = e?.retardRelais;
    final noms = [for (final a in e?.appareils ?? const <Appareil>[]) (uuid: a.uuid, etiquette: a.etiquette)];
    return corps([
      grilleKpi([
        KpiSigh(libelle: 'Santé de la mère', valeur: libSante ?? nonDisponible, ton: tonSante, icone: LucideIcons.heartPulse,
            indice: s == null ? 'le service de la mère ne répond pas' : null),
        kpiMra('Époque', e?.epoch, icone: LucideIcons.history),
        kpiMra('Opérations', e?.seqMax, icone: LucideIcons.listOrdered),
        kpiMra('Retard vers le relais', retard,
            indice: retard == null ? null : 'opérations pas encore répliquées (chiffrées)',
            ton: retard == null || retard == 0 ? TonSigh.succes : TonSigh.attention,
            icone: LucideIcons.cloudUpload),
      ]),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (peutEcrire)
          BoutonSigh(
              libelle: 'Sauvegarder maintenant',
              icone: LucideIcons.save,
              onPressed: () => geste((x) => x.sauvegarderMaintenant(), ok: 'Sauvegarde chiffrée effectuée.')),
        BoutonSigh(libelle: 'Actualiser', icone: LucideIcons.refreshCw, variante: VarianteBouton.secondaire, onPressed: actualiser),
      ]),
      CarteSigh(
          titre: 'Contrôles',
          sansRemplissage: true,
          child: tableauMra(
            colonnes: [
              const ColonneTableau(cle: 'nom', libelle: 'Contrôle'),
              ColonneTableau(cle: 'etatTexte', libelle: 'État', triable: false, rendu: (_, l) => badgeEtat('${l['etat']}'), texte: (l) => '${l['etatTexte']}'),
              const ColonneTableau(cle: 'detail', libelle: 'Détail', triable: false),
            ],
            lignes: [
              for (final c in s?.controles ?? const <Controle>[])
                {'id': c.nom, 'nom': c.nom, 'etat': c.etat, 'etatTexte': badgeTexte(c.etat), 'detail': c.detail}
            ],
            messageVide: s == null ? 'Contrôles $nonDisponible.' : 'Aucun contrôle renvoyé par la mère.',
            indiceVide: s == null ? 'Le service de la mère ne répond pas : un état inconnu ne rassure jamais.' : null,
            nomExport: 'controles-mere',
          )),
      if (e != null) ..._volets(e, noms),
    ]);
  }

  String badgeTexte(String etat) => switch (etat) { 'ok' => 'OK', 'attention' => 'À surveiller', 'alerte' => 'ALERTE', _ => 'Inconnu' };

  List<Widget> _volets(EtatMere e, List<({String uuid, String etiquette})> noms) => [
        if (e.derives.isNotEmpty)
          NoteSigh('Horloge à vérifier (dérive supérieure à 2 min) : ${e.derives.map((u) => nomAppareil(u, noms)).join(', ')}.', ton: TonSigh.attention),
        if (e.restauration != null) NoteSigh('Restauration : ${e.restauration}', ton: TonSigh.attention),
        sectionMra(
            'Intégrité et alertes',
            e.alertes.isEmpty
                ? const VideSigh('Aucune alerte.', indice: 'Enveloppes altérées ou manquantes, appareils inconnus : rien à signaler.')
                : CarteSigh(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final a in e.alertes.reversed.take(50))
                      Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            const Icon(LucideIcons.triangleAlert, size: 16, color: JetonsShell.warning600),
                            const SizedBox(width: 8),
                            Expanded(child: Text('${_libelleAlerte(a)}${a['appareil'] == null ? '' : ' (${nomAppareil('${a['appareil']}', noms)})'}')),
                          ])),
                  ]))),
        if (e.bloques.isNotEmpty)
          sectionMra(
              'Appareils bloqués',
              CarteSigh(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final u in e.bloques)
                  Row(children: [
                    Expanded(child: Text(nomAppareil(u, noms))),
                    if (peutEcrire)
                      BoutonSigh(
                          libelle: 'Débloquer',
                          taille: TailleBouton.sm,
                          variante: VarianteBouton.secondaire,
                          onPressed: () => geste((x) => x.debloquer(u), ok: 'Appareil débloqué.')),
                  ]),
              ]))),
      ];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-appareils
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranMraAppareils extends EcranMra {
  const EcranMraAppareils({super.key, super.source, super.intervalle, super.maintenant});
  @override
  String get titre => 'Appareils et appairage';
  @override
  String get description =>
      'Postes fileuls et mobiles de la clinique : contact, retard, horloge, version ; appairer, révoquer, débloquer.';
  @override
  List<(String, String)> get voisins => const [
        ('mere-supervision', 'Supervision'),
        ('mere-conflits', 'Conflits et doublons'),
      ];
  @override
  State<EcranMraAppareils> createState() => _EtatAppareils();
}

class _EtatAppareils extends EtatEcranMra<EcranMraAppareils> {
  LectureMra<EtatMere> _etat = const LectureMra(null);

  @override
  Future<void> charger() async => _etat = await lire((s) => s.etat());

  static String _type(String role) => switch (role) {
        'fileul' => 'Poste fileul',
        'mobile' => 'Mobile',
        'mere' => 'Mère',
        final r => r,
      };

  Future<void> _revoquer(Appareil a) async {
    final ok = await confirmerSigh(context,
        titre: 'Révoquer cet appareil ?',
        message:
            '« ${a.etiquette.isEmpty ? a.uuid : a.etiquette} » ne pourra plus synchroniser. Ses données locales sont conservées (poste) ou effacées à son prochain contact (mobile).',
        libelleOk: 'Révoquer',
        dangereux: true);
    if (ok) await geste((s) => s.revoquer(a.uuid), ok: 'Appareil révoqué.');
  }

  Future<void> _renvoyer() async {
    final ok = await confirmerSigh(context,
        titre: 'Renvoyer vers tous les postes ?',
        message: 'Chaque poste fera un tirage complet de son périmètre et l’acquittera ; un poste éteint acquittera à sa reconnexion.',
        libelleOk: 'Renvoyer');
    if (ok) await geste((s) => s.renvoyerATous(), ok: 'Demande de renvoi déposée.');
  }

  Future<void> _appairer({required bool mobile}) async {
    final s = source;
    if (s == null) return;
    final String etiquette;
    String profil = '';
    String? fonction;
    if (mobile) {
      // E1600 : le profil et la fonction sont affectés ICI, par le code ; le téléphone ne les déclare plus.
      final a = await demanderAffectationMobile(context);
      if (a == null || !mounted) return;
      etiquette = a.etiquette;
      profil = a.profil;
      fonction = a.fonction;
    } else {
      final ctl = ControleurFormulaire(const [
        ChampDef(nom: 'etiquette', libelle: 'Nom de l’appareil (ex. Réception, Dr Yeni)', requis: true, col: ColChamp.plein),
      ]);
      final saisie = await afficherModale<Map<String, Object?>>(context,
          titre: 'Appairer un poste',
          taille: TailleModale.sm,
          corps: FormulaireSigh(controleur: ctl),
          pied: (fermer) => [
                BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
                BoutonSigh(
                    libelle: 'Générer le code',
                    onPressed: () {
                      final v = ctl.valider();
                      if (v != null) Navigator.of(context, rootNavigator: true).pop(v);
                    }),
              ]);
      if (saisie == null || !mounted) return;
      etiquette = '${saisie['etiquette']}'.trim();
    }
    try {
      final String code;
      String? cle;
      if (mobile) {
        final r = await s.codeMobile(etiquette, profil: profil, fonction: fonction);
        code = r.code;
        cle = r.cle;
      } else {
        code = await s.codeAppareil(etiquette);
      }
      if (!mounted) return;
      await afficherModale<void>(context,
          titre: 'Code d’appairage',
          sousTitre: etiquette,
          taille: TailleModale.sm,
          corps: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(code, key: const Key('mra-code'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 4)),
            const Text('À usage unique, valable 15 minutes.', style: styleMraPetit),
            if (cle != null) ...[
              Text('Ce code appaire : ${profil == 'reception' ? libelleProfilMobile(profil) : '${libelleProfilMobile(profil)}, ${mobLibelleFonction(fonction ?? '')}'}.',
                  key: const Key('mra-affectation'), style: styleMraPetit),
              const SizedBox(height: 12),
              const Text('Clé de la clinique à saisir sur le téléphone (ne jamais l’envoyer par messagerie) :'),
              SelectableText(cle, key: const Key('mra-cle'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 4),
              const Text('QR de la clé : $nonDisponible, la clé s’affiche en texte.', style: styleMraPetit),
            ],
          ]),
          pied: (fermer) => [BoutonSigh(libelle: 'Fermer', onPressed: fermer)]);
      await actualiser();
    } catch (e) {
      if (mounted) ToastsSigh.afficher(context, '$e', type: TypeToast.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _etat.valeur;
    final actifs = e?.appareils.where((a) => !a.revoque).toList();
    final noms = [for (final a in e?.appareils ?? const <Appareil>[]) (uuid: a.uuid, etiquette: a.etiquette)];
    final ecriture = peutEcrire;
    final accuses = e == null || e.marqueResync == null
        ? null
        : mraAccuses([for (final a in actifs!) a.uuid], e.acksResync);
    return corps([
      grilleKpi([
        kpiMra('Appareils actifs', actifs?.length, icone: LucideIcons.monitorSmartphone),
        kpiMra('Postes fileuls', actifs?.where((a) => a.role == 'fileul').length, icone: LucideIcons.monitor),
        kpiMra('Mobiles', actifs?.where((a) => a.role == 'mobile').length, icone: LucideIcons.smartphone),
        kpiMra('Horloge à vérifier', e?.derives.length,
            ton: e == null || e.derives.isEmpty ? TonSigh.succes : TonSigh.attention, icone: LucideIcons.clock),
      ]),
      if (ecriture)
        Wrap(spacing: 8, runSpacing: 8, children: [
          BoutonSigh(libelle: 'Appairer un poste', icone: LucideIcons.monitor, onPressed: () => _appairer(mobile: false)),
          BoutonSigh(libelle: 'Appairer un mobile', icone: LucideIcons.smartphone, variante: VarianteBouton.secondaire, onPressed: () => _appairer(mobile: true)),
          BoutonSigh(libelle: 'Renvoyer vers tous', icone: LucideIcons.refreshCw, variante: VarianteBouton.secondaire, onPressed: _renvoyer),
        ]),
      if (accuses != null)
        NoteSigh(
            'Dernier renvoi vers tous : ${accuses.recus.length} accusé(s) sur ${accuses.recus.length + accuses.attendus.length}'
            '${accuses.attendus.isEmpty ? '.' : ' ; en attente : ${accuses.attendus.map((u) => nomAppareil(u, noms)).join(', ')} (un poste éteint acquittera à sa reconnexion).'}',
            ton: accuses.attendus.isEmpty ? TonSigh.succes : TonSigh.info),
      tableauMra(
        colonnes: [
          const ColonneTableau(cle: 'appareil', libelle: 'Appareil'),
          const ColonneTableau(cle: 'type', libelle: 'Type'),
          const ColonneTableau(cle: 'fonction', libelle: 'Fonction', triable: false),
          const ColonneTableau(cle: 'agent', libelle: 'Agent', triable: false),
          const ColonneTableau(cle: 'contact', libelle: 'Dernier contact', triable: false),
          const ColonneTableau(cle: 'retard', libelle: 'Retard', droite: true),
          const ColonneTableau(cle: 'horloge', libelle: 'Horloge', triable: false),
          const ColonneTableau(cle: 'version', libelle: 'Version', triable: false),
          ColonneTableau(cle: 'etat', libelle: 'État', triable: false, rendu: (_, l) => BadgeSigh('${l['etat']}', ton: l['ton'] as TonSigh), texte: (l) => '${l['etat']}'),
        ],
        lignes: [
          for (final a in e?.appareils ?? const <Appareil>[])
            {
              'id': a.uuid,
              'brut': a,
              'appareil': a.etiquette.isEmpty ? a.uuid : a.etiquette,
              'type': _type(a.role),
              'fonction': a.role == 'mobile' ? libelleFonctionMobile(a.profil, a.fonction) : 'Aucune',
              'agent': nonDisponible,
              'contact': ageDepuis(a.dernierContact, maintenant()),
              'retard': mraRetard(e!.seqMax, a.derniereSeq),
              'horloge': a.dernierContact == null
                  ? 'inconnue'
                  : e.derives.contains(a.uuid)
                      ? 'À vérifier (écart ${(a.deriveMs / 60000).round()} min)'
                      : 'Conforme',
              'version': nonDisponible,
              'etat': a.revoque ? 'Révoqué' : (e.bloques.contains(a.uuid) ? 'Bloqué' : 'Actif'),
              'ton': a.revoque ? TonSigh.danger : (e.bloques.contains(a.uuid) ? TonSigh.attention : TonSigh.succes),
            }
        ],
        messageVide: e == null ? 'Appareils $nonDisponible.' : 'Aucun appareil appairé.',
        indiceVide: e == null ? 'Le service de la mère ne répond pas.' : 'Appairer un poste ou un mobile pour commencer.',
        nomExport: 'appareils',
        triInitial: 'appareil',
        actionsLigne: ecriture
            ? (ctx, l) {
                final a = l['brut'] as Appareil;
                return [
                  if (!a.revoque && e!.bloques.contains(a.uuid))
                    BoutonSigh(libelle: 'Débloquer', taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => geste((x) => x.debloquer(a.uuid), ok: 'Appareil débloqué.')),
                  if (!a.revoque)
                    BoutonSigh(libelle: 'Révoquer', taille: TailleBouton.sm, variante: VarianteBouton.danger, onPressed: () => _revoquer(a)),
                ];
              }
            : null,
      ),
      carteGestes([
        ('Appairer un poste, Appairer un mobile', 'génère un code à usage unique (15 minutes) ; le mobile reçoit aussi la clé de la clinique.'),
        ('Renvoyer vers tous', 'demande à chaque poste un tirage complet ; les accusés se lisent ci-dessus et au journal des opérations.'),
        ('Révoquer', 'coupe la synchronisation de l’appareil ; ses données locales sont conservées (RG-14, aucune suppression).'),
        ('Agent et Version', '$nonDisponible : la mère ne tient ni l’agent connecté ni la version de l’application de chaque appareil.'),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-conflits
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranMraConflits extends EcranMra {
  const EcranMraConflits({super.key, super.source, super.intervalle, super.maintenant});
  @override
  String get titre => 'Conflits et doublons';
  @override
  String get description =>
      'Ce que la mère ne peut pas trancher seule : même champ modifié sur deux postes, homonymes créés hors ligne.';
  @override
  List<(String, String)> get voisins => const [
        ('mere-supervision', 'Supervision'),
        ('mere-appareils', 'Appareils et appairage'),
      ];
  @override
  State<EcranMraConflits> createState() => _EtatConflits();
}

class _EtatConflits extends EtatEcranMra<EcranMraConflits> {
  LectureMra<List<Conflit>> _conflits = const LectureMra(null);
  LectureMra<EtatMere> _etat = const LectureMra(null);

  @override
  Future<void> charger() async {
    _conflits = await lire((s) => s.tousLesConflits());
    _etat = await lire((s) => s.etat());
  }

  String _decrire(Object? v) => v == null ? 'vide' : (v is String ? v : '$v');

  String _decision(Conflit c) => switch (c.decision) {
        'a' => c.estDoublon ? 'Classé sans fusion' : 'Version A conservée',
        'b' => 'Version B retenue',
        _ => 'Tranché',
      };

  Widget _boutons(Conflit c) => Wrap(spacing: 6, runSpacing: 6, children: [
        if (c.estDoublon)
          BoutonSigh(
              libelle: 'Ce n’est pas un doublon',
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () => geste((s) => s.trancher(c.id, 'a'), ok: 'Classé sans fusion.'))
        else ...[
          BoutonSigh(libelle: 'Garder A', taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => geste((s) => s.trancher(c.id, 'a'), ok: 'Version A conservée.')),
          BoutonSigh(libelle: 'Garder B', taille: TailleBouton.sm, onPressed: () => geste((s) => s.trancher(c.id, 'b'), ok: 'Version B retenue.')),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final tous = _conflits.valeur;
    final ouverts = tous?.where((c) => c.etat == 'ouvert').toList();
    final tranches = tous?.where((c) => c.etat != 'ouvert').toList();
    final rep = ouverts == null ? null : mraRepartirConflits(ouverts.map((c) => c.champ));
    final noms = [for (final a in _etat.valeur?.appareils ?? const <Appareil>[]) (uuid: a.uuid, etiquette: a.etiquette)];
    final ecriture = peutEcrire;
    return corps([
      grilleKpi([
        kpiMra('Ouverts', ouverts?.length, ton: ouverts == null || ouverts.isEmpty ? TonSigh.succes : TonSigh.attention, icone: LucideIcons.gitCompare),
        kpiMra('Doublons possibles', rep?.doublons, icone: LucideIcons.copy),
        kpiMra('Tranchés (30 j)', null,
            indice: tranches == null
                ? null
                : 'la mère ne date pas la décision ; ${tranches.length} tranché(s) au total'),
      ]),
      CarteSigh(
          titre: 'À arbitrer',
          sansRemplissage: true,
          child: tableauMra(
            colonnes: [
              const ColonneTableau(cle: 'num', libelle: 'N°', droite: true),
              const ColonneTableau(cle: 'fiche', libelle: 'Fiche'),
              const ColonneTableau(cle: 'champ', libelle: 'Champ'),
              const ColonneTableau(cle: 'a', libelle: 'Version A', triable: false),
              const ColonneTableau(cle: 'b', libelle: 'Version B', triable: false),
              const ColonneTableau(cle: 'origine', libelle: 'Origine'),
              const ColonneTableau(cle: 'decision', libelle: 'Décision', triable: false),
            ],
            lignes: [
              for (final c in ouverts ?? const <Conflit>[])
                {
                  'id': c.id,
                  'brut': c,
                  'num': c.id,
                  'fiche': '${c.collection} / ${c.fiche}',
                  'champ': c.estDoublon ? 'doublon possible' : c.champ,
                  'a': _decrire(c.a),
                  'b': _decrire(c.b),
                  'decision': 'À arbitrer',
                  'origine': c.appareil == null || c.appareil!.isEmpty ? nonDisponible : nomAppareil(c.appareil!, noms),
                }
            ],
            messageVide: tous == null ? 'Conflits $nonDisponible.' : 'Aucun conflit à régulariser.',
            indiceVide: tous == null ? 'Le service de la mère ne répond pas.' : null,
            nomExport: 'conflits',
            triInitial: 'num',
            actionsLigne: ecriture ? (ctx, l) => [_boutons(l['brut'] as Conflit)] : null,
          )),
      carteGestes([
        ('Garder A', 'conserve la version déjà enregistrée par la mère.'),
        ('Garder B', 'retient la version proposée : la mère pose une nouvelle opération signée de son nom.'),
        ('Ce n’est pas un doublon', 'classe le doublon possible sans fusion ; le code patient attribué ne change jamais (RG-01).'),
        ('Fusionner à la main', '$nonDisponible depuis la console : la mère n’offre aucune route de fusion, une fusion passe par une nouvelle opération.'),
      ]),
      if (tranches != null && tranches.isNotEmpty)
        sectionMra(
            'Décisions déjà prises',
            CarteSigh(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in tranches.reversed.take(20))
                Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('N° ${c.id} · ${c.collection} / ${c.fiche} · ${c.estDoublon ? 'doublon possible' : c.champ} : ${_decision(c)}')),
            ]))),
    ]);
  }
}
