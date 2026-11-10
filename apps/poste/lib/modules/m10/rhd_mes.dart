import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/mes_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';
import 'rhc_commun.dart';

/// `m10-mes`, « Mon espace » (lot L7, Direction, 09/11/2026, Planning Q5, Q6, Q8) : l'espace « Mes » de l'agent, ses dix-sept rubriques, en LECTURE. Ouvert à tout agent
/// connecté sous son propre compte (`universel` au manifeste), y compris sur un POSTE PARTAGÉ en secours. Chaque rubrique est lue par `EspaceMesPoste.lire` (domaine
/// `lireMes`, rejoué sur les vecteurs de la maquette) : filtrée sur l'agent de la session, sans droit d'écran sur la collection entière (RG-13) ; un compte NON NOMINATIF
/// reçoit un refus nommé. Rien ne se saisit ici : chaque demande reste à son écran. La fiche de paie est la PIÈCE ÉMISE, jamais recalculée.
///
/// Rien n'est gardé : l'écran relit le magasin à chaque rendu. Seule la rubrique ouverte est retenue ([MesAffichage]) : le verrou la garde (retour à l'écran quitté), la
/// déconnexion l'efface (l'agent suivant du poste partagé arrive sur la première rubrique).
class EcranMes extends StatefulWidget with EcranMaquette {
  const EcranMes({super.key});

  @override
  String get titre => 'Mon espace';
  @override
  String get description =>
      'Mes informations d’agent, en lecture : poste, paie, contrat, planning, présences, congés, missions, primes, événements, assurance, notes de service, agenda.';
  @override
  String get regle =>
      'Cet espace montre vos données et celles d’aucun autre agent (RG-13). Il se lit, il ne se saisit pas : chaque demande reste à son écran. Sur un poste partagé, ouvrez votre propre session ; le compte d’un poste n’a pas d’espace « Mes ». À la déconnexion, l’affichage est vidé ; au verrou, seule la rubrique ouverte est gardée. La fiche de paie est la pièce émise, jamais recalculée.';

  @override
  State<EcranMes> createState() => _EtatMes();
}

/// Les colonnes de chaque rubrique : libellé, champ, format (`date`, `money`), comme `COLONNES_MES` de la maquette.
const Map<String, List<(String, String, String?)>> _colonnes = {
  'fiche_poste': [('Intitulé', 'intitule', null), ('Rattachement', 'rattachement', null), ('Résumé', 'resume', null)],
  'fiche_paie': [('Référence', 'reference', null), ('Période', 'periode', null), ('Brut', 'brut', 'money'), ('Retenues', 'totalRetenues', 'money'), ('Net à payer', 'net', 'money'), ('Diffusée le', 'dateDiffusion', 'date')],
  'contrat': [('Référence', 'reference', null), ('Nature', 'nature', null), ('Poste', 'poste', null), ('Début', 'dateDebut', 'date'), ('Fin', 'dateFin', 'date')],
  'planning': [('Date', 'date', 'date'), ('Vacation', 'type', null), ('Service', 'service', null), ('Régime', 'regime', null)],
  'presences': [('Date', 'date', 'date'), ('État', 'etat', null), ('Arrivée', 'heureArrivee', null), ('Départ', 'heureDepart', null)],
  'conges': [('Référence', 'reference', null), ('Nature', 'nature', null), ('Du', 'dateDebut', 'date'), ('Au', 'dateFin', 'date'), ('Décision', 'statutConge', null)],
  'missions': [('Référence', 'reference', null), ('Objet', 'objet', null), ('Destination', 'destination', null), ('Départ', 'dateDepart', 'date'), ('Retour', 'dateRetour', 'date'), ('Décision', 'statutMission', null)],
  'primes': [('Période', 'periode', null), ('Primes', 'totalPrimes', 'money'), ('Heures supplémentaires', 'heuresSupMontant', 'money')],
  'evenements': [('Référence', 'reference', null), ('Événement', 'libelle', null), ('Date', 'date', 'date')],
  'participations': [('Événement', 'evenementLibelle', null), ('Montant', 'montant', 'money'), ('Mode', 'mode', null), ('Règlement', 'statutPaiement', null)],
  'agenda': [('Date', 'date', 'date'), ('Patient', 'patient', null), ('Nature', 'type', null), ('Motif', 'motif', null)],
  'rendez_vous': [('Date', 'date', 'date'), ('Praticien', 'medecin', null), ('Nature', 'type', null), ('Motif', 'motif', null)],
};

String _cellule(Object? v, String? f) {
  if (v == null || '$v'.isEmpty) return '—';
  if (f == 'date') return rhcDate(v);
  if (f == 'money') return rhcMontant(v);
  return '$v';
}

class _EtatMes extends State<EcranMes> {
  @override
  Widget build(BuildContext context) {
    // Verrouillé, le poste garde l'écran monté sous l'écran verrouillé (caché, sans animation) : celui-ci ne garde RIEN de ce qu'il montrait (le shell coupe les
    // animations au verrou, `TickerMode` le dit). Au déverrouillage il se redessine depuis le magasin, sur la rubrique retenue.
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();
    return _ecoute();
  }

  Widget _ecoute() => RhbEcoute(collections: const [
        'fichesPoste', 'bulletins', 'contrats', 'planning', 'presences', 'conges', 'missions', 'evenements', 'participations', 'patients', 'consultations', 'demandesAnalyses',
        'admissions', 'personnel', 'parametres'
      ], construire: _corps);

  EspaceMesPoste _mes(ContexteEcran c) => EspaceMesPoste(c.magasin, auteur: () => acteur(c).nom, role: c.role, horloge: () => c.aujourdhui);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final e = _mes(c);
    final a = e.agent();
    final peutRegler = c.role == 'admin' || c.role == 'da';
    if (a.refus != null) {
      return rhbEspace([
        if (peutRegler) _carteCopie(context, c, e),
        CarteSigh(titre: 'Espace non disponible', child: VideSigh(a.refus!.motif, icone: LucideIcons.userX, indice: a.refus!.geste)),
      ]);
    }
    final courante = rubriqueMes(MesAffichage.rubrique)?.id ?? rubriquesMes.first.id;
    return rhbEspace([
      if (peutRegler) _carteCopie(context, c, e),
      LayoutBuilder(builder: (ctx, w) {
        final liste = _liste(c, e, courante);
        final contenu = _rubrique(context, c, e, courante);
        if (w.maxWidth < 1024) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [liste, const SizedBox(height: 16), contenu]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: (w.maxWidth - 16) / 4, child: liste),
          const SizedBox(width: 16),
          Expanded(child: contenu),
        ]);
      }),
    ]);
  }

  Widget _liste(ContexteEcran c, EspaceMesPoste e, String courante) => CarteSigh(
      titre: 'Rubriques',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in rubriquesMes)
          InkWell(
              key: Key('mes:rubrique:${r.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                MesAffichage.rubrique = r.id;
                setState(() {});
              },
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: r.id == courante ? JetonsShell.navy50 : null, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(
                        child: Text(r.libelle,
                            style: TextStyle(
                                color: r.id == courante ? JetonsShell.navy900 : JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: r.id == courante ? FontWeight.w600 : FontWeight.w400))),
                    Text(() {
                      final lu = e.lire(r.id);
                      return lu.ok ? nombre(lu.total) : '—';
                    }(), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
                  ]))),
      ]));

  Widget _rubrique(BuildContext context, ContexteEcran c, EspaceMesPoste e, String id) {
    final r = rubriqueMes(id)!;
    final lu = e.lire(id);
    if (!lu.ok) return CarteSigh(titre: r.libelle, child: VideSigh(lu.refus!.motif, icone: LucideIcons.lock, indice: lu.refus!.geste));
    final corps = <Widget>[];
    if (r.lectureSeule) {
      corps.add(const NoteSigh('Lecture seule. La clinique soigne ses agents à 100 % : rien ne se saisit ici, rien ne remonte à la comptabilité.', ton: TonSigh.info, icone: LucideIcons.lock));
    }
    if (r.id == 'fiche_paie') {
      corps.add(NoteSigh('Pièce émise (diffusée) : elle n’est jamais recalculée. Copie chiffrée sur le téléphone : ${e.copiePaieActive() ? 'activée' : 'désactivée'} au poste de la mère.',
          ton: TonSigh.info, icone: LucideIcons.smartphone));
    }
    switch (r.calcule) {
      case 'garde':
      case 'permanence':
        corps.add(KpiGrilleSigh(colonnes: 1, kpis: [
          KpiSigh(libelle: r.calcule == 'garde' ? 'Gardes effectuées' : 'Permanences assurées', valeur: nombre(lu.total), icone: LucideIcons.calendarCheck, ton: TonSigh.navy, indice: 'Planning validé seul'),
        ]));
      case 'presence':
        corps.add(KpiGrilleSigh(colonnes: 3, kpis: [
          KpiSigh(libelle: 'Présences', valeur: nombre(lu.presents ?? 0), icone: LucideIcons.userCheck, ton: TonSigh.succes),
          KpiSigh(libelle: 'Retards', valeur: nombre(lu.retards ?? 0), icone: LucideIcons.clock, ton: TonSigh.attention),
          KpiSigh(libelle: 'Absences', valeur: nombre(lu.absents ?? 0), icone: LucideIcons.userX, ton: TonSigh.danger),
        ]));
      case 'notes':
        corps.add(MiniTableauSigh(colonnes: [
          ColonneMini('Note', (n) => '${n['reference']}'),
          ColonneMini('Objet', (n) => '${n['objet']}'),
          ColonneMini('Version', (n) => 'Version ${n['version']}'),
        ], lignes: <Fiche>[
          for (final n in [admNs131, admNs132]) {'reference': n.reference, 'objet': n.objet, 'version': n.version}
        ]));
      case 'assurance':
        final as = e.assurance()!;
        corps.add(KpiGrilleSigh(colonnes: 2, kpis: [
          KpiSigh(libelle: 'Prestations prises en charge', valeur: nombre(as.lignes.length), icone: LucideIcons.stethoscope, ton: TonSigh.info),
          KpiSigh(
              libelle: 'Valeur de l’avantage',
              valeur: money(as.total),
              icone: LucideIcons.gift,
              ton: TonSigh.succes,
              indice: as.sansMontant > 0 ? '${as.sansMontant} sans montant renseigné (non comptées)' : 'Ni recette, ni créance'),
        ]));
        final tri = [...as.lignes]..sort((x, y) => y.date.compareTo(x.date));
        corps.add(tri.isEmpty
            ? const VideSigh('Aucune prestation.', icone: LucideIcons.shieldCheck)
            : MiniTableauSigh(colonnes: [
                ColonneMini('Date', (l) => rhcDate(l['date'])),
                ColonneMini('Nature', (l) => '${l['nature']}'),
                ColonneMini('Valeur', (l) => l['valeur'] == null ? 'Non renseigné' : rhcMontant(l['valeur'])),
              ], lignes: <Fiche>[for (final l in tri) {'date': l.date, 'nature': l.nature, 'valeur': l.valeur}]));
      default:
        final cols = _colonnes[r.id] ?? const [];
        final fiches = e.fiches(r, lu);
        corps.add(fiches.isEmpty
            ? const VideSigh('Aucune fiche à votre nom.')
            : MiniTableauSigh(colonnes: [for (final k in cols) ColonneMini(k.$1, (f) => _cellule(f[k.$2], k.$3))], lignes: fiches));
    }
    corps.add(Align(
        alignment: Alignment.centerLeft,
        child: BoutonSigh(libelle: 'Ouvrir l’écran de gestion', icone: LucideIcons.arrowRight, variante: VarianteBouton.fantome, taille: TailleBouton.sm, onPressed: () => c.aller(r.ecran))));
    return CarteSigh(titre: r.libelle, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, w) in corps.indexed) ...[if (i > 0) const SizedBox(height: 12), w]]));
  }

  Widget _carteCopie(BuildContext context, ContexteEcran c, EspaceMesPoste e) => CarteSigh(
      titre: 'Copie de la fiche de paie sur le téléphone',
      actions: [
        BoutonSigh(libelle: 'Régler', icone: LucideIcons.settings2, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _regler(context, c, e)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([('Copie chiffrée sur le téléphone de l’agent', e.copiePaieActive() ? 'Oui' : 'Non')]),
        const SizedBox(height: 8),
        const Text('La copie ne porte que la pièce émise de l’agent lui-même, jamais celle d’un autre ni l’ensemble de la paie. Elle se règle à la mère et se synchronise.',
            style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
      ]));

  void _regler(BuildContext ctx, ContexteEcran c, EspaceMesPoste e) {
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'oui', libelle: 'La fiche de paie émise de l’agent est copiée, chiffrée, sur son téléphone', type: TypeChamp.case_, col: ColChamp.plein),
    ], {'oui': e.copiePaieActive()});
    afficherModale<void>(ctx,
        titre: 'Copie de la fiche de paie sur le téléphone',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh('Désactiver retire la copie des téléphones à leur prochaine synchronisation.'),
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
                    final r = e.definirCopiePaie(v['oui'] == true);
                    if (r['ok'] != true) {
                      ToastsSigh.afficher(ctx, '${r['motif']}', type: TypeToast.erreur, detail: '${r['geste']}');
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Réglage enregistré.', type: TypeToast.succes);
                  }),
            ]);
  }
}
