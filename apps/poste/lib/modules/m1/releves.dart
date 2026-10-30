import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m1.dart';

String _t(Object? v, [String vide = '—']) => patVrai(v) ? '$v' : vide;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m1-antecedents
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranAntecedents extends StatelessWidget with EcranMaquette {
  const EcranAntecedents({super.key});

  @override
  String get description =>
      'Recensement des antécédents médicaux, chirurgicaux et des allergies connues, consultables depuis toute prescription.';

  @override
  String get regle =>
      'Les éléments saisis ici appartiennent au dossier du patient : ils sont repris dans la fiche patient, à la prescription (M2) et à la dispensation en pharmacie (M6).';

  /// Les mêmes champs que la section « Éléments médicaux » de la fiche patient — des LISTES (écart E304).
  static List<ChampDef> champs() => [
        ChampDef(
            nom: 'antecedents',
            libelle: 'Antécédents',
            type: TypeChamp.multiselect,
            col: ColChamp.plein,
            options: [for (final a in patAntecedents) if (a != 'Aucun antécédent notable') OptionChamp(a)]),
        const ChampDef(nom: 'antecedentsAutres', libelle: 'Autres antécédents', col: ColChamp.plein),
        ChampDef(
            nom: 'allergies',
            libelle: 'Allergies connues',
            type: TypeChamp.multiselect,
            col: ColChamp.plein,
            options: [for (final a in patAllergies) if (a != 'Aucune allergie connue') OptionChamp(a)]),
        const ChampDef(nom: 'traitementEnCours', libelle: 'Traitement en cours', col: ColChamp.plein),
        ChampDef(
            nom: 'groupeSanguin',
            libelle: 'Groupe sanguin',
            type: TypeChamp.select,
            options: [for (final g in patGroupesSanguins) OptionChamp(g)]),
      ];

  void _modifier(BuildContext ctx, ContexteEcran c, Fiche p) {
    final defs = champs();
    final ctl = ControleurFormulaire(defs, {
      ...valeursFormulaire(p),
      'antecedents': patListe(p['antecedents']),
      'allergies': patListe(p['allergies']),
    });
    afficherModale<void>(ctx,
        titre: 'Antécédents et allergies',
        sousTitre: '${p['nom']} ${p['prenom']} — ${p['code']}',
        taille: TailleModale.md,
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
                    final annuler = c.magasin.collection('patients').mettreAJour(p['id'], v);
                    ToastsSigh.afficher(ctx, 'Éléments médicaux enregistrés.',
                        type: TypeToast.succes, detail: '${p['code']}', annuler: annuler);
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('patients');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final k = patKpisAntecedents(rows);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Dossiers renseignés', valeur: nombre(k.renseignes), icone: LucideIcons.clipboardList),
              KpiSigh(libelle: 'Allergies déclarées', valeur: nombre(k.allergies), icone: LucideIcons.triangleAlert, ton: TonSigh.attention),
              KpiSigh(libelle: 'Antécédents à risque', valeur: nombre(k.risque), icone: LucideIcons.heartPulse, ton: TonSigh.danger),
              KpiSigh(libelle: 'Sans antécédent notable', valeur: nombre(k.sansAntecedent), icone: LucideIcons.check, ton: TonSigh.succes),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'Les allergies déclarées sont remontées automatiquement à la prescription (M2) et à la dispensation en pharmacie (M6) afin de bloquer toute délivrance contre-indiquée.'),
            const SizedBox(height: 16),
            TableauSigh(
              titre: 'Antécédents et allergies par dossier',
              lignes: rows,
              nomExport: 'antecedents',
              taillePage: 12,
              libelleRecherche: 'Patient, code dossier, antécédent…',
              filtres: [
                FiltreTableau(
                    nom: 'allergies',
                    libelle: 'Allergie',
                    options: [for (final a in patAllergies) OptionChamp(a)],
                    correspond: (r, v) => patFiltreAllergie(r, v)),
                FiltreTableau(
                    nom: 'antecedents',
                    libelle: 'Antécédent',
                    options: [for (final a in patAntecedents) OptionChamp(a)],
                    correspond: (r, v) => patFiltreAntecedent(r, v)),
              ],
              colonnes: [
                ColonneTableau(cle: 'code', libelle: 'Dossier', sansCoupure: true, rendu: (_, r) => enMono('${r['code']}'), texte: (r) => '${r['code']}'),
                ColonneTableau(
                    cle: 'nom', libelle: 'Patient', valeur: (r) => '${r['nom']} ${r['prenom']}', texte: (r) => '${r['nom']} ${r['prenom']}'),
                const ColonneTableau(cle: 'groupeSanguin', libelle: 'Groupe', droite: true),
                ColonneTableau(
                    cle: 'antecedents',
                    libelle: 'Antécédents',
                    texte: (r) => '${patTexteListe(r['antecedents'], 'Aucun antécédent notable')} ${r['antecedentsAutres'] ?? ''}',
                    rendu: (_, r) {
                      if (patListe(r['antecedents']).isEmpty) {
                        return Text('Aucun antécédent notable', style: styleM1(t: 12, c: JetonsShell.slate400));
                      }
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        patRisque(r)
                            ? BadgeSigh(patTexteListe(r['antecedents']), ton: TonSigh.danger)
                            : Text(patTexteListe(r['antecedents']), style: styleM1()),
                        if (patVrai(r['antecedentsAutres'])) Text('${r['antecedentsAutres']}', style: styleM1(t: 12, c: JetonsShell.slate400)),
                      ]);
                    }),
                ColonneTableau(
                    cle: 'allergies',
                    libelle: 'Allergies',
                    texte: (r) => patTexteListe(r['allergies'], 'Aucune allergie connue'),
                    rendu: (_, r) => patAllergique(r)
                        ? BadgeSigh(patTexteListe(r['allergies']), ton: TonSigh.attention)
                        : Text('Aucune allergie connue', style: styleM1(t: 12, c: JetonsShell.slate400))),
                ColonneTableau(cle: 'traitementEnCours', libelle: 'Traitement en cours', texte: (r) => _t(r['traitementEnCours'])),
                ColonneTableau(
                    cle: '_risque',
                    libelle: 'Risque',
                    droite: true,
                    triable: false,
                    texte: (r) => patRisque(r) ? 'Élevé' : 'Standard',
                    rendu: (_, r) => patRisque(r) ? const BadgeSigh('Élevé', ton: TonSigh.danger) : const BadgeSigh('Standard')),
              ],
              // Le clic sur la ligne ouvre le formulaire : sans ce garde-fou, il contournerait le bouton retiré.
              alClicLigne: (r) {
                if (!c.droit.editer) {
                  ToastsSigh.afficher(context, 'Modification impossible.',
                      type: TypeToast.erreur, detail: 'Votre profil consulte les antécédents sans les modifier.');
                  return;
                }
                _modifier(context, c, r);
              },
              actionsLigne: (ctx, r) => [
                if (c.droit.editer)
                  BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier les antécédents', onPressed: () => _modifier(ctx, c, r)),
                BoutonIcone(icone: LucideIcons.user, libelle: 'Ouvrir la fiche patient', onPressed: () => c.aller('m1-patient-profil')),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Source : Dossier patient — les éléments médicaux sont saisis par le personnel soignant habilité (RG-13).',
                style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
          ]);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m1-constantes
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranConstantes extends StatelessWidget with EcranMaquette {
  const EcranConstantes({super.key});

  @override
  String get description => 'Température, poids, taille, tension, SpO₂ et pouls relevés dès l’arrivée du patient.';

  @override
  String get regle =>
      'Les constantes prises à l’accueil alimentent la feuille de température et la fiche de surveillance : une seule collection, deux présentations. L’accueil relève des constantes — ce n’est pas une donnée clinique interprétée, et cela reste dans son périmètre.';

  static List<ChampDef> champs(ContexteEcran c, Fiche? e) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: optionsPatientsM1(c.magasin)),
        const ChampDef(nom: 'dateReleve', libelle: 'Date du relevé', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'heureReleve', libelle: 'Heure du relevé (hh:mm)', requis: true),
        const ChampDef(
            nom: 'moment',
            libelle: 'Moment',
            type: TypeChamp.select,
            requis: true,
            options: [OptionChamp('matin', 'Matin'), OptionChamp('midi', 'Midi'), OptionChamp('soir', 'Soir')],
            aide: 'La feuille de température comporte trois colonnes par jour : matin, midi, soir.'),
        const ChampDef.section('Constantes'),
        ChampDef(nom: 'temperature', libelle: 'Température (°C)', type: TypeChamp.nombre, valider: _borne(30, 45)),
        ChampDef(nom: 'tensionSys', libelle: 'Tension systolique (cmHg)', type: TypeChamp.nombre, valider: _borne(4, 30)),
        ChampDef(nom: 'tensionDia', libelle: 'Tension diastolique (cmHg)', type: TypeChamp.nombre, valider: _borne(2, 20)),
        ChampDef(nom: 'pouls', libelle: 'Pouls (bpm)', type: TypeChamp.nombre, valider: _borne(30, 220)),
        ChampDef(nom: 'fr', libelle: 'Fréquence respiratoire (/min)', type: TypeChamp.nombre, valider: _borne(5, 70)),
        ChampDef(nom: 'spo2', libelle: 'SpO₂ (%)', type: TypeChamp.nombre, valider: _borne(50, 100)),
        ChampDef(nom: 'diurese', libelle: 'Diurèse (L)', type: TypeChamp.nombre, valider: _borne(0, 5)),
        const ChampDef.section('Mensurations'),
        ChampDef(nom: 'poids', libelle: 'Poids (kg)', type: TypeChamp.nombre, valider: _borne(0, 250)),
        ChampDef(nom: 'taille', libelle: 'Taille (cm)', type: TypeChamp.nombre, valider: _borne(20, 230)),
        const ChampDef(nom: 'releveePar', libelle: 'Relevé par', requis: true),
      ];

  static String? Function(Object?, Map<String, Object?>) _borne(num min, num max) => (v, _) {
        final n = num.tryParse('$v'.replaceAll(',', '.'));
        return n == null || n < min || n > max ? 'Valeur comprise entre $min et $max.' : null;
      };

  static Fiche _transformer(ContexteEcran c, Map<String, Object?> s, Fiche? existante) {
    final v = {...s};
    final d = v.remove('dateReleve');
    final h = v.remove('heureReleve');
    v['dateHeure'] = '${d}T${h ?? '00:00'}';
    final calc = patValeursReleve(v, c.magasin.collection('patients').actives);
    final out = {...v, ...calc};
    if (existante == null) {
      out['reference'] = patReferenceSuivante('CST-', 5, [for (final f in c.magasin.collection('constantes').toutes) '${f['reference'] ?? ''}']);
      out['origine'] = 'accueil';
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('constantes');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final k = patKpisConstantes(rows, c.aujourdhui);
          final tri = trierPar(rows, (r) => r['dateHeure']).reversed.toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Relevés enregistrés', valeur: nombre(k.releves), icone: LucideIcons.thermometer),
              KpiSigh(libelle: 'Aujourd’hui', valeur: nombre(k.aujourdhui), icone: LucideIcons.calendar, ton: TonSigh.info),
              KpiSigh(libelle: 'Patients suivis', valeur: nombre(k.patients), icone: LucideIcons.users, ton: TonSigh.neutre),
              KpiSigh(
                  libelle: 'Constantes hors bornes',
                  valeur: nombre(k.horsBornes),
                  icone: LucideIcons.triangleAlert,
                  ton: k.horsBornes > 0 ? TonSigh.attention : TonSigh.succes),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'Ces relevés alimentent la feuille de température (graphique à cinq échelles) et la fiche de surveillance (le même relevé en tableau). Une seule collection, deux présentations : les tenir séparées produirait deux vérités divergentes sur les constantes d’un même patient.',
                icone: LucideIcons.activity),
            const SizedBox(height: 16),
            RegistreM1(
              collection: col,
              entite: 'Relevé',
              lignes: (_, __) => tri,
              libelleNouveau: 'Nouveau relevé',
              titreNouveau: 'Relever les constantes',
              messageVide: 'Aucun relevé de constantes enregistré.',
              champs: champs,
              valeursInitiales: (cc) => {
                'dateReleve': iso(cc.aujourdhui),
                'heureReleve': '${cc.aujourdhui.hour.toString().padLeft(2, '0')}:${cc.aujourdhui.minute.toString().padLeft(2, '0')}',
              },
              valeursEdition: (f) {
                final dh = '${f['dateHeure'] ?? ''}';
                return {
                  ...valeursFormulaire(f),
                  'dateReleve': dh.length >= 10 ? dh.substring(0, 10) : '',
                  'heureReleve': dh.length >= 16 ? dh.substring(11, 16) : '',
                };
              },
              transformer: _transformer,
              colonnes: [
                ColonneTableau(
                    cle: 'dateHeure', libelle: 'Date et heure', texte: (r) => '${r['dateHeure'] ?? ''}', rendu: (_, r) => Text(dateHeureM1(r['dateHeure']), style: styleM1())),
                ColonneTableau(cle: 'patient', libelle: 'Patient', texte: (r) => '${r['patient']} — ${r['patientCode']}'),
                ColonneTableau(cle: 'moment', libelle: 'Moment', texte: (r) => patMoments['${r['moment']}'] ?? '—'),
                ColonneTableau(
                    cle: 'temperature', libelle: 'T°', droite: true, texte: (r) => r['temperature'] == null ? '—' : '${r['temperature']} °C'),
                ColonneTableau(cle: 'tension', libelle: 'TA', droite: true, texte: (r) => _t(r['tension'])),
                ColonneTableau(cle: 'pouls', libelle: 'Pouls', droite: true, texte: (r) => r['pouls'] == null ? '—' : '${r['pouls']} bpm'),
                ColonneTableau(cle: 'spo2', libelle: 'SpO₂', droite: true, texte: (r) => r['spo2'] == null ? '—' : '${r['spo2']} %'),
                ColonneTableau(cle: 'imc', libelle: 'IMC', droite: true, texte: (r) => r['imc'] == null ? '—' : '${r['imc']}'),
                ColonneTableau(
                    cle: 'alerte',
                    libelle: 'Contrôle',
                    triable: false,
                    texte: (r) {
                      final m = patAnormale(r);
                      return m.isEmpty ? 'normales' : 'hors bornes : ${m.join(', ')}';
                    },
                    rendu: (_, r) {
                      final m = patAnormale(r);
                      return m.isEmpty
                          ? const BadgeSigh('normales', ton: TonSigh.succes)
                          : BadgeSigh('hors bornes : ${m.join(', ')}', ton: TonSigh.attention);
                    }),
              ],
              titreDetail: (r) => '${r['patient']} — ${dateHeureM1(r['dateHeure'])}',
              detail: (ctx, r) {
                final m = patAnormale(r);
                String u(String k, String unite) => r[k] == null ? '—' : '${r[k]} $unite';
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DescListeSigh([
                    ('Patient', '${r['patient']} — ${r['patientCode']}'),
                    ('Date et heure', dateHeureM1(r['dateHeure'])),
                    ('Moment', patMoments['${r['moment']}'] ?? '—'),
                    ('Température', u('temperature', '°C')),
                    ('Tension artérielle', _t(r['tension'])),
                    ('Pouls', u('pouls', 'bpm')),
                    ('Fréquence respiratoire', u('fr', '/min')),
                    ('SpO₂', u('spo2', '%')),
                    ('Diurèse', u('diurese', 'L')),
                    ('Poids', u('poids', 'kg')),
                    ('Taille', u('taille', 'cm')),
                    ('IMC', r['imc'] == null ? '—' : '${r['imc']} (calculé)'),
                    ('Relevé par', _t(r['releveePar'])),
                  ]),
                  if (m.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    NoteSigh(
                        'Constantes hors bornes : ${m.join(', ')}. Le logiciel signale, il ne diagnostique pas — l’appréciation revient au soignant.',
                        ton: TonSigh.attention,
                        icone: LucideIcons.triangleAlert),
                  ],
                ]);
              },
            ),
          ]);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m1-reference
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranReference extends StatelessWidget with EcranMaquette {
  const EcranReference({super.key});

  @override
  String get description => 'Patients orientés vers un autre centre, et patients adressés à la clinique.';

  @override
  String get regle =>
      'La fiche part avec le patient et porte ses constantes, ses traitements reçus et le motif de la référence. Une fiche entrante ouvre un dossier local sans effacer la pièce d’origine — celle-ci est numérisée et conservée. La contre-référence attendue est suivie : son absence est un indicateur, pas un oubli.';

  static List<ChampDef> champs(ContexteEcran c, Fiche? e) => [
        ChampDef(
            nom: 'sens',
            libelle: 'Sens de la référence',
            type: TypeChamp.select,
            requis: true,
            options: [for (final s in patSensReference) OptionChamp(s.$1, s.$2)]),
        const ChampDef(nom: 'urgent', libelle: 'URGENT', type: TypeChamp.case_),
        ChampDef(nom: 'patientCode', libelle: 'Patient', type: TypeChamp.select, requis: true, options: optionsPatientsM1(c.magasin)),
        const ChampDef.section('Formation sanitaire'),
        const ChampDef(
            nom: 'formationSanitaire',
            libelle: 'Nom de la formation sanitaire',
            requis: true,
            aide: 'Pour une référence sortante : la clinique. Pour une entrante : le centre qui adresse.'),
        const ChampDef(nom: 'centreAlerte', libelle: 'Centre d’accueil alerté', type: TypeChamp.case_),
        const ChampDef(nom: 'dateAdmission', libelle: 'Date d’admission', type: TypeChamp.date),
        const ChampDef(nom: 'heureAdmission', libelle: 'Heure d’admission'),
        const ChampDef.section('Constantes vitales à la référence'),
        const ChampDef(nom: 'pouls', libelle: 'Pouls (bpm)', type: TypeChamp.nombre),
        const ChampDef(nom: 'temperature', libelle: 'Température (°C)', type: TypeChamp.nombre),
        const ChampDef(nom: 'tension', libelle: 'Tension artérielle'),
        const ChampDef(nom: 'abordVeineux', libelle: 'Abord veineux posé', type: TypeChamp.case_),
        const ChampDef.section('Personne à contacter'),
        const ChampDef(nom: 'contactNom', libelle: 'Nom et prénom'),
        const ChampDef(nom: 'contactAdresse', libelle: 'Adresse et téléphone'),
        const ChampDef.section('Éléments cliniques'),
        const ChampDef(nom: 'symptomes', libelle: 'Symptômes dominants / diagnostic', type: TypeChamp.textarea, requis: true, col: ColChamp.plein),
        const ChampDef(nom: 'traitements', libelle: 'Traitements donnés', type: TypeChamp.textarea, col: ColChamp.plein),
        const ChampDef(
            nom: 'observations',
            libelle: 'Observations',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein,
            aide: 'Décrire une situation pertinente dans le traitement ou la référence.'),
        const ChampDef.section('Référence'),
        ChampDef(
            nom: 'motifs',
            libelle: 'Motif de la référence',
            type: TypeChamp.multiselect,
            requis: true,
            options: [for (final m in patMotifsReference) OptionChamp(m)]),
        const ChampDef(nom: 'motifAutre', libelle: 'Autre motif — à préciser'),
        const ChampDef(nom: 'centreDestination', libelle: 'Centre ou service où le patient est référé', requis: true),
        const ChampDef(nom: 'dateReference', libelle: 'Date de la référence', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'heureReference', libelle: 'Heure de la référence'),
        ChampDef(
            nom: 'moyen',
            libelle: 'Moyen de transport utilisé',
            type: TypeChamp.select,
            options: [for (final m in patMoyensTransport) OptionChamp(m)]),
        const ChampDef(nom: 'agentReferent', libelle: 'Agent qui réfère — nom, qualification, téléphone', requis: true),
        const ChampDef.section('Transport (rempli par l’ambulancier)'),
        const ChampDef(nom: 'departLe', libelle: 'Date et heure de départ'),
        const ChampDef(nom: 'arriveeLe', libelle: 'Date et heure d’arrivée au centre d’accueil'),
        const ChampDef(nom: 'ambulancier', libelle: 'Nom de l’ambulancier'),
      ];

  static void _imprimer(BuildContext ctx, Fiche r) {
    String constantes() => [
          if (patVrai(r['pouls'])) 'Pouls ${r['pouls']}',
          if (patVrai(r['temperature'])) 'T° ${r['temperature']}',
          if (patVrai(r['tension'])) 'TA ${r['tension']}',
        ].join('   ');
    final motifs = ((r['motifs'] as List?) ?? const []).join(' · ');
    imprimerM1(ctx,
        titre: 'FICHE DE RÉFÉRENCE',
        sousTitre: 'N° ${r['numero']}${patVrai(r['urgent']) ? '   —   URGENT' : ''}',
        cartouche: [
          ('Formation sanitaire', '${r['formationSanitaire']}'),
          ('Centre d’accueil alerté', patVrai(r['centreAlerte']) ? 'Oui' : 'Non'),
          ('Patient', '${r['patient']}'),
          ('Dossier', '${r['patientCode']}'),
          ('Âge', r['age'] != null ? '${r['age']} ans' : '—'),
          ('Sexe', _t(r['sexe'])),
          ('Adresse', _t(r['adresse'])),
          ('Personne à contacter', '${_t(r['contactNom'])}${patVrai(r['contactAdresse']) ? ' — ${r['contactAdresse']}' : ''}'),
          ('Constantes vitales', constantes().isEmpty ? '—' : constantes()),
          ('Abord veineux', patVrai(r['abordVeineux']) ? 'Oui' : 'Non'),
          ('Centre destinataire', '${r['centreDestination']}'),
          ('Date et heure de référence', '${dateFrM1(r['dateReference'])}${patVrai(r['heureReference']) ? ' à ${r['heureReference']}' : ''}'),
          ('Moyen utilisé', _t(r['moyen'])),
        ],
        blocs: [
          const BlocTexte('Symptômes dominants / diagnostic', gras: true),
          BlocTexte(_t(r['symptomes'])),
          const BlocTexte('Traitements donnés', gras: true),
          BlocTexte(_t(r['traitements'])),
          const BlocTexte('Motif de la référence', gras: true),
          BlocTexte('$motifs${patVrai(r['motifAutre']) ? ' — ${r['motifAutre']}' : ''}'),
          const BlocTexte('Transport', gras: true),
          BlocTexte('Départ : ${patVrai(r['departLe']) ? r['departLe'] : '……………'}     Arrivée au centre d’accueil : ${patVrai(r['arriveeLe']) ? r['arriveeLe'] : '……………'}'),
        ],
        signatures: [
          Signature('L’agent qui réfère', nom: '${r['agentReferent']}', mention: 'Signature et téléphone'),
          Signature('L’ambulancier', nom: '${r['ambulancier'] ?? ''}', mention: 'Signature et nom'),
        ]);
  }

  static Widget _detail(BuildContext ctx, Fiche r) {
    final c = ContexteEcran.of(ctx);
    final cr = patContreReferenceDe(r, c.magasin.collection('contreReferences').toutes);
    final constantes = [
      if (patVrai(r['pouls'])) 'pouls ${r['pouls']}',
      if (patVrai(r['temperature'])) '${r['temperature']} °C',
      if (patVrai(r['tension'])) 'TA ${r['tension']}',
    ].join(' · ');
    final motifs = [for (final m in (r['motifs'] as List? ?? const [])) '$m'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DescListeSigh([
        ('N° de référence', '${r['numero']}'),
        ('Sens', r['sens'] == 'entrante' ? 'Entrante — patient adressé à la clinique' : 'Sortante — patient orienté ailleurs'),
        ('Urgence', patVrai(r['urgent']) ? 'OUI' : 'Non'),
        ('Patient', '${r['patient']} — ${r['patientCode']}'),
        ('Formation sanitaire', r['formationSanitaire']),
        ('Centre d’accueil alerté', patVrai(r['centreAlerte']) ? 'Oui' : 'Non'),
        ('Constantes', constantes.isEmpty ? '—' : constantes),
        ('Abord veineux', patVrai(r['abordVeineux']) ? 'Posé' : 'Non posé'),
        ('Centre destinataire', r['centreDestination']),
        ('Date et heure', '${dateFrM1(r['dateReference'])}${patVrai(r['heureReference']) ? ' à ${r['heureReference']}' : ''}'),
        ('Moyen de transport', _t(r['moyen'])),
        ('Agent référent', r['agentReferent']),
        ('Départ', _t(r['departLe'])),
        ('Arrivée', _t(r['arriveeLe'])),
        ('Ambulancier', _t(r['ambulancier'])),
      ]),
      sectionM1('Symptômes dominants / diagnostic', paragrapheM1(_t(r['symptomes']))),
      if (patVrai(r['traitements'])) sectionM1('Traitements donnés', paragrapheM1('${r['traitements']}')),
      sectionM1(
          'Motif de la référence',
          MiniTableauSigh(colonnes: [
            ColonneMini('Motif', (x) => '${x['m']}')
          ], lignes: [
            for (final m in motifs)
              {'m': m == 'Autre (à préciser)' && patVrai(r['motifAutre']) ? '$m — ${r['motifAutre']}' : m}
          ])),
      const SizedBox(height: 12),
      if (cr != null)
        NoteSigh(
            'Contre-référence reçue le ${dateFrM1(cr['dateArrivee'])} — diagnostic de sortie : ${_t(cr['diagnosticSortie'])} · concordance : ${patVrai(cr['concordance']) ? 'OUI' : 'NON'} · référence ${patVrai(cr['justifiee']) ? 'justifiée' : 'NON justifiée'}.',
            ton: patVrai(cr['concordance']) ? TonSigh.succes : TonSigh.attention,
            icone: LucideIcons.reply)
      else if (r['sens'] == 'sortante')
        const NoteSigh(
            'Aucune contre-référence reçue à ce jour. Son absence est suivie : c’est un indicateur de la relation avec le centre d’accueil, pas un oubli de saisie.',
            ton: TonSigh.attention,
            icone: LucideIcons.clock),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('fichesReference');
    final colK = c.magasin.collection('contreReferences');
    return ListenableBuilder(
        listenable: Listenable.merge([col, colK]),
        builder: (context, _) {
          final rows = col.actives;
          final k = patKpisReference(rows, colK.toutes);
          final sans = patSansContreReference(rows, colK.toutes);
          final sortantes = rows.where((r) => r['sens'] == 'sortante').toList();
          final entrantes = rows.where((r) => r['sens'] == 'entrante').toList();
          Widget tableau(List<Fiche> l) => RegistreM1(
                collection: col,
                entite: 'Fiche de référence',
                lignes: (_, __) => trierPar(l, (r) => r['dateReference']).reversed.toList(),
                libelleNouveau: 'Nouvelle fiche de référence',
                titreNouveau: 'Fiche de référence',
                taille: TailleModale.xl,
                messageVide: 'Aucune fiche de référence enregistrée.',
                champs: champs,
                valeursInitiales: (_) => const {},
                transformer: (cc, s, e) => e != null
                    ? s
                    : patDeduitReference(s, cc.magasin.collection('patients').actives, col.toutes, cc.aujourdhui),
                titreDetail: (r) => '${r['numero']}',
                detail: _detail,
                etat: _imprimer,
                colonnes: [
                  ColonneTableau(
                      cle: 'numero',
                      libelle: 'N° de référence',
                      texte: (r) => '${r['numero']}${patVrai(r['urgent']) ? ' URGENT' : ''}',
                      rendu: (_, r) => Row(mainAxisSize: MainAxisSize.min, children: [
                            enMono('${r['numero']}'),
                            if (patVrai(r['urgent'])) ...[const SizedBox(width: 8), const BadgeSigh('URGENT', ton: TonSigh.danger)],
                          ])),
                  ColonneTableau(
                      cle: 'sens',
                      libelle: 'Sens',
                      texte: (r) => r['sens'] == 'entrante' ? 'Entrante' : 'Sortante',
                      rendu: (_, r) => r['sens'] == 'entrante'
                          ? const BadgeSigh('Entrante', ton: TonSigh.succes)
                          : const BadgeSigh('Sortante', ton: TonSigh.info)),
                  ColonneTableau(cle: 'patient', libelle: 'Patient', texte: (r) => '${r['patient']} — ${r['patientCode']}'),
                  const ColonneTableau(cle: 'centreDestination', libelle: 'Centre destinataire'),
                  ColonneTableau(cle: 'dateReference', libelle: 'Date', texte: (r) => dateFrM1(r['dateReference']), valeur: (r) => r['dateReference']),
                  const ColonneTableau(cle: 'agentReferent', libelle: 'Agent référent'),
                  ColonneTableau(
                      cle: 'retour',
                      libelle: 'Contre-référence',
                      triable: false,
                      texte: (r) {
                        final cr = patContreReferenceDe(r, colK.toutes);
                        if (cr != null) return 'Reçue le ${dateFrM1(cr['dateArrivee'])}';
                        return r['sens'] == 'sortante' ? 'Attendue' : '—';
                      },
                      rendu: (_, r) {
                        final cr = patContreReferenceDe(r, colK.toutes);
                        if (cr != null) return BadgeSigh('Reçue le ${dateFrM1(cr['dateArrivee'])}', ton: TonSigh.succes);
                        return r['sens'] == 'sortante' ? const BadgeSigh('Attendue', ton: TonSigh.attention) : tiret();
                      }),
                ],
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Fiches de référence', valeur: nombre(k.fiches), icone: LucideIcons.share2),
              KpiSigh(libelle: 'Sortantes', valeur: nombre(k.sortantes), icone: LucideIcons.arrowUpRight, ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Entrantes',
                  valeur: nombre(k.entrantes),
                  icone: LucideIcons.arrowDownLeft,
                  ton: TonSigh.succes,
                  indice: 'patients adressés à la clinique'),
              KpiSigh(
                  libelle: 'Sans contre-référence',
                  valeur: nombre(k.sansRetour),
                  icone: LucideIcons.clock,
                  ton: k.sansRetour > 0 ? TonSigh.attention : TonSigh.succes,
                  indice: 'le centre d’accueil n’a pas encore répondu'),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'Une fiche entrante ouvre un dossier local sans effacer la pièce d’origine : celle-ci est numérisée et conservée au dossier, avec sa couverture d’assurance. Le patient référé arrive avec ses documents — les jeter reviendrait à perdre tout ce que le centre d’origine a déjà fait.',
                icone: LucideIcons.paperclip),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(id: 'toutes', libelle: 'Toutes', compte: rows.length, construire: (_) => tableau(rows)),
              OngletDef(id: 'sortantes', libelle: 'Sortantes', compte: sortantes.length, construire: (_) => tableau(sortantes)),
              OngletDef(id: 'entrantes', libelle: 'Entrantes', compte: entrantes.length, construire: (_) => tableau(entrantes)),
              OngletDef(id: 'attente', libelle: 'Contre-référence attendue', compte: sans.length, construire: (_) => tableau(sans)),
            ]),
          ]);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m1-contre-reference
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranContreReference extends StatelessWidget with EcranMaquette {
  const EcranContreReference({super.key});

  @override
  String get description =>
      'Retours des centres d’accueil sur les patients référés : diagnostic de sortie, concordance, évolution.';

  @override
  String get regle =>
      'La contre-référence se rattache à la fiche de référence par son numéro — le seul identifiant que les deux établissements partagent. La concordance des diagnostics et le caractère justifié de la référence sont les deux indicateurs que le formulaire officiel demande : ils disent si la clinique oriente à bon escient.';

  static List<ChampDef> champs(ContexteEcran c, Fiche? e) => [
        ChampDef(
            nom: 'numeroReference',
            libelle: 'N° de la fiche de référence',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [
              for (final r in c.magasin.collection('fichesReference').actives)
                if (r['sens'] == 'sortante') OptionChamp('${r['numero']}', '${r['numero']} — ${r['patient']}')
            ],
            aide: 'Le numéro est le seul lien que les deux établissements partagent.'),
        const ChampDef(nom: 'centreAccueil', libelle: 'Nom du centre d’accueil', requis: true),
        const ChampDef(nom: 'service', libelle: 'Service'),
        const ChampDef(nom: 'dateArrivee', libelle: 'Date d’arrivée', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'heureArrivee', libelle: 'Heure d’arrivée'),
        const ChampDef(nom: 'agentReferent', libelle: 'Nom de l’agent qui a référé'),
        const ChampDef(nom: 'structureProvenance', libelle: 'Structure de provenance'),
        const ChampDef(nom: 'hospitalise', libelle: 'Le patient a-t-il été hospitalisé ?', type: TypeChamp.case_),
        const ChampDef(nom: 'numeroDossier', libelle: 'N° du dossier au centre d’accueil'),
        const ChampDef.section('Diagnostics'),
        const ChampDef(nom: 'diagnosticEntree', libelle: 'Diagnostic d’entrée', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
        const ChampDef(nom: 'diagnosticSortie', libelle: 'Diagnostic de sortie', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
        const ChampDef(
            nom: 'concordance',
            libelle: 'Concordance entre les diagnostics de référence et de sortie',
            type: TypeChamp.case_,
            col: ColChamp.plein,
            aide: 'Une discordance n’est pas une faute : c’est une information à exploiter.'),
        const ChampDef(nom: 'justifiee', libelle: 'Référence justifiée', type: TypeChamp.case_),
        const ChampDef(nom: 'motifNonJustifiee', libelle: 'Si non justifiée — pourquoi'),
        const ChampDef.section('Évolution'),
        ChampDef(
            nom: 'evolution',
            libelle: 'Évolution de la maladie',
            type: TypeChamp.select,
            requis: true,
            options: [for (final e in patEvolutions) OptionChamp(e)]),
        const ChampDef(
            nom: 'observations',
            libelle: 'Observations et conseils à l’attention du centre de référence',
            type: TypeChamp.textarea,
            lignes: 3,
            col: ColChamp.plein),
        const ChampDef(nom: 'chefService', libelle: 'Nom et prénom du chef de service ou son représentant', requis: true),
      ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('contreReferences');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final k = patKpisContreReference(rows);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Contre-références reçues', valeur: nombre(k.recues), icone: LucideIcons.reply),
              KpiSigh(
                  libelle: 'Diagnostics concordants',
                  valeur: nombre(k.concordantes),
                  icone: LucideIcons.checkCheck,
                  ton: TonSigh.succes,
                  indice: k.partConcordance),
              KpiSigh(
                  libelle: 'Références justifiées',
                  valeur: nombre(k.justifiees),
                  icone: LucideIcons.thumbsUp,
                  ton: k.justifiees == rows.length ? TonSigh.succes : TonSigh.attention,
                  indice: k.partJustifiees),
              KpiSigh(
                  libelle: 'Décès au centre d’accueil',
                  valeur: nombre(k.deces),
                  icone: LucideIcons.cross,
                  ton: k.deces > 0 ? TonSigh.danger : TonSigh.neutre),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'Une discordance de diagnostic ou une référence jugée non justifiée n’est pas une faute à masquer : c’est l’information la plus utile que le centre d’accueil puisse renvoyer. Le taux de concordance mesure la qualité de l’orientation, pas la compétence d’un agent.',
                icone: LucideIcons.target),
            const SizedBox(height: 16),
            RegistreM1(
              collection: col,
              entite: 'Contre-référence',
              lignes: (_, l) => trierPar(l, (r) => r['dateArrivee']).reversed.toList(),
              libelleNouveau: 'Enregistrer une contre-référence',
              titreNouveau: 'Fiche de contre-référence',
              taille: TailleModale.xl,
              messageVide: 'Aucune contre-référence reçue.',
              champs: champs,
              valeursInitiales: (_) => const {},
              transformer: (cc, s, e) => e != null
                  ? s
                  : patDeduitContreReference(s, cc.magasin.collection('fichesReference').toutes, col.toutes),
              titreDetail: (r) => '${r['reference']}',
              detail: (ctx, r) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DescListeSigh([
                  ('Référence', '${r['reference']}'),
                  ('Fiche de référence', '${r['numeroReference']}'),
                  ('Patient', '${r['patient']}'),
                  ('Centre d’accueil', r['centreAccueil']),
                  ('Service', _t(r['service'])),
                  ('Arrivée', '${dateFrM1(r['dateArrivee'])}${patVrai(r['heureArrivee']) ? ' à ${r['heureArrivee']}' : ''}'),
                  ('Structure de provenance', _t(r['structureProvenance'])),
                  ('Hospitalisé', patVrai(r['hospitalise']) ? 'Oui' : 'Non'),
                  ('N° de dossier au centre d’accueil', _t(r['numeroDossier'])),
                  ('Évolution', r['evolution']),
                  ('Chef de service', r['chefService']),
                ]),
                sectionM1('Diagnostic d’entrée', paragrapheM1('${r['diagnosticEntree']}')),
                sectionM1('Diagnostic de sortie', paragrapheM1('${r['diagnosticSortie']}')),
                const SizedBox(height: 12),
                NoteSigh(
                    'Concordance des diagnostics : ${patVrai(r['concordance']) ? 'OUI' : 'NON'} — Référence ${patVrai(r['justifiee']) ? 'justifiée' : 'NON justifiée'}${patVrai(r['motifNonJustifiee']) ? ' : ${r['motifNonJustifiee']}' : ''}.',
                    ton: patVrai(r['concordance']) && patVrai(r['justifiee']) ? TonSigh.succes : TonSigh.attention,
                    icone: LucideIcons.target),
                if (patVrai(r['observations'])) sectionM1('Observations et conseils', paragrapheM1('${r['observations']}')),
              ]),
              colonnes: [
                const ColonneTableau(cle: 'reference', libelle: 'Référence'),
                ColonneTableau(cle: 'numeroReference', libelle: 'Fiche de référence', rendu: (_, r) => enMono('${r['numeroReference']}'), texte: (r) => '${r['numeroReference']}'),
                const ColonneTableau(cle: 'patient', libelle: 'Patient'),
                const ColonneTableau(cle: 'centreAccueil', libelle: 'Centre d’accueil'),
                ColonneTableau(cle: 'dateArrivee', libelle: 'Arrivée', texte: (r) => dateFrM1(r['dateArrivee']), valeur: (r) => r['dateArrivee']),
                const ColonneTableau(cle: 'evolution', libelle: 'Évolution'),
                ColonneTableau(
                    cle: 'concordance',
                    libelle: 'Concordance',
                    texte: (r) => patVrai(r['concordance']) ? 'Oui' : 'NON',
                    rendu: (_, r) => patVrai(r['concordance']) ? const BadgeSigh('Oui', ton: TonSigh.succes) : const BadgeSigh('NON', ton: TonSigh.attention)),
                ColonneTableau(
                    cle: 'justifiee',
                    libelle: 'Justifiée',
                    texte: (r) => patVrai(r['justifiee']) ? 'Oui' : 'NON',
                    rendu: (_, r) => patVrai(r['justifiee']) ? const BadgeSigh('Oui', ton: TonSigh.succes) : const BadgeSigh('NON', ton: TonSigh.attention)),
              ],
            ),
          ]);
        });
  }
}
