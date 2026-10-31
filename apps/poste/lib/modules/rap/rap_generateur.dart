import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rap_commun.dart';

/// `rapports-generateur` — « Générateur de rapports » : la composition d'un rapport personnalisé — périmètre, période, sections d'indicateurs et mise en
/// forme — puis prévisualisation et impression sur le papier à en-tête officiel. Quatre modèles enregistrés préchargent le formulaire.
///
/// Les indicateurs sont CALCULÉS depuis les registres du poste (`rapDonneesSection`), jamais saisis. L'écran PRODUIT une pièce : il est fermé aux rôles
/// qui n'écrivent pas (vague 67). Un refus se nomme : aucune section cochée, formulaire invalide.
class EcranRapGenerateur extends StatelessWidget with EcranMaquette {
  const EcranRapGenerateur({super.key});

  @override
  String get titre => 'Générateur de rapports';

  @override
  String get description =>
      'Composition d’un rapport personnalisé : périmètre, période, indicateurs et mise en forme.';

  @override
  Widget build(BuildContext context) => const _VueGenerateur();
}

class _VueGenerateur extends StatefulWidget {
  const _VueGenerateur();
  @override
  State<_VueGenerateur> createState() => _VueGenerateurState();
}

class _VueGenerateurState extends State<_VueGenerateur> {
  ControleurFormulaire? _f;
  final Map<String, bool> _coche = {
    for (final s in rapSections) s.id: s.id == 'activite' || s.id == 'financier'
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = ContexteEcran.of(context);
    // La date de début est celle de la maquette (1ᵉʳ août 2026, écrite en dur dans `rapports.js`) : portée fidèlement, signalée (E1043).
    _f ??= ControleurFormulaire([
      const ChampDef(
          nom: 'titre',
          libelle: 'Titre du rapport',
          requis: true,
          col: ColChamp.plein),
      const ChampDef(
          nom: 'sousTitre', libelle: 'Sous-titre', col: ColChamp.plein),
      ChampDef(
          nom: 'destinataire',
          libelle: 'Destinataire',
          type: TypeChamp.select,
          options: [
            const OptionChamp('', '—'),
            for (final d in rapDestinataires) OptionChamp(d)
          ]),
      ChampDef(
          nom: 'periode',
          libelle: 'Période',
          type: TypeChamp.select,
          requis: true,
          options: [for (final p in rapPeriodesRapport) OptionChamp(p)]),
      const ChampDef(nom: 'dateDebut', libelle: 'Du', type: TypeChamp.date),
      const ChampDef(nom: 'dateFin', libelle: 'Au', type: TypeChamp.date),
      ChampDef(
          nom: 'filigrane',
          libelle: 'Filigrane',
          type: TypeChamp.select,
          options: [
            const OptionChamp('', '—'),
            for (final f in rapFiligranes) OptionChamp(f)
          ]),
    ], {
      'titre': 'Rapport d’activité',
      'sousTitre': 'Période : ${moisAnnee(c.aujourdhui)}',
      'periode': 'Mensuelle',
      'dateDebut': '2026-08-01',
      'dateFin': iso(c.aujourdhui),
    });
  }

  @override
  void dispose() {
    _f?.dispose();
    super.dispose();
  }

  void _charger(BuildContext ctx, RapModele m) {
    final r = rapChargerModele(m);
    _f!.poser('titre', r.titre);
    _f!.poser('destinataire', r.destinataire);
    setState(() {
      for (final s in rapSections) {
        _coche[s.id] = r.sections.contains(s.id);
      }
    });
    ToastsSigh.afficher(ctx, 'Modèle « ${m.nom} » chargé.',
        type: TypeToast.info);
  }

  RapSources _sources(Magasin m) => RapSources(
        patients: m.collection('patients').actives,
        consultations: m.collection('consultations').actives,
        admissions: m.collection('admissions').actives,
        factures: m.collection('factures').actives,
        produits: m.collection('produits').actives,
        lots: m.collection('lots').actives,
        personnel: m.collection('personnel').actives,
        ecritures: m.collection('ecritures').actives,
        demandesAnalyses: m.collection('demandesAnalyses').actives,
        // D.ANALYSES et D.ASSUREURS de la maquette sont des référentiels statiques ; au poste ce sont les collections `analyses` et `assureurs`.
        nbAnalyses: m.collection('analyses').actives.length,
        nbAssureurs: m.collection('assureurs').actives.length,
      );

  void _generer(BuildContext ctx, ContexteEcran c) {
    final v = _f!.valider();
    if (v == null) {
      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.',
          type: TypeToast.erreur);
      return;
    }
    final cochees = [
      for (final s in rapSections)
        if (_coche[s.id] == true) s.id
    ];
    final refus =
        rapRefusGeneration(titre: '${v['titre']}', sectionsCochees: cochees);
    if (refus != null) {
      ToastsSigh.afficher(ctx, refus, type: TypeToast.erreur);
      return;
    }
    final r = rapComposerRapport(
        titre: '${v['titre']}',
        sousTitre: '${v['sousTitre'] ?? ''}',
        destinataire: '${v['destinataire'] ?? ''}',
        periode: '${v['periode']}',
        dateDebut: v['dateDebut'],
        dateFin: v['dateFin'],
        filigrane: '${v['filigrane'] ?? ''}',
        sectionsCochees: cochees,
        utilisateur: c.utilisateur,
        sources: _sources(c.magasin));
    String jour(Object? d) => rapMs(d) == null
        ? ''
        : dateFR(DateTime.fromMillisecondsSinceEpoch(rapMs(d)!, isUtc: true));
    rapApercu(
        ctx,
        PieceA4(
          titre: r.titre,
          sousTitre: r.sousTitre,
          filigrane: r.filigrane,
          reference: rapReference(c),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: r.cartouche,
          // Les filtres EN FORCE de la page : listes d'abord, puis les dates (`filtresDeLaPage()`).
          filtres: rapFiltresEnForce([
            ('Destinataire', '${v['destinataire'] ?? ''}'),
            ('Période *', '${v['periode']}'),
            ('Filigrane', '${v['filigrane'] ?? ''}'),
            ('Du', jour(v['dateDebut'])),
            ('Au', jour(v['dateFin'])),
          ]),
          blocs: [
            for (final (intitule, lignes) in r.sections) ...[
              BlocTexte(intitule.toUpperCase(), gras: true),
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Indicateur', valeur: (x) => x['k']),
                ColonneEtat(
                    libelle: 'Valeur', droite: true, valeur: (x) => x['v']),
              ], lignes: [
                for (final (k, val) in lignes) {'k': k, 'v': val}
              ])),
            ]
          ],
          signatures: [
            Signature('Le Rédacteur', nom: c.utilisateur),
            const Signature('La Directrice Administrative',
                nom: 'TAKI Alimatou'),
            const Signature('Le Directeur Médical',
                nom: 'BASSONGUI Chabi Séko'),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final principal =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Paramètres du rapport',
          child: FormulaireSigh(controleur: _f!)),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Sections à inclure',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, s) in rapSections.indexed)
              Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  child: InkWell(
                      key: Key('rap:section:${s.id}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(
                          () => _coche[s.id] = !(_coche[s.id] ?? false)),
                      child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: JetonsShell.slate200)),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                        value: _coche[s.id] ?? false,
                                        onChanged: (v) => setState(
                                            () => _coche[s.id] = v == true),
                                        activeColor: JetonsShell.navy900,
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap)),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(s.libelle,
                                        style: const TextStyle(
                                            color: JetonsShell.slate700,
                                            fontSize: 14,
                                            height: 20 / 14))),
                              ])))),
          ])),
    ]);
    final lateral =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Génération',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BoutonSigh(
                libelle: 'Prévisualiser et imprimer',
                icone: LucideIcons.printer,
                onPressed: () => _generer(context, c)),
            const SizedBox(height: 8),
            const NoteSigh(
                'Le rapport reprend automatiquement l’entête et le pied de page officiels de la clinique.'),
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Modèles enregistrés',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, m) in rapModeles.indexed)
              Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  // Le bouton de la maquette se lit « nom » + « destinataire » SANS espace (deux blocs d'un même `<button>`, écart E1044) : l'infobulle
                  // porte cette forme jointe, qui est celle que la fiche extraite attend ; la carte affiche les deux lignes.
                  child: Tooltip(
                      message: '${m.nom}${m.destinataire}',
                      waitDuration: const Duration(milliseconds: 600),
                      child: InkWell(
                          key: Key('rap:modele:$i'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _charger(context, m),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: JetonsShell.slate200)),
                              child: Row(children: [
                                Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                        color: TonSigh.navy.fond50,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Icon(LucideIcons.fileText,
                                        size: 16,
                                        color: TonSigh.navy.icone600)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(m.nom,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: JetonsShell.slate800,
                                              fontSize: 14,
                                              height: 20 / 14,
                                              fontWeight: FontWeight.w500)),
                                      Text(m.destinataire,
                                          style: const TextStyle(
                                              color: JetonsShell.slate400,
                                              fontSize: 12,
                                              height: 16 / 12)),
                                    ])),
                              ]))))),
          ])),
    ]);
    return LayoutBuilder(builder: (context, k) {
      if (k.maxWidth < 1024) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [principal, const SizedBox(height: 16), lateral]);
      }
      final u = (k.maxWidth - 32) / 3;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: u * 2 + 16, child: principal),
        const SizedBox(width: 16),
        SizedBox(width: u, child: lateral),
      ]);
    });
  }
}
