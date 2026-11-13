import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../donnees/demandes_import_poste.dart';
import '../../donnees/magasin.dart';
import '../../import/classeur_xlsx.dart';
import '../../import/port_magasin.dart';
import '../../import/profil_import.dart';
import '../../import/selecteurs_import.dart';
import '../../kit/kit.dart';
import '../../kit/validation_poste.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/flux_reprise.dart';

/// MODULE D'IMPORTATION (IMP), port de `prototype_html/assets/js/modules/import.js` : UN écran par jeu d'import (`EcranImportJeu`), plus l'accueil du module
/// (`EcranImportAccueil`). Le moteur et les dix jeux sont dans `packages/domaine` (`src/import/`) : cet écran ne connaît AUCUNE règle, il enchaîne les
/// gestes : télécharger le modèle .xlsx, téléverser (sélecteur natif INJECTABLE), analyse COMPLÈTE sans écriture, aperçu ligne par ligne, confirmation,
/// écriture atomique du lot, historique, annulation du lot par archivage (RG-14), rapport d'erreurs .xlsx.

PortMagasin _port(ContexteEcran c) =>
    PortMagasin(c.magasin, aujourdhui: () => c.aujourdhui, nomAgent: c.agent.nom, profil: profilImportDe(c));

/// Les anciennes fiches de lot (RG-14 : elles restent lisibles) portent l'identifiant des deux jeux qui ont changé de nom avec le référentiel de prix unique (lot IMP-A).
const _anciensJeux = {'actes': 'tarifs', 'analyses': 'analyses-modele'};
String _jeuDeLot(Fiche l) => '${_anciensJeux[l['jeu']] ?? l['jeu']}';

/// La demande d'import : l'état d'une demande se LIT (en attente, appliquée, refusée avec son code, son motif et son geste, restitution du fileul), jamais une valeur de cellule.
/// Le libellé vient du domaine (`libelleEtatDemandeImport`) : un lot écrit chez le fileul n'est jamais dit « appliqué » avant que la mère l'ait confirmé (lot IMP-D).
(String, TonSigh) _etatDemande(Fiche d) {
  final e = libelleEtatDemandeImport(d);
  return (e.libelle, const {'succes': TonSigh.succes, 'danger': TonSigh.danger, 'attention': TonSigh.attention}[e.ton] ?? TonSigh.neutre);
}

/// La réponse de la mère et la suite chez le fileul, en une phrase sans valeur de cellule.
String _reponseDeLaMere(Fiche d) {
  switch (d['etat']) {
    case demandeImportAppliquee:
      return 'Lot ${d['resultatLot']} : ${d['resultatEcrits']} fiche(s) écrite(s) à la mère.';
    case demandeImportRefusee:
      final r = d['restitution'];
      final restit = d['ecritureDirecte'] != true
          ? ''
          : r == restitutionFaite
              ? ' Votre écriture locale a été restituée (${d['restitutionArchives'] ?? 0} fiche(s) archivée(s)).'
              : r == restitutionPartielle
                  ? ' Votre écriture locale a été restituée, sauf ${((d['restitutionGardees'] as List?) ?? const []).length} fiche(s) qu’une pièce émise utilise : elles restent, marquées.'
                  : ' La restitution de votre écriture locale est en cours.';
      return '${d['resultatCode']} : ${d['resultatMotif']}. ${d['resultatGeste']}$restit';
    case demandeImportEnAttente:
      return d['ecritureDirecte'] == true ? 'Les fiches sont écrites chez vous et marquées « en attente de la mère ». Elle confirmera ou refusera.' : '';
    case demandeImportRetiree:
      return 'Vous avez annulé le lot avant la réponse de la mère : la demande est retirée.';
  }
  return '';
}

DemandesImportPoste _demandes(ContexteEcran c) => DemandesImportPoste(c.magasin,
    role: c.role,
    auteur: () => c.agent.nom,
    matrice: c.donnees!.matrice,
    aujourdhui: () => c.aujourdhui,
    etiquette: c.magasin.poste.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase());

/// La VOIE de ce jeu sur ce poste (lot IMP-D) : directe (la mère, un poste autonome, ou un jeu d'activité), directe ET demande (un fileul rattaché, configuration seule), demande
/// seule (configuration ET quantités de stock), réservée à la mère (jeu restreint de configuration).
VoieImportFileul _voie(ContexteEcran c, String jeuId) => c.donnees == null
    ? VoieImportFileul.directe
    : DemandesImportPoste.voie(fileulRattache: ServiceInstallation.de(c.magasin).rattache, declaration: c.donnees!.matrice.matriceImport.declaration(jeuId));

/// Le tableau des demandes que CE poste a envoyées à la mère, pour un jeu : l'agent voit la réponse nommée, jamais les lignes de son fichier.
Widget tableauDemandes(List<Fiche> demandes) => TableauSigh(
      lignes: [for (final d in demandes) {...d, '_etat': _etatDemande(d).$1}],
      taillePage: 10,
      triInitial: 'demandeLe',
      sensInitial: 'desc',
      nomExport: 'demandes-importation',
      messageVide: 'Aucune demande envoyée à la mère.',
      colonnes: [
        ColonneTableau(
            cle: 'id',
            libelle: 'Demande',
            sansCoupure: true,
            texte: (l) => '${l['id']}',
            rendu: (_, l) => Text('${l['id']}', style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, fontWeight: FontWeight.w600, color: JetonsShell.navy800))),
        const ColonneTableau(cle: 'fichier', libelle: 'Fichier'),
        ColonneTableau(cle: 'demandeLe', libelle: 'Envoyée le', texte: (l) => _dateJour(l['demandeLe']), valeur: (l) => l['demandeLe']),
        const ColonneTableau(cle: 'aEcrire', libelle: 'Lignes', droite: true),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            texte: (l) => '${l['_etat']}',
            rendu: (_, l) {
              final t = _etatDemande(l);
              return BadgeSigh(t.$1, ton: t.$2, key: Key('imp-demande-etat-${l['etat']}'));
            }),
        ColonneTableau(
            cle: 'resultatMotif',
            libelle: 'Réponse de la mère',
            triable: false,
            texte: _reponseDeLaMere,
            rendu: (_, l) => l['etat'] == demandeImportAppliquee
                ? Text(_reponseDeLaMere(l), key: const Key('imp-demande-appliquee'), style: const TextStyle(fontSize: 12, color: JetonsShell.success700))
                : (l['etat'] == demandeImportRefusee
                    ? Text(_reponseDeLaMere(l), key: Key('imp-demande-refus-${l['resultatCode']}'), style: const TextStyle(fontSize: 12, color: JetonsShell.danger700))
                    : Text(_reponseDeLaMere(l), key: const Key('imp-demande-attente'), style: const TextStyle(fontSize: 12, color: JetonsShell.slate600))),
            ),
      ],
    );

/// Un lot se lit de son AUTEUR et des profils qui SUPERVISENT (droit d'annuler sur chaque jeu : tiré du droit, pas d'un nom de rôle), pour un jeu que le profil voit.
bool _lotVisible(ProfilImport p, String agent, Fiche l) {
  final id = _jeuDeLot(l);
  if (!p.droit(id).voir) return false;
  return p.supervise || l['par'] == agent;
}

/// L'annulation est une commande de CE JEU : son droit est celui du jeu et de l'auteur du lot, jamais celui de l'écran. Le moteur refuse aussi (`annulerLot`).
bool _peutAnnuler(ProfilImport p, String agent, Fiche l) => p.droit(_jeuDeLot(l)).annuler && (l['par'] == agent || p.supervise);

const _tonsEtat = {
  'applique': ('Appliqué', TonSigh.succes),
  'refuse': ('Refusé, rien écrit', TonSigh.danger),
  'annule': ('Annulé', TonSigh.neutre),
  'restitue': ('Restitué (refusé par la mère)', TonSigh.danger),
};
const _tonsLigne = {
  'valide': ('Valide', TonSigh.succes),
  'avertissement': ('Avertissement', TonSigh.attention),
  'refus': ('Refus', TonSigh.danger),
  'ignore': ('Ignorée', TonSigh.neutre),
  'inchange': ('Inchangée', TonSigh.neutre),
  'non': ('Non (non appliquée)', TonSigh.neutre),
};

String _dateJour(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// Le contenu du classeur-modèle d'un jeu : Données, Instructions, Listes (les mêmes que celui de la maquette).
Uint8List classeurModele(JeuImport j, PortImport port) {
  final m = modeleImport(j, port);
  return ecrireClasseur([
    FeuilleXlsx('Données', m.donnees,
        largeurs: [for (final c in colonnesDe(j, port)) c.label.length + 4 < 14 ? 14.0 : c.label.length + 4.0], validations: m.validations, colonnesTexte: m.colonnesTexte),
    FeuilleXlsx('Instructions', m.instructions, entete: false, largeurs: const [28, 12, 28, 46, 22, 70]),
    FeuilleXlsx('Listes', m.listes, largeurs: [for (var i = 0; i < m.listes.first.length; i++) 30.0]),
  ]);
}

/// Le classeur du rapport d'erreurs d'un lot ou d'une analyse : la feuille « Erreurs » puis le « Résumé ».
Uint8List classeurRapport(String jeuLibelle, String fichier, String lot, int nbLignes, List<Map<String, Object?>> problemes, {int ignores = 0, bool sansValeur = false}) =>
    ecrireClasseur([
      FeuilleXlsx('Erreurs', rapportImport(problemes, sansValeur: sansValeur), largeurs: sansValeur ? const [8, 26, 14, 24, 70, 70] : const [8, 26, 24, 14, 24, 70, 70]),
      FeuilleXlsx('Résumé', resumeRapportImport(jeuLibelle, fichier, lot, nbLignes, problemes.length, ignores: ignores, sansValeur: sansValeur), entete: false, largeurs: const [34, 50]),
    ]);

/// Lit un fichier choisi en lignes : .csv (UTF-8, séparateur détecté) ou classeur .xlsx (feuille « Données », à défaut la première). `null` + motif quand
/// le fichier est illisible.
({List<List<Object?>>? lignes, String? motif}) lireFichierImport(FichierChoisi f) {
  try {
    if (RegExp(r'\.(csv|txt)$', caseSensitive: false).hasMatch(f.nom)) {
      return (lignes: [for (final l in importLireCsv(utf8.decode(f.octets, allowMalformed: true))) List<Object?>.of(l)], motif: null);
    }
    final feuilles = lireClasseur(f.octets);
    if (feuilles.isEmpty) throw const FormatException('le classeur ne contient aucune feuille');
    final donnees = feuilles.where((x) => normaliser(x.nom) == normaliser('Données')).firstOrNull ?? feuilles.first;
    return (lignes: donnees.lignes, motif: null);
  } on FormatException catch (e) {
    return (lignes: null, motif: e.message);
  } catch (e) {
    return (lignes: null, motif: '$e');
  }
}

String _valeursPermisesTexte(ColonneImport c, PortImport port, dynamic ctx) {
  if (c.type == 'liste') return valeursListe(c, ctx).map((x) => x.label).join(' ; ');
  if (c.type == 'entier') return 'entier${c.min != null ? ' ≥ ${c.min}' : ''}${c.max != null ? ' et ≤ ${c.max}' : ''}';
  if (c.type == 'tarif') return 'montant entier en FCFA ; NC ; tiret (-)${c.unique ? ' ; UNIQUE (prix unique)' : ''}';
  if (c.motifTexte != null) return c.motifTexte!;
  if (c.longueurMax != null) return 'jusqu’à ${c.longueurMax} caractères';
  return '';
}

String _typeLisible(ColonneImport c) =>
    const {
      'texte': 'Texte',
      'entier': 'Nombre entier',
      'decimal': 'Nombre',
      'date': 'Date (AAAA-MM-JJ ou JJ/MM/AAAA)',
      'liste': 'Liste de valeurs',
      'tarif': 'Montant, NC ou tiret'
    }[c.type] ??
    c.type;

/// L'état d'un lot tel qu'on le lit. Un lot écrit chez un fileul et que la mère n'a pas confirmé n'est PAS « appliqué » tout court : il est écrit chez soi, en attente de la mère (lot IMP-D).
(String, TonSigh) _etatLot(ContexteEcran c, Fiche l) {
  if (l['etat'] == 'applique') {
    final d = c.magasin.collection(demandesImportCollection).toutes.where((x) => x['statut'] != 'archive' && x['lotLocalId'] == l['id']).firstOrNull;
    if (d != null && d['ecritureDirecte'] == true && d['etat'] != demandeImportAppliquee) return ('Écrit chez vous, en attente de la mère', TonSigh.attention);
  }
  return _tonsEtat[l['etat']] ?? ('${l['etat']}', TonSigh.neutre);
}

/// L'historique des lots : un tableau filtrable ; « Rapport » pour tout lot qui porte des constats, « Annuler le lot » (droit d'annuler) pour un lot appliqué.
Widget tableauLots(BuildContext contexte, ContexteEcran c, List<Fiche> lots, VoidCallback rafraichir) {
  final profil = profilImportDe(c);
  return TableauSigh(
    lignes: [
      for (final l in lots)
        {
          ...l,
          '_etat': _etatLot(c, l).$1,
          '_valide': '${l['validePar'] ?? l['par'] ?? ''}',
        }
    ],
    taillePage: 10,
    triInitial: 'reference',
    sensInitial: 'desc',
    nomExport: 'lots-importation',
    filtres: [
      FiltreTableau(
          nom: 'etat',
          libelle: 'État',
          options: const [OptionChamp('applique', 'Appliqué'), OptionChamp('refuse', 'Refusé'), OptionChamp('annule', 'Annulé'), OptionChamp('restitue', 'Restitué')],
          correspond: (l, v) => l['etat'] == v),
    ],
    messageVide: 'Aucun lot.',
    colonnes: [
      ColonneTableau(
          cle: 'reference',
          libelle: 'Lot',
          sansCoupure: true,
          texte: (l) => '${l['reference']}',
          rendu: (_, l) => Text('${l['reference']}',
              style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, fontWeight: FontWeight.w600, color: JetonsShell.navy800))),
      const ColonneTableau(cle: 'jeuLibelle', libelle: 'Jeu d’import'),
      const ColonneTableau(cle: 'fichier', libelle: 'Fichier'),
      ColonneTableau(cle: 'date', libelle: 'Date', texte: (l) => _dateJour(l['date']), valeur: (l) => l['date']),
      const ColonneTableau(cle: 'nbLignes', libelle: 'Lignes', droite: true),
      const ColonneTableau(cle: 'nbAvertissements', libelle: 'Avert.', droite: true),
      ColonneTableau(cle: '_valide', libelle: 'Validé par', texte: (l) => '${l['_valide']}'),
      ColonneTableau(
          cle: 'etat',
          libelle: 'État',
          texte: (l) => '${l['_etat']}',
          rendu: (_, l) {
            final t = _etatLot(c, l);
            return BadgeSigh(t.$1, ton: t.$2, key: Key('imp-lot-etat-${l['reference']}'));
          }),
    ],
    actionsLigne: (ctx, l) => [
      if (((l['erreurs'] as List?) ?? const []).isNotEmpty)
        BoutonIcone(
            icone: LucideIcons.fileDown,
            libelle: 'Rapport d’erreurs (.xlsx)',
            onPressed: () => _telechargerRapport(contexte, c, l)),
      // Une commande interdite est ABSENTE : un lot écrit chez un fileul que la mère a déjà confirmé ou refusé ne s'annule plus ici (refusAnnulationLotDirect).
      if (l['etat'] == 'applique' && _peutAnnuler(profil, c.agent.nom, l) && refusAnnulationLotDirect(_demandes(c).demandeDuLot(l['id'])) == null)
        BoutonIcone(
            icone: LucideIcons.undo2,
            libelle: 'Annuler le lot',
            variante: VarianteBouton.danger,
            onPressed: () => _annulerLot(contexte, c, l, rafraichir)),
    ],
  );
}

Future<void> _telechargerRapport(BuildContext contexte, ContexteEcran c, Fiche lot) async {
  // Pour un jeu RESTREINT : ni valeur de cellule, ni motif qui la cite (un lot déjà masqué reste masqué : le masquage est idempotent).
  final jeu = jeuImportParId(_jeuDeLot(lot));
  final port = _port(c);
  final restreint = jeu != null && port.profil.restreint(jeu.id);
  final problemes = [
    for (final p in (lot['erreurs'] as List).cast<Map>())
      if (jeu != null && restreint)
        masquerProbleme(
                jeu,
                ProblemeImport(
                    n: (p['n'] as num?)?.toInt() ?? 0,
                    colonne: '${p['colonne'] ?? ''}',
                    valeur: p['valeur'],
                    code: '${p['code']}',
                    motif: '${p['motif']}',
                    geste: '${p['geste']}',
                    niveau: '${p['niveau']}'),
                port)
            .versJson()
      else
        p.cast<String, Object?>()
  ];
  final octets = classeurRapport('${lot['jeuLibelle'] ?? ''}', '${lot['fichier'] ?? ''}', '${lot['reference']}', (lot['nbLignes'] as num?)?.toInt() ?? 0, problemes,
      ignores: (lot['ignoresTotal'] as num?)?.toInt() ?? 0, sansValeur: restreint);
  await _enregistrer(contexte, 'rapport-${lot['reference']}.xlsx', octets);
}

Future<void> _enregistrer(BuildContext contexte, String nom, Uint8List octets) async {
  final chemin = await SelecteursImport.enregistrer(nom, octets);
  if (!contexte.mounted) return;
  if (chemin != null) ToastsSigh.afficher(contexte, 'Fichier enregistré.', type: TypeToast.succes, detail: chemin);
}

Future<void> _annulerLot(BuildContext contexte, ContexteEcran c, Fiche lot, VoidCallback rafraichir) async {
  final nb = (lot['ecrits'] as List).length;
  final direct = _demandes(c).demandeDuLot(lot['id']) != null;
  final ok = await confirmerSigh(contexte,
      titre: 'Annuler le lot ${lot['reference']} ?',
      message:
          'Les $nb fiches écrites par ce lot seront archivées (RG-14), jamais supprimées. L’annulation est refusée si un acte s’appuie déjà sur elles.${direct ? ' La demande envoyée à la mère est retirée : elle ne la traitera plus.' : ''}',
      libelleOk: 'Annuler le lot',
      dangereux: true);
  if (!ok || !contexte.mounted) return;
  // Un lot écrit chez un fileul s'annule par son propre geste : tant que la mère n'a pas statué (la demande est alors retirée), refusé en nommant une fois qu'elle a confirmé.
  final r = _demandes(c).demandeDuLot(lot['id']) != null
      ? _demandes(c).annulerLotDuFileul(lot['id'], motif: 'annulation demandée par ${c.agent.nom}')
      : annulerLot(jeuImportParId, lot['id'], 'annulation demandée par ${c.agent.nom}', _port(c));
  if (r.ok) {
    ToastsSigh.afficher(contexte, 'Lot annulé.', type: TypeToast.succes, detail: '${r.archives} fiche(s) archivée(s).');
  } else {
    ToastsSigh.afficher(contexte, 'Annulation refusée.', type: TypeToast.erreur, detail: '${r.motif}. ${r.geste}');
  }
  rafraichir();
}

// --- L'écran d'un jeu, et la FENÊTRE du bouton « Importer les données » : UN SEUL contenu, deux portes ----------------------------------------------

/// La fenêtre en trois temps (le MODÈLE, la VÉRIFICATION sans écriture, l'IMPORT confirmé) pour un jeu. [modale] : celle du bouton « Importer les données » des écrans métier
/// (sans indicateurs, sans validation du jeu, sans historique ni reprise valorisée) ; sinon la page `imp-<jeu>`, qui porte aussi l'historique. Une seule construction :
/// deux copies divergeraient au premier champ ajouté.
class EcranImportJeu extends StatefulWidget with EcranMaquette {
  const EcranImportJeu(this.jeuId, {this.modale = false, super.key});

  /// L'identifiant du moteur (`grand-stock`, `patients`…).
  final String jeuId;
  final bool modale;

  JeuImport get jeu => jeuImportParId(jeuId)!;

  @override
  String? get titre => jeu.libelle;

  @override
  String? get description => jeu.description;

  @override
  String? get regle =>
      'Source : ${jeu.source} Le fichier est analysé en entier avant toute écriture ; chaque fiche écrite porte source, lot d’import et validé par (RG-12).';

  @override
  State<EcranImportJeu> createState() => _EtatEcranImportJeu();
}

class _EtatEcranImportJeu extends State<EcranImportJeu> {
  AnalyseImport? _analyse;
  Fiche? _lotRefuse;
  String? _resultat;
  bool _resultatOk = true;
  bool _occupe = false;

  JeuImport get _jeu => widget.jeu;

  Future<void> _telechargerModele(ContexteEcran c, {required bool csv}) async {
    final port = _port(c);
    final Uint8List octets;
    final String nom;
    if (csv) {
      octets = Uint8List.fromList(utf8.encode(modeleCsvImport(_jeu, port)));
      nom = '${_jeu.fichierModele}.csv';
    } else {
      octets = classeurModele(_jeu, port);
      nom = '${_jeu.fichierModele}.xlsx';
    }
    await _enregistrer(context, nom, octets);
  }

  Future<void> _televerser(ContexteEcran c) async {
    final f = await SelecteursImport.choisir();
    if (f == null || !mounted) return;
    final port = _port(c);
    final lu = lireFichierImport(f);
    final a = analyserFichier(_jeu, lu.lignes, f.nom, port, motifIllisible: lu.motif, empreinte: importCrc32(f.octets));
    // Un refus de droit ne se consigne pas : rien n'a été tenté par un détenteur du droit.
    final Fiche? lot = a.accepte ? null : consigner(_jeu, a, port);
    setState(() {
      _analyse = a;
      _lotRefuse = lot;
      _resultat = null;
    });
  }

  Future<void> _confirmer(ContexteEcran c) async {
    final a = _analyse!;
    final ok = await confirmerSigh(context,
        titre: 'Écrire ce lot ?',
        message:
            '${a.aEcrire} ligne(s) du fichier « ${a.fichier} » vont s’écrire en un seul geste, au nom de ${c.agent.nom} (validé par). Le lot pourra être annulé tant qu’aucun acte ne s’appuie dessus.',
        libelleOk: 'Écrire le lot');
    if (!ok || !mounted) return;
    setState(() => _occupe = true);
    final r = appliquer(_jeu, a, _port(c));
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _analyse = null;
      _lotRefuse = null;
      _resultatOk = r.ok;
      _resultat = r.ok
          ? 'Lot ${r.lot!['reference']} appliqué. ${r.ecrits} fiche(s) écrite(s), journalisées (RG-12).'
          : 'Importation refusée. ${r.motif}. ${r.geste}';
    });
    if (r.ok) {
      ToastsSigh.afficher(context, 'Lot ${r.lot!['reference']} appliqué.', type: TypeToast.succes, detail: '${r.ecrits} fiche(s) écrite(s).');
    } else {
      ToastsSigh.afficher(context, 'Importation refusée.', type: TypeToast.erreur, detail: r.motif);
    }
  }

  /// FILEUL (configuration seule) : écrit le fichier VÉRIFIÉ chez soi, tout de suite, ET dépose la demande à la mère, en un seul geste (lot IMP-D). La fenêtre dit AVANT le oui ce qui va se
  /// passer : l'écriture est immédiate, la mère confirmera ou refusera, un refus restitue.
  Future<void> _importerEtDemander(ContexteEcran c) async {
    final a = _analyse!;
    final ok = await confirmerSigh(context,
        titre: 'Écrire chez vous et prévenir la mère ?',
        message:
            '${a.aEcrire} ligne(s) du fichier « ${a.fichier} » vont s’écrire CHEZ VOUS maintenant, au nom de ${c.agent.nom} (validé par). Une demande part automatiquement à la mère, qui rejoue la vérification sous votre profil puis confirme ou refuse. '
            'Tant qu’elle n’a pas répondu, ces fiches portent le marquage « en attente de la mère »${_jeu.cibles.contains('lots') ? ' et ce stock n’est vu que de votre poste' : ''}. Si elle refuse, elles sont restituées (archivées, RG-14${_jeu.cibles.contains('lots') ? ' ; chaque entrée est contre-passée par un mouvement inverse nommé, un article déjà sorti reste en place' : ''}) et vous lisez le motif sur votre demande. Vous pouvez annuler le lot tant qu’elle n’a pas statué.',
        libelleOk: 'Écrire chez moi et envoyer la demande');
    if (!ok || !mounted) return;
    setState(() => _occupe = true);
    final r = _demandes(c).importerEtDemander(_jeu, a);
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _analyse = null;
      _lotRefuse = null;
      _resultatOk = r.resultat.ok;
      _resultat = r.resultat.ok
          ? 'Lot ${r.resultat.lot!['reference']} écrit chez vous (${r.resultat.ecrits} fiche(s)). La demande ${r.demande!['id']} est partie à la mère : en attente de sa confirmation, les fiches portent le marquage « en attente de la mère ».'
          : 'Importation refusée. ${r.resultat.motif}. ${r.resultat.geste}';
    });
    if (r.resultat.ok) {
      ToastsSigh.afficher(context, 'Écrit chez vous, en attente de la mère.',
          type: TypeToast.succes, detail: '${r.resultat.lot!['reference']} : ${r.resultat.ecrits} fiche(s). Demande ${r.demande!['id']} envoyée.');
    } else {
      ToastsSigh.afficher(context, 'Importation refusée.', type: TypeToast.erreur, detail: r.resultat.motif);
    }
  }

  Future<void> _rapportAnalyse(ContexteEcran c) async {
    final a = _analyse!;
    final lot = _lotRefuse;
    final port = _port(c);
    // Le rapport d'un jeu RESTREINT ne recopie aucune valeur de cellule : il lit les constats MASQUÉS, comme l'historique.
    final ps = [for (final p in problemesConsignes(_jeu, a, port)) p.versJson()];
    await _enregistrer(
        context,
        'rapport-${lot != null ? lot['reference'] : 'analyse'}.xlsx',
        classeurRapport(_jeu.libelle, a.fichier, lot != null ? '${lot['reference']}' : 'non consigné', a.nbLignes, ps,
            ignores: a.compte.ignores, sansValeur: port.profil.restreint(_jeu.id)));
  }

  Widget _apercu(ContexteEcran c, AnalyseImport a, DroitImport droit, {required VoieImportFileul voie}) {
    final reserve = voie == VoieImportFileul.reserveeALaMere, direct = voie == VoieImportFileul.directeEtDemande;
    final ps = a.problemes;
    final avecDetail = a.lignes.any((l) => l.detail != null && l.detail!.isNotEmpty);
    return CarteSigh(
      titre: 'Résultat de l’analyse du fichier « ${a.fichier} »',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          BadgeSigh('${a.nbLignes} ligne(s) lue(s)', ton: TonSigh.navy),
          BadgeSigh('${a.compte.valides} valide(s)', ton: TonSigh.succes),
          BadgeSigh('${a.compte.avertissements} avertissement(s)', ton: TonSigh.attention),
          BadgeSigh('${a.compte.refus} refus', ton: a.compte.refus > 0 ? TonSigh.danger : TonSigh.neutre),
          if (a.compte.ignores > 0) BadgeSigh('${a.compte.ignores} ignorée(s) (fiche déjà tenue)', ton: TonSigh.neutre),
          if (a.compte.inchanges > 0) BadgeSigh('${a.compte.inchanges} inchangée(s)', ton: TonSigh.neutre),
          if (a.compte.non > 0) BadgeSigh('${a.compte.non} « Non » (non appliquée(s))', ton: TonSigh.neutre),
        ]),
        const SizedBox(height: 12),
        if (a.accepte && a.aEcrire > 0)
          NoteSigh(
              'Analyse conforme. ${a.aEcrire} ligne(s) peuvent être écrites${a.compte.avertissements > 0 ? ', dont ${a.compte.avertissements} avec avertissement' : ''}. Rien n’est encore écrit.',
              ton: TonSigh.succes,
              icone: LucideIcons.circleCheck)
        else if (a.accepte)
          const NoteSigh(
              'Rien à écrire. Toutes les lignes sont ignorées, inchangées ou refusées par leur auteur (Non) : aucune erreur, aucun lot consigné.',
              icone: LucideIcons.info)
        else if (a.droitRefuse)
          NoteSigh('Importation refusée. ${a.globaux.first.motif}. ${a.globaux.first.geste}', ton: TonSigh.danger, icone: LucideIcons.octagonAlert)
        else
          NoteSigh(
              'Fichier refusé. Rien n’a été écrit. Le fichier est consigné au lot ${_lotRefuse?['reference']} ; corrigez les points ci-dessous puis téléversez de nouveau.',
              ton: TonSigh.danger,
              icone: LucideIcons.octagonAlert),
        if (a.globaux.isNotEmpty) ...[
          const SizedBox(height: 12),
          CarteSigh(
              titre: 'Points concernant le fichier entier',
              sansRemplissage: true,
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Niveau', (l) => l['niveau'] == importRefus ? 'Refus' : 'Avertissement'),
                ColonneMini('Colonne', (l) => '${l['colonne'] ?? ''}'),
                ColonneMini('Motif', (l) => '${l['motif']}'),
                ColonneMini('Geste de correction', (l) => '${l['geste']}'),
              ], lignes: [for (final p in a.globaux) p.versJson()])),
        ],
        if (a.lignes.isNotEmpty) ...[
          const SizedBox(height: 12),
          CarteSigh(
              titre: 'Aperçu ligne par ligne',
              sansRemplissage: true,
              child: TableauSigh(
                lignes: [
                  for (final l in a.lignes)
                    {'n': l.n, 'etat': l.etat, 'resume': l.brut.take(3).where((x) => x.isNotEmpty).join(' · '), 'detail': l.detail ?? '', 'problemes': l.problemes}
                ],
                taillePage: 10,
                triInitial: 'n',
                nomExport: 'apercu-importation',
                filtres: [
                  FiltreTableau(
                      nom: 'etat',
                      libelle: 'État',
                      options: [for (final e in _tonsLigne.entries) OptionChamp(e.key, e.value.$1)],
                      correspond: (l, v) => l['etat'] == v),
                ],
                colonnes: [
                  const ColonneTableau(cle: 'n', libelle: 'Ligne', droite: true),
                  ColonneTableau(
                      cle: 'etat',
                      libelle: 'État',
                      texte: (l) => _tonsLigne[l['etat']]!.$1,
                      rendu: (_, l) => BadgeSigh(_tonsLigne[l['etat']]!.$1, ton: _tonsLigne[l['etat']]!.$2)),
                  const ColonneTableau(cle: 'resume', libelle: 'Contenu'),
                  if (avecDetail) const ColonneTableau(cle: 'detail', libelle: 'Détail de la ligne'),
                  ColonneTableau(
                      cle: 'problemes',
                      libelle: 'Constats',
                      triable: false,
                      texte: (l) => [for (final p in (l['problemes'] as List<ProblemeImport>)) '${p.colonne} : ${p.motif}'].join(' | '),
                      rendu: (_, l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (final p in (l['problemes'] as List<ProblemeImport>))
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                      '${p.colonne} ${p.valeur != null && '${p.valeur}'.isNotEmpty ? '« ${p.valeur} » : ' : ': '}${p.motif}. ${p.geste}',
                                      key: Key('imp-constat-${p.code}'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: p.estRefus
                                              ? JetonsShell.danger700
                                              : (p.niveau == 'ignore' || p.niveau == 'info' ? JetonsShell.slate500 : JetonsShell.warning700)))),
                          ])),
                ],
              )),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          // La commande d'écriture n'existe que pour qui détient le droit d'IMPORTER CE JEU (pas celui d'éditer l'écran) : absente, jamais grisée.
          if (a.accepte && a.aEcrire > 0 && droit.importer && !reserve && !direct)
            BoutonSigh(
                libelle: 'Confirmer l’importation (${a.aEcrire} ligne${a.aEcrire > 1 ? 's' : ''})',
                icone: LucideIcons.packageCheck,
                onPressed: _occupe ? null : () => _confirmer(c)),
          // Sur un FILEUL rattaché, un référentiel de configuration s'écrit chez lui TOUT DE SUITE et la demande à la mère part toute seule (lot IMP-D).
          if (a.accepte && a.aEcrire > 0 && droit.importer && direct)
            BoutonSigh(
                key: const Key('imp-importer-et-demander'),
                libelle: 'Écrire chez moi et prévenir la mère (${a.aEcrire} ligne${a.aEcrire > 1 ? 's' : ''})',
                icone: LucideIcons.packageCheck,
                onPressed: _occupe ? null : () => _importerEtDemander(c)),
          if (ps.isNotEmpty && !a.droitRefuse)
            BoutonSigh(
                libelle: 'Rapport d’erreurs (.xlsx)',
                icone: LucideIcons.fileDown,
                variante: VarianteBouton.secondaire,
                onPressed: () => _rapportAnalyse(c)),
          BoutonSigh(libelle: 'Abandonner', variante: VarianteBouton.secondaire, onPressed: () => setState(() => _analyse = null)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final j = _jeu;
    final modale = widget.modale;
    final lots = c.magasin.collection(collectionLots);
    final vp = ValidationPoste(c);
    // Un jeu en proposition se valide par le moteur commun (famille `jeux_import`, cible = l'écran du jeu) : l'état se LIT, il ne se déduit pas de la constante.
    return ListenableBuilder(
      listenable: Listenable.merge([lots, c.magasin.collection(valCollectionValidations), c.magasin.collection('reglages'), c.magasin.collection(demandesImportCollection)]),
      builder: (context, _) {
        final port = _port(c);
        final profil = port.profil;
        final d = profil.droit(j.id);
        final siens = [for (final l in lots.toutes) if (_jeuDeLot(l) == j.id && _lotVisible(profil, c.agent.nom, l)) l];
        final appliques = siens.where((l) => l['etat'] == 'applique').toList();
        final ctx = j.contexte(port);
        final cols = colonnesDe(j, port);
        final mode = profil.modeDoublon(j.id);
        final jeuValide = vp.etat('jeux_import', j.ecran)?.enAttente == false;
        final reprise = !modale && j.id == 'grand-stock';
        final voie = _voie(c, j.id);
        final reserve = voie == VoieImportFileul.reserveeALaMere;
        final direct = voie == VoieImportFileul.directeEtDemande;
        // La REPRISE valorisée du Grand Stock a ses propres droits (ceux de M6) : elle reste atteignable de qui l'a, même sans détenir le JEU.
        Widget repriseValorisee() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
              SizedBox(height: 24),
              Text('Stock repris : traçabilité et valorisation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JetonsShell.navy900)),
              SizedBox(height: 12),
              NoteSigh(
                  'Le stock initial n’a pas été saisi manuellement : il provient de l’import de l’inventaire « Grand Stock ». Chaque article conserve sa source, son lot d’import et sa quantité d’origine, afin de distinguer les données reprises des mouvements opérationnels ultérieurs. Les références que le document ne tarife pas se valorisent ici, à part, datées et signées.',
                  icone: LucideIcons.history),
              SizedBox(height: 16),
              EcranReprise(),
            ]);
        if (!d.voir) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const NoteSigh('Votre profil ne détient pas ce jeu d’import : ni son modèle, ni son historique ne vous sont ouverts.', ton: TonSigh.attention, icone: LucideIcons.lock),
            if (reprise) repriseValorisee(),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!modale)
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Lots appliqués', valeur: '${appliques.length}', icone: LucideIcons.packageCheck, ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Fiches importées',
                  valeur: nombre(appliques.fold<int>(0, (t, l) => t + (l['ecrits'] as List).length)),
                  icone: LucideIcons.database,
                  ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Fichiers refusés',
                  valeur: '${siens.where((l) => l['etat'] == 'refuse').length}',
                  icone: LucideIcons.fileX,
                  ton: TonSigh.attention),
              KpiSigh(
                  libelle: 'Statut du jeu',
                  valeur: j.supporte ? 'Supporté' : (jeuValide ? 'Validé' : 'À valider'),
                  icone: LucideIcons.badgeCheck,
                  ton: j.supporte || jeuValide ? TonSigh.succes : TonSigh.attention),
            ]),
          if (!j.supporte && !jeuValide) ...[
            const SizedBox(height: 16),
            NoteSigh('Proposition à valider. ${j.limite}', ton: TonSigh.attention, icone: LucideIcons.circleHelp),
            if (!modale)
              if (vp.bouton(context, 'jeux_import', j.ecran) case final b?) Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerRight, child: b)),
          ] else if (!j.supporte) ...[
            const SizedBox(height: 16),
            NoteSigh('Jeu validé. ${(j.limite ?? '').replaceFirst(RegExp(r'^PROPOSITION À VALIDER\\s*:\\s*'), '')}', icone: LucideIcons.circleCheck),
            if (!modale)
              if (vp.badge('jeux_import', j.ecran) case final b?) Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerRight, child: b)),
          ] else if (j.limite != null) ...[
            const SizedBox(height: 16),
            NoteSigh(j.limite!, icone: LucideIcons.info),
          ],
          if (direct && j.cibles.contains('lots')) ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Un stock chez vous d’abord. Les articles, les lots et les entrées de ce fichier ne sont vus que de votre poste tant que la mère n’a pas confirmé : vous pouvez en sortir, aucun autre poste n’y touche, et rien n’est compté deux fois chez la mère. Si elle refuse, chaque entrée est contre-passée par un mouvement inverse nommé (un mouvement écrit ne se réécrit pas) et les articles sont archivés ; un article dont vous avez déjà sorti du stock reste en place, marqué « refusée par la mère » (restitution partielle), car une pièce émise ne se réécrit jamais.',
                icone: LucideIcons.packageCheck),
          ],
          if (direct) ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Écrit chez vous maintenant, la mère confirmera. Ce jeu écrit la configuration de la clinique, dont la mère reste l’autorité : votre fichier est vérifié, puis écrit dans VOTRE magasin tout de suite, et une demande part automatiquement à la mère. Elle rejoue la vérification sous votre profil et applique ou refuse. Tant qu’elle n’a pas répondu, les fiches portent le marquage « en attente de la mère » ; si elle refuse, elles sont restituées (archivées) et vous lisez le motif sur votre demande ; hors ligne, la demande attend dans votre file. En cas de conflit, la mère l’emporte.',
                icone: LucideIcons.serverCog),
          ],
          if (reserve) ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Réglé sur la mère et jeu restreint. Ce jeu écrit la configuration de la clinique et porte des données sensibles : ses lignes ne voyagent pas dans une demande. Il s’importe au poste de la mère ; le fichier peut être vérifié ici, rien n’y est écrit.',
                icone: LucideIcons.shieldAlert),
          ],
          if (profil.restreint(j.id)) ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Jeu restreint (RG-13). Le fichier est lu et contrôlé ici, mais aucune valeur de cellule n’est recopiée dans l’historique ni dans le rapport : chaque constat porte la ligne, la colonne, le code et le geste de correction. Les lots ne sont visibles que de leur auteur et des profils qui supervisent les importations.',
                icone: LucideIcons.shieldCheck),
          ],
          if (mode == 'ignorer') ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Fiches déjà tenues : ignorées. Une ligne dont la fiche existe déjà n’écrit rien et ne modifie rien ; elle est comptée et nommée au rapport. Un fichier peut donc être rejoué sans refus (mode arrêté par la Direction pour ce jeu seulement).',
                icone: LucideIcons.copyMinus),
          ],
          if (mode == 'versionner') ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Une ligne qui change un prix devient une version datée, jamais un écrasement. Les erreurs refusent le fichier entier ; le prix en vigueur ne change jamais à l’import par lui-même.',
                icone: LucideIcons.tags),
          ],
          const SizedBox(height: 16),
          CarteSigh(
            titre: '1. Télécharger le modèle',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                  'Le modèle est un classeur .xlsx de trois feuilles : « Données » (en-têtes exacts et une ligne d’exemple), « Instructions » (colonnes, formats, valeurs permises) et « Listes » (les référentiels de contrôle).',
                  style: TextStyle(fontSize: 14, color: JetonsShell.slate600)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                BoutonSigh(libelle: 'Télécharger le modèle (.xlsx)', icone: LucideIcons.fileDown, onPressed: () => _telechargerModele(c, csv: false)),
                BoutonSigh(
                    libelle: 'Modèle CSV',
                    icone: LucideIcons.fileText,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _telechargerModele(c, csv: true)),
              ]),
              const SizedBox(height: 12),
              MiniTableauSigh(colonnes: [
                ColonneMini('Colonne', (l) => (l['c'] as ColonneImport).label),
                ColonneMini('Obligatoire', (l) => (l['c'] as ColonneImport).obligatoire ? 'oui' : 'non'),
                ColonneMini('Type', (l) => _typeLisible(l['c'] as ColonneImport)),
                ColonneMini('Valeurs permises', (l) => _valeursPermisesTexte(l['c'] as ColonneImport, port, ctx)),
                ColonneMini('Exemple', (l) => texteDe((l['c'] as ColonneImport).exemple)),
              ], lignes: [for (final col in cols) {'c': col}]),
            ]),
          ),
          const SizedBox(height: 16),
          CarteSigh(
            titre: '2. Téléverser et analyser',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                  'L’analyse est complète et ne modifie rien : chaque ligne est contrôlée, un refus est nommé, et c’est vous qui confirmez l’écriture. Taille maximale de ce jeu : ${nombre(profil.borne(j.id))} lignes.',
                  style: const TextStyle(fontSize: 14, color: JetonsShell.slate600)),
              const SizedBox(height: 12),
              // La commande est ABSENTE (jamais grisée) sans le droit d'IMPORTER CE JEU : un profil qui le voit sans pouvoir y importer le lit.
              if (d.importer)
                Row(children: [
                  BoutonSigh(libelle: 'Téléverser un fichier (.xlsx ou .csv)', icone: LucideIcons.upload, onPressed: () => _televerser(c)),
                ])
              else
                const Text('Votre profil voit ce jeu sans pouvoir y importer : le téléversement n’est pas proposé.', style: TextStyle(fontSize: 14, color: JetonsShell.slate500)),
            ]),
          ),
          if (_resultat != null) ...[
            const SizedBox(height: 16),
            NoteSigh(_resultat!, ton: _resultatOk ? TonSigh.succes : TonSigh.danger, icone: _resultatOk ? LucideIcons.circleCheck : LucideIcons.octagonAlert),
          ],
          if (_analyse != null) ...[const SizedBox(height: 16), _apercu(c, _analyse!, d, voie: voie)],
          if (direct) ...[
            const SizedBox(height: 16),
            CarteSigh(titre: 'Demandes envoyées à la mère', sansRemplissage: true, child: tableauDemandes(_demandes(c).sesDemandes(jeu: j.id))),
          ],
          if (!modale) ...[
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Historique des lots de ce jeu',
                sansRemplissage: true,
                child: tableauLots(context, c, siens, () => setState(() {}))),
          ],
          // LE GRAND STOCK A DEUX FACES SUR LE MÊME ÉCRAN (E2158, corrigé le 06/11/2026) : l'import l'écrit (ci-dessus), la reprise le suit et le
          // valorise (ci-dessous). Le retrait de l'écran de reprise (8800c17) avait fait disparaître du poste la valorisation des références sans prix.
          if (reprise) repriseValorisee(),
        ]);
      },
    );
  }
}

// --- L'accueil du module ------------------------------------------------------------------------------------------------------------

class EcranImportAccueil extends StatelessWidget with EcranMaquette {
  const EcranImportAccueil({super.key});

  @override
  String? get titre => 'Importation de données';

  @override
  String? get description =>
      'Les jeux d’import de la clinique en démarrage : modèle .xlsx à télécharger, fichier à téléverser, analyse complète avant écriture, historique et annulation des lots.';

  @override
  String? get regle =>
      'Un import n’invente rien : il écrit ce que le fichier porte, après une analyse ligne par ligne. Un refus se nomme (ligne, colonne, valeur, motif, geste). Un fichier refusé est consigné et n’écrit rien. Un lot s’annule en archivant ses fiches (RG-14). '
      'Le droit d’importer est propre à chaque jeu (voir, importer, annuler) ; chacun lit ses lots, les profils qui supervisent lisent tous les lots.';

  /// Régler la taille maximale d'un fichier pour un jeu (réservé à qui SUPERVISE) : le réglage `importBornes` est écrit en base, motivé et journalisé.
  static Future<void> _regler(BuildContext contexte, ContexteEcran c, DeclarationImport d, int borne, VoidCallback rafraichir) async {
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'lignes', libelle: 'Taille maximale (lignes)', type: TypeChamp.nombre, requis: true, col: ColChamp.plein, aide: 'Entier de 1 à ${ProfilImport.borneMaximale}.'),
      const ChampDef(nom: 'motif', libelle: 'Motif du réglage', requis: true, col: ColChamp.plein),
    ], {'lignes': borne});
    final saisie = await afficherModale<Map<String, Object?>>(contexte,
        titre: 'Taille maximale : ${d.libelle}',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v != null) Navigator.of(contexte, rootNavigator: true).pop(v);
                  }),
            ]);
    if (saisie == null || !contexte.mounted) return;
    final port = _port(c);
    final r = definirBorneImport(d.id, saisie['lignes'], '${saisie['motif'] ?? ''}', port, jeu: jeuImportParId);
    if (!r.ok) {
      ToastsSigh.afficher(contexte, 'Réglage refusé.', type: TypeToast.erreur, detail: '${r.motif}. ${r.geste}');
      return;
    }
    final col = c.magasin.collection('reglages');
    if (col.parId('importBornes') == null) {
      col.inserer({'id': 'importBornes', 'valeur': r.bornes});
    } else {
      col.mettreAJour('importBornes', {'valeur': r.bornes});
    }
    c.magasin.journaliser('Taille maximale d’un fichier d’import', 'IMP', 'reglage', d.id, {'lignes': r.avant}, {'lignes': r.lignes, 'motif': '${saisie['motif']}'.trim().substring(0, '${saisie['motif']}'.trim().length.clamp(0, 60))});
    ToastsSigh.afficher(contexte, 'Taille maximale réglée.', type: TypeToast.succes, detail: '${nombre(r.lignes)} lignes (avant : ${nombre(r.avant)}).');
    rafraichir();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final lots = c.magasin.collection(collectionLots);
    final vp = ValidationPoste(c);
    return ListenableBuilder(
      listenable: Listenable.merge([lots, c.magasin.collection(valCollectionValidations), c.magasin.collection('reglages')]),
      builder: (context, _) {
        final profil = profilImportDe(c);
        // Les jeux que ce profil VOIT (calculé du droit de la matrice, jamais d'une liste de rôles) et les lots qu'il peut lire (les siens, ou tous pour qui supervise).
        final tous = [for (final l in lots.toutes) if (_lotVisible(profil, c.agent.nom, l)) l];
        final visibles = [for (final d in profil.matrice.declarations) if (profil.droit(d.id).voir) d];
        final superviseur = profil.supervise;
        int compte(String e) => tous.where((l) => l['etat'] == e).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh(
              superviseur
                  ? 'Supervision. Votre profil détient le droit d’annuler sur chaque jeu : vous lisez les lots de tous les agents. Chacun des autres ne lit que les siens.'
                  : 'Vous lisez les lots que vous avez vous-même écrits, pour les jeux que votre profil détient. Les profils qui supervisent les importations lisent tous les lots.',
              icone: LucideIcons.eye),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Jeux d’import', valeur: '${visibles.length}', icone: LucideIcons.files, ton: TonSigh.navy),
            KpiSigh(libelle: 'Lots appliqués', valeur: '${compte('applique')}', icone: LucideIcons.packageCheck, ton: TonSigh.succes),
            KpiSigh(libelle: 'Fichiers refusés', valeur: '${compte('refuse')}', icone: LucideIcons.fileX, ton: TonSigh.attention),
            KpiSigh(libelle: 'Lots annulés', valeur: '${compte('annule')}', icone: LucideIcons.undo2, ton: TonSigh.neutre),
          ]),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(
                id: 'jeux',
                libelle: 'Jeux d’import',
                construire: (_) => Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final d in visibles)
                        SizedBox(
                            width: 360,
                            child: CarteSigh(child: _carteJeu(c, vp, d, [for (final l in tous) if (_jeuDeLot(l) == d.id) l]))),
                    ])),
            OngletDef(
                id: 'historique',
                libelle: 'Historique des lots',
                compte: tous.length,
                construire: (ctx) => tableauLots(ctx, c, tous, () {})),
            OngletDef(
                id: 'tailles',
                libelle: 'Tailles maximales',
                construire: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      NoteSigh(
                          'La taille maximale d’un fichier est un réglage en base, par jeu, avec un défaut. Un fichier plus long est refusé en le nommant, avant tout travail. ${superviseur ? 'Votre profil la règle.' : 'Elle se règle par un profil qui supervise les importations.'}',
                          icone: LucideIcons.gauge),
                      const SizedBox(height: 12),
                      TableauSigh(
                        lignes: [
                          for (final d in visibles) {'id': d.id, 'jeu': d.libelle, 'borne': profil.borne(d.id), 'defaut': ProfilImport.borneParDefaut}
                        ],
                        taillePage: 12,
                        triInitial: 'jeu',
                        nomExport: 'tailles-importation',
                        colonnes: [
                          const ColonneTableau(cle: 'jeu', libelle: 'Jeu d’import'),
                          ColonneTableau(cle: 'borne', libelle: 'Maximum (lignes)', droite: true, texte: (l) => nombre(l['borne'] as num)),
                          ColonneTableau(cle: 'defaut', libelle: 'Défaut (lignes)', droite: true, texte: (l) => nombre(l['defaut'] as num)),
                        ],
                        actionsLigne: (cx, l) => [
                          if (superviseur)
                            BoutonIcone(
                                icone: LucideIcons.pencil,
                                libelle: 'Régler la taille maximale',
                                onPressed: () => _regler(cx, c, visibles.firstWhere((d) => d.id == l['id']), (l['borne'] as num).toInt(), () {})),
                        ],
                      ),
                    ])),
          ]),
        ]);
      },
    );
  }

  /// La carte d'un jeu : un jeu porté se décrit et s'ouvre ; un jeu que le poste ne porte pas encore le DIT (la page existe à la maquette), sans bouton.
  static Widget _carteJeu(ContexteEcran c, ValidationPoste vp, DeclarationImport d, List<Fiche> siens) {
    final j = jeuImportParId(d.id);
    if (j == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(d.libelle, style: const TextStyle(fontWeight: FontWeight.w600, color: JetonsShell.navy900))),
          const BadgeSigh('Non porté au poste', ton: TonSigh.neutre),
        ]),
        const SizedBox(height: 8),
        const Text('Ce jeu existe à la maquette : le poste ne le porte pas encore (lot IMP-C, à porter). Aucun bouton « Importer les données » ne le propose.',
            style: TextStyle(fontSize: 14, color: JetonsShell.slate600)),
        const SizedBox(height: 4),
        Text('Écrit dans : ${d.collections.join(', ')}.', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(j.libelle, style: const TextStyle(fontWeight: FontWeight.w600, color: JetonsShell.navy900))),
        j.supporte
            ? const BadgeSigh('Supporté', ton: TonSigh.succes)
            : (vp.etat('jeux_import', j.ecran)?.enAttente == false
                ? (vp.badge('jeux_import', j.ecran) ?? const BadgeSigh('Validé', ton: TonSigh.succes))
                : const BadgeSigh('Proposition à valider', ton: TonSigh.attention)),
      ]),
      const SizedBox(height: 8),
      Text(j.description, style: const TextStyle(fontSize: 14, color: JetonsShell.slate600)),
      const SizedBox(height: 8),
      Text('Source : ${j.source}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
      const SizedBox(height: 4),
      Text('Écrit dans : ${j.cibles.join(', ')}. ${_dernier(siens)}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
      const SizedBox(height: 12),
      if (c.ouvre == null || c.ouvre!(j.ecran))
        BoutonSigh(libelle: 'Ouvrir', icone: LucideIcons.arrowRight, onPressed: () => c.aller(j.ecran))
      else
        const Text('La page de ce jeu n’est pas ouverte à votre profil.', style: TextStyle(fontSize: 12, color: JetonsShell.slate400)),
    ]);
  }

  static String _dernier(List<Fiche> siens) {
    final l = siens.firstOrNull;
    if (l == null) return 'Aucun lot à ce jour.';
    return 'Dernier lot : ${l['reference']} (${_tonsEtat[l['etat']]?.$1 ?? l['etat']}).';
  }
}
