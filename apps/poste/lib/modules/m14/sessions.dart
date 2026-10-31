import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m14.dart';

/// `m14-sessions` — « Sessions actives » : connexions en cours, postes de travail et délai d'inactivité avant verrouillage.
///
/// ÉCRAN CALCULÉ, comme dans la maquette : les douze premières sessions sont tirées des comptes actifs (`secSessions`, graine 3413) — ce ne sont pas
/// des connexions réelles. Le poste ne tient aucun registre de connexions ; « Clôturer » JOURNALISE la demande (RG-12) sans fermer de session, comme
/// la maquette. L'écran le dit en pied de page (une restriction s'annonce).
class EcranSessions extends StatelessWidget with EcranMaquette {
  const EcranSessions({super.key});

  @override
  String get description =>
      'Connexions en cours, postes de travail et délai d’inactivité avant verrouillage.';

  @override
  String get regle =>
      'Écran calculé : les sessions reflètent les connexions en cours. Elles ne se créent ni ne se modifient — elles se terminent, et la clôture est journalisée (RG-12).';

  Future<void> _cloturer(
      BuildContext ctx, ContexteEcran c, SessionSec s) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Clôturer la session de ${s.nomComplet} ?',
        message:
            'L’utilisateur sera immédiatement déconnecté du poste ${s.poste}. L’opération est journalisée.',
        libelleOk: 'Clôturer la session',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    journaliserM14(c, 'Modification', 'SessionUtilisateur', s.identifiant,
        avant: secSessionAvant, apres: secSessionApres);
    ToastsSigh.afficher(ctx, 'Session clôturée.',
        type: TypeToast.succes, detail: '${s.nomComplet} — ${s.poste}');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final rows =
        secSessions(m.collection('utilisateurs').actives, c.aujourdhui);
    final postes = rows.map((r) => r.poste).toSet();
    final lignes = <Map<String, Object?>>[
      for (final r in rows)
        {
          'id': r.id,
          'identifiant': r.identifiant,
          'nomComplet': r.nomComplet,
          'role': libelleRole(m, r.role),
          'poste': r.poste,
          'adresseIp': r.adresseIp,
          'debut': r.debut.toIso8601String(),
          'inactivite': r.inactivite,
          'verrouillage': r.verrouillage,
        }
    ];
    SessionSec de(Map<String, Object?> l) =>
        rows.firstWhere((r) => r.id == l['id']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Sessions ouvertes',
            valeur: nombre(rows.length),
            icone: LucideIcons.monitor,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Postes distincts',
            valeur: nombre(postes.length),
            icone: LucideIcons.network,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Verrouillées pour inactivité',
            valeur: nombre(rows.where((r) => r.verrouillage).length),
            icone: LucideIcons.lock,
            ton: TonSigh.attention),
        const KpiSigh(
            libelle: 'Délai de verrouillage',
            valeur: '$secDelaiVerrouillageMin min',
            icone: LucideIcons.timer,
            ton: TonSigh.neutre,
            indice: 'Postes partagés'),
      ]),
      const SizedBox(height: 16),
      const NoteSigh(
          'Sur les postes partagés — accueil et caisse — un délai d’inactivité de 15 minutes entraîne le verrouillage automatique de l’écran.',
          ton: TonSigh.info,
          icone: LucideIcons.lock),
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Sessions en cours',
        lignes: lignes,
        taillePage: 15,
        nomExport: 'sessions',
        colonnes: [
          ColonneTableau(
              cle: 'identifiant',
              libelle: 'Identifiant',
              sansCoupure: true,
              rendu: (_, r) => Text('${r['identifiant']}',
                  style: const TextStyle(
                      fontFamily: 'LiberationMono',
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w600,
                      color: JetonsShell.slate800))),
          const ColonneTableau(cle: 'nomComplet', libelle: 'Utilisateur'),
          ColonneTableau(
              cle: 'role',
              libelle: 'Rôle',
              rendu: (_, r) => BadgeSigh('${r['role']}', ton: TonSigh.navy)),
          ColonneTableau(
              cle: 'poste',
              libelle: 'Poste',
              sansCoupure: true,
              rendu: (_, r) => Text('${r['poste']}', style: styleMono)),
          ColonneTableau(
              cle: 'adresseIp',
              libelle: 'Adresse réseau',
              sansCoupure: true,
              rendu: (_, r) => Text('${r['adresseIp']}',
                  style: styleMono.copyWith(color: JetonsShell.slate500))),
          ColonneTableau(
              cle: 'debut',
              libelle: 'Ouverture',
              sansCoupure: true,
              texte: (r) => heure(DateTime.parse('${r['debut']}')),
              rendu: (_, r) => Text(heure(DateTime.parse('${r['debut']}')),
                  style: const TextStyle(
                      color: JetonsShell.slate700,
                      fontSize: 14,
                      height: 20 / 14))),
          ColonneTableau(
              cle: 'inactivite',
              libelle: 'Inactivité',
              droite: true,
              texte: (r) => '${r['inactivite']} min',
              rendu: (_, r) {
                final n = (r['inactivite'] as int);
                return Text('$n min',
                    style: TextStyle(
                        color: n >= secDelaiVerrouillageMin
                            ? JetonsShell.warning600
                            : JetonsShell.slate600,
                        fontWeight: n >= secDelaiVerrouillageMin
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()]));
              }),
          ColonneTableau(
              cle: 'verrouillage',
              libelle: 'État',
              texte: (r) =>
                  r['verrouillage'] == true ? 'Verrouillée' : 'Active',
              rendu: (_, r) => r['verrouillage'] == true
                  ? const BadgeSigh('Verrouillée', ton: TonSigh.attention)
                  : const BadgeSigh('Active', ton: TonSigh.succes)),
        ],
        // La maquette offre « Clôturer » à tout profil qui ouvre l'écran ; c'est une écriture (le journal) : ABSENTE sans le droit d'éditer (E593).
        actionsLigne: (context, r) => [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Clôturer',
                icone: LucideIcons.logOut,
                taille: TailleBouton.sm,
                variante: VarianteBouton.danger,
                onPressed: () => _cloturer(context, c, de(r))),
        ],
      ),
      const SizedBox(height: 16),
      const NoteSigh(
          'Limite du poste : ces sessions sont calculées à partir des comptes actifs, non relevées. Le poste ne tient pas de registre de connexions ; « Clôturer » inscrit la demande au journal d’audit sans fermer de session (comme la maquette).',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}
