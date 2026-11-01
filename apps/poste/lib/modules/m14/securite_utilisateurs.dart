import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../auth/acc_registre_sessions.dart';
import 'commun_m14.dart';

/// `m14-securite-utilisateurs` : « Sécurité des utilisateurs » (retour de la Direction du 01/11/2026 : « l'écran n'est pas implémenté »).
///
/// Aucun écran ne portait ce nom : la sécurité des comptes était éparpillée entre `m14-utilisateurs` (création, double facteur), `m14-roles` (tentatives
/// refusées) et `m14-sessions`. Cet écran les RASSEMBLE sans les dupliquer : la politique est une fiche unique (`politiqueSecurite`), les comptes sont ceux de
/// `utilisateurs`, les tentatives celles de `tentativesConnexion`, les sessions celles du registre de `m14-sessions`.
///
/// CHAQUE PARAMÈTRE DIT SA SOURCE ET S'IL EST APPLIQUÉ. Au poste, le verrou après échecs (3 échecs, 15 minutes), la politique de mot de passe et le délai
/// d'inactivité sont appliqués pour de bon ; ce que la politique règle ici est ce que le poste LIT : le délai d'inactivité s'applique aussitôt à la session
/// ouverte. La profondeur de l'historique des mots de passe reste une PROPOSITION À VALIDER (aucun document ne la fixe).
///
/// Un mot de passe ne passe jamais ici : « Imposer la réinitialisation » oblige l'agent à en choisir un nouveau à sa prochaine connexion, rien de plus.
/// Droits : administrateur seul (manifeste). Bloquer, débloquer et clôturer sont journalisés (RG-12) ; rien n'est supprimé (RG-14).
class EcranSecuriteUtilisateurs extends StatefulWidget with EcranMaquette {
  const EcranSecuriteUtilisateurs({super.key});

  @override
  String get description => 'Politique de mot de passe, verrouillage, double facteur, comptes bloqués et tentatives de connexion.';

  @override
  String get regle =>
      'Écran réservé à l’administrateur système. La politique est une fiche unique ; chaque paramètre dit sa source et s’il est appliqué par la maquette. Un mot de passe ne s’affiche ni ne se conserve ici : on impose sa réinitialisation. Bloquer, débloquer et clôturer sont journalisés (RG-12) ; rien n’est supprimé (RG-14).';

  @override
  State<EcranSecuriteUtilisateurs> createState() => _EtatSecurite();
}

class _EtatSecurite extends State<EcranSecuriteUtilisateurs> {
  bool _amorce = false;
  String _onglet = 'politique';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    // La politique de référence : amorcée par l'écran, sans écriture au journal (comme la maquette).
    if (m.collection('politiqueSecurite').actives.isEmpty) {
      m.collection('politiqueSecurite').ajouterSansJournal({'id': 'POL-001', 'statut': 'actif', ...secPolitiqueDefaut, '_creePar': 'Système'});
    }
    RegistreSessions.de(m).amorcerDemonstration(m.collection('utilisateurs').actives, c.aujourdhui);
  }

  Map<String, int> _politique(Magasin m) => secPolitique(m.collection('politiqueSecurite').actives.firstOrNull);

  SecActeurCompte _acteur(ContexteEcran c) {
    final a = c.agent;
    return SecActeurCompte(identifiant: a.identifiant.isEmpty ? c.role : a.identifiant, nom: a.nom.isEmpty ? c.role : a.nom);
  }

  bool _verrouEnCours(ContexteEcran c, String id) {
    final f = c.magasin.collection('identifiants').parId(id);
    return f != null && accVerrouJusqua(f, c.aujourdhui) != null;
  }

  /// La vue du compte pour le calcul : le poste tient le haché, sa date de définition et l'obligation de changer dans `identifiants`.
  Fiche _vue(ContexteEcran c, Fiche u) {
    final idf = c.magasin.collection('identifiants').parId(u['id']);
    return {
      ...u,
      if (u['motDePasseDefiniLe'] == null && idf?['definiLe'] != null) 'motDePasseDefiniLe': idf!['definiLe'],
      if (u['doitChangerMotDePasse'] != true && idf != null && accChangementObligatoire(idf, c.aujourdhui)) 'doitChangerMotDePasse': true,
    };
  }

  List<Fiche> _sessionsOuvertes(ContexteEcran c, [String? identifiant]) => [
        for (final f in RegistreSessions.de(c.magasin).fiches)
          if (secSessionOuverte(f) && (identifiant == null || '${f['identifiant']}' == identifiant)) f
      ];

  List<Map<String, Object?>> _lignesComptes(ContexteEcran c) {
    final pol = _politique(c.magasin);
    final comptes = [...c.magasin.collection('utilisateurs').actives]..sort((a, b) => '${a['nomComplet']}'.compareTo('${b['nomComplet']}'));
    return [
      for (final u in comptes)
        () {
          final v = _vue(c, u);
          final role = '${u['role']}';
          return <String, Object?>{
            'id': u['id'],
            'identifiant': u['identifiant'],
            'nomComplet': u['nomComplet'],
            'role': role,
            'actif': secVrai(u['actif']),
            'bloque': secEstBloque(u, pol, verrouEnCours: _verrouEnCours(c, '${u['id']}')),
            'echecs': u['echecs'] is num ? (u['echecs'] as num).toInt() : 0,
            'mfa': secVrai(u['mfa']),
            'mfaExige': secDoubleFacteurExige(role),
            'jours': secJoursAvantExpiration(v, pol, c.aujourdhui),
            'reinit': secAReinitialiser(v, pol, c.aujourdhui),
            'imposee': v['doitChangerMotDePasse'] == true,
            'sessions': _sessionsOuvertes(c, '${u['identifiant']}').length,
          };
        }()
    ];
  }

  void _refus(BuildContext ctx, RefusSec r) => ToastsSigh.afficher(ctx, r.motif, type: TypeToast.erreur, detail: r.geste);

  void _modifierPolitique(BuildContext ctx, ContexteEcran c) {
    final pol = _politique(c.magasin);
    final f = ControleurFormulaire([
      for (final p in secParametresPolitique)
        ChampDef(nom: p.cle, libelle: '${p.libelle} (${p.unite})', type: TypeChamp.nombre, requis: true),
    ], {for (final p in secParametresPolitique) p.cle: pol[p.cle]});
    afficherModale<void>(ctx,
        titre: 'Modifier la politique de sécurité',
        taille: TailleModale.lg,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Chaque valeur est bornée. Le délai d’inactivité s’applique aussitôt au verrou de session de ce poste ; les autres valeurs sont celles que le poste applique et que cet écran calcule.',
              ton: TonSigh.info),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final r = secValiderPolitique(v);
                    if (!r.ok) {
                      _refus(ctx, r.refus!);
                      return;
                    }
                    final fiche = c.magasin.collection('politiqueSecurite').actives.firstOrNull;
                    if (fiche == null) {
                      c.magasin.collection('politiqueSecurite').inserer({'id': 'POL-001', 'statut': 'actif', ...r.patch}, prefixe: 'POL');
                    } else {
                      c.magasin.collection('politiqueSecurite').mettreAJour(fiche['id'], {...r.patch, 'modifieeLe': c.aujourdhui.toIso8601String()});
                    }
                    // Le délai d'inactivité s'applique aussitôt à la session ouverte.
                    RegistreSessions.de(c.magasin).appliquerDelaiVerrou?.call(Duration(minutes: r.patch['inactiviteMin']! as int));
                    fermer();
                    ToastsSigh.afficher(ctx, 'Politique de sécurité enregistrée.', type: TypeToast.succes);
                  }),
            ]);
  }

  void _demanderBlocage(BuildContext ctx, ContexteEcran c, Map<String, Object?> r) {
    final f = ControleurFormulaire(const [ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, requis: true, col: ColChamp.plein)]);
    afficherModale<void>(ctx,
        titre: 'Bloquer le compte de ${r['nomComplet']}',
        taille: TailleModale.md,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Un compte bloqué ne peut plus ouvrir de session tant qu’un administrateur ne l’a pas débloqué. Les sessions déjà ouvertes ne sont pas fermées : utiliser « Clôturer les sessions ».',
              ton: TonSigh.attention,
              icone: LucideIcons.shieldAlert),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Bloquer le compte',
                  icone: LucideIcons.lock,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final res = secBloquerCompte(c.magasin.collection('utilisateurs').parId(r['id']),
                        motif: '${v['motif']}', acteur: _acteur(c), politique: _politique(c.magasin), maintenant: c.aujourdhui);
                    if (!res.ok) {
                      _refus(ctx, res.refus!);
                      return;
                    }
                    c.magasin.collection('utilisateurs').mettreAJour(r['id'], res.patch);
                    fermer();
                    ToastsSigh.afficher(ctx, 'Compte bloqué.', type: TypeToast.succes, detail: '${r['nomComplet']}');
                  }),
            ]);
  }

  Future<void> _agir(BuildContext ctx, ContexteEcran c, String libelle, Map<String, Object?> r, String message, void Function() geste) async {
    final ok = await confirmerSigh(ctx, titre: '$libelle : ${r['nomComplet']} ?', message: message, libelleOk: libelle);
    if (!ok || !ctx.mounted) return;
    geste();
  }

  void _debloquer(BuildContext ctx, ContexteEcran c, Map<String, Object?> r) {
    final id = '${r['id']}';
    final u = c.magasin.collection('utilisateurs').parId(id);
    final res = secDebloquerCompte(u, acteur: _acteur(c), politique: _politique(c.magasin), maintenant: c.aujourdhui, verrouEnCours: _verrouEnCours(c, id));
    if (!res.ok) {
      _refus(ctx, res.refus!);
      return;
    }
    c.magasin.collection('utilisateurs').mettreAJour(id, res.patch);
    // Au poste, le verrou après échecs vit dans la fiche `identifiants` : le lever est ce qui rend vraiment l'accès.
    if (c.magasin.collection('identifiants').parId(id) != null) {
      c.magasin.collection('identifiants').mettreAJour(id, {'echecs': 0, 'verrouJusqua': null});
    }
    ToastsSigh.afficher(ctx, 'Débloquer effectué.', type: TypeToast.succes, detail: '${r['nomComplet']}');
  }

  void _imposer(BuildContext ctx, ContexteEcran c, Map<String, Object?> r) {
    final id = '${r['id']}';
    final res = secImposerReinitialisation(c.magasin.collection('utilisateurs').parId(id), acteur: _acteur(c), maintenant: c.aujourdhui);
    if (!res.ok) {
      _refus(ctx, res.refus!);
      return;
    }
    c.magasin.collection('utilisateurs').mettreAJour(id, res.patch);
    // Au poste, c'est la fiche `identifiants` qui oblige à changer à la prochaine connexion.
    if (c.magasin.collection('identifiants').parId(id) != null) {
      c.magasin.collection('identifiants').mettreAJour(id, {'doitChanger': true});
    }
    ToastsSigh.afficher(ctx, 'Imposer la réinitialisation effectué.', type: TypeToast.succes, detail: '${r['nomComplet']}');
  }

  void _cloturerSessions(BuildContext ctx, ContexteEcran c, Map<String, Object?> r) {
    final reg = RegistreSessions.de(c.magasin);
    final ouvertes = _sessionsOuvertes(c, '${r['identifiant']}');
    final refus = secRefusCloturerSessionsCompte(ouvertes, sessionPropre: reg.sessionCourante);
    if (refus != null) {
      _refus(ctx, refus);
      return;
    }
    for (final f in ouvertes) {
      final res = reg.cloturer('${f['id']}',
          acteur: SecActeurSession(role: c.role, identifiant: _acteur(c).identifiant, nom: _acteur(c).nom, sessionId: reg.sessionCourante),
          droitEditer: c.droit.editer,
          maintenant: c.aujourdhui,
          motif: 'Clôture depuis Sécurité des utilisateurs');
      if (!res.ok) {
        _refus(ctx, res.refus!);
        return;
      }
    }
    ToastsSigh.afficher(ctx, 'Clôturer les sessions effectué.', type: TypeToast.succes, detail: '${r['nomComplet']}');
  }

  Widget _ongletPolitique(BuildContext ctx, ContexteEcran c) {
    final m = c.magasin;
    final pol = _politique(m);
    final lignes = <Map<String, Object?>>[
      for (final p in secParametresPolitique)
        {'cle': p.cle, 'libelle': p.libelle, 'valeur': '${pol[p.cle]} ${p.unite}', 'source': p.source, 'application': p.application},
      {
        'cle': 'complexite',
        'libelle': 'Composition du mot de passe',
        'valeur': 'Majuscule, minuscule, chiffre et caractère spécial',
        'source': 'Politique affichée par l’écran de réinitialisation (écart E1107)',
        'application': 'Affichée, non appliquée par la maquette',
      },
      {
        'cle': 'mfa',
        'libelle': 'Double facteur obligatoire pour les rôles',
        'valeur': secRolesDoubleFacteur.map((r) => libelleRole(m, r)).join(', '),
        'source': 'CDCT §12.2 nomme l’Administrateur et la Direction ; la création de compte l’impose aussi à la DAF et au Directeur Médical',
        'application': 'Appliquée à la création d’un compte (m14-utilisateurs)',
      },
    ];
    TextStyle petit() => const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Les valeurs de cette liste sont celles que la maquette affiche ou que le poste applique. La profondeur de l’historique des mots de passe est une proposition à valider : aucun document ne la fixe.',
          ton: TonSigh.info,
          icone: LucideIcons.info),
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Politique de sécurité des comptes',
        lignes: lignes,
        taillePage: 20,
        recherche: false,
        nomExport: 'politique-securite',
        colonnes: [
          const ColonneTableau(cle: 'libelle', libelle: 'Paramètre'),
          ColonneTableau(
              cle: 'valeur',
              libelle: 'Valeur',
              sansCoupure: true,
              rendu: (_, r) => Text('${r['valeur']}', style: const TextStyle(color: JetonsShell.slate800, fontWeight: FontWeight.w600))),
          ColonneTableau(cle: 'source', libelle: 'Source', rendu: (_, r) => Text('${r['source']}', style: petit())),
          ColonneTableau(cle: 'application', libelle: 'Application', rendu: (_, r) => Text('${r['application']}', style: petit())),
        ],
        actions: [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Modifier la politique',
                icone: LucideIcons.slidersHorizontal,
                onPressed: () => _modifierPolitique(ctx, c)),
        ],
      ),
    ]);
  }

  Widget _ongletComptes(BuildContext ctx, ContexteEcran c) {
    final m = c.magasin;
    return TableauSigh(
      titre: 'Comptes et situation de sécurité',
      lignes: _lignesComptes(c),
      taillePage: 15,
      nomExport: 'securite-comptes',
      filtres: [
        FiltreTableau(
            nom: 'situation',
            libelle: 'Situation',
            options: const [
              OptionChamp('bloques', 'Comptes bloqués'),
              OptionChamp('reinit', 'À réinitialiser'),
              OptionChamp('sessions', 'Avec session ouverte'),
              OptionChamp('sansmfa', 'Double facteur manquant'),
            ],
            correspond: (r, v) {
              if (v == 'bloques') return r['bloque'] == true;
              if (v == 'reinit') return r['reinit'] == true;
              if (v == 'sessions') return (r['sessions'] as int) > 0;
              return r['mfaExige'] == true && r['mfa'] != true;
            }),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'identifiant',
            libelle: 'Identifiant',
            sansCoupure: true,
            rendu: (_, r) => Text('${r['identifiant']}',
                style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.slate800))),
        const ColonneTableau(cle: 'nomComplet', libelle: 'Utilisateur'),
        ColonneTableau(
            cle: 'role',
            libelle: 'Rôle',
            texte: (r) => libelleRole(m, r['role']),
            rendu: (_, r) => BadgeSigh(libelleRole(m, r['role']), ton: TonSigh.navy)),
        ColonneTableau(
            cle: 'bloque',
            libelle: 'Accès',
            texte: (r) => r['bloque'] == true ? 'Bloqué' : (r['actif'] == true ? 'Ouvert' : 'Désactivé'),
            rendu: (_, r) => r['bloque'] == true
                ? const BadgeSigh('Bloqué', ton: TonSigh.danger)
                : (r['actif'] == true ? const BadgeSigh('Ouvert', ton: TonSigh.succes) : const BadgeSigh('Désactivé', ton: TonSigh.neutre))),
        ColonneTableau(
            cle: 'echecs',
            libelle: 'Échecs',
            droite: true,
            texte: (r) => '${r['echecs']}',
            rendu: (_, r) => (r['echecs'] as int) > 0
                ? Text('${r['echecs']}', style: const TextStyle(color: JetonsShell.warning600, fontWeight: FontWeight.w600))
                : const Text('—')),
        ColonneTableau(
            cle: 'mfa',
            libelle: 'Double facteur',
            texte: (r) => r['mfa'] == true ? 'Activé' : (r['mfaExige'] == true ? 'Manquant' : 'Non requis'),
            rendu: (_, r) => r['mfa'] == true
                ? const BadgeSigh('Activé', ton: TonSigh.info)
                : (r['mfaExige'] == true
                    ? const BadgeSigh('Manquant', ton: TonSigh.danger)
                    : const Text('Non requis', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)))),
        ColonneTableau(
            cle: 'reinit',
            libelle: 'Mot de passe',
            texte: (r) => r['imposee'] == true
                ? 'Réinitialisation imposée'
                : (r['reinit'] == true ? 'À renouveler' : (r['jours'] == null ? 'Date non relevée' : 'Valide')),
            rendu: (_, r) {
              if (r['imposee'] == true) return const BadgeSigh('Réinitialisation imposée', ton: TonSigh.attention);
              if (r['reinit'] == true) return const BadgeSigh('À renouveler', ton: TonSigh.attention);
              if (r['jours'] == null) return const Text('Date non relevée', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));
              return Text('Valide, ${r['jours']} j restants', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12));
            }),
        ColonneTableau(cle: 'sessions', libelle: 'Sessions', droite: true, texte: (r) => '${r['sessions']}', rendu: (_, r) => Text('${r['sessions']}')),
      ],
      // Toutes ces commandes sont des ÉCRITURES : absentes sans le droit d'éditer (jamais grisées).
      actionsLigne: (context, r) => [
        if (c.droit.editer) ...[
          if (r['bloque'] == true)
            BoutonSigh(
                libelle: 'Débloquer',
                icone: LucideIcons.lockOpen,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () => _agir(context, c, 'Débloquer', r,
                    'Le compte retrouve l’accès et son compteur d’échecs repart de zéro. L’opération est journalisée.', () => _debloquer(context, c, r)))
          else if (r['actif'] == true)
            BoutonSigh(
                libelle: 'Bloquer',
                icone: LucideIcons.lock,
                taille: TailleBouton.sm,
                variante: VarianteBouton.danger,
                onPressed: () => _demanderBlocage(context, c, r)),
          if (r['imposee'] != true)
            BoutonSigh(
                libelle: 'Imposer la réinitialisation',
                icone: LucideIcons.keyRound,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () => _agir(
                    context,
                    c,
                    'Imposer la réinitialisation',
                    r,
                    'L’agent devra choisir un nouveau mot de passe à sa prochaine connexion. Aucun mot de passe n’est affiché ni conservé ici.',
                    () => _imposer(context, c, r))),
          if ((r['sessions'] as int) > 0)
            BoutonSigh(
                libelle: 'Clôturer les sessions',
                icone: LucideIcons.logOut,
                taille: TailleBouton.sm,
                variante: VarianteBouton.danger,
                onPressed: () => _agir(
                    context,
                    c,
                    'Clôturer les sessions',
                    r,
                    'Les ${r['sessions']} session(s) ouverte(s) de ce compte seront clôturées ; le poste retombe sur la connexion à son prochain geste.',
                    () => _cloturerSessions(context, c, r))),
        ],
      ],
    );
  }

  Widget _ongletTentatives(BuildContext ctx, ContexteEcran c) {
    final m = c.magasin;
    final rows = <Map<String, Object?>>[
      for (final t in m.collection('tentativesConnexion').actives)
        {
          ...t,
          'quand': DateTime.tryParse('${t['horodatage'] ?? ''}') == null ? '—' : dateHeure(DateTime.parse('${t['horodatage']}').toLocal()),
          'roleLabel': libelleRole(m, t['role']),
        }
    ]..sort((a, b) => '${b['horodatage']}'.compareTo('${a['horodatage']}'));
    if (rows.isEmpty) {
      return const CarteSigh(
          titre: 'Tentatives de connexion refusées',
          child: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Aucune tentative refusée.'))));
    }
    return TableauSigh(
      titre: 'Tentatives de connexion refusées',
      lignes: rows,
      taillePage: 15,
      nomExport: 'securite-tentatives',
      colonnes: [
        const ColonneTableau(cle: 'quand', libelle: 'Date et heure', sansCoupure: true),
        ColonneTableau(cle: 'identifiant', libelle: 'Identifiant', rendu: (_, r) => Text('${r['identifiant'] ?? '—'}', style: styleMono)),
        const ColonneTableau(cle: 'nom', libelle: 'Compte'),
        const ColonneTableau(cle: 'roleLabel', libelle: 'Rôle'),
        ColonneTableau(
            cle: 'motif',
            libelle: 'Motif du refus',
            rendu: (_, r) => Text('${r['motif']}', style: const TextStyle(color: JetonsShell.danger700, fontSize: 12, height: 16 / 12))),
      ],
    );
  }

  Widget _ongletSessions(BuildContext ctx, ContexteEcran c) {
    final ouvertes = _sessionsOuvertes(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh('Le détail des sessions, leur clôture et leur historique sont à l’écran Sessions actives.', ton: TonSigh.info, icone: LucideIcons.monitor),
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Sessions ouvertes',
        lignes: [
          for (final f in ouvertes) {'id': f['id'], 'identifiant': f['identifiant'], 'nomComplet': f['nomComplet'], 'poste': f['poste'], 'etat': f['etat']}
        ],
        taillePage: 10,
        nomExport: 'securite-sessions',
        colonnes: [
          const ColonneTableau(cle: 'identifiant', libelle: 'Identifiant', sansCoupure: true),
          const ColonneTableau(cle: 'nomComplet', libelle: 'Utilisateur'),
          const ColonneTableau(cle: 'poste', libelle: 'Poste', sansCoupure: true),
          ColonneTableau(
              cle: 'etat',
              libelle: 'État',
              texte: (r) => secLibelleEtatSession('${r['etat']}'),
              rendu: (_, r) => '${r['etat']}' == 'suspendue' ? const BadgeSigh('Suspendue', ton: TonSigh.attention) : const BadgeSigh('Active', ton: TonSigh.succes)),
        ],
        actions: [BoutonSigh(libelle: 'Ouvrir les sessions actives', icone: LucideIcons.monitor, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m14-sessions'))],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([
          m.collection('utilisateurs'),
          m.collection('sessionsUtilisateur'),
          m.collection('politiqueSecurite'),
          m.collection('tentativesConnexion'),
          m.collection('identifiants'),
        ]),
        builder: (context, _) {
          final pol = _politique(m);
          final comptes = _lignesComptes(c);
          final actifs = comptes.where((r) => r['actif'] == true).toList();
          final tentatives = m.collection('tentativesConnexion').actives.length;
          final ouvertes = _sessionsOuvertes(c).length;
          final aSurveiller = comptes.where((r) => r['bloque'] == true || r['reinit'] == true).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Comptes actifs', valeur: nombre(actifs.length), icone: LucideIcons.userCheck, ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Comptes bloqués',
                  valeur: nombre(comptes.where((r) => r['bloque'] == true).length),
                  icone: LucideIcons.lock,
                  ton: comptes.any((r) => r['bloque'] == true) ? TonSigh.danger : TonSigh.succes),
              KpiSigh(
                  libelle: 'Mots de passe à renouveler',
                  valeur: nombre(comptes.where((r) => r['reinit'] == true).length),
                  icone: LucideIcons.keyRound,
                  ton: TonSigh.attention),
              KpiSigh(
                  libelle: 'Double facteur manquant',
                  valeur: nombre(actifs.where((r) => r['mfaExige'] == true && r['mfa'] != true).length),
                  icone: LucideIcons.shieldAlert,
                  ton: TonSigh.attention),
              KpiSigh(libelle: 'Tentatives refusées', valeur: nombre(tentatives), icone: LucideIcons.shieldX, ton: tentatives > 0 ? TonSigh.danger : TonSigh.neutre),
              KpiSigh(
                  libelle: 'Sessions ouvertes',
                  valeur: nombre(ouvertes),
                  icone: LucideIcons.monitor,
                  ton: TonSigh.info,
                  indice: 'Verrou à ${pol['inactiviteMin']} min'),
            ]),
            const SizedBox(height: 16),
            OngletsSigh(
              ancre: _onglet,
              alChangement: (id) => _onglet = id,
              onglets: [
                OngletDef(id: 'politique', libelle: 'Politique', construire: (cx) => _ongletPolitique(cx, c)),
                OngletDef(id: 'comptes', libelle: 'Comptes', compte: aSurveiller > 0 ? aSurveiller : null, construire: (cx) => _ongletComptes(cx, c)),
                OngletDef(id: 'tentatives', libelle: 'Tentatives de connexion', compte: tentatives > 0 ? tentatives : null, construire: (cx) => _ongletTentatives(cx, c)),
                OngletDef(id: 'sessions', libelle: 'Sessions', compte: ouvertes, construire: (cx) => _ongletSessions(cx, c)),
              ],
            ),
          ]);
        });
  }
}
