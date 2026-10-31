import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m14.dart';
import 'crud_m14.dart';

/// `m14-utilisateurs` — « Utilisateurs » : les comptes individuels, leur rôle, leur état et le double facteur.
///
/// LE MOT DE PASSE EST SAISI, IL N'EST PAS GARDÉ : il n'existe qu'à la création (champ masqué, huit caractères au minimum, confirmation), et ce qui
/// entre au magasin est la date de définition, son auteur et l'obligation de changer à la première connexion — jamais le secret
/// (`secTransformerCompte`). L'authentification elle-même n'est pas dans cet écran : la collection `utilisateurs` est l'annuaire des comptes, pas le
/// coffre des mots de passe (les hachés vivent côté serveur).
class EcranUtilisateurs extends StatelessWidget with EcranMaquette {
  const EcranUtilisateurs({super.key});

  @override
  String get description =>
      'Comptes individuels, rôles attribués, état d’activation et double facteur.';

  @override
  String get regle =>
      'Aucun compte partagé : chaque agent dispose d’un identifiant individuel. Le double facteur est exigé pour les profils à privilèges élevés (Administrateur et Direction).';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final roles = rolesDe(m);
    final optionsRoles = [for (final r in roles) OptionChamp(r.id, r.label)];
    return CrudM14(
      collection: m.collection('utilisateurs'),
      entite: 'compte',
      entiteP: 'comptes',
      prefixeId: 'UTI',
      triInitial: 'nomComplet',
      taillePage: 20,
      provenance: 'Organigramme de la clinique — un compte par agent.',
      valeursCreation: secCompteParDefaut(),
      colonnes: [
        ColonneTableau(
          cle: 'identifiant',
          libelle: 'Identifiant',
          sansCoupure: true,
          texte: (u) => '${u['identifiant'] ?? ''}',
          rendu: (_, u) => Text('${u['identifiant'] ?? ''}',
              style: const TextStyle(
                  fontFamily: 'LiberationMono',
                  color: JetonsShell.navy800,
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w600)),
        ),
        ColonneTableau(
          cle: 'nomComplet',
          libelle: 'Utilisateur',
          texte: (u) => '${u['nomComplet'] ?? ''} ${u['poste'] ?? ''}',
          valeur: (u) => u['nomComplet'],
          rendu: (_, u) => Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: JetonsShell.slate100, shape: BoxShape.circle),
              child: Text(initiales('${u['nomComplet'] ?? ''}'),
                  style: const TextStyle(
                      color: JetonsShell.slate600,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${u['nomComplet'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: JetonsShell.slate800,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w500)),
                    Text('${u['poste'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                  ]),
            ),
          ]),
        ),
        ColonneTableau(
          cle: 'role',
          libelle: 'Rôle',
          texte: (u) => libelleRole(m, u['role']),
          valeur: (u) => libelleRole(m, u['role']),
          rendu: (_, u) => BadgeSigh(libelleRole(m, u['role']), ton: TonSigh.navy),
        ),
        const ColonneTableau(cle: 'service', libelle: 'Service'),
        ColonneTableau(
          cle: 'actif',
          libelle: 'État',
          texte: (u) => secVrai(u['actif']) ? 'Actif' : 'Désactivé',
          rendu: (_, u) => secVrai(u['actif'])
              ? const BadgeSigh('Actif', ton: TonSigh.succes)
              : const BadgeSigh('Désactivé', ton: TonSigh.danger),
        ),
        ColonneTableau(
          cle: 'mfa',
          libelle: 'Double facteur',
          texte: (u) => secVrai(u['mfa']) ? 'Activé' : 'Non requis',
          rendu: (_, u) => secVrai(u['mfa'])
              ? const BadgeSigh('Activé', ton: TonSigh.info)
              : const Text('Non requis',
                  style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
        ),
        ColonneTableau(
          cle: 'dernierAcces',
          libelle: 'Dernier accès',
          sansCoupure: true,
          texte: (u) => dateFrOuVide(u['dernierAcces']),
          rendu: (_, u) {
            final d = dateIso(u['dernierAcces']);
            final j = d == null ? 0 : nbJoursEntre(d, c.aujourdhui);
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dateFrOuVide(u['dernierAcces']),
                      style: const TextStyle(
                          color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                  Text('il y a $j j',
                      style: TextStyle(
                          color: j > 30 ? JetonsShell.warning600 : JetonsShell.slate400,
                          fontSize: 12,
                          height: 16 / 12)),
                ]);
          },
        ),
        ColonneTableau(
          cle: 'echecs',
          libelle: 'Échecs',
          droite: true,
          texte: (u) => secVrai(u['echecs']) ? '${u['echecs']}' : '—',
          rendu: (_, u) => secVrai(u['echecs'])
              ? Text('${u['echecs']}',
                  style: const TextStyle(
                      color: JetonsShell.warning600, fontWeight: FontWeight.w600))
              : const Text('—'),
        ),
      ],
      champs: (ctx, record) {
        final personnel = [...m.collection('personnel').actives]
          ..sort((a, b) => '${a['nomComplet']}'.compareTo('${b['nomComplet']}'));
        return [
          const ChampDef(
              nom: 'identifiant',
              libelle: 'Identifiant de connexion',
              requis: true,
              aide: 'Format usuel : initiale du prénom, point, nom.'),
          ChampDef(
              nom: 'employeId',
              libelle: 'Agent rattaché',
              type: TypeChamp.select,
              col: ColChamp.plein,
              options: [
                for (final e in personnel)
                  OptionChamp('${e['id']}', '${e['matricule']} — ${e['nomComplet']}')
              ]),
          ChampDef(
              nom: 'role',
              libelle: 'Rôle (RBAC)',
              type: TypeChamp.select,
              requis: true,
              options: optionsRoles),
          ChampDef(
              nom: 'service',
              libelle: 'Service',
              type: TypeChamp.select,
              options: [for (final s in secServices) OptionChamp(s)]),
          const ChampDef(nom: 'actif', libelle: 'Compte actif', type: TypeChamp.case_),
          const ChampDef(
              nom: 'mfa',
              libelle: 'Authentification à deux facteurs',
              type: TypeChamp.case_),
          // Le mot de passe se définit à la CRÉATION et nulle part ailleurs : le changer n'est pas « corriger une fiche », c'est un geste distinct.
          if (record == null) ...const [
            ChampDef.section('Mot de passe'),
            ChampDef(
                nom: 'motDePasse',
                libelle: 'Mot de passe',
                type: TypeChamp.motDePasse,
                requis: true,
                col: ColChamp.demi,
                aide:
                    'Huit caractères au minimum. Il n’est pas conservé en clair : l’agent devra le changer à sa première connexion.'),
            ChampDef(
                nom: 'motDePasseConfirmation',
                libelle: 'Confirmer le mot de passe',
                type: TypeChamp.motDePasse,
                requis: true),
            ChampDef(
                nom: 'doitChangerMotDePasse',
                libelle: 'Changement obligatoire à la première connexion',
                type: TypeChamp.case_),
          ],
        ];
      },
      avant: (ctx, saisie, record) =>
          secVerifierCompte(saisie, comptes: m.collection('utilisateurs').toutes, record: record),
      transformer: (ctx, saisie, record) {
        final id = '${saisie['employeId'] ?? ''}';
        final agent = id.isEmpty ? null : m.collection('personnel').parId(id);
        return secTransformerCompte(saisie,
            record: record,
            agent: agent,
            utilisateur: c.utilisateur,
            maintenant: c.aujourdhui,
            jour: iso(c.aujourdhui));
      },
      filtres: [
        FiltreTableau(nom: 'role', libelle: 'Rôle', options: optionsRoles),
        FiltreTableau(
            nom: 'actif',
            libelle: 'État',
            options: const [OptionChamp('oui', 'Actifs'), OptionChamp('non', 'Désactivés')],
            correspond: (u, v) => v == 'oui' ? secVrai(u['actif']) : !secVrai(u['actif'])),
        FiltreTableau(
            nom: 'service', libelle: 'Service', options: [for (final s in secServices) OptionChamp(s)]),
      ],
      kpis: (rows) => [
        KpiSigh(
            libelle: 'Comptes utilisateurs',
            valeur: nombre(rows.length),
            icone: LucideIcons.usersRound,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Comptes actifs',
            valeur: nombre(rows.where((u) => secVrai(u['actif'])).length),
            icone: LucideIcons.userCheck,
            ton: TonSigh.succes),
        KpiSigh(
            libelle: 'Désactivés',
            valeur: nombre(rows.where((u) => !secVrai(u['actif'])).length),
            icone: LucideIcons.userX,
            ton: TonSigh.danger),
        KpiSigh(
            libelle: 'Avec double facteur',
            valeur: nombre(rows.where((u) => secVrai(u['mfa'])).length),
            icone: LucideIcons.shieldCheck,
            ton: TonSigh.info),
      ],
      detail: (ctx, u) {
        final perms = modulesOuverts(m, '${u['role']}');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            (
              'Identifiant',
              Text('${u['identifiant']}',
                  style: const TextStyle(
                      fontFamily: 'LiberationMono',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: JetonsShell.slate800))
            ),
            ('Nom complet', u['nomComplet']),
            ('Matricule', u['matricule'] ?? '—'),
            ('Rôle', BadgeSigh(libelleRole(m, u['role']), ton: TonSigh.navy)),
            ('Service', u['service']),
            ('Poste', u['poste'] ?? '—'),
            (
              'Compte actif',
              secVrai(u['actif'])
                  ? const BadgeSigh('Actif', ton: TonSigh.succes)
                  : const BadgeSigh('Désactivé', ton: TonSigh.danger)
            ),
            (
              'Double facteur',
              secVrai(u['mfa'])
                  ? const BadgeSigh('Activé', ton: TonSigh.info)
                  : const BadgeSigh('Non requis')
            ),
            ('Dernier accès', dateFrOuVide(u['dernierAcces'])),
            ('Tentatives infructueuses', '${u['echecs'] ?? 0}'),
            ('Compte créé le', dateFrOuVide(u['creeLe'])),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Périmètre d’accès (RBAC)',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${perms.length} module(s) accessible(s) avec ce rôle.',
                    style: const TextStyle(
                        color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final p in perms) BadgeSigh(p, ton: TonSigh.navy)
                ]),
              ])),
        ]);
      },
      titreDetail: (u) => '${u['identifiant']}',
      sousTitreDetail: (u) => '${u['nomComplet'] ?? ''}',
      etat: (ctx, u) {
        final reference = referenceImpression(c);
        afficherApercu(
            ctx,
            PieceA4(
              titre: 'Fiche de compte utilisateur',
              sousTitre: '${u['identifiant']}',
              reference: reference,
              utilisateur: c.utilisateur,
              edite: c.aujourdhui,
              cartouche: [
                ('Identifiant', '${u['identifiant']}'),
                ('Nom complet', '${u['nomComplet'] ?? ''}'),
                ('Rôle', libelleRole(m, u['role'])),
                ('Service', '${u['service'] ?? ''}'),
                ('État', secVrai(u['actif']) ? 'Actif' : 'Désactivé'),
                ('Double facteur', secVrai(u['mfa']) ? 'Activé' : 'Non requis'),
              ],
              blocs: [
                BlocTableau(TableauEtat(colonnes: [
                  ColonneEtat(libelle: 'Rubrique', valeur: (r) => '${r['k']}'),
                  ColonneEtat(libelle: 'Information', valeur: (r) => '${r['v']}'),
                ], lignes: [
                  {'k': 'Matricule de l’agent', 'v': '${u['matricule'] ?? '—'}'},
                  {'k': 'Poste occupé', 'v': '${u['poste'] ?? '—'}'},
                  {'k': 'Date de création du compte', 'v': dateFrOuVide(u['creeLe'])},
                  {'k': 'Dernier accès', 'v': dateFrOuVide(u['dernierAcces'])},
                  {
                    'k': 'Modules accessibles',
                    'v': modulesOuverts(m, '${u['role']}').join(', ')
                  },
                ])),
                const BlocTexte(
                    'L’utilisateur s’engage à ne pas communiquer ses identifiants et reconnaît que toute action réalisée sous son compte lui est imputable, conformément à la politique de sécurité de l’établissement (RG-12).',
                    italique: true),
              ],
              signatures: [
                Signature('L’Utilisateur', nom: '${u['nomComplet'] ?? ''}', mention: 'Lu et approuvé'),
                const Signature('L’Administrateur système'),
              ],
            ));
      },
    );
  }
}
