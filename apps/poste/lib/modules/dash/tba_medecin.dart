import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// `dash-medecin` — « Tableau de bord — Médecin » : le médecin a prescrit et il attend ; la validation biologique est ce qui lui rend le résultat.
/// La file du praticien est faite de DEUX listes jamais fondues : ceux qui l'attendent nommément, et le vivier commun.
class EcranDashMedecin extends StatelessWidget with EcranMaquette {
  const EcranDashMedecin({super.key});

  @override
  String get titre => 'Tableau de bord — Médecin';

  @override
  String get description =>
      'Consultations du jour, patients hospitalisés sous responsabilité et prescriptions récentes.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['demandesAnalyses', 'fileAttente', 'consultations', 'admissions', 'taches']),
      builder: (context, _) {
        final d = tbaMedecin(
          demandesAnalyses: tbaActives(c, 'demandesAnalyses'),
          fileAttente: tbaActives(c, 'fileAttente'),
          consultations: tbaActives(c, 'consultations'),
          admissions: tbaActives(c, 'admissions'),
          // Écart E923 : le poste ne porte pas le nom de l'agent (la maquette lit `session.nomComplet`) ; c'est l'intitulé du profil.
          nom: c.utilisateur,
          auj: c.aujourdhui,
        );
        return TbaDash(
          alerte: FileAttenteSigh(
              type: 'acte',
              titre: 'Actes prescrits en attente d’exécution',
              vide: 'Aucun acte prescrit en attente.',
              action: 'Ouvrir les soins',
              icone: LucideIcons.arrowRight,
              surAction: (_, __) => c.aller('m3-soins')),
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m2-consultation-fiche', 'clipboard-plus', 'Nouvelle consultation', 'Diagnostic et prescription'),
              ('m5-demandes', 'flask-conical', 'Prescrire une analyse', 'Demande au laboratoire'),
              ('m3-admissions', 'bed-double', 'Décider une hospitalisation', 'Admission et affectation de lit'),
              ('m2-domicile', 'house-plus', 'Consultation à domicile', 'Planification et facturation'),
            ]),
            _MaFile(d.file, c),
            tbaCarte('Ce que vous faites ici — vos parcours', const ParcoursSigh(_parcours)),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte(
                'File d’attente et consultations récentes',
                tbaMiniTableau([
                  ColonneMini('Date', (x) => tbaDateHeure(x['date'])),
                  ColonneMini('Dossier', (x) => '${x['patientCode'] ?? ''}', rendu: (x) => tbaMono(x['patientCode'])),
                  ColonneMini('Patient', (x) => '${x['patient'] ?? ''}'),
                  ColonneMini('Motif', (x) => '${x['motif'] ?? ''}'),
                  ColonneMini('Statut', (x) => '', rendu: (x) => statutBadge(x['statut'])),
                ], d.recentes),
                actions: [tbaLien(c, 'm2-consultations', 'Toutes les consultations', 'arrow-right')],
                sansRemplissage: true),
            tbaDeuxCartes(
              CarteSigh(titre: 'Motifs de consultation les plus fréquents', child: ClassementTba([for (final m in d.motifs) (m.$1, m.$2)])),
              CarteSigh(
                  titre: 'Diagnostics posés',
                  child: GraphiqueBarres(
                      horizontal: true,
                      hauteur: 280,
                      etiquettes: [for (final x in d.diagnostics) x.$1],
                      series: [SerieGraphique('Cas', [for (final x in d.diagnostics) x.$2])])),
            ),
          ],
        );
      },
    );
  }
}

/// « Vos patients en attente » : ceux qui vous attendent NOMMÉMENT, le vivier commun, et — à part — la charge des confrères.
class _MaFile extends StatelessWidget {
  const _MaFile(this.f, this.c);
  final TbaFilePraticien f;
  final ContexteEcran c;

  @override
  Widget build(BuildContext context) {
    final moi = c.utilisateur;
    return tbaCarte(
        'Vos patients en attente',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh(
              f.miens.isNotEmpty
                  ? '${f.miens.length} patient(s) vous attendent nommément, et ${f.communs.length} patient(s) sont en file commune — le prochain praticien libre les prend.'
                  : 'Aucun patient ne vous est adressé nommément. ${f.communs.length} patient(s) attendent en file commune : le prochain praticien libre les reçoit.',
              ton: f.miens.isNotEmpty ? TonSigh.attention : TonSigh.info,
              icone: LucideIcons.listOrdered),
          const SizedBox(height: 12),
          if (f.miens.isNotEmpty) ...[
            tbaCarte('Adressés à ${moi.isEmpty ? 'vous' : moi}',
                _TableFile(f.miens, c, vide: 'Aucun patient ne vous est adressé.', export: 'ma-file'),
                sansRemplissage: true),
            const SizedBox(height: 12),
          ],
          tbaCarte('File commune de consultation', _TableFile(f.communs, c, vide: 'Aucun patient en file commune.', export: 'file-commune'),
              sansRemplissage: true),
          if (f.autres.isNotEmpty) ...[
            const SizedBox(height: 12),
            NoteSigh(
                '${f.autres.length} patient(s) attendent un autre praticien. Ils figurent au poste de consultation, pas dans votre liste.',
                ton: TonSigh.neutre,
                icone: LucideIcons.users),
          ],
          const SizedBox(height: 4),
          Align(
              alignment: Alignment.centerLeft,
              child: BoutonSigh(
                  libelle: 'Ouvrir la file d’attente',
                  icone: LucideIcons.listOrdered,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => c.aller('m2-file-attente'))),
        ]));
  }
}

/// Le tableau d'une file, ordonné comme le couloir : priorité, puis heure.
class _TableFile extends StatelessWidget {
  const _TableFile(this.tickets, this.c, {required this.vide, required this.export});
  final List<Fiche> tickets;
  final ContexteEcran c;
  final String vide;
  final String export;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) return VideSigh(vide, icone: LucideIcons.userCheck);
    // « Recevoir » mène à la fiche de consultation : un profil à qui elle est fermée ne voit pas la commande (elle serait refusée).
    final peutRecevoir = c.ouvre?.call('m2-consultation-fiche') ?? true;
    return TableauSigh(
      lignes: tbaOrdreCouloir(tickets),
      taillePage: 8,
      recherche: false,
      nomExport: export,
      colonnes: [
        ColonneTableau(cle: 'numero', libelle: 'N°', sansCoupure: true, rendu: (_, r) => tbaMono(r['numero'])),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Patient',
            texte: (r) => '${r['patient'] ?? ''}',
            rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['patient'] ?? ''}',
                      style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
                  Text('${r['patientCode'] ?? ''}', style: const TextStyle(color: JetonsShell.slate400, fontSize: 10)),
                ])),
        ColonneTableau(
            cle: 'priorite',
            libelle: 'Priorité',
            texte: (r) => tbaPriorite(r['priorite']).libelle,
            rendu: (_, r) {
              final p = tbaPriorite(r['priorite']);
              return BadgeSigh(p.libelle, ton: tbaTon(p.ton));
            }),
        const ColonneTableau(cle: 'motif', libelle: 'Motif'),
        ColonneTableau(
            cle: 'arriveeLe',
            libelle: 'Arrivé à',
            sansCoupure: true,
            texte: (r) => _hhmm(r['arriveeLe']),
            rendu: (_, r) => Text(_hhmm(r['arriveeLe']), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14))),
      ],
      actionsLigne: peutRecevoir
          ? (ctx, r) => [
                BoutonSigh(
                    libelle: 'Recevoir',
                    icone: LucideIcons.stethoscope,
                    taille: TailleBouton.sm,
                    onPressed: () => c.aller('m2-consultation-fiche'))
              ]
          : null,
    );
  }
}

String _hhmm(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 16 ? s.substring(11, 16) : '—';
}

const _parcours = [
  ParcoursTba('Recevoir un patient', 'stethoscope', 'Ouvrir la consultation', 'Le patient est appelé, la consultation commence.', [
    EtapeTba('Enregistrer le dossier de consultation',
        ecran: 'm2-dossiers-consultation',
        detail: 'Anamnèse, trois catégories d’antécédents, examen IPPOA par appareil. Les constantes de l’accueil y sont lues, pas ressaisies.'),
    EtapeTba('Fiche de consultation : diagnostic et prescription',
        ecran: 'm2-consultation-fiche',
        detail: 'Code de pathologie ET diagnostic rédigé ; médicaments, analyses et imagerie — ici seulement.'),
    EtapeTba('Le patient règle', poste: 'Caisse'),
    EtapeTba('Le laboratoire prélève', poste: 'Laboratoire'),
  ]),
  ParcoursTba('Lire les résultats', 'flask-conical', 'Voir les résultats', 'Vos prescriptions d’analyses sont revenues.', [
    EtapeTba('Consulter les résultats rendus', ecran: 'm5-resultats', detail: 'Seuls les résultats VALIDÉS BIOLOGIQUEMENT vous sont visibles.'),
    EtapeTba('Réajuster le traitement', ecran: 'm2-ordonnances'),
    EtapeTba('Programmer le contrôle', ecran: 'm2-rendezvous'),
  ]),
  ParcoursTba('Hospitaliser', 'bed-double', 'Admettre', 'L’état du patient justifie un séjour.', [
    EtapeTba('Créer l’admission et attribuer un lit', ecran: 'm3-admissions', detail: 'Un lit ne porte qu’une admission active à la fois.'),
    EtapeTba('Prescrire le traitement d’entrée', ecran: 'm2-prescriptions'),
    EtapeTba('Suivre les constantes', ecran: 'm3-surveillance'),
    EtapeTba('Rédiger le rapport médical à la sortie', ecran: 'm3-rapport'),
    EtapeTba('Vérifier le solde avant sortie', ecran: 'm8-reliquats', detail: 'RG-06 — pas de sortie sans solde apuré.'),
  ]),
  ParcoursTba('Délivrer un certificat', 'stamp', 'Délivrer', 'Le patient réclame une pièce certifiante.', [
    EtapeTba('Établir la pièce', ecran: 'm1-pieces', detail: 'Quatorze types. Le prénuptial se remplit depuis les résultats validés.'),
    EtapeTba('Encaisser', poste: 'Caisse'),
  ]),
];
