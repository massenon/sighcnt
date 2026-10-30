import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'hos_commun.dart';

/// `m3-feuille-temperature` — « Feuille de température » : le relevé numérique des constantes d'un patient HOSPITALISÉ (tension, fréquence cardiaque,
/// saturation, diurèse, poids, taille, fréquence respiratoire, traitement), la courbe de température (axe borné 35–41 °C), la courbe cardiaque et la
/// saturation, le tableau des relevés et la feuille imprimable. Saisir un relevé est un geste clinique : la commande est ABSENTE sans le droit
/// d'écrire (RG-13), « Saisir le premier relevé » comprise (E371). Un relevé s'archive, il ne se supprime pas (RG-14).
class EcranFeuilleTemperature extends StatefulWidget with EcranMaquette {
  const EcranFeuilleTemperature({super.key});

  @override
  String get titre => 'Feuille de température';

  @override
  String get description =>
      'Relevé numérique des constantes : tension, fréquence cardiaque, saturation, diurèse, poids, taille, fréquence respiratoire et traitement.';

  /// Plage physiologique de la température saisie (°C).
  static const temperatureMin = 30, temperatureMax = 45;

  /// Un nombre saisi (virgule ou point) ; vide ou illisible → `null`. Un entier reste un entier (`Number('80')` s'écrit 80).
  static num? nombreSaisi(Object? v) {
    final s = '${v ?? ''}'.trim().replaceAll(',', '.');
    return s.isEmpty ? null : num.tryParse(s);
  }

  /// Les relevés d'une admission, du plus récent au plus ancien (date puis heure).
  static List<Fiche> relevesDe(Iterable<Fiche> releves, Object? admissionId) => trierPar(
      [for (final r in releves) if (r['admissionId'] == admissionId) r], (r) => '${r['date']} ${r['heure']}',
      descendant: true);

  /// La fiche enregistrée par « Enregistrer » (champs vides → `null`, comme `f.collect()` de la maquette).
  static Fiche construireReleve(Map<String, Object?> v, Object? admissionId, String saisiPar) => {
        'statut': 'actif',
        'date': v['date'],
        'heure': v['heure'],
        'temperature': nombreSaisi(v['temperature']),
        'tension': v['tension'],
        'fc': nombreSaisi(v['fc']),
        'spo2': nombreSaisi(v['spo2']),
        'fr': nombreSaisi(v['fr']),
        'diurese': nombreSaisi(v['diurese']),
        'poids': nombreSaisi(v['poids']),
        'taille': nombreSaisi(v['taille']),
        'traitement': v['traitement'],
        'admissionId': admissionId,
        'saisiPar': saisiPar,
      };

  static String _n(Object? v) => v is num ? hosNum(v) : ('${v ?? ''}'.isEmpty ? '—' : '$v');

  @override
  State<EcranFeuilleTemperature> createState() => _EtatTemperature();
}

class _EtatTemperature extends State<EcranFeuilleTemperature> {
  ControleurFormulaire? _sel;
  String _signature = '';

  /// Le sélecteur de patient (`U.combo`) : reconstruit si la liste des patients hospitalisés change.
  ControleurFormulaire _selecteur(List<Fiche> ec) {
    final sig = ec.map((a) => a['id']).join('|');
    if (_sel == null || sig != _signature) {
      final ancien = _sel?['admissionId'];
      _signature = sig;
      _sel = ControleurFormulaire([
        ChampDef(
            nom: 'admissionId',
            libelle: 'Patient hospitalisé',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [for (final a in ec) OptionChamp('${a['id']}', '${a['patient']}')])
      ], {
        'admissionId': ec.any((a) => a['id'] == ancien) ? ancien : (ec.isEmpty ? null : ec.first['id'])
      });
    }
    return _sel!;
  }

  @override
  void dispose() {
    _sel?.dispose();
    super.dispose();
  }

  Color _couleurTemperature(num? t) =>
      t == null ? JetonsShell.slate700 : (t >= 38 ? JetonsShell.danger600 : (t < 36 ? JetonsShell.info600 : JetonsShell.slate700));

  void _saisie(BuildContext ctx, Fiche courant) {
    final c = ContexteEcran.of(ctx);
    final col = c.magasin.collection('releves');
    final ctl = ControleurFormulaire(const [
      ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
      ChampDef(nom: 'heure', libelle: 'Heure', requis: true, indicatif: 'HH:mm', valider: validerHeure),
      ChampDef(nom: 'temperature', libelle: 'Température (°C)', type: TypeChamp.nombre, requis: true, valider: _validerTemperature),
      ChampDef(nom: 'tension', libelle: 'Tension artérielle', requis: true, indicatif: '12/8'),
      ChampDef(nom: 'fc', libelle: 'Fréquence cardiaque (bpm)', type: TypeChamp.nombre, requis: true),
      ChampDef(nom: 'spo2', libelle: 'Saturation SpO₂ (%)', type: TypeChamp.nombre, requis: true),
      ChampDef(nom: 'fr', libelle: 'Fréquence respiratoire', type: TypeChamp.nombre),
      ChampDef(nom: 'diurese', libelle: 'Diurèse (ml)', type: TypeChamp.nombre),
      ChampDef(nom: 'poids', libelle: 'Poids (kg)', type: TypeChamp.nombre),
      ChampDef(nom: 'taille', libelle: 'Taille (cm)', type: TypeChamp.nombre),
      ChampDef(nom: 'traitement', libelle: 'Traitement administré', col: ColChamp.plein),
    ], {
      'date': iso(c.aujourdhui),
      'heure': '08:00',
    });
    afficherModale<void>(ctx,
        titre: 'Nouveau relevé de constantes',
        sousTitre: '${courant['patient']} — lit ${courant['lit']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    fermer();
                    final r = col.inserer(EcranFeuilleTemperature.construireReleve(v, courant['id'], c.utilisateur), prefixe: 'REL');
                    ToastsSigh.afficher(ctx, 'Relevé enregistré.', type: TypeToast.succes, annuler: r.annuler);
                  }),
            ]);
  }

  static String? _validerTemperature(Object? v, Map<String, Object?> _) {
    final t = EcranFeuilleTemperature.nombreSaisi(v);
    if (t == null) return null;
    return (t < EcranFeuilleTemperature.temperatureMin || t > EcranFeuilleTemperature.temperatureMax)
        ? 'Valeur hors plage physiologique (30–45 °C).'
        : null;
  }

  void _imprimer(BuildContext ctx, Fiche courant, List<Fiche> rel) {
    final c = ContexteEcran.of(ctx);
    final asc = trierPar(rel, (r) => '${r['date']} ${r['heure']}');
    afficherApercu(
        ctx,
        PieceA4(
            titre: 'Feuille de température',
            sousTitre: 'Suivi des constantes — hospitalisation',
            cartouche: [
              ('Patient', '${courant['patient']}'),
              ('Dossier', '${courant['patientCode']}'),
              ('Lit', '${courant['lit']}'),
              ('Chambre', hosLibelleTypeChambre(courant['typeChambre'])),
              ('Date d’entrée', jourFR(courant['dateEntree'])),
              ('Diagnostic', '${courant['diagnosticEntree'] ?? ''}'),
            ],
            blocs: asc.isEmpty
                ? [const BlocTexte('Aucun relevé enregistré.', italique: true)]
                : [
                    BlocTableau(TableauEtat(colonnes: [
                      ColonneEtat(libelle: 'Date', valeur: (r) => jourFR(r['date'])),
                      ColonneEtat(libelle: 'Heure', valeur: (r) => r['heure']),
                      ColonneEtat(libelle: 'T° (°C)', droite: true, valeur: (r) => EcranFeuilleTemperature._n(r['temperature'])),
                      ColonneEtat(libelle: 'TA', droite: true, valeur: (r) => r['tension']),
                      ColonneEtat(libelle: 'FC', droite: true, valeur: (r) => EcranFeuilleTemperature._n(r['fc'])),
                      ColonneEtat(libelle: 'SpO₂', droite: true, valeur: (r) => EcranFeuilleTemperature._n(r['spo2'])),
                      ColonneEtat(libelle: 'FR', droite: true, valeur: (r) => EcranFeuilleTemperature._n(r['fr'])),
                      ColonneEtat(libelle: 'Diurèse', droite: true, valeur: (r) => EcranFeuilleTemperature._n(r['diurese'])),
                      ColonneEtat(libelle: 'Traitement', valeur: (r) => r['traitement']),
                    ], lignes: asc))
                  ],
            signatures: [
              Signature('L’Infirmier traitant', nom: '${courant['infirmier'] ?? ''}'),
              const Signature('Le Médecin'),
            ],
            reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: c.aujourdhui));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final adm = c.magasin.collection('admissions');
    final releves = c.magasin.collection('releves');
    return ListenableBuilder(
      listenable: Listenable.merge([adm, releves]),
      builder: (context, _) {
        final ec = hosEnCours(adm.actives);
        if (ec.isEmpty) {
          return CarteSigh(
              child: VideSigh('Aucun patient hospitalisé actuellement.',
                  indice: 'La feuille de température se saisit pour les patients en cours d’hospitalisation.',
                  icone: LucideIcons.bed,
                  action: BoutonSigh(
                      libelle: 'Créer une admission',
                      icone: LucideIcons.userPlus,
                      onPressed: () => c.aller('m3-admissions'))));
        }
        final sel = _selecteur(ec);
        return ListenableBuilder(
          listenable: sel,
          builder: (context, _) {
            final courant = ec.firstWhere((a) => a['id'] == sel['admissionId'], orElse: () => ec.first);
            final rel = EcranFeuilleTemperature.relevesDe(releves.actives, courant['id']);
            final derniers = rel.take(24).toList().reversed.toList();
            String etiq(Fiche r) {
              final d = hosVersDate(r['date']);
              return '${d == null ? '' : dateFR(d).substring(0, 5)} ${r['heure']}';
            }

            num serie(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CarteSigh(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 512),
                            child: FormulaireSigh(controleur: sel)))),
                const SizedBox(width: 12),
                if (c.droit.editer) ...[
                  BoutonSigh(libelle: 'Nouveau relevé', icone: LucideIcons.plus, onPressed: () => _saisie(context, courant)),
                  const SizedBox(width: 12),
                ],
                BoutonSigh(
                    libelle: 'Imprimer la feuille',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _imprimer(context, courant, rel)),
              ])),
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Patient',
                  child: DescListeSigh([
                    ('Patient', courant['patient']),
                    ('Dossier', texteMono('${courant['patientCode']}')),
                    ('Lit', courant['lit']),
                    ('Chambre', hosLibelleTypeChambre(courant['typeChambre'])),
                    ('Entrée', jourFR(courant['dateEntree'])),
                    ('Séjour', '${hosDureeSejour(courant, c.aujourdhui)} jour(s)'),
                    ('Diagnostic', courant['diagnosticEntree']),
                    ('Infirmier référent', courant['infirmier']),
                  ])),
              const SizedBox(height: 16),
              if (rel.isEmpty)
                CarteSigh(
                    child: VideSigh('Aucun relevé enregistré pour ce patient.',
                        icone: LucideIcons.thermometer,
                        action: c.droit.editer
                            ? BoutonSigh(
                                libelle: 'Saisir le premier relevé',
                                icone: LucideIcons.plus,
                                onPressed: () => _saisie(context, courant))
                            : null))
              else ...[
                deuxColonnes(
                  CarteSigh(
                      titre: 'Courbe de température (°C)',
                      child: GraphiqueLigne(min: 35, max: 41, etiquettes: [
                        for (final r in derniers) etiq(r)
                      ], series: [
                        SerieGraphique('Température', [for (final r in derniers) serie(r['temperature'])],
                            couleur: JetonsShell.danger500)
                      ])),
                  CarteSigh(
                      titre: 'Fréquence cardiaque et saturation',
                      child: GraphiqueLigne(etiquettes: [
                        for (final r in derniers) etiq(r)
                      ], series: [
                        SerieGraphique('FC (bpm)', [for (final r in derniers) serie(r['fc'])],
                            couleur: JetonsShell.navy900, aire: false),
                        SerieGraphique('SpO₂ (%)', [for (final r in derniers) serie(r['spo2'])],
                            couleur: JetonsShell.success500, aire: false),
                      ])),
                ),
                const SizedBox(height: 16),
                TableauSigh(
                  titre: 'Relevés de constantes',
                  lignes: rel,
                  recherche: false,
                  nomExport: 'feuille-temperature',
                  taillePage: 12,
                  colonnes: [
                    ColonneTableau(
                        cle: 'date',
                        libelle: 'Date',
                        sansCoupure: true,
                        texte: (r) => jourFR(r['date'])),
                    const ColonneTableau(cle: 'heure', libelle: 'Heure', sansCoupure: true),
                    ColonneTableau(
                        cle: 'temperature',
                        libelle: 'T° (°C)',
                        droite: true,
                        texte: (r) => EcranFeuilleTemperature._n(r['temperature']),
                        rendu: (_, r) {
                          final t = r['temperature'] is num ? r['temperature'] as num : null;
                          return Text(EcranFeuilleTemperature._n(r['temperature']),
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 20 / 14,
                                  color: _couleurTemperature(t),
                                  fontWeight: t != null && (t >= 38 || t < 36) ? FontWeight.w600 : FontWeight.w400));
                        }),
                    const ColonneTableau(cle: 'tension', libelle: 'TA', droite: true),
                    ColonneTableau(cle: 'fc', libelle: 'FC', droite: true, texte: (r) => EcranFeuilleTemperature._n(r['fc'])),
                    ColonneTableau(
                        cle: 'spo2',
                        libelle: 'SpO₂',
                        droite: true,
                        texte: (r) => r['spo2'] == null ? '—' : '${EcranFeuilleTemperature._n(r['spo2'])} %',
                        rendu: (_, r) {
                          final s = r['spo2'] is num ? r['spo2'] as num : null;
                          return Text(r['spo2'] == null ? '—' : '${EcranFeuilleTemperature._n(r['spo2'])} %',
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 20 / 14,
                                  color: s != null && s < 94 ? JetonsShell.danger600 : JetonsShell.slate700,
                                  fontWeight: s != null && s < 94 ? FontWeight.w600 : FontWeight.w400));
                        }),
                    ColonneTableau(cle: 'fr', libelle: 'FR', droite: true, texte: (r) => EcranFeuilleTemperature._n(r['fr'])),
                    ColonneTableau(
                        cle: 'diurese', libelle: 'Diurèse (ml)', droite: true, texte: (r) => EcranFeuilleTemperature._n(r['diurese'])),
                    ColonneTableau(
                        cle: 'poids', libelle: 'Poids (kg)', droite: true, texte: (r) => EcranFeuilleTemperature._n(r['poids'])),
                    const ColonneTableau(cle: 'traitement', libelle: 'Traitement'),
                    const ColonneTableau(cle: 'saisiPar', libelle: 'Saisi par'),
                  ],
                  actionsLigne: (ctx, r) => [
                    if (c.droit.annuler)
                      BoutonIcone(
                          icone: LucideIcons.trash2,
                          libelle: 'Archiver ce relevé',
                          onPressed: () {
                            final annuler = releves.archiver(r['id']);
                            ToastsSigh.afficher(ctx, 'Relevé archivé.', type: TypeToast.succes, annuler: annuler);
                          }),
                  ],
                ),
              ],
            ]);
          },
        );
      },
    );
  }
}
