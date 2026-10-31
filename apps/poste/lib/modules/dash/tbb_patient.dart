import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tbb_commun.dart';

/// `dash-patient` — « Espace patient » : la vue synthétique que le personnel d'accueil et de caisse remet au patient (CDCT §5 : le patient n'a aucun accès
/// direct au système). Un patient se choisit dans le répertoire (par ordre de code) ; l'écran compte ses consultations, ses hospitalisations, ce qui lui a
/// été facturé et ce qu'il reste à payer, et retrace son parcours de soins (les huit dernières consultations).
class EcranDashPatient extends StatefulWidget with EcranMaquette {
  const EcranDashPatient({super.key});

  @override
  String get titre => 'Espace patient';

  @override
  String get description =>
      'Vue synthétique remise au patient : parcours de soins, prescriptions, analyses et situation financière.';

  @override
  String get regle =>
      'Le patient ne dispose d’aucun accès direct au système (CDCT §5) : cet écran est destiné au personnel d’accueil et de caisse pour l’informer et lui remettre ses documents.';

  @override
  State<EcranDashPatient> createState() => _EtatDashPatient();
}

class _EtatDashPatient extends State<EcranDashPatient> {
  ControleurFormulaire? _ctl;
  List<Fiche> _patients = const [];

  List<Fiche> _tries(List<Fiche> actifs) => trierPar(actifs, (p) => p['code']);

  void _initialiser(List<Fiche> tries) {
    final memo = _ctl == null ? null : '${_ctl!['patient']}';
    _patients = tries;
    _ctl?.removeListener(_changement);
    _ctl = ControleurFormulaire([
      ChampDef(
          nom: 'patient',
          libelle: 'Patient',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [for (final p in tries) OptionChamp('${p['id']}', '${p['nom']} ${p['prenom']}')]),
    ], {if (memo != null && tries.any((p) => '${p['id']}' == memo)) 'patient': memo})
      ..addListener(_changement);
  }

  void _changement() => setState(() {});

  @override
  void dispose() {
    _ctl?.removeListener(_changement);
    _ctl?.dispose();
    super.dispose();
  }

  Widget _vue(BuildContext context, ContexteEcran c, Fiche courant) {
    List<Fiche> sien(String col) => [
          for (final x in c.magasin.collection(col).actives)
            if (x['patientId'] == courant['id']) x
        ];
    final cons = sien('consultations');
    final fac = sien('factures');
    final adm = sien('admissions');
    final du = tbbSomme(fac, 'reliquat');
    final recents = trierPar(cons, (x) => x['date'], descendant: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        for (final k in tbbKpisPatient(
            consultations: cons.length, hospitalisations: adm.length, facture: tbbSomme(fac, 'montantTTC'), reste: du))
          kpiDe(k)
      ]),
      const SizedBox(height: 16),
      CarteSigh(
        titre: 'Parcours de soins',
        actions: [
          BoutonSigh(
              libelle: 'Remettre la fiche',
              icone: LucideIcons.printer,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () => _remettre(context, c, courant, cons, du))
        ],
        child: recents.isEmpty
            ? const VideSigh('Aucun événement enregistré.', icone: LucideIcons.history)
            : ChronologieDash([
                for (final x in recents.take(8))
                  (
                    titre: '${x['motif']} — ${x['diagnostic']}',
                    detail: '${x['type']} avec ${x['medecin']}',
                    date: _date(x['date']),
                    ton: x['statut'] == 'terminee' ? TonSigh.succes : TonSigh.info,
                  )
              ]),
      ),
    ]);
  }

  static String _date(Object? v) {
    final d = tbbDate(v);
    return d == null ? '' : dateFR(d);
  }

  /// `P.etat` : la situation du patient, signée du Secrétaire Médical. Les vingt dernières consultations, la plus récente d'abord.
  void _remettre(BuildContext ctx, ContexteEcran c, Fiche p, List<Fiche> cons, num du) {
    final l = trierPar(cons, (x) => x['date'], descendant: true).take(20).toList();
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Situation du patient',
          sousTitre: 'Dossier ${p['code']}',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Patient', '${p['nom']} ${p['prenom']}'),
            ('Dossier', '${p['code']}'),
            ('Consultations', nombre(cons.length)),
            ('Reste à payer', money(du)),
          ],
          tableaux: [
            TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Date', valeur: (x) => _date(x['date'])),
              ColonneEtat(libelle: 'Motif', valeur: (x) => x['motif']),
              ColonneEtat(libelle: 'Diagnostic', valeur: (x) => x['diagnostic']),
              ColonneEtat(libelle: 'Praticien', valeur: (x) => x['medecin']),
            ], lignes: l),
          ],
          signatures: const [Signature('Le Secrétaire Médical')],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final n in const ['patients', 'consultations', 'factures', 'admissions']) c.magasin.collection(n)
      ]),
      builder: (context, _) {
        final tries = _tries(c.magasin.collection('patients').actives);
        if (_ctl == null || tries.length != _patients.length) _initialiser(tries);
        final id = '${_ctl!['patient']}';
        final courant = tries.where((p) => '${p['id']}' == id).firstOrNull ?? tries.firstOrNull;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              titre: 'Accès rapides',
              child: RaccourcisSigh(aller: c.aller, items: [
                raccourci('m1-patients', 'users', 'Répertoire des patients', 'Rechercher ou créer un dossier'),
                raccourci('m2-rendezvous', 'calendar-check', 'Rendez-vous', 'Programmer une consultation'),
                raccourci('m8-facturation', 'file-plus-2', 'Nouvelle facture', 'Établir la note du patient'),
                raccourci('m1-documents', 'paperclip', 'Documents du patient', 'Pièces numérisées à remettre'),
              ])),
          const SizedBox(height: 16),
          CarteSigh(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 448), child: FormulaireSigh(controleur: _ctl!)))),
          const SizedBox(height: 16),
          if (courant == null)
            const CarteSigh(child: VideSigh('Aucun patient.', icone: LucideIcons.users))
          else
            _vue(context, c, courant),
        ]);
      },
    );
  }
}

/// `U.timeline` : une pastille de ton, le titre, le détail et la date.
class ChronologieDash extends StatelessWidget {
  const ChronologieDash(this.etapes, {super.key});
  final List<({String titre, String detail, String date, TonSigh ton})> etapes;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in etapes)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  margin: const EdgeInsets.only(top: 4, right: 12),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: e.ton.icone600, shape: BoxShape.circle)),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.titre, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
                Text(e.detail, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 16 / 12)),
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e.date, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 16 / 12))),
              ])),
            ]),
          ),
      ]);
}
