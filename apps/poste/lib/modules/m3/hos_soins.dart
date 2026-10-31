import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m5/res_commun.dart' show profilLabo;
import '../m6/stock_crud.dart';
import 'hos_commun.dart';

/// `m3-soins` — « Feuille de soins » : la file des actes prescrits à exécuter (infirmiers et sages-femmes), puis le registre des actes réalisés au
/// chevet — injections, pansements, perfusions, surveillance — rattachés à une admission et au soignant qui les a exécutés (RG-12).
///
/// « Ce sont les infirmiers qui font les soins. Ce n'est pas les aides-soignants » : qui n'a pas la capacité d'exécuter lit la règle, et un refus NOMMÉ
/// répond à sa tentative — jamais un bouton muet. L'exécution de la file ne passe PAS par le relais d'administration (`m3-administrations`) : elle clôt la
/// tâche et marque l'ordonnance (`statutActes`), l'heure d'exécution en regard de l'heure de prescription.
class EcranSoins extends StatelessWidget with EcranMaquette {
  const EcranSoins({super.key});

  @override
  String get titre => 'Feuille de soins';

  @override
  String get description =>
      'Actes de soins réalisés au chevet du patient : injections, pansements, perfusions et surveillance.';

  @override
  String get regle =>
      'Chaque acte est rattaché à une admission et au soignant qui l’a exécuté (RG-12). Les actes figurent dans la fiche du patient. '
      'Un acte prescrit et non coché est réputé non fait : la validation enregistre l’heure d’exécution en regard de l’heure de prescription.';

  /// `PR.peutExecuterSoin()` : la capacité « exécuter les soins » de la FONCTION de l'agent (déduite du rôle tant que la coque n'expose pas la fonction).
  static bool peutExecuter(ContexteEcran c) => hosExecuteSoins[profilLabo(c).cap.fonction] == true;

  static String libelleProfil(ContexteEcran c) => profilLabo(c).cap.label;

  static String noteRefus(String libelle) =>
      '$libelle — l’exécution des soins prescrits ne vous revient pas. Les soins prescrits sont réalisés par les infirmiers ; la feuille de soins reste '
      'consultable pour la continuité de la prise en charge, mais aucune validation n’est possible depuis ce poste.';

  /// Les champs du formulaire : le patient se choisit parmi les hospitalisés EN COURS (leur lit est proposé), l'heure se saisit en `HH:mm`.
  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'admissionId',
            libelle: 'Patient hospitalisé',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [
              for (final a in hosEnCours(m.collection('admissions').actives))
                OptionChamp('${a['id']}', '${a['patient']} — lit ${a['lit']} (${a['patientCode']})')
            ]),
        const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'heure', libelle: 'Heure', requis: true, indicatif: 'HH:mm', valider: validerHeure),
        ChampDef(
            nom: 'acte',
            libelle: 'Acte de soins',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [for (final a in hosActesSoins) OptionChamp(a)]),
        const ChampDef(nom: 'produit', libelle: 'Produit administré'),
        const ChampDef(nom: 'quantite', libelle: 'Quantité', type: TypeChamp.nombre),
        const ChampDef(nom: 'soignant', libelle: 'Soignant', requis: true),
        const ChampDef(nom: 'etat', libelle: 'État', type: TypeChamp.select, requis: true, options: [
          OptionChamp('realise', 'Réalisé'),
          OptionChamp('planifie', 'Planifié')
        ]),
        const ChampDef(
            nom: 'observations',
            libelle: 'Observations',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein),
      ];

  /// `transform` : l'acte porte les références du patient, recopiées depuis l'admission choisie — jamais ressaisies ; la quantité est un nombre.
  static Fiche construire(Map<String, Object?> v, Magasin m) {
    final r = {...v};
    final q = '${v['quantite'] ?? ''}'.trim().replaceAll(',', '.');
    r['quantite'] = q.isEmpty ? null : num.tryParse(q);
    final a = m.collection('admissions').parId(v['admissionId']);
    if (a != null) {
      r['patient'] = a['patient'];
      r['patientCode'] = a['patientCode'];
      r['patientId'] = a['patientId'];
      r['lit'] = a['lit'];
    }
    return r;
  }

  static String _qte(Fiche r) {
    final q = r['quantite'];
    return (q == null || q == 0 || q == '') ? '—' : '${q is num ? hosNum(q) : q}';
  }

  static Widget _etat(Fiche r) => r['etat'] == 'realise'
      ? const BadgeSigh('Réalisé', ton: TonSigh.succes)
      : const BadgeSigh('Planifié', ton: TonSigh.attention);

  static Widget detail(BuildContext ctx, Fiche r) => DescListeSigh([
        ('Date et heure', '${jourFR(r['date'])} à ${r['heure']}'),
        ('Patient', r['patient']),
        ('Dossier', r['patientCode']),
        ('Lit', r['lit']),
        ('Acte', r['acte']),
        ('Produit administré', r['produit']),
        ('Quantité', _qte(r)),
        ('Soignant', r['soignant']),
        ('État', _etat(r)),
        ('Observations', r['observations']),
      ]);

  static PieceA4 etat(ContexteEcran c, Fiche r) => PieceA4(
      titre: 'Feuille de soins',
      sousTitre: '${r['patient']} — lit ${r['lit']}',
      cartouche: [
        ('Patient', '${r['patient']}'),
        ('Dossier', '${r['patientCode']}'),
        ('Date', '${jourFR(r['date'])} à ${r['heure']}'),
        ('Soignant', '${r['soignant']}'),
      ],
      tableaux: [
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
          ColonneEtat(libelle: 'Information', valeur: (x) => x['v']),
        ], lignes: [
          {'k': 'Acte réalisé', 'v': r['acte']},
          {'k': 'Produit administré', 'v': (r['produit'] ?? '') == '' ? '—' : r['produit']},
          {'k': 'Quantité', 'v': _qte(r)},
          {'k': 'État', 'v': r['etat'] == 'realise' ? 'Réalisé' : 'Planifié'},
          {'k': 'Observations', 'v': (r['observations'] ?? '') == '' ? '—' : r['observations']},
        ]),
      ],
      signatures: const [Signature('Le soignant'), Signature('Le Directeur Médical')],
      reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
      utilisateur: c.utilisateur,
      edite: c.aujourdhui);

  /// « Marquer le soin fait » : refus NOMMÉ sans la capacité ; sinon confirmation, puis l'ordonnance reçoit `statutActes`/`actesFaitsLe`/`actesFaitsPar`
  /// et la tâche est close avec l'heure et l'agent (`PR.terminer`).
  Future<void> _soinFait(BuildContext ctx, Fiche tache) async {
    final c = ContexteEcran.of(ctx);
    if (!peutExecuter(c)) {
      ToastsSigh.afficher(ctx, 'Cette validation revient aux infirmiers.',
          type: TypeToast.attention,
          detail: '${libelleProfil(c)} — capacité « exécuter les soins » non accordée.');
      return;
    }
    final ok = await confirmerSigh(ctx,
        titre: 'Soin fait ?',
        message:
            'Les actes de la prescription ${tache['reference']} seront marqués exécutés, avec l’heure d’exécution et votre nom. Un acte non coché reste réputé non fait.',
        libelleOk: 'Soin fait');
    if (!ok || !ctx.mounted) return;
    final maintenant = c.aujourdhui;
    final iso = maintenant.toUtc().toIso8601String();
    final ord = c.magasin.collection('ordonnances');
    if (ord.parId(tache['ordonnanceId']) != null) {
      ord.mettreAJour(tache['ordonnanceId'],
          {'statutActes': 'fait', 'actesFaitsLe': iso, 'actesFaitsPar': c.utilisateur});
    }
    c.magasin.collection('taches').mettreAJour(
        tache['id'], {'statut': 'fait', 'faitLe': iso, 'faitPar': c.utilisateur});
    ToastsSigh.afficher(ctx, 'Soin fait — exécution enregistrée à ${heure(maintenant)}.',
        type: TypeToast.succes, detail: '${tache['detail'] ?? ''}');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('soins');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!peutExecuter(c)) ...[
        NoteSigh(noteRefus(libelleProfil(c)), ton: TonSigh.attention, icone: LucideIcons.shieldAlert),
        const SizedBox(height: 16),
      ],
      FileAttenteSigh(
        type: 'acte',
        titre: 'Actes prescrits à exécuter',
        vide: 'Aucun acte prescrit en attente.',
        icone: LucideIcons.check,
        action: 'Marquer le soin fait',
        surAction: (ctx, tache) => _soinFait(ctx, tache),
      ),
      const SizedBox(height: 16),
      ListenableBuilder(
        listenable: col,
        builder: (context, _) => CrudStock(
          collection: col,
          entite: 'acte de soins',
          entiteP: 'actes de soins',
          prefixeId: 'SOI',
          triInitial: 'date',
          sensInitial: 'desc',
          taillePage: 15,
          largeurTiroir: 768,
          messageModification: 'Modifications enregistrées.',
          colonnes: [
            ColonneTableau(
                cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => jourFR(r['date'])),
            const ColonneTableau(cle: 'heure', libelle: 'Heure', sansCoupure: true),
            ColonneTableau(
                cle: 'lit',
                libelle: 'Lit',
                sansCoupure: true,
                rendu: (_, r) => texteMono('${r['lit'] ?? ''}')),
            const ColonneTableau(cle: 'patient', libelle: 'Patient'),
            const ColonneTableau(cle: 'acte', libelle: 'Acte réalisé'),
            ColonneTableau(
                cle: 'produit',
                libelle: 'Produit administré',
                texte: (r) => (r['produit'] ?? '') == '' ? '—' : '${r['produit']}'),
            const ColonneTableau(cle: 'soignant', libelle: 'Soignant'),
            ColonneTableau(
                cle: 'etat',
                libelle: 'État',
                texte: (r) => r['etat'] == 'realise' ? 'Réalisé' : 'Planifié',
                rendu: (_, r) => _etat(r)),
          ],
          filtres: [
            FiltreTableau(nom: 'acte', libelle: 'Type d’acte', options: [
              for (final a in hosActesSoins) OptionChamp(a)
            ]),
            const FiltreTableau(nom: 'etat', libelle: 'État', options: [
              OptionChamp('realise', 'Réalisé'),
              OptionChamp('planifie', 'Planifié')
            ]),
          ],
          kpis: (ctx, rows) => [
            KpiSigh(
                libelle: 'Actes enregistrés',
                valeur: nombre(rows.length),
                icone: LucideIcons.syringe,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Réalisés',
                valeur: nombre(rows.where((r) => r['etat'] == 'realise').length),
                icone: LucideIcons.circleCheck,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Planifiés',
                valeur: nombre(rows.where((r) => r['etat'] == 'planifie').length),
                icone: LucideIcons.clock,
                ton: TonSigh.attention),
            KpiSigh(
                libelle: 'Patients concernés',
                valeur: nombre({for (final r in rows) '${r['patientCode']}'}.length),
                icone: LucideIcons.bedDouble,
                ton: TonSigh.info),
          ],
          champs: champs,
          valeursInitiales: () => {
            'date': iso(c.aujourdhui),
            'heure': '08:00',
            'etat': 'realise',
            'soignant': c.utilisateur,
            'quantite': '1',
          },
          transformer: (ctx, v) => construire(v, c.magasin),
          detail: detail,
          titreDetail: (r) => '${r['patient'] ?? r['id']}',
          etat: (ctx, r) => afficherApercu(ctx, etat(ContexteEcran.of(ctx), r)),
        ),
      ),
    ]);
  }
}
