import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../import/classeur_xlsx.dart';
import '../../import/port_magasin.dart';
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
    PortMagasin(c.magasin, aujourdhui: () => c.aujourdhui, nomAgent: c.agent.nom);

const _tonsEtat = {
  'applique': ('Appliqué', TonSigh.succes),
  'refuse': ('Refusé, rien écrit', TonSigh.danger),
  'annule': ('Annulé', TonSigh.neutre),
};
const _tonsLigne = {
  'valide': ('Valide', TonSigh.succes),
  'avertissement': ('Avertissement', TonSigh.attention),
  'refus': ('Refus', TonSigh.danger),
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
        largeurs: [for (final c in j.colonnes) c.label.length + 4 < 14 ? 14.0 : c.label.length + 4.0], validations: m.validations, colonnesTexte: m.colonnesTexte),
    FeuilleXlsx('Instructions', m.instructions, entete: false, largeurs: const [28, 12, 28, 46, 22, 70]),
    FeuilleXlsx('Listes', m.listes, largeurs: [for (var i = 0; i < m.listes.first.length; i++) 30.0]),
  ]);
}

/// Le classeur du rapport d'erreurs d'un lot ou d'une analyse : la feuille « Erreurs » puis le « Résumé ».
Uint8List classeurRapport(String jeuLibelle, String fichier, String lot, int nbLignes, List<Map<String, Object?>> problemes) =>
    ecrireClasseur([
      FeuilleXlsx('Erreurs', rapportImport(problemes), largeurs: const [8, 26, 24, 14, 24, 70, 70]),
      FeuilleXlsx('Résumé', resumeRapportImport(jeuLibelle, fichier, lot, nbLignes, problemes.length), entete: false, largeurs: const [24, 50]),
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
  if (c.type == 'tarif') return 'montant entier en FCFA ; NC ; tiret (-)';
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

/// L'historique des lots : un tableau filtrable ; « Rapport » pour tout lot qui porte des constats, « Annuler le lot » (droit d'annuler) pour un lot appliqué.
Widget tableauLots(BuildContext contexte, ContexteEcran c, List<Fiche> lots, VoidCallback rafraichir) {
  return TableauSigh(
    lignes: [
      for (final l in lots)
        {
          ...l,
          '_etat': (_tonsEtat[l['etat']]?.$1 ?? '${l['etat']}'),
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
          options: const [OptionChamp('applique', 'Appliqué'), OptionChamp('refuse', 'Refusé'), OptionChamp('annule', 'Annulé')],
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
            final t = _tonsEtat[l['etat']] ?? ('${l['etat']}', TonSigh.neutre);
            return BadgeSigh(t.$1, ton: t.$2);
          }),
    ],
    actionsLigne: (ctx, l) => [
      if (((l['erreurs'] as List?) ?? const []).isNotEmpty)
        BoutonIcone(
            icone: LucideIcons.fileDown,
            libelle: 'Rapport d’erreurs (.xlsx)',
            onPressed: () => _telechargerRapport(contexte, c, l)),
      if (l['etat'] == 'applique' && c.droit.annuler)
        BoutonIcone(
            icone: LucideIcons.undo2,
            libelle: 'Annuler le lot',
            variante: VarianteBouton.danger,
            onPressed: () => _annulerLot(contexte, c, l, rafraichir)),
    ],
  );
}

Future<void> _telechargerRapport(BuildContext contexte, ContexteEcran c, Fiche lot) async {
  final problemes = [for (final p in (lot['erreurs'] as List).cast<Map>()) p.cast<String, Object?>()];
  final octets = classeurRapport('${lot['jeuLibelle'] ?? ''}', '${lot['fichier'] ?? ''}', '${lot['reference']}', (lot['nbLignes'] as num?)?.toInt() ?? 0, problemes);
  await _enregistrer(contexte, 'rapport-${lot['reference']}.xlsx', octets);
}

Future<void> _enregistrer(BuildContext contexte, String nom, Uint8List octets) async {
  final chemin = await SelecteursImport.enregistrer(nom, octets);
  if (!contexte.mounted) return;
  if (chemin != null) ToastsSigh.afficher(contexte, 'Fichier enregistré.', type: TypeToast.succes, detail: chemin);
}

Future<void> _annulerLot(BuildContext contexte, ContexteEcran c, Fiche lot, VoidCallback rafraichir) async {
  final nb = (lot['ecrits'] as List).length;
  final ok = await confirmerSigh(contexte,
      titre: 'Annuler le lot ${lot['reference']} ?',
      message:
          'Les $nb fiches écrites par ce lot seront archivées (RG-14), jamais supprimées. L’annulation est refusée si un acte s’appuie déjà sur elles.',
      libelleOk: 'Annuler le lot',
      dangereux: true);
  if (!ok || !contexte.mounted) return;
  final r = annulerLot(jeuImportParId, lot['id'], 'annulation demandée par ${c.agent.nom}', _port(c));
  if (r.ok) {
    ToastsSigh.afficher(contexte, 'Lot annulé.', type: TypeToast.succes, detail: '${r.archives} fiche(s) archivée(s).');
  } else {
    ToastsSigh.afficher(contexte, 'Annulation refusée.', type: TypeToast.erreur, detail: '${r.motif}. ${r.geste}');
  }
  rafraichir();
}

// --- L'écran d'un jeu -------------------------------------------------------------------------------------------------------------

/// Un jeu d'import : [jeuId] est l'identifiant du moteur (`grand-stock`, `patients`…).
class EcranImportJeu extends StatefulWidget with EcranMaquette {
  const EcranImportJeu(this.jeuId, {super.key});
  final String jeuId;

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
      octets = Uint8List.fromList(utf8.encode(modeleCsvImport(_jeu)));
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
    Fiche? lot;
    if (!a.accepte) lot = consigner(_jeu, a, port);
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
            '${a.nbLignes} ligne(s) du fichier « ${a.fichier} » vont s’écrire en un seul geste, au nom de ${c.agent.nom} (validé par). Le lot pourra être annulé tant qu’aucun acte ne s’appuie dessus.',
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

  Future<void> _rapportAnalyse(ContexteEcran c) async {
    final a = _analyse!;
    final lot = _lotRefuse;
    final ps = [for (final p in a.problemes) p.versJson()];
    await _enregistrer(context, 'rapport-${lot != null ? lot['reference'] : 'analyse'}.xlsx',
        classeurRapport(_jeu.libelle, a.fichier, lot != null ? '${lot['reference']}' : 'non consigné', a.nbLignes, ps));
  }

  Widget _apercu(ContexteEcran c, AnalyseImport a) {
    final ps = a.problemes;
    return CarteSigh(
      titre: 'Résultat de l’analyse du fichier « ${a.fichier} »',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          BadgeSigh('${a.nbLignes} ligne(s) lue(s)', ton: TonSigh.navy),
          BadgeSigh('${a.compte.valides} valide(s)', ton: TonSigh.succes),
          BadgeSigh('${a.compte.avertissements} avertissement(s)', ton: TonSigh.attention),
          BadgeSigh('${a.compte.refus} refus', ton: a.compte.refus > 0 ? TonSigh.danger : TonSigh.neutre),
        ]),
        const SizedBox(height: 12),
        if (a.accepte)
          NoteSigh(
              'Analyse conforme. ${a.nbLignes} ligne(s) peuvent être écrites${a.compte.avertissements > 0 ? ', dont ${a.compte.avertissements} avec avertissement' : ''}. Rien n’est encore écrit.',
              ton: TonSigh.succes,
              icone: LucideIcons.circleCheck)
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
                    {'n': l.n, 'etat': l.etat, 'resume': l.brut.take(3).where((x) => x.isNotEmpty).join(' · '), 'problemes': l.problemes}
                ],
                taillePage: 10,
                triInitial: 'n',
                nomExport: 'apercu-importation',
                filtres: [
                  FiltreTableau(
                      nom: 'etat',
                      libelle: 'État',
                      options: const [OptionChamp('valide', 'Valide'), OptionChamp('avertissement', 'Avertissement'), OptionChamp('refus', 'Refus')],
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
                                      style: TextStyle(fontSize: 12, color: p.estRefus ? JetonsShell.danger700 : JetonsShell.warning700))),
                          ])),
                ],
              )),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (a.accepte && c.droit.editer)
            BoutonSigh(
                libelle: 'Confirmer l’importation (${a.nbLignes} ligne${a.nbLignes > 1 ? 's' : ''})',
                icone: LucideIcons.packageCheck,
                onPressed: _occupe ? null : () => _confirmer(c)),
          if (ps.isNotEmpty)
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
    final lots = c.magasin.collection(collectionLots);
    final vp = ValidationPoste(c);
    // Un jeu en proposition se valide par le moteur commun (famille `jeux_import`, cible = l'écran du jeu) : l'état se LIT, il ne se déduit pas de la constante.
    return ListenableBuilder(
      listenable: Listenable.merge([lots, c.magasin.collection(valCollectionValidations)]),
      builder: (context, _) {
        final port = _port(c);
        final siens = [for (final l in lots.toutes) if (l['jeu'] == j.id) l];
        final appliques = siens.where((l) => l['etat'] == 'applique').toList();
        final ctx = j.contexte(port);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                valeur: j.supporte ? 'Supporté' : 'À valider',
                icone: LucideIcons.badgeCheck,
                ton: j.supporte ? TonSigh.succes : TonSigh.attention),
          ]),
          if (!j.supporte && !(vp.etat('jeux_import', j.ecran)?.enAttente == false)) ...[
            const SizedBox(height: 16),
            NoteSigh('Proposition à valider. ${j.limite}', ton: TonSigh.attention, icone: LucideIcons.circleHelp),
            if (vp.bouton(context, 'jeux_import', j.ecran) case final b?) Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerRight, child: b)),
          ] else if (!j.supporte) ...[
            const SizedBox(height: 16),
            NoteSigh('Jeu validé. ${j.limite ?? ''}', icone: LucideIcons.circleCheck),
            if (vp.badge('jeux_import', j.ecran) case final b?) Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerRight, child: b)),
          ] else if (j.limite != null) ...[
            const SizedBox(height: 16),
            NoteSigh(j.limite!, icone: LucideIcons.info),
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
              ], lignes: [for (final col in j.colonnes) {'c': col}]),
            ]),
          ),
          const SizedBox(height: 16),
          CarteSigh(
            titre: '2. Téléverser et analyser',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                  'L’analyse est complète et ne modifie rien : chaque ligne est contrôlée, un refus est nommé, et c’est vous qui confirmez l’écriture.',
                  style: TextStyle(fontSize: 14, color: JetonsShell.slate600)),
              const SizedBox(height: 12),
              // La commande d'écriture est ABSENTE (jamais grisée) sans le droit d'écrire.
              if (c.droit.editer)
                Row(children: [
                  BoutonSigh(libelle: 'Téléverser un fichier (.xlsx ou .csv)', icone: LucideIcons.upload, onPressed: () => _televerser(c)),
                ]),
            ]),
          ),
          if (_resultat != null) ...[
            const SizedBox(height: 16),
            NoteSigh(_resultat!, ton: _resultatOk ? TonSigh.succes : TonSigh.danger, icone: _resultatOk ? LucideIcons.circleCheck : LucideIcons.octagonAlert),
          ],
          if (_analyse != null) ...[const SizedBox(height: 16), _apercu(c, _analyse!)],
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Historique des lots de ce jeu',
              sansRemplissage: true,
              child: tableauLots(context, c, siens, () => setState(() {}))),
          // LE GRAND STOCK A DEUX FACES SUR LE MÊME ÉCRAN (E2158, corrigé le 06/11/2026) : l'import l'écrit (ci-dessus), la reprise le suit et le
          // valorise (ci-dessous). Le retrait de l'écran de reprise (8800c17) avait fait disparaître du poste la valorisation des références sans prix.
          if (j.id == 'grand-stock') ...[
            const SizedBox(height: 24),
            const Text('Stock repris : traçabilité et valorisation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JetonsShell.navy900)),
            const SizedBox(height: 12),
            const NoteSigh(
                'Le stock initial n’a pas été saisi manuellement : il provient de l’import de l’inventaire « Grand Stock ». Chaque article conserve sa source, son lot d’import et sa quantité d’origine, afin de distinguer les données reprises des mouvements opérationnels ultérieurs. Les références que le document ne tarife pas se valorisent ici, à part, datées et signées.',
                icone: LucideIcons.history),
            const SizedBox(height: 16),
            const EcranReprise(),
          ],
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
      'Un import n’invente rien : il écrit ce que le fichier porte, après une analyse ligne par ligne. Un refus se nomme (ligne, colonne, valeur, motif, geste). Un fichier refusé est consigné et n’écrit rien. Un lot s’annule en archivant ses fiches (RG-14).';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final lots = c.magasin.collection(collectionLots);
    final vp = ValidationPoste(c);
    return ListenableBuilder(
      listenable: Listenable.merge([lots, c.magasin.collection(valCollectionValidations)]),
      builder: (context, _) {
        final tous = lots.toutes;
        final visibles = [for (final j in jeuxImport) if (c.ouvre == null || c.ouvre!(j.ecran)) j];
        int compte(String e) => tous.where((l) => l['etat'] == e).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Jeux d’import', valeur: '${jeuxImport.length}', icone: LucideIcons.files, ton: TonSigh.navy),
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
                      for (final j in visibles)
                        SizedBox(
                            width: 360,
                            child: CarteSigh(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                              Text(
                                  'Écrit dans : ${j.cibles.join(', ')}. ${_dernier(tous, j.id)}',
                                  style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
                              const SizedBox(height: 12),
                              BoutonSigh(libelle: 'Ouvrir', icone: LucideIcons.arrowRight, onPressed: () => c.aller(j.ecran)),
                            ]))),
                    ])),
            OngletDef(
                id: 'historique',
                libelle: 'Historique des lots',
                compte: tous.length,
                construire: (ctx) => tableauLots(ctx, c, [
                      for (final l in tous)
                        if (visibles.any((j) => j.id == l['jeu'])) l
                    ], () {})),
          ]),
        ]);
      },
    );
  }

  static String _dernier(List<Fiche> tous, String jeu) {
    final l = tous.where((x) => x['jeu'] == jeu).firstOrNull;
    if (l == null) return 'Aucun lot à ce jour.';
    return 'Dernier lot : ${l['reference']} (${_tonsEtat[l['etat']]?.$1 ?? l['etat']}).';
  }
}
