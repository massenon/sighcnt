import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mrb_commun.dart';
import 'mrb_journal.dart' show mrbLimiteJournal;
import 'mrb_source.dart';

/// `mere-integrite` : enveloppes altérées ou manquantes, appareils bloqués, décisions de l'administrateur (M-11).
///
/// Ce que le moteur fait (`Pont.relever`) : une enveloppe qui échoue à l'authentification GCM OU dont le rang n'est pas le rang attendu BLOQUE l'appareil
/// (`bloque:<uuid>`) et lève une alerte. Sources de l'écran : `GET /admin/etat` (appareils bloqués, alertes en mémoire du service) et le journal technique
/// (les mêmes alertes, persistées : c'est lui qui porte le compte « 30 j »). Les alertes en mémoire se perdent au redémarrage du service : l'écran le dit.
class _Integrite {
  const _Integrite(this.etat, this.journal);
  final MrbEtat etat;
  final List<MrbLigneJournal> journal;
}

class EcranIntegrite extends StatefulWidget with EcranMaquette {
  const EcranIntegrite({super.key});
  @override
  String get titre => 'Intégrité et altérations';
  @override
  String get description => 'Enveloppes altérées ou manquantes, appareils bloqués, décisions de l’administrateur.';
  @override
  String get regle =>
      'Avant de débloquer : vérifier l’appareil en personne (perdu ? volé ? relais compromis ?). Débloquer sans vérifier annule le contrôle.';

  @override
  State<EcranIntegrite> createState() => _EtatIntegrite();
}

class _EtatIntegrite extends MrbEtatEcran<EcranIntegrite, _Integrite> {
  @override
  Future<_Integrite> charger(MrbSource s) async => _Integrite(await s.etat(), await s.journal(limite: mrbLimiteJournal));

  /// La dernière alerte levée pour cet appareil, telle que le service la tient en mémoire.
  Map<String, Object?>? _derniereAlerte(MrbEtat e, String uuid) {
    Map<String, Object?>? r;
    for (final a in e.alertes) {
      if (a['appareil'] == uuid) r = a;
    }
    return r;
  }

  Future<void> _debloquer(BuildContext contexte, MrbAppareilBloque b) async {
    final s = source;
    if (s == null) return;
    final ok = await confirmerSigh(contexte,
        titre: 'Débloquer cet appareil ?',
        message: 'Avant de débloquer : vérifier l’appareil « ${b.nom} » en personne (perdu ? volé ? relais compromis ?). '
            'Débloquer sans vérifier annule le contrôle : l’appareil reprend ses envois au prochain tour.',
        libelleOk: 'Débloquer');
    if (ok && contexte.mounted) await geste(contexte, () => s.debloquer(b.uuid), ok: 'Appareil débloqué.');
  }

  Future<void> _revoquer(BuildContext contexte, MrbAppareilBloque b) async {
    final s = source;
    if (s == null) return;
    final ok = await confirmerSigh(contexte,
        titre: 'Révoquer cet appareil ?',
        message: '« ${b.nom} » ne pourra plus synchroniser. Ses données locales sont conservées (poste) ou effacées à son prochain contact (mobile).',
        libelleOk: 'Révoquer',
        dangereux: true);
    if (ok && contexte.mounted) await geste(contexte, () => s.revoquer(b.uuid), ok: 'Appareil révoqué.');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final d = donnees;
    final maintenant = c.aujourdhui.millisecondsSinceEpoch;
    final comptes = d == null ? null : mrbCompterAlterations(d.journal, maintenantMs: maintenant);
    final tronque = d != null &&
        mrbCompterJournal(d.journal, maintenantMs: maintenant, limite: mrbLimiteJournal, fenetreMs: 30 * 24 * 3600 * 1000).tronque;
    final indice = comptes == null ? null : (tronque ? 'au moins : journal lu sur $mrbLimiteJournal lignes' : '30 derniers jours, d’après le journal');
    final bloques = <MrbAppareilBloque>[
      if (d != null)
        for (final u in d.etat.bloques)
          MrbAppareilBloque(
              uuid: u, nom: d.etat.appareil(u)?.nom ?? u, connu: d.etat.appareil(u) != null, alerte: _derniereAlerte(d.etat, u)),
    ];
    final rows = <Ligne>[
      for (final b in bloques)
        {
          'id': b.uuid,
          'appareil': b.nom,
          'cause': b.alerte == null ? 'Cause non conservée par le service (redémarrage depuis le blocage)' : (mrbCauseAlteration('${b.alerte!['type']}') ?? '${b.alerte!['type']}'),
          'detecte': b.alerte?['quand'] is num ? mrbDateHeureMs((b.alerte!['quand']! as num).toInt()) : mrbNonDisponible,
          'rang': b.alerte == null ? mrbNonDisponible : (mrbRangAlteration(b.alerte!) ?? mrbNonDisponible),
        }
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      mrbBandeauPanne(panne),
      mrbGrilleKpi([
        mrbKpi('Appareils bloqués', d == null ? null : '${bloques.length}',
            ton: bloques.isEmpty ? TonSigh.succes : TonSigh.danger, icone: LucideIcons.shieldAlert),
        mrbKpi('Enveloppes altérées (30 j)', comptes == null ? null : '${comptes.alterees}',
            indice: indice, ton: (comptes?.alterees ?? 0) > 0 ? TonSigh.danger : TonSigh.succes, icone: LucideIcons.fileWarning),
        mrbKpi('Trous détectés', comptes == null ? null : '${comptes.trous}',
            indice: indice, ton: (comptes?.trous ?? 0) > 0 ? TonSigh.danger : TonSigh.succes, icone: LucideIcons.unlink),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
        titre: 'Appareils bloqués',
        sansRemplissage: true,
        child: MrbTableau(
          recherche: false,
          messageVide: d == null ? 'Appareils bloqués non lus : le service ne répond pas.' : 'Aucun appareil bloqué.',
          indiceVide: d == null ? null : 'Une enveloppe altérée ou manquante bloque l’appareil qui l’a envoyée : il apparaîtrait ici.',
          colonnes: const [
            ColonneTableau(cle: 'appareil', libelle: 'Appareil'),
            ColonneTableau(cle: 'cause', libelle: 'Cause'),
            ColonneTableau(cle: 'detecte', libelle: 'Détecté'),
            ColonneTableau(cle: 'rang', libelle: 'Rang'),
          ],
          lignes: rows,
          actionsLigne: (c.peutEcrire || c.peutAnnuler)
              ? (ctx, l) {
                  final b = bloques.firstWhere((x) => x.uuid == l['id']);
                  return [
                    if (c.peutEcrire)
                      BoutonSigh(
                          libelle: 'Débloquer', taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _debloquer(context, b)),
                    if (c.peutAnnuler && b.connu)
                      BoutonSigh(libelle: 'Révoquer', taille: TailleBouton.sm, variante: VarianteBouton.danger, onPressed: () => _revoquer(context, b)),
                  ];
                }
              : null,
        ),
      ),
      const SizedBox(height: 12),
      const NoteSigh(
          'Débloquer remet l’appareil en circulation après vérification en personne ; Révoquer le retire définitivement. Les alertes que le service tient en mémoire '
          'sont perdues à son redémarrage : le compte des 30 jours se lit dans le journal technique, qui les conserve.',
          icone: LucideIcons.info),
    ]);
  }
}

class MrbAppareilBloque {
  const MrbAppareilBloque({required this.uuid, required this.nom, required this.connu, this.alerte});
  final String uuid;
  final String nom;

  /// L'appareil figure à la table des appareils (sinon : appareil inconnu, il n'y a rien à révoquer).
  final bool connu;
  final Map<String, Object?>? alerte;
}
