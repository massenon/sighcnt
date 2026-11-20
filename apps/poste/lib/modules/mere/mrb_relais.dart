import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mrb_commun.dart';
import 'mrb_source.dart';

/// `mere-relais` : l'état de la liaison avec le relais en ligne (M-13).
///
/// Le relais est OPAQUE : la mère lui dépose des enveloppes chiffrées de bout en bout (AES-256-GCM, clé de clinique) et le relais ne voit que l'appareil,
/// la date et la taille (spec §12). Sources : le contrôle « Relais en ligne » de la supervision, le retard de réplication (`seq_max` moins `rep_seq`) et le
/// nombre d'enveloppes de journal déposées (`rep_n`). Non exposés par le moteur, donc « non disponible » : l'heure du dernier battement, le journal des
/// échanges, le test de liaison, la rotation du secret (écarts E1355 à E1359).
class _Liaison {
  const _Liaison(this.sante, this.etat, this.echanges, this.battement);
  final MrbSante sante;
  final MrbEtat etat;
  final List<MrbEchangeRelais>? echanges;
  final DateTime? battement;
}

class EcranRelais extends StatefulWidget with EcranMaquette {
  const EcranRelais({super.key});
  @override
  String get titre => 'Relais en ligne';
  @override
  String get description =>
      'État de la liaison avec le relais (hébergement mutualisé) : battement, retard de réplication, secret de la mère.';
  @override
  String get regle =>
      'Le relais est opaque : tout ce que la mère lui dépose est chiffré de bout en bout avec la clé de clinique, que le relais ne possède pas. '
      'Il ne voit que l’appareil, la date et la taille de chaque enveloppe.';

  @override
  State<EcranRelais> createState() => _EtatRelais();
}

class _EtatRelais extends MrbEtatEcran<EcranRelais, _Liaison> {
  @override
  Future<_Liaison> charger(MrbSource s) async =>
      _Liaison(await s.supervision(), await s.etat(), await s.echanges(), await s.dernierBattement());

  Future<void> _tester(BuildContext contexte) async {
    final s = source;
    if (s != null) await geste(contexte, s.testerLiaison, ok: 'La liaison avec le relais fonctionne.');
  }

  Future<void> _secret(BuildContext contexte) async {
    final s = source;
    if (s == null) return;
    final ok = await confirmerSigh(contexte,
        titre: 'Faire tourner le secret de la mère ?',
        message: 'Le secret authentifie la mère auprès du relais. Après rotation, l’ancien secret est refusé : la mère et le relais doivent porter le nouveau, '
            'sans quoi la réplication s’arrête.',
        libelleOk: 'Faire tourner le secret',
        dangereux: true);
    if (ok && contexte.mounted) await geste(contexte, s.tournerSecretMere, ok: 'Secret de la mère renouvelé.');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final d = donnees;
    final liaison = d?.sante.controle('Relais en ligne');
    final echanges = d?.echanges;
    final rows = <Ligne>[
      for (final x in echanges ?? const <MrbEchangeRelais>[])
        {
          'quand': x.quand.millisecondsSinceEpoch,
          'sens': mrbLibelleSens(x.sens),
          'contenu': x.contenu,
          'resultat': x.resultat,
        }
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      mrbBandeauPanne(panne),
      mrbGrilleKpi([
        mrbKpi('Liaison', liaison == null ? null : mrbLibelleEtat(liaison.etat),
            indice: liaison?.detail, ton: liaison == null ? TonSigh.neutre : mrbTon(liaison.etat), icone: LucideIcons.cloud),
        mrbKpi('Dernier battement', d?.battement == null ? null : mrbDateHeure(d!.battement!),
            indice: d?.battement == null ? 'Le service de la mère ne publie pas l’heure du dernier échange réussi.' : null, icone: LucideIcons.heartPulse),
        mrbKpi('Retard de réplication', d == null ? null : '${d.etat.retardRelais}',
            indice: d == null ? null : 'opération(s) pas encore répliquées (chiffrées)',
            ton: d == null || d.etat.retardRelais <= 0 ? TonSigh.succes : TonSigh.attention,
            icone: LucideIcons.timer),
        mrbKpi('Enveloppes au relais', d?.etat.repN == null ? null : '${d!.etat.repN}',
            indice: d?.etat.repN == null ? 'Compteur non fourni par le service.' : 'enveloppes de journal déposées par la mère',
            icone: LucideIcons.mails),
      ]),
      const SizedBox(height: 12),
      if (c.peutEcrire || c.peutAnnuler)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (c.peutEcrire) BoutonSigh(libelle: 'Tester la liaison', icone: LucideIcons.activity, onPressed: () => _tester(context)),
            if (c.peutAnnuler)
              BoutonSigh(
                  libelle: 'Faire tourner le secret de la mère',
                  icone: LucideIcons.keyRound,
                  variante: VarianteBouton.danger,
                  onPressed: () => _secret(context)),
          ]),
        ),
      CarteSigh(
        titre: 'Derniers échanges',
        sansRemplissage: true,
        child: MrbTableau(
          recherche: false,
          messageVide: echanges == null && d != null
              ? 'Journal des échanges non disponible : le service de la mère ne le tient pas.'
              : (d == null ? 'Échanges non lus : le service ne répond pas.' : 'Aucun échange enregistré.'),
          indiceVide: 'Le contenu des enveloppes n’est jamais affiché : il est chiffré de bout en bout et le relais ne peut pas le lire.',
          colonnes: [
            ColonneTableau(cle: 'quand', libelle: 'Quand', sansCoupure: true, texte: (l) => mrbDateHeureMs(l['quand']! as int)),
            const ColonneTableau(cle: 'sens', libelle: 'Sens'),
            const ColonneTableau(cle: 'contenu', libelle: 'Contenu'),
            const ColonneTableau(cle: 'resultat', libelle: 'Résultat'),
          ],
          lignes: rows,
        ),
      ),
    ]);
  }
}
