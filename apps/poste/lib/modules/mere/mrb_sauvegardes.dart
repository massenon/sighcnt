import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mrb_commun.dart';
import 'mrb_source.dart';

/// `mere-sauvegardes` : sauvegardes chiffrées de la mère, restauration, remplacement de la mère (M-09).
///
/// Ce que le service expose : `POST /admin/sauvegarder` (sauvegarde chiffrée avec la clé de clinique, `.enc`), le contrôle « Sauvegarde » de la supervision
/// (date de la dernière) et le champ `restauration` de l'état. Ce qu'il n'expose PAS : le catalogue des fichiers, leur taille, la règle de conservation,
/// la vérification de restauration. Ces valeurs s'affichent « non disponible » tant que la source ne les fournit pas (écarts E1340 à E1344).
class _Sauv {
  const _Sauv(this.sante, this.etat, this.catalogue);
  final MrbSante sante;
  final MrbEtat etat;
  final List<MrbSauvegarde>? catalogue;
}

class EcranSauvegardesMere extends StatefulWidget with EcranMaquette {
  const EcranSauvegardesMere({super.key});
  @override
  String get titre => 'Sauvegardes et restauration';
  @override
  String get description =>
      'Sauvegarde chiffrée quotidienne, vérification de restauration, restauration depuis le relais, remplacement de la mère.';
  @override
  String get regle =>
      'Toute sauvegarde est chiffrée avec la clé de clinique avant d’être écrite : le fichier en clair n’existe que le temps de l’écriture. '
      'Sans la clé, une sauvegarde est irrécupérable : la copie papier sous scellé (écran « Clé de clinique ») est la seule assurance.';

  @override
  State<EcranSauvegardesMere> createState() => _EtatSauvegardes();
}

class _EtatSauvegardes extends MrbEtatEcran<EcranSauvegardesMere, _Sauv> {
  /// Les sauvegardes déclenchées depuis CETTE console : le seul historique que la source garantit quand elle ne publie pas de catalogue.
  final List<MrbSauvegarde> _seances = [];
  DateTime? _verifieeLe;

  @override
  Future<_Sauv> charger(MrbSource s) async =>
      _Sauv(await s.supervision(), await s.etat(), await s.sauvegardes());

  Future<void> _sauvegarder(BuildContext contexte, ContexteEcran c) async {
    final s = source;
    if (s == null) return;
    try {
      final chemin = await s.sauvegarderMaintenant();
      _seances.insert(0, MrbSauvegarde(date: c.aujourdhui, nature: 'Manuelle'));
      if (contexte.mounted) ToastsSigh.afficher(contexte, 'Sauvegarde chiffrée effectuée : $chemin', type: TypeToast.succes);
    } catch (e) {
      if (contexte.mounted) ToastsSigh.afficher(contexte, 'Sauvegarde refusée : ${mrbCause(e)}', type: TypeToast.erreur);
    }
    await actualiser();
  }

  Future<void> _verifier(BuildContext contexte, ContexteEcran c) async {
    final s = source;
    if (s == null) return;
    final ok = await geste(contexte, s.verifierDerniereSauvegarde, ok: 'Vérification de restauration réussie.');
    if (ok) setState(() => _verifieeLe = c.aujourdhui);
  }

  Widget _kpis() {
    final d = donnees;
    final ctrl = d?.sante.controle('Sauvegarde');
    String? derniere;
    String? indiceDerniere = ctrl?.detail;
    var ton = TonSigh.navy;
    if (ctrl != null) {
      final v = ctrl.valeur;
      if (v is num) {
        derniere = mrbDateHeureMs(v.toInt());
      } else {
        derniere = 'Aucune';
      }
      ton = mrbTon(ctrl.etat);
    }
    return mrbGrilleKpi([
      mrbKpi('Dernière sauvegarde', derniere, indice: indiceDerniere, ton: ton, icone: LucideIcons.databaseBackup),
      mrbKpi('Conservation', null,
          indice: 'Règle non lue du service (valeur par défaut du moteur : 7 sauvegardes chiffrées).', icone: LucideIcons.archive),
      mrbKpi('Dernière vérification', _verifieeLe == null ? null : mrbDateHeure(_verifieeLe!),
          indice: _verifieeLe == null ? 'Le service de la mère ne tient aucune vérification de restauration.' : 'Test à blanc lancé depuis cette console.',
          icone: LucideIcons.shieldCheck),
    ]);
  }

  Widget _ongletSauvegardes(BuildContext contexte, ContexteEcran c) {
    final catalogue = donnees?.catalogue;
    final lignes = <MrbSauvegarde>[...?catalogue, if (catalogue == null) ..._seances];
    final rows = <Ligne>[
      for (final s in lignes)
        {
          'date': s.date.millisecondsSinceEpoch,
          'taille': s.tailleOctets == null ? mrbNonDisponible : mrbTaille(s.tailleOctets!),
          'nature': s.nature,
          'verification': s.verification ?? (_verifieeLe == null ? 'Non vérifiée' : 'Dernière vérifiée le ${mrbDateHeure(_verifieeLe!)}'),
        }
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (c.peutEcrire)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            BoutonSigh(libelle: 'Sauvegarder maintenant', icone: LucideIcons.save, onPressed: () => _sauvegarder(contexte, c)),
            BoutonSigh(
                libelle: 'Vérifier la dernière',
                icone: LucideIcons.shieldCheck,
                variante: VarianteBouton.secondaire,
                onPressed: () => _verifier(contexte, c)),
          ]),
        ),
      CarteSigh(
        sansRemplissage: true,
        child: MrbTableau(
          recherche: false,
          messageVide: catalogue == null
              ? 'Catalogue des sauvegardes non disponible : le service de la mère ne liste pas ses fichiers.'
              : 'Aucune sauvegarde enregistrée.',
          indiceVide: catalogue == null ? 'Seules les sauvegardes lancées depuis cette console apparaissent ci-dessous.' : null,
          colonnes: [
            ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (l) => mrbDateHeureMs(l['date']! as int)),
            const ColonneTableau(cle: 'taille', libelle: 'Taille'),
            const ColonneTableau(cle: 'nature', libelle: 'Nature'),
            const ColonneTableau(cle: 'verification', libelle: 'Vérification'),
          ],
          lignes: rows,
        ),
      ),
    ]);
  }

  Widget _ongletRestaurer() {
    final r = donnees?.etat.restauration;
    final (etat, ton) = switch (r) {
      null => ('Aucune restauration n’a été lancée sur cette mère.', TonSigh.neutre),
      'en_cours' => ('Restauration en cours : la réplication vers le relais est suspendue jusqu’à sa fin.', TonSigh.attention),
      'terminee' => ('Restauration terminée : l’époque a été incrémentée, les postes se resynchronisent.', TonSigh.succes),
      final e => (e.startsWith('echec') ? 'Restauration en échec : ${e.substring(e.indexOf(':') + 1).trim()}' : 'Restauration : $e', TonSigh.danger),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('État de la restauration', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        BadgeSigh(donnees == null ? mrbNonDisponible : switch (r) { null => 'Aucune', 'en_cours' => 'En cours', 'terminee' => 'Terminée', _ => 'En échec' }, ton: donnees == null ? TonSigh.neutre : ton),
      ]),
      const SizedBox(height: 6),
      Text(donnees == null ? 'État non lu : le service de la mère ne répond pas.' : etat),
      const SizedBox(height: 12),
      const NoteSigh(
          'La restauration depuis le relais ne se lance pas depuis cette console. Le moteur ne la déclenche qu’au démarrage d’une mère dont le journal est VIDE, '
          'avec la clé de clinique : tout est déchiffré et vérifié avant la moindre écriture. Procédure (spec §10) :'),
      const SizedBox(height: 8),
      for (final (i, e) in const [
        'Installer le logiciel sur la machine de remplacement, en mode mère.',
        'Saisir le code émis par le panneau en ligne.',
        'Saisir la clé de clinique (copie papier sous scellé).',
        'Tirer l’instantané et les enveloppes depuis le relais, déchiffrer, rejouer dans la base.',
        'L’époque est incrémentée (époque + 1).',
        'Les postes se resynchronisent.',
      ].indexed)
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${i + 1}. $e')),
      const SizedBox(height: 8),
      const Text('Perte maximale : ce qui n’a pas atteint le relais. Le retard de réplication est visible à tout moment à l’écran « Relais en ligne ».'),
    ]);
  }

  Widget _ongletRemplacer() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh(
            'Remplacer la mère se fait par RESTAURATION sur la nouvelle machine, jamais par copie de fichiers. Une seule mère peut être active par clinique : '
            'le relais refuse une seconde activation en nommant la mère déjà déclarée, sauf demande explicite de remplacement.'),
        const SizedBox(height: 12),
        for (final (i, e) in const [
          'Sur l’ancienne mère (si elle répond encore) : sauvegarder maintenant, puis désactiver le mode mère (le service s’arrête, les données sont conservées).',
          'Sur la nouvelle machine : activer le mode mère avec le secret de la mère et la clé de clinique, en demandant le remplacement au relais.',
          'Restaurer depuis le relais (onglet « Restaurer »).',
          'Contrôler à la supervision que les postes se resynchronisent, puis réappairer ceux qui l’exigent.',
        ].indexed)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${i + 1}. $e')),
        const SizedBox(height: 8),
        const Text('Cet écran ne déclenche pas le remplacement : l’activation relève de la page « Ce poste » (réglages du poste) et de la restauration ci-dessus.'),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      mrbBandeauPanne(panne),
      _kpis(),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(id: 'sauvegardes', libelle: 'Sauvegardes', construire: (ctx) => _ongletSauvegardes(ctx, c)),
        OngletDef(id: 'restaurer', libelle: 'Restaurer', construire: (_) => _ongletRestaurer()),
        OngletDef(id: 'remplacer', libelle: 'Remplacer la mère', construire: (_) => _ongletRemplacer()),
      ]),
    ]);
  }
}
