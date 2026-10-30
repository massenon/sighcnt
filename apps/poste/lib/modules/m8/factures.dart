import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String _m(Object? v) => money(v, avecDevise: false);
String _date(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

const _natures = [
  'Consultation',
  'Hospitalisation',
  'Laboratoire',
  'Pharmacie',
  'Soins à domicile'
];

/// Colonnes partagées par les écrans de facturation (`colNumero`, `colPatientF`, … de m8-facturation.js).
final colNumero = ColonneTableau(
  cle: 'numero',
  libelle: 'N° facture',
  sansCoupure: true,
  rendu: (_, f) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${f['numero']}',
            style: const TextStyle(
                fontFamily: 'LiberationMono',
                color: JetonsShell.navy800,
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w600)),
        if (f['numeroMecef'] != null)
          Text('${f['numeroMecef']}',
              style: const TextStyle(
                  fontFamily: 'LiberationMono',
                  color: JetonsShell.slate400,
                  fontSize: 10,
                  height: 15 / 10)),
      ]),
  texte: (f) => '${f['numero'] ?? ''}',
);

final colPatient = ColonneTableau(
  cle: 'patient',
  libelle: 'Patient',
  rendu: (_, f) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${f['patient'] ?? ''}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: JetonsShell.slate800,
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w500)),
        Text('${f['patientCode'] ?? ''}',
            style: const TextStyle(
                fontFamily: 'LiberationMono',
                color: JetonsShell.slate400,
                fontSize: 12,
                height: 16 / 12)),
      ]),
  texte: (f) => '${f['patient'] ?? ''} ${f['patientCode'] ?? ''}',
);

final colDate = ColonneTableau(
    cle: 'date',
    libelle: 'Date',
    sansCoupure: true,
    texte: (f) => _date(f['date']),
    valeur: (f) => f['date']);

final colMontant = ColonneTableau(
  cle: 'montantTTC',
  libelle: 'Montant',
  droite: true,
  texte: (f) => _m(f['montantTTC']),
  rendu: (_, f) => Text(_m(f['montantTTC']),
      style: const TextStyle(
          color: JetonsShell.slate700,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()])),
);

final colReliquat = ColonneTableau(
  cle: 'reliquat',
  libelle: 'Reste dû',
  droite: true,
  texte: (f) => _m(f['reliquat']),
  rendu: (_, f) => _n(f['reliquat']) > 0
      ? Text(_m(f['reliquat']),
          style: const TextStyle(
              color: JetonsShell.danger600,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()]))
      : const Text('—',
          style: TextStyle(
              color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
);

final colStatutPaiement = ColonneTableau(
    cle: 'statutPaiement',
    libelle: 'Règlement',
    rendu: (_, f) => statutBadge(f['statutPaiement']),
    texte: (f) =>
        '${statutsMetier['${f['statutPaiement']}']?.$1 ?? f['statutPaiement'] ?? ''}');

Widget _badgeMecef(Object? s) {
  const m = {
    'valide': ('Validée', TonSigh.succes),
    'en_attente': ('En attente', TonSigh.attention),
    'rejete': ('Rejetée', TonSigh.danger)
  };
  final x = m['$s'] ?? ('—', TonSigh.neutre);
  return BadgeSigh(x.$1, ton: x.$2);
}

const _modes = {
  'especes': 'Espèces',
  'mobile_money': 'Mobile money',
  'carte': 'Carte bancaire',
  'virement': 'Virement',
  'cheque': 'Chèque',
  'assurance': 'Assurance'
};

/// Détail d'une facture (`detailFacture`) : deux KPI, puis la fiche. Les lignes de la pièce s'affichent sous la fiche.
Widget detailFacture(Fiche f) {
  final reste = _n(f['reliquat']);
  final assure = f['assureur'] != null;
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    KpiGrilleSigh(colonnes: 2, kpis: [
      KpiSigh(
          libelle: 'Montant total',
          valeur: money(f['montantTTC']),
          icone: LucideIcons.receipt),
      KpiSigh(
          libelle: 'Reste à payer',
          valeur: money(f['reliquat']),
          icone: LucideIcons.wallet,
          ton: reste > 0 ? TonSigh.danger : TonSigh.succes),
    ]),
    const SizedBox(height: 16),
    DescListeSigh([
      (
        'N° facture',
        Text('${f['numero']}',
            style: const TextStyle(
                fontFamily: 'LiberationMono',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: JetonsShell.slate800))
      ),
      (
        'N° MECeF',
        f['numeroMecef'] != null
            ? Text('${f['numeroMecef']}',
                style: const TextStyle(
                    fontFamily: 'LiberationMono',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: JetonsShell.slate800))
            : const BadgeSigh('Non transmise', ton: TonSigh.attention)
      ),
      ('Date', _date(f['date'])),
      ('Patient', f['patient']),
      (
        'Dossier',
        Text('${f['patientCode'] ?? '—'}',
            style: const TextStyle(
                fontFamily: 'LiberationMono',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: JetonsShell.slate800))
      ),
      ('Nature', f['type']),
      ('Montant HT', money(f['montantHT'])),
      ('Montant TTC', money(f['montantTTC'])),
      (
        'Part assurance',
        assure
            ? '${money(f['partAssurance'])} (${f['tauxPriseEnCharge']} %)'
            : 'Sans objet'
      ),
      ('Part patient', money(f['partPatient'])),
      ('Montant réglé', money(f['montantPaye'])),
      (
        'Mode de règlement',
        _modes['${f['modePaiement']}'] ?? f['modePaiement']
      ),
      ('Statut', statutBadge(f['statutPaiement'])),
    ]),
  ]);
}

/// `m8-factures` — « Factures » : consultation du registre des factures émises. Une facture s'établit depuis l'écran d'émission.
class EcranFactures extends StatelessWidget with EcranMaquette {
  const EcranFactures({super.key});

  @override
  String get description =>
      'Ensemble des factures émises, avec suivi du règlement, de la prise en charge assurance et de la transmission MECeF.';

  @override
  String get regle =>
      'Cet écran consulte les factures émises. Une facture s’établit depuis l’écran d’émission, seul endroit où se choisissent les prestations, les remises et la répartition assureur / patient : le bouton « Nouveau » y conduit plutôt que d’ouvrir une saisie incomplète.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Avoirs',
          icone: LucideIcons.fileMinus,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m8-remboursements')),
      if (c.droit.editer)
        BoutonSigh(
            libelle: 'Nouvelle facture',
            icone: LucideIcons.plus,
            onPressed: () => c.aller('m8-facturation')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return CrudSigh(
      collection: c.magasin.collection('factures'),
      entite: 'facture',
      entiteP: 'factures',
      creerVers: 'm8-facturation',
      triInitial: 'date',
      sensInitial: 'desc',
      taillePage: 15,
      colonnes: [
        colNumero,
        colDate,
        colPatient,
        ColonneTableau(
            cle: 'type',
            libelle: 'Nature',
            rendu: (_, f) => BadgeSigh('${f['type'] ?? ''}', ton: TonSigh.navy),
            texte: (f) => '${f['type'] ?? ''}'),
        colMontant,
        ColonneTableau(
          cle: 'partAssurance',
          libelle: 'Part assurance',
          droite: true,
          texte: (f) => f['assureur'] != null ? _m(f['partAssurance']) : '',
          rendu: (_, f) => f['assureur'] != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                      Text(_m(f['partAssurance']),
                          style: const TextStyle(
                              color: JetonsShell.slate700,
                              fontSize: 14,
                              height: 20 / 14)),
                      Text('${f['assureur']} ${f['tauxPriseEnCharge']} %',
                          style: const TextStyle(
                              color: JetonsShell.slate400,
                              fontSize: 12,
                              height: 16 / 12)),
                    ])
              : const Text('—',
                  style: TextStyle(
                      color: JetonsShell.slate400,
                      fontSize: 12,
                      height: 16 / 12)),
        ),
        ColonneTableau(
            cle: 'montantPaye',
            libelle: 'Réglé',
            droite: true,
            texte: (f) => _m(f['montantPaye'])),
        colReliquat,
        colStatutPaiement,
        ColonneTableau(
            cle: 'statutMecef',
            libelle: 'MECeF',
            rendu: (_, f) => _badgeMecef(f['statutMecef']),
            texte: (f) => '${f['statutMecef'] ?? ''}'),
      ],
      filtres: [
        FiltreTableau(nom: 'statutPaiement', libelle: 'Règlement', options: [
          OptionChamp('soldee', 'Soldée'),
          OptionChamp('partielle', 'Partielle'),
          OptionChamp('impayee', 'Impayée')
        ]),
        FiltreTableau(
            nom: 'type',
            libelle: 'Nature',
            options: [for (final n in _natures) OptionChamp(n)]),
        FiltreTableau(nom: 'statutMecef', libelle: 'MECeF', options: [
          OptionChamp('valide', 'Validée'),
          OptionChamp('en_attente', 'En attente'),
          OptionChamp('rejete', 'Rejetée')
        ]),
        FiltreTableau(
            nom: 'assurance',
            libelle: 'Couverture',
            options: [
              OptionChamp('oui', 'Avec assurance'),
              OptionChamp('non', 'Sans assurance')
            ],
            correspond: _couverture),
      ],
      kpis: (rows) => [
        KpiSigh(
            libelle: 'Factures',
            valeur: nombre(rows.length),
            icone: LucideIcons.receipt),
        KpiSigh(
            libelle: 'Chiffre d’affaires',
            valeur: money(_somme(rows, 'montantTTC')),
            icone: LucideIcons.trendingUp,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Encaissé',
            valeur: money(_somme(rows, 'montantPaye')),
            icone: LucideIcons.banknote,
            ton: TonSigh.succes),
        KpiSigh(
            libelle: 'Reste à recouvrer',
            valeur: money(_somme(rows, 'reliquat')),
            icone: LucideIcons.handCoins,
            ton: TonSigh.attention),
      ],
      detail: detailFacture,
      titreDetail: (f) => '${f['numero']}',
      sousTitreDetail: (f) => '${f['patient'] ?? ''}',
    );
  }

  static bool _couverture(Fiche f, String v) =>
      v == 'oui' ? f['assureur'] != null : f['assureur'] == null;
  static num _somme(List<Fiche> rows, String cle) =>
      rows.fold<num>(0, (a, r) => a + _n(r[cle]));
}
