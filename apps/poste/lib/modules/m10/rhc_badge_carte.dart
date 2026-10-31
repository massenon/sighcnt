import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../impression/feuilles.dart' show mm;
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/qual_qr.dart';

/// LE BADGE, TROISIÈME GABARIT D'IMPRESSION (à côté du A4 et du rouleau 80 mm) : la carte CR80, 85,6 × 54 mm — le format des imprimantes à cartes et des porte-badges
/// du commerce. Composée en MILLIMÈTRES, pas en pixels : c'est ce qui permet de l'imprimer telle quelle sur une carte.
///
/// L'EN-TÊTE OFFICIEL NE S'APPLIQUE PAS TEL QUEL : logo, dénomination et devise ; ni IFU ni RCCM — ce sont des mentions FISCALES, destinées à une pièce comptable,
/// pas à une carte qu'on accroche à une blouse. AUCUNE couleur en dur hors des jetons du design system : changer la charte change le badge.
/// Le QR ne porte QUE le matricule et le numéro de série (`rhcBadgeQR`).
const double rhcLargeurCr80 = 85.6;
const double rhcHauteurCr80 = 54;

/// La photographie d'un badge est une URL de données (`data:image/png;base64,…`) : décodée sans réseau.
Uint8List? rhcPhoto(Object? donnees) {
  final s = '${donnees ?? ''}';
  if (!s.startsWith('data:')) return null;
  try {
    return UriData.parse(s).contentAsBytes();
  } catch (_) {
    return null;
  }
}

class CarteBadgeSigh extends StatelessWidget {
  const CarteBadgeSigh({super.key, required this.badge, required this.modele, this.agent, this.verso = false});

  /// La fiche du badge (numéro, matricule, agent, poste, service, validité, photo).
  final Fiche badge;
  final RhcModele modele;

  /// La fiche du personnel, quand le badge n'a pas figé le nom (aperçu d'un spécimen : `null`).
  final Fiche? agent;
  final bool verso;

  @override
  Widget build(BuildContext context) {
    final portrait = modele.portrait;
    final l = portrait ? rhcHauteurCr80 : rhcLargeurCr80, h = portrait ? rhcLargeurCr80 : rhcHauteurCr80;
    return Container(
      key: Key(verso ? 'rhc:carte:verso' : 'rhc:carte:recto'),
      width: mm(l),
      height: mm(h),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(mm(2.5)), border: Border.all(color: JetonsShell.slate300, width: mm(0.2))),
      child: DefaultTextStyle.merge(style: const TextStyle(fontFamily: 'Inter', color: JetonsShell.slate900), child: verso ? _verso() : _recto(h)),
    );
  }

  Widget _verso() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(IdentiteClinique.nom, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: JetonsShell.navy900)),
          Container(margin: const EdgeInsets.only(top: 4), height: 1, color: JetonsShell.slate200),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final t in modele.mentionsVerso)
                      Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(t, style: const TextStyle(fontSize: 6, height: 1.375, color: JetonsShell.slate600))),
                  ]))),
          Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('N° de série', style: TextStyle(fontSize: 6, color: JetonsShell.slate500)),
              Text('${badge['numero'] ?? '—'}', style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 7, fontWeight: FontWeight.w700, color: JetonsShell.slate800)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Valable jusqu’au', style: TextStyle(fontSize: 6, color: JetonsShell.slate500)),
              Text(badge['expireLe'] != null && badge['expireLe'] != '' ? _date(badge['expireLe']) : 'non fixée',
                  style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: JetonsShell.slate800)),
            ]),
          ]),
          const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(IdentiteClinique.slogan, textAlign: TextAlign.center, style: TextStyle(fontSize: 6, fontStyle: FontStyle.italic, color: JetonsShell.navy800))),
        ]),
      );

  static String _date(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}'.padRight(10).substring(0, 10).trim());
    return d == null ? '$v' : dateFR(d);
  }

  Widget _recto(double h) {
    final z = modele.zones;
    final photo = rhcPhoto(badge['photo']);
    final charge = rhcBadgeQR(badge);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: mm(11),
        color: JetonsShell.navy900,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Image.asset('assets/img/logo.jpeg', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
          const SizedBox(width: 6),
          const Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CLINIQUE NASSIERA TOO',
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8, height: 1.25, fontWeight: FontWeight.w700, color: Colors.white)),
            Text(IdentiteClinique.slogan, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 6, height: 1.25, fontStyle: FontStyle.italic, color: JetonsShell.navy100)),
          ])),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (z['photo'] != false) ...[
              Container(
                  width: mm(20),
                  height: mm(26),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: JetonsShell.slate100, borderRadius: BorderRadius.circular(4), border: Border.all(color: JetonsShell.slate300)),
                  // Une photo manquante SE DIT : un cadre vide se lirait comme un défaut d'impression, et le badge partirait tel quel.
                  child: photo != null
                      ? Image.memory(photo, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                      : const Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('PHOTO', style: TextStyle(fontSize: 6, height: 1.25, color: JetonsShell.slate400)),
                          Text('À COLLER', style: TextStyle(fontSize: 6, height: 1.25, color: JetonsShell.slate400)),
                        ]))),
              const SizedBox(width: 8),
            ],
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (z['nom'] != false)
                Text((agent != null ? '${agent!['nomComplet']}' : '${badge['agent'] ?? '—'}').toUpperCase(),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.25, fontWeight: FontWeight.w700, color: JetonsShell.navy950)),
              if (z['fonction'] != false)
                Text(_ou(badge['poste'], agent?['poste']),
                    style: const TextStyle(fontSize: 7, height: 1.25, fontWeight: FontWeight.w600, color: JetonsShell.navy700)),
              if (z['service'] != false)
                Text('Service : ${_ou(badge['service'], agent?['service'])}', style: const TextStyle(fontSize: 7, height: 1.25, color: JetonsShell.slate600)),
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Matricule ${badge['matricule'] ?? '—'}',
                      style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 7, height: 1.25, color: JetonsShell.slate700))),
              const Spacer(),
              Text('${badge['numero'] ?? ''}', style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 6, height: 1.25, color: JetonsShell.slate500)),
            ])),
            if (z['qr'] != false) ...[
              const SizedBox(width: 8),
              Column(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.max, children: [
                // Au-delà de 106 octets le code ne se lirait plus : refusé, et dit (jamais un carré illisible).
                if (rhcQrAcceptable(charge))
                  QrSigh(charge, taille: mm(17), marge: 2, libelle: 'Code du badge')
                else
                  SizedBox(width: mm(17), child: const Text('Code trop long', style: TextStyle(fontSize: 6, color: JetonsShell.danger700))),
                const Padding(padding: EdgeInsets.only(top: 2), child: Text('Contrôle SIGH', style: TextStyle(fontSize: 5, color: JetonsShell.slate400))),
              ]),
            ],
          ]),
        ),
      ),
    ]);
  }

  static String _ou(Object? a, Object? b) {
    final x = '${a ?? ''}'.isNotEmpty ? a : (('${b ?? ''}'.isNotEmpty) ? b : null);
    return x == null ? '—' : '$x';
  }
}

/// `P.badge` — une carte, RECTO et VERSO l'un sous l'autre, dans l'aperçu commun aux trois gabarits.
Future<void> afficherApercuBadge(BuildContext ctx, ContexteEcran c, {required Fiche badge, required RhcModele modele, Fiche? agent}) {
  final ref = PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());
  final l = modele.portrait ? rhcHauteurCr80 : rhcLargeurCr80;
  Widget etiquette(String t, {double haut = 0}) => Padding(
      padding: EdgeInsets.only(top: haut, bottom: 4),
      child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 7, letterSpacing: 0.5, color: JetonsShell.slate400)));
  return afficherModale<void>(ctx,
      titre: 'Badge — ${badge['agent'] ?? ''}',
      sousTitre: ref,
      taille: TailleModale.sm,
      corps: Container(
        color: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.all(16),
        child: Center(
            child: Container(
          key: const Key('rhc:feuille-badge'),
          width: mm(l + 8),
          padding: EdgeInsets.all(mm(4)),
          color: Colors.white,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            etiquette('Recto'),
            CarteBadgeSigh(badge: badge, modele: modele, agent: agent),
            etiquette('Verso', haut: 12),
            CarteBadgeSigh(badge: badge, modele: modele, agent: agent, verso: true),
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Réf. $ref — ${c.utilisateur} — ${dateHeure(c.aujourdhui)}', style: const TextStyle(fontSize: 6, color: JetonsShell.slate400))),
          ]),
        )),
      ),
      pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
}

/// `P.planche` — la feuille A4 pour les cliniques SANS imprimante à cartes : dix badges par feuille (2 × 5), avec des repères de découpe. Le pied normalisé
/// (date, utilisateur, identifiant) va sur la PLANCHE et non sur les cartes : un badge n'a pas à porter l'heure de son impression. Au-delà de dix cartes,
/// les feuilles nécessaires s'empilent dans le même aperçu, dans l'ordre du tableau.
Future<void> afficherApercuPlanche(BuildContext ctx, ContexteEcran c, {required RhcModele modele, required List<({Fiche badge, Fiche? agent})> badges}) {
  final feuilles = <List<({Fiche badge, Fiche? agent})>>[
    for (var i = 0; i < badges.length; i += 10) badges.sublist(i, i + 10 > badges.length ? badges.length : i + 10)
  ];
  Widget coin(Alignment a) => Positioned(
      left: a.x < 0 ? 0 : null,
      right: a.x > 0 ? 0 : null,
      top: a.y < 0 ? 0 : null,
      bottom: a.y > 0 ? 0 : null,
      child: Container(
          width: mm(3),
          height: mm(3),
          decoration: BoxDecoration(
              border: Border(
                  top: a.y < 0 ? BorderSide(color: JetonsShell.slate400, width: mm(0.2)) : BorderSide.none,
                  bottom: a.y > 0 ? BorderSide(color: JetonsShell.slate400, width: mm(0.2)) : BorderSide.none,
                  left: a.x < 0 ? BorderSide(color: JetonsShell.slate400, width: mm(0.2)) : BorderSide.none,
                  right: a.x > 0 ? BorderSide(color: JetonsShell.slate400, width: mm(0.2)) : BorderSide.none))));
  Widget feuille(List<({Fiche badge, Fiche? agent})> l) {
    final ref = PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());
    return Container(
      key: const Key('rhc:feuille-planche'),
      width: mm(210),
      constraints: BoxConstraints(minHeight: mm(297)),
      padding: EdgeInsets.all(mm(12)),
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('PLANCHE DE BADGES — ${nombre(l.length)} CARTE(S)',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: JetonsShell.navy900))),
        Wrap(children: [
          for (final b in l)
            Padding(
                padding: EdgeInsets.all(mm(1.5)),
                child: Stack(children: [
                  Padding(padding: EdgeInsets.all(mm(0.1)), child: CarteBadgeSigh(badge: b.badge, agent: b.agent, modele: modele)),
                  coin(Alignment.topLeft),
                  coin(Alignment.topRight),
                  coin(Alignment.bottomLeft),
                  coin(Alignment.bottomRight),
                ])),
        ]),
        SizedBox(height: mm(24)),
        Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate300))),
            child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 8, height: 1.4, color: JetonsShell.slate500),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('${IdentiteClinique.nom} — ${IdentiteClinique.rccm} — IFU ${IdentiteClinique.ifu}'),
                    Text('Document généré par ${c.utilisateur} le ${dateHeure(c.aujourdhui)}'),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Réf. document : $ref', style: const TextStyle(fontFamily: 'LiberationMono')),
                    const Text('Édité depuis le SIGH-CNT'),
                  ]),
                ]))),
      ]),
    );
  }

  return afficherModale<void>(ctx,
      titre: 'Planche de badges',
      sousTitre: '${feuilles.length} feuille(s) A4 — ${badges.length} carte(s)',
      taille: TailleModale.xl,
      corps: Container(
          color: const Color(0xFFE2E8F0),
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Column(children: [for (final l in feuilles) feuille(l)]))),
      pied: (fermer) => [BoutonSigh(libelle: 'Fermer', icone: LucideIcons.x, variante: VarianteBouton.secondaire, onPressed: fermer)]);
}
