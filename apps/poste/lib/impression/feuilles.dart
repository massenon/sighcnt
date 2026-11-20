import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../shell/logo_clinique.dart';
import 'piece.dart';

/// 1 mm = 96/25,4 px logiques : le gabarit imprimé garde ses dimensions physiques à l'aperçu (A4 = 210 × 297 mm, rouleau = 80 mm).
const double pxParMm = 96 / 25.4;
double mm(double v) => v * pxParMm;

const _mono = 'LiberationMono';

/// Rouleau de caisse 80 mm (`P.ticket`) : largeur 80 mm, marge 4 mm, police chasse fixe, tailles 7–11 px de la maquette.
class FeuilleTicket extends StatelessWidget {
  const FeuilleTicket(
      {super.key, required this.entree, required this.reference, this.identite = IdentiteImprimee.semence});
  final EntreeTicket entree;
  final String reference;

  /// L'identité en force à la date du ticket (`P.ticket({date})`).
  final IdentiteImprimee identite;

  @override
  Widget build(BuildContext context) {
    final lignes = lignesTicket(entree, identite: identite);
    return Container(
      key: const Key('impression:ticket'),
      width: mm(80),
      padding: EdgeInsets.all(mm(4)),
      color: Colors.white,
      child: DefaultTextStyle(
        style: const TextStyle(
            fontFamily: _mono,
            fontSize: 9,
            height: 1.375,
            color: JetonsShell.slate900),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final l in lignes) _ligne(l),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Réf. $reference',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 7, color: JetonsShell.slate400))),
        ]),
      ),
    );
  }

  Widget _ligne(LigneTicket l) {
    if (l.estPaire) {
      final s =
          TextStyle(fontWeight: l.gras ? FontWeight.w700 : FontWeight.w400);
      return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: Text(l.gauche, style: s)),
            const SizedBox(width: 8),
            Text(l.droite!, textAlign: TextAlign.right, style: s),
          ]);
    }
    return switch (l.style) {
      StyleLigne.titre => Text(l.gauche,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, height: 1.25)),
      StyleLigne.centre => Text(l.gauche,
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 8)),
      StyleLigne.centreGras => Text(l.gauche,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      StyleLigne.lettres => Text(l.gauche,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600)),
      StyleLigne.separateur => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(l.gauche,
              style: const TextStyle(height: 1, color: JetonsShell.slate400))),
      _ => Text(l.gauche),
    };
  }
}

/// Feuille A4 (`P.etat`) : 210 × 297 mm, marge 12 mm. En-tête : filet navy-900 de 3 px, logo, nom 22 px gras, coordonnées 9–10 px.
class FeuilleA4 extends StatelessWidget {
  const FeuilleA4({super.key, required this.piece});
  final PieceA4 piece;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('impression:a4'),
        width: mm(piece.paysage ? 297 : 210),
        constraints: BoxConstraints(minHeight: mm(piece.paysage ? 210 : 297)),
        padding: EdgeInsets.all(mm(12)),
        color: Colors.white,
        child: DefaultTextStyle.merge(
          style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              height: 1.625,
              color: JetonsShell.slate900),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _entete(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Container(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: JetonsShell.navy900, width: 2))),
                    child: Text(piece.titre.toUpperCase(),
                        key: const Key('impression:titre'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: JetonsShell.navy950,
                            height: 1.5))),
                if (piece.sousTitre != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(piece.sousTitre!,
                          style: const TextStyle(color: JetonsShell.slate600))),
              ]),
            ),
            if (piece.filtres.isNotEmpty) _filtres(),
            if (piece.cartouche.isNotEmpty) _cartouche(),
            for (final b in piece.blocs)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12), child: _bloc(b)),
            if (piece.lieuDate)
              Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text('Fait à Natitingou, le ${dateLong(piece.edite)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          color: JetonsShell.slate700))),
            if (piece.signatures.isNotEmpty) _signatures(),
            _pied(),
          ]),
        ),
      );

  Widget _entete() {
    final i = piece.identiteImprimee;
    return Container(
        key: const Key('impression:entete'),
        padding: const EdgeInsets.only(bottom: 8),
        decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: JetonsShell.navy900, width: 3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const LogoClinique(largeur: 64, hauteur: 64),
          const SizedBox(width: 16),
          Flexible(
            child: Column(children: [
              Text(i.nomCourt,
                  key: const Key('impression:entete:nom'),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      letterSpacing: -0.5,
                      color: JetonsShell.navy950)),
              Text(
                  '${i.bp}   TÉL. : ${i.telephones.join('  /  ')}',
                  style: const TextStyle(
                      fontSize: 10,
                      height: 1.375,
                      color: JetonsShell.slate700)),
              Text(
                  'AUTORISATION D’OUVERTURE ${i.autorisation}',
                  style: const TextStyle(
                      fontSize: 9, height: 1.375, color: JetonsShell.slate700)),
              Text(
                  'IFU : ${i.ifu}   RCCM : ${i.rccm}',
                  key: const Key('impression:entete:ifu-rccm'),
                  style: const TextStyle(
                      fontSize: 9,
                      height: 1.375,
                      fontWeight: FontWeight.w600,
                      color: JetonsShell.slate800)),
              Text('E-mail : ${i.email}',
                  style: const TextStyle(
                      fontSize: 9, height: 1.375, color: JetonsShell.slate700)),
              Text(i.slogan,
                  style: const TextStyle(
                      fontSize: 9,
                      height: 1.375,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                      color: JetonsShell.navy800)),
            ]),
          ),
          const SizedBox(width: 16),
          const SizedBox(width: 64, height: 64),
        ]),
      );
  }

  Widget _filtres() => Container(
        key: const Key('impression:filtres'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            border: Border.all(color: JetonsShell.slate300),
            borderRadius: BorderRadius.circular(4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('FILTRES APPLIQUÉS À CET ÉTAT',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: JetonsShell.slate600)),
          Wrap(spacing: 16, runSpacing: 4, children: [
            for (final f in piece.filtres)
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${f.$1} : ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: f.$2)
              ])),
          ]),
          const Text(
              'L’état ne porte que les enregistrements retenus par ces filtres.',
              style: TextStyle(
                  fontStyle: FontStyle.italic, color: JetonsShell.slate500)),
        ]),
      );

  Widget _cartouche() => Container(
        key: const Key('impression:cartouche'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            border: Border.all(color: JetonsShell.slate300),
            borderRadius: BorderRadius.circular(4)),
        child: Wrap(spacing: 24, runSpacing: 4, children: [
          for (final p in piece.cartouche)
            SizedBox(
                width: 300,
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${p.$1} : ',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: p.$2),
                ]))),
        ]),
      );

  Widget _bloc(BlocPiece b) => switch (b) {
        BlocTableau() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (b.titre != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 4),
                    child: Text(b.titre!.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: b.alerte
                                ? JetonsShell.danger700
                                : JetonsShell.navy900))),
              _tableau(b.tableau),
            ],
          ),
        BlocTexte() => Text(b.texte,
            style: TextStyle(
                fontWeight: b.gras ? FontWeight.w600 : FontWeight.w400,
                fontStyle: b.italique ? FontStyle.italic : FontStyle.normal,
                color: JetonsShell.slate800)),
        BlocOrganigramme() => _organigramme(b.miseEnPage),
        BlocQr() => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(key: const Key('impression:qr'), width: b.cote, height: b.cote, child: CustomPaint(painter: _PeintreQr(b.matrice))),
              if (b.legende != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(b.legende!, textAlign: TextAlign.center, style: const TextStyle(color: JetonsShell.slate800))),
            ])),
      };

  /// L'organigramme : les boîtes aux mesures du domaine, les connecteurs tracés dessous (aucune couleur en dur : celles du design system).
  Widget _organigramme(OrgMiseEnPage m) => Center(
        child: SizedBox(
            key: const Key('impression:organigramme'),
            width: mm(m.largeur),
            height: mm(m.hauteur),
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: CustomPaint(painter: _PeintreOrganigramme(m))),
              for (final b in m.boites)
                Positioned(
                    left: mm(b.gauche),
                    top: mm(b.haut),
                    width: mm(b.largeur),
                    height: mm(b.hauteur),
                    child: Container(
                        key: Key('organigramme:${b.poste}'),
                        clipBehavior: Clip.hardEdge,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                            color: b.racine ? JetonsShell.navy50 : Colors.white,
                            border: Border.all(color: b.racine ? JetonsShell.navy900 : JetonsShell.slate500, width: 0.75),
                            borderRadius: BorderRadius.circular(2)),
                        alignment: Alignment.center,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (var i = 0; i < b.lignes.length; i++)
                            Text(b.lignes[i],
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: i == 0 ? 9 : 8.5, height: 1.2, fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400, color: JetonsShell.slate900)),
                        ]))),
            ])),
      );

  Widget _tableau(TableauEtat t) {
    final pied = t.pied;
    Widget cellule(String s,
            {bool droite = false, bool entete = false, bool total = false}) =>
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: entete
                    ? JetonsShell.slate100
                    : (total ? JetonsShell.slate50 : null),
                border: Border.all(
                    color: entete || total
                        ? JetonsShell.slate400
                        : JetonsShell.slate300,
                    width: 0.5)),
            alignment: droite ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(s,
                textAlign: droite ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                    height: 1.3,
                    fontWeight: entete
                        ? FontWeight.w600
                        : (total ? FontWeight.w700 : FontWeight.w400),
                    fontFeatures:
                        droite ? const [FontFeature.tabularFigures()] : null)));
    return Table(
        key: const Key('impression:tableau'),
        defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
        children: [
          TableRow(children: [
            for (final c in t.colonnes)
              cellule(c.libelle, droite: c.droite, entete: true)
          ]),
          for (final r in t.cellules)
            TableRow(children: [
              for (var i = 0; i < r.length; i++)
                cellule(r[i], droite: t.colonnes[i].droite)
            ]),
          if (pied != null)
            TableRow(children: [
              for (var i = 0; i < pied.length; i++)
                cellule(pied[i], droite: t.colonnes[i].droite, total: true)
            ]),
        ]);
  }

  Widget _signatures() => Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Row(children: [
          for (final s in piece.signatures.take(4))
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(children: [
                  Text(s.role,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: JetonsShell.slate700)),
                  if (s.nom != null)
                    Text(s.nom!,
                        style: const TextStyle(
                            fontSize: 9, color: JetonsShell.slate500)),
                  const SizedBox(height: 40),
                  const Divider(height: 1, color: JetonsShell.slate400),
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(s.mention,
                          style: const TextStyle(
                              fontSize: 8, color: JetonsShell.slate400))),
                ]),
              ),
            ),
        ]),
      );

  Widget _pied() => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        key: const Key('impression:pied'),
        padding: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: JetonsShell.slate300))),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
              fontSize: 8, height: 1.4, color: JetonsShell.slate500),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      '${piece.identiteImprimee.nom} — ${piece.identiteImprimee.rccm} — IFU ${piece.identiteImprimee.ifu}'),
                  Text(
                      'Document généré par ${piece.utilisateur} le ${dateHeure(piece.edite)}'),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Réf. document : ${piece.reference}',
                      style: const TextStyle(fontFamily: _mono)),
                  const Text('Édité depuis le SIGH-CNT'),
                ]),
              ]),
        ),
      ));
}

/// Les connecteurs de l'organigramme : un tronc depuis le parent, une barre à mi-écart, une descente vers chaque enfant et sa flèche (mesures en millimètres).
class _PeintreOrganigramme extends CustomPainter {
  _PeintreOrganigramme(this.m);
  final OrgMiseEnPage m;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..color = JetonsShell.slate500
      ..strokeWidth = mm(0.35)
      ..strokeCap = StrokeCap.square;
    for (final t in m.traits) {
      canvas.drawLine(Offset(mm(t.x1), mm(t.y1)), Offset(mm(t.x2), mm(t.y2)), trait);
    }
    final pointe = Paint()
      ..color = JetonsShell.slate500
      ..style = PaintingStyle.fill;
    for (final f in m.fleches) {
      final p = Path()..moveTo(mm(f.points[0].$1), mm(f.points[0].$2));
      for (final q in f.points.skip(1)) {
        p.lineTo(mm(q.$1), mm(q.$2));
      }
      canvas.drawPath(p..close(), pointe);
    }
  }

  @override
  bool shouldRepaint(_PeintreOrganigramme old) => old.m != m;
}


/// Le QR de l'affiche : modules noirs sur fond blanc, zone de silence de quatre modules.
class _PeintreQr extends CustomPainter {
  _PeintreQr(this.m);
  final List<List<bool>> m;

  @override
  void paint(Canvas canvas, Size taille) {
    canvas.drawRect(Offset.zero & taille, Paint()..color = Colors.white);
    final n = m.length + 8;
    final u = taille.width / n;
    final p = Paint()..color = Colors.black;
    for (var r = 0; r < m.length; r++) {
      for (var c = 0; c < m[r].length; c++) {
        if (m[r][c]) canvas.drawRect(Rect.fromLTWH((c + 4) * u, (r + 4) * u, u + 0.4, u + 0.4), p);
      }
    }
  }

  @override
  bool shouldRepaint(_PeintreQr o) => o.m != m;
}
