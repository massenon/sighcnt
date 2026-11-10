import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart' show Fiche;
import '../../donnees/mes_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';
import 'rhc_badge_carte.dart';
import 'rhc_commun.dart';

/// `m10-badges-verification` — « Vérifier un badge » : on saisit ou l'on scanne le numéro ; le logiciel répond VALIDE, EXPIRÉ, RETIRÉ ou INCONNU (et « non remis »),
/// montre la photo et la fonction, et JOURNALISE la vérification (RG-12). C'est ce contrôle qui donne sa valeur au badge : sans lui, une carte plastifiée n'atteste rien.
/// La saisie MANUELLE est acceptée autant que le scan : la refuser rendrait le contrôle impossible le jour où le QR est abîmé, c'est-à-dire le jour où il sert le plus.
///
/// Lot L8 (Direction, 09/11/2026, Planning Q7) : le badge sert de POINTAGE (réglage oui par défaut). La commande « Pointer » (absente sans droit ni quand le réglage est coupé)
/// écrit l'arrivée puis le départ au registre des présences, « à valider » par le circuit du lot L5 ; chaque refus se nomme (code, motif, geste) et chaque passage se journalise.
class EcranBadgesVerification extends StatefulWidget with EcranMaquette {
  const EcranBadgesVerification({super.key});

  @override
  String get titre => 'Vérifier un badge';
  @override
  String get description => 'Le badge présenté est-il valide ? Réponse immédiate, avec la photo et la fonction — et la vérification est journalisée.';
  @override
  String get regle =>
      'Le code QR ne portant que le matricule et le numéro de série, la réponse vient du logiciel et non de la carte : lui seul sait si le badge a été retiré. Chaque vérification est journalisée (RG-12) et se retrouve au journal d’audit.';

  @override
  State<EcranBadgesVerification> createState() => _EtatVerification();
}

class _EtatVerification extends State<EcranBadgesVerification> {
  final _saisie = TextEditingController();
  Widget? _reponse;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  void _verifier(ContexteEcran c, BuildContext ctx) {
    final texte = _saisie.text.trim();
    if (texte.isEmpty) {
      setState(() => _reponse = null);
      ToastsSigh.afficher(ctx, 'Saisir ou scanner un numéro de badge.', type: TypeToast.attention);
      return;
    }
    final lu = rhcLireBadgeQR(texte)!;
    // Les badges RETIRÉS se vérifient aussi : on cherche dans toute la collection.
    final b = rhcBadgeDuNumero(c.magasin.collection('badges').toutes, lu.numero);
    final v = rhcVerdictBadge(b, c.aujourdhui);
    rhcJournaliserAcces(c,
        action: 'Vérification de badge',
        entite: 'Badge',
        reference: b != null ? '${b['numero']}' : (texte.length > 40 ? texte.substring(0, 40) : texte),
        cible: b != null ? '${b['agent']}' : null,
        ecran: 'm10-badges-verification',
        motif: v.label,
        trouve: b != null);
    final (fond, bord, texteTon) = switch (v.ton) {
      'success' => (JetonsShell.success50, JetonsShell.success300, JetonsShell.success700),
      'warning' => (JetonsShell.warning50, JetonsShell.warning300, JetonsShell.warning700),
      _ => (JetonsShell.danger50, JetonsShell.danger300, JetonsShell.danger700),
    };
    final photo = b != null ? rhcPhoto(b['photo']) : null;
    final incoherent = b != null && lu.matricule != null && '${b['matricule'] ?? ''}'.isNotEmpty && lu.matricule != '${b['matricule']}';
    setState(() => _reponse = Container(
          key: const Key('rhc:verdict'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12), border: Border.all(color: bord)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (photo != null) ...[
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photo, width: 96, height: 112, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
              const SizedBox(width: 16),
            ],
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.label, style: TextStyle(color: texteTon, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w700)),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(v.message, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              if (b != null) ...[
                const SizedBox(height: 12),
                DescListeSigh([
                  ('Agent', b['agent']),
                  ('Matricule', b['matricule']),
                  ('Fonction', b['poste'] ?? '—'),
                  ('Service', b['service'] ?? '—'),
                  ('N° de série', b['numero']),
                ]),
                // Le QR porte DEUX informations : si elles se contredisent, le code a été fabriqué ailleurs. C'est la seule chose qu'un contrôle hors ligne puisse
                // détecter, et elle vaut d'être dite.
                if (incoherent) ...[
                  const SizedBox(height: 12),
                  NoteSigh(
                      'Incohérence : le code présenté annonce le matricule ${lu.matricule}, le registre porte le matricule ${b['matricule']} pour ce numéro de série. Badge à retenir et à signaler.',
                      ton: TonSigh.danger,
                      icone: LucideIcons.triangleAlert),
                ],
              ],
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Vérification journalisée le ${dateHeure(c.aujourdhui)} par ${acteur(c).nom}.',
                      style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
            ])),
          ]),
        ));
  }

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['badges', 'parametres', 'presences'], construire: _corps);

  PointageBadgePoste _pointage(ContexteEcran c) => PointageBadgePoste(c.magasin, auteur: () => acteur(c).nom, role: c.role, horloge: () => c.aujourdhui);

  void _pointer(ContexteEcran c, BuildContext ctx) {
    final texte = _saisie.text.trim();
    if (texte.isEmpty) {
      setState(() => _reponse = null);
      ToastsSigh.afficher(ctx, 'Saisir ou scanner un numéro de badge.', type: TypeToast.attention);
      return;
    }
    final r = _pointage(c).pointer(texte);
    if (r['ok'] != true) {
      setState(() => _reponse = Container(
            key: const Key('rhc:pointage-refuse'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: JetonsShell.danger50, borderRadius: BorderRadius.circular(12), border: Border.all(color: JetonsShell.danger300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Pointage refusé', style: TextStyle(color: JetonsShell.danger700, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w700)),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['motif']}', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['geste']}', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
            ]),
          ));
      return;
    }
    Fiche? ag;
    for (final e in c.magasin.collection('personnel').toutes) {
      if (e['id'] == r['agentId']) ag = e;
    }
    setState(() => _reponse = Container(
          key: const Key('rhc:pointage-ok'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: JetonsShell.success50, borderRadius: BorderRadius.circular(12), border: Border.all(color: JetonsShell.success300)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['geste'] == 'arrivee' ? 'Arrivée pointée' : 'Départ pointé', style: const TextStyle(color: JetonsShell.success700, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w700)),
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${ag?['nomComplet'] ?? ''} à ${r['heure']}. Présence à valider par le circuit.', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
          ]),
        ));
  }

  /// La carte du pointage : l'état du réglage, le délai (valeur d'attente dite telle), et « Régler » pour l'administrateur et la DA seuls.
  Widget _cartePointage(BuildContext context, ContexteEcran c) {
    final p = _pointage(c);
    final peut = c.role == 'admin' || c.role == 'da';
    final d = p.delai();
    return CarteSigh(
        titre: 'Pointage par badge',
        actions: [
          if (peut) BoutonSigh(libelle: 'Régler', icone: LucideIcons.settings2, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _regler(context, c, p)),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Le badge sert de pointage', p.actif() ? 'Oui' : 'Non'),
            ('Délai minimal entre deux pointages', '$d minute${d > 1 ? 's' : ''}${d == delaiPointageBadgeDefaut ? ' (valeur d’attente, à valider)' : ''}'),
          ]),
          const SizedBox(height: 8),
          const Text(
              'Un badge vérifié valide crée une présence « à valider » (arrivée, puis départ au passage suivant) : elle ne compte pas tant que le circuit de validation ne l’a pas tranchée.',
              style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ]));
  }

  void _regler(BuildContext ctx, ContexteEcran c, PointageBadgePoste p) {
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'actif', libelle: 'Le badge sert de pointage', type: TypeChamp.case_, col: ColChamp.plein),
      const ChampDef(nom: 'delai', libelle: 'Délai minimal entre deux pointages (minutes)', type: TypeChamp.nombre, requis: true, col: ColChamp.plein),
    ], {'actif': p.actif(), 'delai': '${p.delai()}'});
    afficherModale<void>(ctx,
        titre: 'Pointage par badge',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NoteSigh('Le délai de $delaiPointageBadgeDefaut minutes est une proposition à valider par la Direction. Le réglage se règle à la mère et se synchronise.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final r = p.regler(actif: v['actif'] == true, delai: v['delai']);
                    if (r['ok'] != true) {
                      ToastsSigh.afficher(ctx, '${r['motif']}', type: TypeToast.erreur, detail: '${r['geste']}');
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Réglage enregistré.', type: TypeToast.succes);
                  }),
            ]);
  }

  Widget _corps(BuildContext context, ContexteEcran c) {
    final retires = trierPar([for (final b in rhbActives(c, 'badges')) if (!rhcEtatBadge(b['etat']).actif) b], (b) => b['retireLe']).reversed.take(10).toList();
    final peutPointer = rolesPointageBadge.contains(c.role) && _pointage(c).actif();
    return rhbEspace([
      _cartePointage(context, c),
      CarteSigh(
          titre: 'Badge présenté',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
              ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 288, maxWidth: 640),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text('Numéro de série ou code scanné', style: TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500))),
                    TextField(
                      key: const Key('rhc:saisie'),
                      controller: _saisie,
                      onSubmitted: (_) => _verifier(c, context),
                      style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 18, height: 28 / 18, color: JetonsShell.slate900),
                      decoration: InputDecoration(
                          hintText: 'BDG-00007-2026 — ou coller le contenu du QR',
                          hintStyle: const TextStyle(fontFamily: 'LiberationMono', fontSize: 18, color: JetonsShell.slate400),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: JetonsShell.slate300))),
                    ),
                  ])),
              BoutonSigh(libelle: 'Vérifier', icone: LucideIcons.scanFace, onPressed: () => _verifier(c, context)),
              if (peutPointer) BoutonSigh(libelle: 'Pointer', icone: LucideIcons.logIn, variante: VarianteBouton.succes, onPressed: () => _pointer(c, context)),
            ]),
            const SizedBox(height: 12),
            const NoteSigh(
                'La saisie manuelle est acceptée autant que le scan : refuser le numéro à la main rendrait le contrôle impossible le jour où le QR est abîmé — c’est-à-dire le jour où il sert le plus.',
                icone: LucideIcons.keyboard),
            if (_reponse != null) ...[const SizedBox(height: 12), _reponse!],
          ])),
      CarteSigh(
          titre: 'Badges retirés — à refuser à l’entrée',
          child: retires.isEmpty
              ? const VideSigh('Aucun badge retiré.', icone: LucideIcons.circleCheck)
              : MiniTableauSigh(colonnes: [
                  ColonneMini('N° de série', (b) => '${b['numero']}'),
                  ColonneMini('Agent', (b) => '${b['agent']}'),
                  ColonneMini('Motif', (b) => '${b['motifRetrait'] ?? '—'}'.isEmpty ? '—' : '${b['motifRetrait'] ?? '—'}'),
                  ColonneMini('Depuis le', (b) => '${b['retireLe'] ?? ''}'.isEmpty ? '—' : rhcDate(b['retireLe'])),
                ], lignes: retires)),
    ]);
  }
}
