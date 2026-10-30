import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m8/commun.dart' show n, m, dateDe;

export '../m8/commun.dart' show n, m, dateDe;

/// Le référentiel fiscal de la maquette (`D.PARAM_FISCAL`), tel que le poste l'embarque.
ParamFiscal paramFiscal(Magasin mag) =>
    ParamFiscal.depuis((mag.referentiels['paramFiscal'] as Map).cast());

/// Les factures NORMALISÉES : tout sauf les pro-forma. La maquette les filtre aussi par exercice (sélecteur de l'en-tête M12) : ce sélecteur n'est
/// pas encore porté, le registre montre donc tous les exercices — limite dite dans le plan.
List<Fiche> normalisees(Magasin mag) => [
      for (final f in mag.collection('factures').actives)
        if (f['proforma'] != true) f
    ];

const statutsMecef = {
  'valide': ('Validée', TonSigh.succes),
  'en_attente': ('En attente de transmission', TonSigh.attention),
  'rejete': ('Rejetée', TonSigh.danger),
};

Widget badgeStatut(Object? s) {
  final x = statutsMecef['$s'];
  return BadgeSigh(x?.$1 ?? '—', ton: x?.$2 ?? TonSigh.neutre);
}

Widget _mono(String t, {double taille = 12, Color? couleur, FontWeight? poids}) =>
    Text(t,
        style: TextStyle(
            fontFamily: 'LiberationMono',
            fontSize: taille,
            color: couleur ?? JetonsShell.slate900,
            fontWeight: poids));

ColonneTableau colFacture() => ColonneTableau(
    cle: 'numero',
    libelle: 'N° facture',
    sansCoupure: true,
    texte: (f) => '${f['numero']}',
    rendu: (_, f) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _mono('${f['numero']}',
                  couleur: JetonsShell.navy800, poids: FontWeight.w600),
              f['numeroMecef'] != null
                  ? _mono('${f['numeroMecef']}',
                      taille: 10, couleur: JetonsShell.slate400)
                  : const Text('Non transmise',
                      style: TextStyle(
                          color: JetonsShell.warning600, fontSize: 10)),
            ]));

ColonneTableau colDate() => ColonneTableau(
    cle: 'date',
    libelle: 'Date',
    sansCoupure: true,
    texte: (f) => dateDe(f['date']));

ColonneTableau colMontantTtc() => ColonneTableau(
    cle: 'montantTTC',
    libelle: 'Montant TTC',
    droite: true,
    texte: (f) => m(f['montantTTC']),
    rendu: (_, f) => Text(m(f['montantTTC']),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));

ColonneTableau colTva(ParamFiscal p) => ColonneTableau(
    cle: 'tva',
    libelle: 'TVA',
    droite: true,
    valeur: (f) => tvaRegistre(n(f['montantTTC']), p),
    texte: (f) => m(tvaRegistre(n(f['montantTTC']), p)));

ColonneTableau colStatut() => ColonneTableau(
    cle: 'statutMecef',
    libelle: 'Statut fiscal',
    texte: (f) => statutsMecef['${f['statutMecef']}']?.$1 ?? '—',
    rendu: (_, f) => badgeStatut(f['statutMecef']));

/// La facture normalisée imprimée, d'après la facture SoBAPS n° 26FNA00026 : lignes HT/TTC, taxes, totaux, montant en lettres, bloc de certification.
PieceA4 pieceFactureNormalisee(Fiche f, ParamFiscal p,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final fn = factureNormalisee(f, p);
  return PieceA4(
    titre: 'Facture de vente — normalisée',
    sousTitre: '${f['numero']}${f['numeroMecef'] != null ? ' — ${f['numeroMecef']}' : ''}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Facture n°', '${f['numero']}'),
      ('Date', dateDe(f['date'])),
      ('Client', '${f['patient'] ?? ''}'),
      ('Dossier client', '${f['patientCode'] ?? ''}'),
      // Écart E14 porté et signalé : l'« IFU client » imprimé est celui de la clinique.
      ('IFU client', ifuClientImprime),
      ('Nature', '${f['type'] ?? ''}'),
    ],
    blocs: [
      BlocTableau(fn.lignes),
      BlocTableau(fn.taxes),
      if (fn.mentionExoneration != null)
        BlocTexte(fn.mentionExoneration!, italique: true),
      BlocTableau(fn.totaux),
      const BlocTexte('Devise : FCFA'),
      BlocTexte('${p.mentionMontant} :', gras: true),
      BlocTexte(fn.enLettres.toUpperCase(), gras: true),
      // Le QR est un EMPLACEMENT : la certification réelle vient du boîtier physique (protocole attendu de la Direction).
      const BlocTexte('QR CODE MECeF — emplacement réservé (simulation)',
          italique: true),
      const BlocTexte('Code MECeF / DGI', gras: true),
      BlocTexte(fn.codeDgi, gras: true),
      BlocTexte('MECeF NIM : ${fn.nim}'),
      BlocTexte('MECeF Compteurs : ${fn.compteurs}'),
      const BlocTexte(
          'IFU émetteur : ${IdentiteClinique.ifu} — RCCM : ${IdentiteClinique.rccm}'),
      const BlocTexte(
          'Facture normalisée émise conformément au dispositif de facturation électronique en vigueur en République du Bénin. Toute facture non revêtue du code MECeF/DGI et du code à barres de vérification est réputée non conforme.',
          italique: true),
    ],
    signatures: const [
      Signature('Mention du caissier', mention: 'Signature et cachet'),
      Signature('Visa et cachet de la Direction'),
    ],
  );
}

Future<void> imprimerFactureNormalisee(BuildContext ctx, Fiche f) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(
      ctx,
      pieceFactureNormalisee(f, paramFiscal(c.magasin),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          reference: PieceA4.reference_(
              c.aujourdhui, ImpressionPoste.prochainNumero())));
}
