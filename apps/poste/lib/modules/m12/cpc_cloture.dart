import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart' show Signature;
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpc_commun.dart';

/// `m12-cloture` — « Exercices & clôtures » : sélecteur d'exercice, pré-clôture, clôture EN DEUX GESTES, à-nouveaux et lettrage des tiers.
///
/// TROIS ÉTATS (arbitrage du 05/11/2026) : ouvert, en clôture (les modules n'écrivent plus), clôturé (lecture seule). QUATRE TRANSITIONS : le comptable
/// DÉMARRE la clôture, peut REPRENDRE la saisie tant que rien n'est clôturé, la Direction ou la DAF CLÔTURE DÉFINITIVEMENT (une autre personne), et seul le
/// comptable ROUVRE (motif de dix caractères), par contre-passation. La clôture pose la pièce CL puis la pièce AN dans un seul tenant : un échec défait tout.
/// Le moteur est dans `cpc_exercice.dart` et `cpc_archive.dart` ; la garde de lecture seule est posée sur la collection `ecritures` du magasin.
///
/// Écarts : E800 (l'acteur d'un geste est le libellé du rôle de la session, le poste ne porte pas d'identité nominative) ; E801 (le sélecteur
/// d'exercice de la coque n'est pas porté : l'exercice choisi est celui de l'horloge, E717) ; E802 (hors du poste : l'archive de clôture dans la GED et
/// l'export CSV de l'exercice clos).
class EcranCloture extends StatefulWidget with EcranMaquette {
  const EcranCloture({super.key});

  @override
  String get titre => 'Exercices & clôtures';

  @override
  String get description =>
      'Sélecteur d’exercice, pré-clôture, clôture en deux gestes, à-nouveaux et lettrage des tiers.';

  @override
  String get regle =>
      'Trois états : ouvert, en clôture (les modules n’écrivent plus), clôturé (lecture seule). Le comptable démarre la clôture, la Direction ou la DAF clôture définitivement (une autre personne), et seul le comptable rouvre, avec un motif, par contre-passation. La caisse continue d’encaisser : une pièce s’enregistre toujours dans l’exercice de sa date.';

  @override
  State<EcranCloture> createState() => _EtatCloture();
}

String _tronque(String s, int n) => s.length > n ? s.substring(0, n) : s;

class _EtatCloture extends State<EcranCloture> {
  bool _amorce = false;
  late final ControleurFormulaire _compte;
  bool _compteInit = false;
  final Set<Object?> _coches = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    final c = ContexteEcran.of(context);
    amorcerExercices(c.magasin, c.aujourdhui);
  }

  List<Fiche> _ecritures(ContexteEcran c) => c.magasin.collection('ecritures').actives;

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // TRANSITIONS 1 ET 2 — démarrer la clôture, reprendre la saisie
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _preCloture(BuildContext ctx, ContexteEcran c, Fiche x, bool peutDemarrer) {
    final annee = x['annee'] as int;
    final pre = cpcPreCloture(_ecritures(c), annee, exercices: c.magasin.collection('exercices').toutes);
    afficherModale<void>(ctx,
        titre: 'Pré-clôture — exercice $annee',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Résultat provisoire de l’exercice $annee : '),
            TextSpan(text: money(pre.resultat), style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' sur ${nombre(pre.nbEcritures)} ligne(s) validée(s).'),
          ]), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Contrôle', (l) => '${l['libelle']}'),
            ColonneMini('Nature', (l) => l['bloquant'] == true ? 'Bloquant' : 'Signalé'),
            ColonneMini('État', (l) => l['ok'] == true ? 'Conforme' : (l['bloquant'] == true ? 'ÉCHEC' : 'À voir')),
            ColonneMini('Détail / où corriger', (l) => l['ok'] == true ? '—' : '${l['detail']} → ${libellesEcransM12[l['ecran']] ?? l['ecran']}'),
          ], lignes: [
            for (final k in pre.controles)
              {'libelle': k.libelle, 'bloquant': k.bloquant, 'ok': k.ok, 'detail': k.detail, 'ecran': k.ecran}
          ]),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer),
              if (peutDemarrer && cpcEtatExercice(c.magasin.collection('exercices').toutes, annee) == 'ouvert')
                BoutonSigh(
                    libelle: 'Démarrer la clôture',
                    icone: LucideIcons.lock,
                    onPressed: () {
                      fermer();
                      _demarrer(ctx, c, x);
                    }),
            ]);
  }

  Future<void> _demarrer(BuildContext ctx, ContexteEcran c, Fiche x) async {
    final annee = x['annee'] as int;
    final ok = await confirmerSigh(ctx,
        titre: 'Démarrer la clôture de l’exercice $annee ?',
        message:
            'Dès maintenant, les modules n’écrivent plus dans $annee : seul le comptable y passe ses écritures d’inventaire. Rien n’est figé : la saisie peut reprendre tant que la Direction n’a pas clôturé définitivement.',
        libelleOk: 'Démarrer la clôture');
    if (!ok || !ctx.mounted) return;
    final r = cpcDemarrerCloture(c.magasin.collection('exercices').toutes, _ecritures(c), annee,
        acteur: acteurDe(c), acteurId: acteurIdDe(c), role: c.role, maintenant: c.aujourdhui);
    if (!r.ok) {
      ToastsSigh.afficher(ctx, 'Démarrage refusé.', type: TypeToast.erreur, detail: r.motif);
      return;
    }
    c.magasin.collection('exercices').mettreAJour(x['id'], r.patch!);
    c.magasin.journaliser('Démarrage de la clôture', 'M12', 'Exercice', '$annee', {'etat': 'ouvert'}, {'etat': 'en_cloture', 'resultat': r.pre!.resultat});
    notifier(c,
        type: 'cloture',
        poste: 'direction',
        libelle: 'Clôture $annee à valider',
        detail: 'Le comptable a démarré la clôture de l’exercice $annee : les modules n’y écrivent plus.',
        priorite: 'haute',
        reference: '$annee');
    ToastsSigh.afficher(ctx, 'Clôture $annee démarrée.', type: TypeToast.succes, detail: 'Les modules n’écrivent plus dans cet exercice.');
  }

  Future<void> _reprendre(BuildContext ctx, ContexteEcran c, Fiche x) async {
    final annee = x['annee'] as int;
    final ok = await confirmerSigh(ctx,
        titre: 'Reprendre la saisie de l’exercice $annee ?',
        message: 'Les modules écrivent de nouveau dans $annee. Possible tant que rien n’est clôturé.',
        libelleOk: 'Reprendre la saisie');
    if (!ok || !ctx.mounted) return;
    final r = cpcReprendreSaisie(c.magasin.collection('exercices').toutes, annee, acteur: acteurDe(c), role: c.role, maintenant: c.aujourdhui);
    if (!r.ok) {
      ToastsSigh.afficher(ctx, 'Reprise refusée.', type: TypeToast.erreur, detail: r.motif);
      return;
    }
    c.magasin.collection('exercices').mettreAJour(x['id'], r.patch!);
    c.magasin.journaliser('Reprise de la saisie', 'M12', 'Exercice', '$annee', {'etat': 'en_cloture'}, {'etat': 'ouvert'});
    ToastsSigh.afficher(ctx, 'Saisie de $annee reprise.', type: TypeToast.succes);
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // TRANSITION 3 — clôturer définitivement : CL, AN, verrou, archive, d'un seul tenant
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _cloturer(BuildContext ctx, ContexteEcran c, Fiche x) {
    final annee = x['annee'] as int;
    final motif = ControleurFormulaire(const [
      ChampDef(nom: 'motif', libelle: 'Motif de la clôture (obligatoire)', type: TypeChamp.textarea, col: ColChamp.plein, lignes: 3)
    ]);
    afficherModale<void>(ctx,
        titre: 'Clôturer définitivement l’exercice $annee',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Clôture démarrée par '),
            TextSpan(text: '${x['demandePar'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
                text:
                    '. Les contrôles sont rejoués, puis, d’un seul tenant : pièce de clôture (journal CL) qui solde les classes 6, 7 et 8 centre par centre, pièce d’à-nouveaux (journal AN) de ${annee + 1}, verrou, archive. Seul le comptable peut ensuite rouvrir l’exercice.'),
          ]), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: motif),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Clôturer définitivement',
                  icone: LucideIcons.lock,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    final ecr = c.magasin.collection('ecritures');
                    final r = cpcValiderCloture(c.magasin.collection('exercices').toutes, _ecritures(c), annee,
                        motif: '${motif['motif'] ?? ''}',
                        acteur: acteurDe(c),
                        acteurId: acteurIdDe(c),
                        role: c.role,
                        maintenant: c.aujourdhui,
                        toutesEcritures: ecr.toutes,
                        comptesResultat: c.magasin.collection('comptesResultat').actives);
                    if (!r.ok) {
                      ToastsSigh.afficher(ctx, 'Clôture refusée.', type: TypeToast.erreur, detail: r.motif);
                      return;
                    }
                    // ATOMICITÉ : une insertion refusée par le journal défait tout ce qui a été posé, l'exercice reste en clôture.
                    final annulations = <VoidCallback>[];
                    try {
                      for (final l in [...r.lignesCL, ...r.lignesAN]) {
                        annulations.add(ecr.inserer(l, prefixe: 'ECR').annuler);
                      }
                    } on EcritureRefusee catch (e) {
                      for (final u in annulations.reversed) {
                        u();
                      }
                      ToastsSigh.afficher(ctx, 'Clôture refusée.', type: TypeToast.erreur, detail: '${e.motif} L’exercice reste en clôture, rien n’a été écrit.');
                      return;
                    }
                    final apres = {...x, ...r.patch!};
                    c.magasin.collection('exercices').mettreAJour(x['id'], r.patch!);
                    if (r.exerciceSuivant != null) c.magasin.collection('exercices').inserer(r.exerciceSuivant!);
                    c.magasin.collection('clotures').inserer(r.cloture!, prefixe: 'CLO');
                    final version = cpcVersionCloture(c.magasin.collection('clotures').toutes, annee);
                    final reference = cpcReferenceArchive(annee, version);
                    final archives = c.magasin.collection('archivesExercice');
                    if (!archives.toutes.any((a) => a['reference'] == reference)) {
                      final fichiers = cpcFichiersArchive(annee, apres, ecr.actives);
                      archives.inserer({
                        'reference': reference,
                        'annee': annee,
                        'version': version,
                        'creeLe': c.aujourdhui.toUtc().toIso8601String(),
                        'par': acteurDe(c),
                        'clNumero': r.clNumero,
                        'anNumero': r.anNumero,
                        'fichiers': fichiers,
                        'manifesteEmpreinte': fichiers.last['empreinte'],
                      }, prefixe: 'ARC');
                    }
                    c.magasin.journaliser('Clôture d’exercice', 'M12', 'Exercice', '$annee', {'etat': 'en_cloture'},
                        {'etat': 'clos', 'resultat': r.resultat, 'cl': r.clNumero, 'an': r.anNumero});
                    notifier(c,
                        type: 'cloture',
                        poste: 'comptable',
                        libelle: 'Exercice $annee clôturé',
                        detail: 'Résultat ${money(r.resultat)} ; pièces ${r.clNumero} et ${r.anNumero} écrites.',
                        reference: '$annee');
                    fermer();
                    ToastsSigh.afficher(ctx, 'Exercice $annee clôturé.',
                        type: TypeToast.succes, detail: 'Résultat ${money(r.resultat)} · ${r.lignesCL.length} ligne(s) de clôture, ${r.lignesAN.length} d’à-nouveau · archive $reference.');
                  }),
            ]);
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // TRANSITION 4 — rouvrir : le comptable seul, par contre-passation
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _rouvrir(BuildContext ctx, ContexteEcran c, Fiche x) {
    final annee = x['annee'] as int;
    final motif = ControleurFormulaire(const [
      ChampDef(nom: 'motif', libelle: 'Motif de la réouverture (dix caractères au moins)', type: TypeChamp.textarea, col: ColChamp.plein, lignes: 3)
    ]);
    afficherModale<void>(ctx,
        titre: 'Rouvrir l’exercice $annee',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
              'La pièce de clôture et la pièce d’à-nouveaux sont contre-passées : rien ne s’efface, la piste d’audit reste entière. L’exercice repasse « en clôture ». La Direction en est informée.',
              style: TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: motif),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Rouvrir',
                  icone: LucideIcons.lockOpen,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    final ecr = c.magasin.collection('ecritures');
                    final r = cpcRouvrirExercice(c.magasin.collection('exercices').toutes, _ecritures(c), annee,
                        motif: '${motif['motif'] ?? ''}',
                        acteur: acteurDe(c),
                        acteurId: acteurIdDe(c),
                        role: c.role,
                        maintenant: c.aujourdhui,
                        toutesEcritures: ecr.toutes);
                    if (!r.ok) {
                      ToastsSigh.afficher(ctx, 'Réouverture refusée.', type: TypeToast.erreur, detail: r.motif);
                      return;
                    }
                    final annulations = <VoidCallback>[];
                    try {
                      for (final l in r.lignes) {
                        annulations.add(ecr.inserer(l, prefixe: 'ECR').annuler);
                      }
                    } on EcritureRefusee catch (e) {
                      for (final u in annulations.reversed) {
                        u();
                      }
                      ToastsSigh.afficher(ctx, 'Réouverture refusée.', type: TypeToast.erreur, detail: '${e.motif} L’exercice reste clôturé, rien n’a été écrit.');
                      return;
                    }
                    c.magasin.collection('exercices').mettreAJour(x['id'], r.patch!);
                    c.magasin.collection('clotures').inserer(r.cloture!, prefixe: 'CLO');
                    c.magasin.journaliser('Réouverture d’exercice', 'M12', 'Exercice', '$annee', {'etat': 'clos'},
                        {'etat': 'en_cloture', 'motif': '${motif['motif']}'.trim(), 'contrePasse': r.cloture!['contrePasse']});
                    notifier(c,
                        type: 'cloture',
                        poste: 'direction',
                        libelle: 'Exercice $annee rouvert',
                        detail: '${acteurDe(c)} a rouvert l’exercice $annee : ${'${motif['motif']}'.trim()}',
                        priorite: 'haute',
                        reference: '$annee');
                    fermer();
                    ToastsSigh.afficher(ctx, 'Exercice $annee rouvert.', type: TypeToast.succes, detail: '${r.pieces.join(' et ')} contre-passent la clôture.');
                  }),
            ]);
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // L'ARCHIVE LÉGALE : fichiers, empreintes, téléchargement qui VÉRIFIE l'empreinte avant de livrer
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _archive(BuildContext ctx, ContexteEcran c, Fiche x) {
    final annee = x['annee'] as int;
    final archives = [for (final a in c.magasin.collection('archivesExercice').actives) if (a['annee'] == annee) a]
      ..sort((a, b) => (n(b['version']) - n(a['version'])).sign.toInt());
    if (archives.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucune archive pour l’exercice $annee.', type: TypeToast.info, detail: 'Elle naît avec la clôture définitive.');
      return;
    }
    afficherModale<void>(ctx,
        titre: 'Archive légale de l’exercice $annee',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final a in archives) ...[
            Text('${a['reference']} : clôture ${a['clNumero']}, déposée le ${dateDe(a['creeLe'])} par ${a['par'] ?? '—'}',
                style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            MiniTableauSigh(colonnes: [
              ColonneMini('Fichier', (f) => '${f['nom']}'),
              ColonneMini('Taille', (f) => '${nombre(f['taille'])} c.', droite: true),
              ColonneMini('Empreinte SHA-256', (f) => '${'${f['empreinte']}'.substring(0, 20)}…'),
              ColonneMini('', (f) => '',
                  rendu: (f) => BoutonSigh(
                      libelle: 'Télécharger',
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.secondaire,
                      icone: LucideIcons.download,
                      onPressed: () => _telecharger(ctx, c, '${a['reference']}', '${f['nom']}'))),
            ], lignes: [for (final f in (a['fichiers'] as List)) (f as Map).cast<String, Object?>()]),
            const SizedBox(height: 16),
          ],
          const NoteSigh(
              'L’archive est immuable et jamais régénérée. Avant chaque téléchargement, l’empreinte du fichier est recalculée et comparée à celle du manifeste : un fichier altéré est refusé.',
              icone: LucideIcons.shieldCheck),
        ]),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
  }

  Future<void> _telecharger(BuildContext ctx, ContexteEcran c, String reference, String nom) async {
    final r = cpcLireArchive(c.magasin.collection('archivesExercice').actives, reference, nom);
    if (!r.ok) {
      ToastsSigh.afficher(ctx, 'Téléchargement refusé.', type: TypeToast.erreur, detail: r.motif);
      return;
    }
    final chemin = await ImpressionPoste.enregistrerTexte('${r.fichier!['contenu']}', nom);
    if (ctx.mounted) ToastsSigh.afficher(ctx, 'Fichier vérifié et enregistré.', type: TypeToast.succes, detail: '$nom : empreinte conforme · $chemin');
  }

  void _procesVerbal(BuildContext ctx, ContexteEcran c, Fiche x) {
    final annee = x['annee'] as int;
    final lignes = cpcSoldesParCompte(cpcEcrituresDe(_ecritures(c), annee));
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Procès-verbal de clôture — exercice $annee',
            sousTitre: 'Détermination du résultat et à-nouveaux de l’exercice ${annee + 1}',
            cartouche: [
              ('Exercice', '${x['debut']} → ${x['fin']}'),
              ('Résultat net', money(n(x['resultat']))),
              ('Demandée par', '${x['demandePar'] ?? '—'}'),
              ('Validée par', '${x['validePar'] ?? '—'}'),
              ('Empreinte SHA-256', '${_tronque('${x['empreinte'] ?? ''}', 32)}…'),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Compte', valeur: (l) => l['compte']),
                ColonneEtat(libelle: 'Intitulé', valeur: (l) => l['libelle']),
                ColonneEtat(libelle: 'Débit', droite: true, valeur: (l) => m(l['debit']), somme: (l) => n(l['debit'])),
                ColonneEtat(libelle: 'Crédit', droite: true, valeur: (l) => m(l['credit']), somme: (l) => n(l['credit'])),
              ], lignes: lignes)
            ],
            signatures: [Signature('Le Comptable', nom: '${x['demandePar'] ?? ''}'), Signature('La Direction', nom: '${x['validePar'] ?? ''}')]));
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // LA TABLE DES COMPTES DE RÉSULTAT (131 bénéfice, 139 perte) : deux fiches, on les MODIFIE, on ne les crée ni ne les archive
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _modifierCompteResultat(BuildContext ctx, ContexteEcran c, Fiche f) {
    final form = ControleurFormulaire(const [
      ChampDef(nom: 'compte', libelle: 'Compte (six chiffres)', requis: true, aide: '131… pour le bénéfice, 139… pour la perte (SYSCOHADA).'),
      ChampDef(nom: 'libelle', libelle: 'Libellé de la pièce', requis: true, col: ColChamp.plein),
    ], {'compte': '${f['compte']}', 'libelle': '${f['libelle']}'});
    afficherModale<void>(ctx,
        titre: f['sens'] == 'benefice' ? 'Compte du bénéfice' : 'Compte de la perte',
        corps: FormulaireSigh(controleur: form),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  onPressed: () {
                    final motif = cpcControleCompteResultat(f, compte: form['compte'], libelle: form['libelle']);
                    if (motif != null) {
                      ToastsSigh.afficher(ctx, 'Compte de résultat refusé.', type: TypeToast.erreur, detail: motif);
                      return;
                    }
                    final avant = {'compte': f['compte'], 'libelle': f['libelle']};
                    final apres = {'compte': '${form['compte']}'.trim(), 'libelle': '${form['libelle']}'.trim()};
                    c.magasin.collection('comptesResultat').mettreAJour(f['id'], apres);
                    c.magasin.journaliser('Compte de résultat modifié', 'M12', 'Compte de résultat', '${f['sens']}', avant, apres);
                    fermer();
                    ToastsSigh.afficher(ctx, 'Compte de résultat enregistré.', type: TypeToast.succes, detail: 'Il vaut pour les prochaines clôtures.');
                  }),
            ]);
  }

  Widget _comptesResultat(BuildContext ctx, ContexteEcran c, bool peut) {
    final lignes = c.magasin.collection('comptesResultat').actives;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          'La clôture solde les classes 6, 7 et 8 vers le compte de bénéfice (131) ou de perte (139) selon le signe du résultat. Ces comptes se paramètrent ici, jamais dans le code. '
          '${peut ? 'Une modification vaut pour les prochaines clôtures : les pièces CL déjà écrites ne changent pas.' : 'Réservé au comptable, à la Directrice Administrative et à l’administrateur : vous consultez.'}'),
      const SizedBox(height: 12),
      TableauSigh(
        titre: 'Comptes du résultat net',
        lignes: lignes,
        nomExport: 'comptes-resultat',
        taillePage: 10,
        recherche: false,
        colonnes: [
          ColonneTableau(
              cle: 'sens',
              libelle: 'Résultat',
              texte: (x) => x['sens'] == 'benefice' ? 'Bénéfice' : 'Perte',
              rendu: (_, x) => x['sens'] == 'benefice' ? const BadgeSigh('Bénéfice', ton: TonSigh.succes) : const BadgeSigh('Perte', ton: TonSigh.danger)),
          ColonneTableau(cle: 'compte', libelle: 'Compte', sansCoupure: true, texte: (x) => '${x['compte']}', rendu: (_, x) => monoTexte('${x['compte']}')),
          ColonneTableau(cle: 'libelle', libelle: 'Libellé', texte: (x) => '${x['libelle']}'),
        ],
        actionsLigne: peut
            ? (cx, x) => [
                  BoutonSigh(
                      libelle: 'Modifier',
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.secondaire,
                      icone: LucideIcons.pencil,
                      onPressed: () => _modifierCompteResultat(ctx, c, x)),
                ]
            : null,
      ),
    ]);
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // LES TROIS ONGLETS
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  Widget _exercices(BuildContext ctx, ContexteEcran c, bool peutDemander, bool peutValider, bool peutRouvrir) {
    final lignes = exercicesActifs(c.magasin);
    return TableauSigh(
      titre: 'Exercices comptables',
      lignes: lignes,
      nomExport: 'exercices',
      taillePage: 10,
      recherche: false,
      triInitial: 'annee',
      sensInitial: 'desc',
      colonnes: [
        ColonneTableau(cle: 'annee', libelle: 'Exercice', sansCoupure: true, texte: (x) => 'Exercice ${x['annee']}'),
        ColonneTableau(
            cle: 'debut', libelle: 'Période', texte: (x) => '${dateDe(x['debut'])} → ${dateDe(x['fin'])}'),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            texte: (x) => '${x['etat']}',
            rendu: (_, x) => switch (x['etat']) {
                  'ouvert' => const BadgeSigh('Ouvert', ton: TonSigh.succes),
                  'en_cloture' || 'en_attente_cloture' => const BadgeSigh('En clôture', ton: TonSigh.attention),
                  'clos' => const BadgeSigh('Clôturé'),
                  _ => BadgeSigh('${x['etat']}')
                }),
        ColonneTableau(
            cle: 'resultat',
            libelle: 'Résultat net',
            droite: true,
            texte: (x) => x['resultat'] == null ? '' : m(x['resultat']),
            rendu: (_, x) => x['resultat'] == null
                ? const Text('—', style: TextStyle(color: JetonsShell.slate400, fontSize: 14, height: 20 / 14))
                : Text(money(x['resultat']), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
        ColonneTableau(
            cle: 'validePar',
            libelle: 'Validée par',
            texte: (x) => x['validePar'] != null ? '${x['validePar']} — ${dateDe(x['valideLe'])}' : '—'),
        ColonneTableau(
            cle: 'empreinte',
            libelle: 'Empreinte',
            texte: (x) => x['empreinte'] != null ? '${'${x['empreinte']}'.substring(0, 12)}…' : '—',
            rendu: (_, x) => x['empreinte'] != null ? monoTexte('${'${x['empreinte']}'.substring(0, 12)}…') : const Text('—')),
      ],
      actionsLigne: (cx, x) => [
        if (x['source'] != 'liasse') ...[
          if (x['etat'] == 'ouvert')
            BoutonSigh(
                libelle: 'Pré-clôture',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.listChecks,
                onPressed: () => _preCloture(ctx, c, x, peutDemander)),
          if (x['etat'] == 'en_cloture' || x['etat'] == 'en_attente_cloture') ...[
            BoutonSigh(
                libelle: 'Contrôles',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.listChecks,
                onPressed: () => _preCloture(ctx, c, x, false)),
            if (peutDemander)
              BoutonSigh(
                  libelle: 'Reprendre la saisie',
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  icone: LucideIcons.rotateCcw,
                  onPressed: () => _reprendre(ctx, c, x)),
            if (peutValider)
              BoutonSigh(libelle: 'Clôturer définitivement', taille: TailleBouton.sm, icone: LucideIcons.lock, onPressed: () => _cloturer(ctx, c, x)),
          ],
          if (x['etat'] == 'clos') ...[
            if (peutRouvrir)
              BoutonSigh(
                  libelle: 'Rouvrir',
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.danger,
                  icone: LucideIcons.lockOpen,
                  onPressed: () => _rouvrir(ctx, c, x)),
            BoutonSigh(
                libelle: 'Archive légale',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.archive,
                onPressed: () => _archive(ctx, c, x)),
            BoutonSigh(
                libelle: 'Procès-verbal',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.printer,
                onPressed: () => _procesVerbal(ctx, c, x)),
          ],
        ]
      ],
    );
  }

  Widget _periodes(BuildContext ctx, ContexteEcran c) {
    final annee = exerciceChoisi(c);
    const mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    final e = cpcEcrituresDe(_ecritures(c), annee, brouillons: true);
    final lignes = <Fiche>[
      for (var i = 0; i < 12; i++)
        () {
          final sel = [for (final x in e) if (DateTime.tryParse('${x['date']}')?.month == i + 1) x];
          final d = sel.fold<double>(0, (a, x) => a + n(x['debit'])), cr = sel.fold<double>(0, (a, x) => a + n(x['credit']));
          return <String, Object?>{
            'id': '$i',
            'mois': '${mois[i][0].toUpperCase()}${mois[i].substring(1)} $annee',
            'nb': sel.length,
            'debit': d,
            'credit': cr,
            'equilibre': d == cr,
            'brouillons': sel.where((x) => x['statut'] == 'brouillon').length,
          };
        }()
    ];
    return TableauSigh(
      titre: 'Périodes comptables — exercice $annee',
      lignes: lignes,
      nomExport: 'periodes',
      taillePage: 12,
      recherche: false,
      colonnes: [
        const ColonneTableau(cle: 'mois', libelle: 'Période', sansCoupure: true, triable: false),
        const ColonneTableau(cle: 'nb', libelle: 'Écritures', droite: true, triable: false),
        ColonneTableau(cle: 'debit', libelle: 'Total débit', droite: true, triable: false, texte: (p) => m(p['debit'])),
        ColonneTableau(cle: 'credit', libelle: 'Total crédit', droite: true, triable: false, texte: (p) => m(p['credit'])),
        ColonneTableau(
            cle: 'equilibre',
            libelle: 'Équilibre',
            triable: false,
            texte: (p) => p['equilibre'] == true ? 'Équilibrée' : 'Déséquilibrée',
            rendu: (_, p) => n(p['nb']) == 0
                ? const Text('—')
                : (p['equilibre'] == true
                    ? const BadgeSigh('Équilibrée', ton: TonSigh.succes)
                    : BadgeSigh('Écart ${money((n(p['debit']) - n(p['credit'])).abs(), avecDevise: false)}', ton: TonSigh.danger))),
        ColonneTableau(
            cle: 'brouillons',
            libelle: 'Brouillons',
            droite: true,
            triable: false,
            texte: (p) => '${p['brouillons']}',
            rendu: (_, p) => n(p['brouillons']) > 0
                ? Text('${p['brouillons']}', style: const TextStyle(color: JetonsShell.warning600, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))
                : const Text('—')),
      ],
    );
  }

  Widget _lettrage(BuildContext ctx, ContexteEcran c) {
    final annee = exerciceChoisi(c);
    final toutes = _ecritures(c);
    final tiers = <String>{for (final e in toutes) if (cpcLettrable(e['compte'])) '${e['compte']}'}.toList()..sort();
    final note = const NoteSigh(
        'Un lettrage rapproche des lignes d’un même compte de tiers dont le total s’annule (une facture et son règlement). À la clôture, seules les lignes non lettrées sont reprises une à une aux à-nouveaux.',
        icone: LucideIcons.link);
    if (tiers.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        note,
        const SizedBox(height: 12),
        const Text('Aucun compte de tiers mouvementé.', style: TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14)),
      ]);
    }
    if (!_compteInit) {
      _compteInit = true;
      _compte = champUnique(
          ChampDef(
              nom: 'compte',
              libelle: 'Compte',
              type: TypeChamp.select,
              col: ColChamp.plein,
              options: [for (final t in tiers) OptionChamp(t, '$t — ${cpaCompteLibelle(t)}')]),
          tiers.first);
      _compte.addListener(() {
        _coches.clear();
        if (mounted) setState(() {});
      });
    }
    final compte = '${_compte['compte']}';
    final lignes = [
      for (final e in toutes)
        if ('${e['compte']}' == compte && cpaAnnee(e['date']) == annee && e['statut'] == 'validee') e
    ];
    final droit = c.droit.editer;
    final exos = c.magasin.collection('exercices').toutes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      note,
      const SizedBox(height: 12),
      Row(children: [
        const Text('Compte  ', style: TextStyle(color: JetonsShell.slate700, fontSize: 14)),
        commande(_compte, largeur: 420),
      ]),
      const SizedBox(height: 12),
      TableauSigh(
        key: ValueKey('lettrage-$compte'),
        titre: 'Lignes du compte $compte',
        lignes: lignes,
        nomExport: 'lettrage',
        taillePage: 10,
        colonnes: [
          ColonneTableau(
              cle: 'select',
              libelle: '',
              triable: false,
              texte: (_) => '',
              rendu: (_, e) {
                final lettre = '${e['lettrage'] ?? ''}'.isNotEmpty;
                final clos = cpcEtatExercice(exos, cpaAnnee(e['date']) ?? annee) == 'clos';
                if (lettre || !droit || clos) return const SizedBox.shrink();
                return Checkbox(
                    key: Key('lettrage:${e['id']}'),
                    value: _coches.contains(e['id']),
                    onChanged: (v) => setState(() => v == true ? _coches.add(e['id']) : _coches.remove(e['id'])));
              }),
          ColonneTableau(cle: 'numero', libelle: 'Pièce', sansCoupure: true, texte: (e) => '${e['numero'] ?? ''}', rendu: (_, e) => monoTexte(e['numero'], couleur: JetonsShell.navy800, poids: FontWeight.w600)),
          colDateEcriture(),
          const ColonneTableau(cle: 'libelle', libelle: 'Libellé'),
          colDebitEcriture(),
          colCreditEcriture(),
          ColonneTableau(
              cle: 'lettrage',
              libelle: 'Lettrage',
              texte: (e) => '${e['lettrage'] ?? 'non lettrée'}',
              rendu: (_, e) => '${e['lettrage'] ?? ''}'.isNotEmpty
                  ? BadgeSigh('${e['lettrage']}', ton: TonSigh.succes)
                  : const Text('non lettrée', style: TextStyle(color: JetonsShell.slate400, fontSize: 14, height: 20 / 14))),
        ],
      ),
      if (droit) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          BoutonSigh(libelle: 'Lettrer la sélection', icone: LucideIcons.link, onPressed: () => _lettrer(ctx, c, compte)),
          BoutonSigh(
              libelle: 'Dé-lettrer un code…',
              icone: LucideIcons.unlink,
              variante: VarianteBouton.secondaire,
              onPressed: () => _delettrer(ctx, c, compte)),
        ]),
      ],
    ]);
  }

  void _lettrer(BuildContext ctx, ContexteEcran c, String compte) {
    final r = cpcLettrer(c.magasin.collection('ecritures').toutes, compte, _coches.toList());
    if (!r.ok) {
      ToastsSigh.afficher(ctx, 'Lettrage refusé.', type: TypeToast.erreur, detail: r.motif);
      return;
    }
    final ecr = c.magasin.collection('ecritures');
    final defaire = <VoidCallback>[];
    final refus = refuseSiClos(ctx, () {
      for (final id in r.ids) {
        defaire.add(ecr.mettreAJour(id, {'lettrage': r.code, 'lettreLe': c.aujourdhui.toUtc().toIso8601String(), 'lettrePar': acteurDe(c)}));
      }
    });
    if (refus) return;
    _coches.clear();
    ToastsSigh.afficher(ctx, 'Lettrage « ${r.code} » posé sur ${r.ids.length} ligne(s).', type: TypeToast.succes);
  }

  void _delettrer(BuildContext ctx, ContexteEcran c, String compte) {
    final f = ControleurFormulaire(const [
      ChampDef(nom: 'code', libelle: 'Code de lettrage à défaire', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'motif', libelle: 'Motif (obligatoire)', type: TypeChamp.textarea, requis: true, col: ColChamp.plein, lignes: 2),
    ]);
    afficherModale<void>(ctx,
        titre: 'Dé-lettrer un code',
        sousTitre: 'Compte $compte',
        taille: TailleModale.sm,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Dé-lettrer',
                  icone: LucideIcons.unlink,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final r = cpcDelettrer(c.magasin.collection('ecritures').toutes, compte, '${v['code']}'.toUpperCase(), '${v['motif']}');
                    if (!r.ok) {
                      ToastsSigh.afficher(ctx, 'Dé-lettrage refusé.', type: TypeToast.erreur, detail: r.motif);
                      return;
                    }
                    final ecr = c.magasin.collection('ecritures');
                    final refus = refuseSiClos(ctx, () {
                      for (final id in r.ids) {
                        ecr.mettreAJour(id, {'lettrage': null, 'delettreLe': c.aujourdhui.toUtc().toIso8601String(), 'delettreMotif': '${v['motif']}'.trim()});
                      }
                    });
                    if (refus) return;
                    fermer();
                    ToastsSigh.afficher(ctx, '${r.ids.length} ligne(s) dé-lettrée(s).', type: TypeToast.succes);
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([for (final k in ['exercices', 'ecritures', 'comptes', 'notifications']) c.magasin.collection(k)]),
      builder: (context, _) {
        final annee = exerciceChoisi(c);
        final exos = c.magasin.collection('exercices').toutes;
        final cur = cpcExercice(exos, annee);
        final pre = cpcPreCloture(_ecritures(c), annee, exercices: exos);
        final etat = cpcEtatExercice(exos, annee);
        final clos = etat == 'clos';
        final peutDemander = c.droit.editer && cpcRolesDemande.contains(c.role);
        final peutValider = cpcRolesValidation.contains(c.role);
        final peutRouvrir = c.droit.editer && (c.role == 'comptable' || c.role == 'admin');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Exercice affiché', valeur: '$annee', icone: LucideIcons.calendar),
            KpiSigh(
                libelle: 'État',
                valeur: switch (etat) { 'ouvert' => 'Ouvert', 'en_cloture' => 'En clôture', _ => 'Clôturé' },
                icone: LucideIcons.lock,
                ton: clos ? TonSigh.succes : TonSigh.info),
            KpiSigh(
                libelle: clos ? 'Résultat net' : 'Résultat provisoire',
                valeur: money(clos ? n(cur?['resultat']) : pre.resultat),
                icone: LucideIcons.scale,
                ton: TonSigh.neutre),
            KpiSigh(
                libelle: 'Contrôles bloquants en échec',
                valeur: nombre(pre.bloquants.length),
                icone: LucideIcons.shieldAlert,
                ton: pre.bloquants.isNotEmpty ? TonSigh.attention : TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(id: 'exercices', libelle: 'Exercices', construire: (ctx) => _exercices(context, c, peutDemander, peutValider, peutRouvrir)),
            OngletDef(id: 'periodes', libelle: 'Périodes de l’exercice', construire: (ctx) => _periodes(context, c)),
            OngletDef(id: 'lettrage', libelle: 'Lettrage des tiers', construire: (ctx) => _lettrage(context, c)),
            OngletDef(id: 'comptes-resultat', libelle: 'Comptes de résultat', construire: (ctx) => _comptesResultat(context, c, c.droit.editer && cpcRolesDemande.contains(c.role))),
          ]),
        ]);
      },
    );
  }
}
