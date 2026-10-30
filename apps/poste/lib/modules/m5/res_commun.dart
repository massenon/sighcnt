import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Briques communes aux quatre écrans du RÉSULTAT d'analyse (`m5-resultats`, `m5-impression-resultats`, `m5-resultats-comparatif`, `m5-stats`).
/// Les règles vivent dans `packages/domaine/lib/src/labo/res_*.dart` ; ici, ce que l'agent VOIT.

/// Qui regarde : la session du laboratoire (rôle, fonction, secteur) et l'agent (identifiant et nom). La coque du poste ne porte que le RÔLE :
/// la fonction est donc DÉDUITE du rôle (`ROLE_VERS_FONCTION`, repli de la maquette) tant que la coque n'expose pas la fonction, le secteur et
/// l'identifiant de l'agent — les écrans les acceptent en paramètres pour qu'elle les branche sans retoucher les écrans.
class ProfilLabo {
  const ProfilLabo(this.session, this.agentId, this.agentNom);
  final SessionLabo session;
  final String? agentId;
  final String agentNom;
  CapaciteLabo get cap => capacites(session);
}

ProfilLabo profilLabo(ContexteEcran c,
    {String? fonction, String? secteur, String? agentId}) {
  var id = agentId;
  if (id == null) {
    for (final p in c.magasin.collection('personnel').actives) {
      if (p['nomComplet'] == c.utilisateur) {
        id = '${p['id']}';
        break;
      }
    }
  }
  return ProfilLabo(
      SessionLabo(
          role: c.role,
          fonction: fonction,
          secteur: secteur,
          id: id,
          nom: c.utilisateur),
      id,
      c.utilisateur);
}

/// `D.resultatRendu(etat)` sur un état de type quelconque (le domaine en porte deux écritures : celle des états du résultat, qui accepte tout).
bool estRendu(Object? etat) => etat == 'valide' || etat == 'rectifie';

num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// `<br>` et balises de mise en forme de la maquette → texte brut (la confirmation Flutter rend un TEXTE, jamais interprété).
String texteBrut(String s) =>
    sansBalises(s.replaceAll(RegExp(r'<br\s*/?>'), '\n'));

TextStyle _st(double taille,
        {Color couleur = JetonsShell.slate700,
        FontWeight poids = FontWeight.w400,
        String? police}) =>
    TextStyle(
        fontFamily: police,
        color: couleur,
        fontSize: taille,
        fontWeight: poids,
        height: taille == 14 ? 20 / 14 : (taille == 12 ? 16 / 12 : 15 / taille));

TextStyle styleLabo(double taille,
        {Color couleur = JetonsShell.slate700,
        FontWeight poids = FontWeight.w400,
        String? police}) =>
    _st(taille, couleur: couleur, poids: poids, police: police);

/// Les demandes lisibles de cet agent (`PR.filtrerResultats(col.active())`) : le filtre porte sur les DONNÉES, pas seulement sur l'accès à l'écran.
List<Fiche> demandesVisibles(ContexteEcran c, ProfilLabo p) =>
    filtrerResultats(c.magasin.collection('demandesAnalyses').actives, p.session);

/// Les collections que lit un écran du résultat : le repaint suit toutes celles-ci.
Listenable ecouteLabo(ContexteEcran c) => Listenable.merge([
      c.magasin.collection('demandesAnalyses'),
      c.magasin.collection('factures'),
      c.magasin.collection('plagesReactif'),
      c.magasin.collection('variablesLabo'),
      c.magasin.collection('examensLabo'),
      c.magasin.collection('patients'),
    ]);

List<Fiche> examensLabo(ContexteEcran c) =>
    c.magasin.collection('examensLabo').actives;
List<Fiche> plagesLabo(ContexteEcran c) =>
    c.magasin.collection('plagesReactif').actives;
List<Fiche> unitesLabo(ContexteEcran c) =>
    c.magasin.collection('unitesLabo').actives;
List<Fiche> variablesLabo(ContexteEcran c) =>
    c.magasin.collection('variablesLabo').actives;

Fiche? patientDe(ContexteEcran c, Object? id) {
  for (final p in c.magasin.collection('patients').actives) {
    if (p['id'] == id) return p;
  }
  return null;
}

String symbole(ContexteEcran c, Object? id) => symboleUnite(id, unitesLabo(c));

/// Les colonnes communes du registre des demandes (`colonnesDemande`).
List<ColonneTableau> colonnesDemande() => [
      ColonneTableau(
          cle: 'reference',
          libelle: 'N°',
          sansCoupure: true,
          texte: (r) =>
              '${r['reference']} ${r['codeAnalyse'] ?? ''} ${r['origine'] == 'ordonnance' ? (r['ordonnanceNumero'] ?? 'Ordonnance') : 'Saisie laboratoire'}',
          rendu: (_, r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${r['reference']}',
                        style: _st(12, police: 'monospace')),
                    if (r['codeAnalyse'] != null && r['codeAnalyse'] != '')
                      Text('${r['codeAnalyse']}',
                          style: _st(10,
                              couleur: JetonsShell.navy700, police: 'monospace')),
                    Text(
                        r['origine'] == 'ordonnance'
                            ? '${r['ordonnanceNumero'] ?? 'Ordonnance'}'
                            : 'Saisie laboratoire',
                        style: _st(10, couleur: JetonsShell.slate400)),
                  ])),
      ColonneTableau(
          cle: 'origine',
          libelle: 'Origine',
          sansCoupure: true,
          valeur: _origineTexte,
          texte: _origineTexte,
          rendu: (_, r) {
            if (r['origine'] == 'service') {
              return const BadgeSigh('Fiche de service', ton: TonSigh.info);
            }
            if (r['origine'] == 'accueil-externe') {
              return const BadgeSigh('Accueil — externe', ton: TonSigh.info);
            }
            if (r['origine'] != 'ordonnance') {
              return const BadgeSigh('Manuelle', ton: TonSigh.neutre);
            }
            final b = r['bloqueParPaiement'];
            return (b != null && b != false && b != '')
                ? const BadgeSigh('Attente caisse', ton: TonSigh.attention)
                : const BadgeSigh('Prépayée', ton: TonSigh.succes);
          }),
      ColonneTableau(
          cle: 'dateHeure',
          libelle: 'Date',
          sansCoupure: true,
          valeur: (r) => dateLocale(r['dateHeure'])?.millisecondsSinceEpoch ?? 0,
          texte: (r) => dateFrJs(r['dateHeure']),
          rendu: (_, r) =>
              Text(dateFrJs(r['dateHeure']), style: _st(14))),
      ColonneTableau(
          cle: 'patient',
          libelle: 'Patient',
          texte: (r) => '${r['patient']} ${r['patientCode']}',
          rendu: (_, r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${r['patient']}',
                        overflow: TextOverflow.ellipsis,
                        style: _st(14,
                            couleur: JetonsShell.slate800,
                            poids: FontWeight.w500)),
                    Text('${r['patientCode']}',
                        style: _st(12,
                            couleur: JetonsShell.slate400, police: 'monospace')),
                  ])),
      ColonneTableau(
          cle: 'analyse',
          libelle: 'Analyse',
          texte: (r) => '${r['analyse']} ${r['categorie']}',
          rendu: (_, r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${r['analyse']}',
                        overflow: TextOverflow.ellipsis, style: _st(14)),
                    Text('${r['categorie'] ?? ''}',
                        style: _st(12, couleur: JetonsShell.slate400)),
                  ])),
      const ColonneTableau(cle: 'echantillon', libelle: 'Échantillon'),
      const ColonneTableau(cle: 'prescripteur', libelle: 'Prescripteur'),
      ColonneTableau(
          cle: 'urgent',
          libelle: 'Priorité',
          texte: (r) => _vrai(r['urgent']) ? 'Urgent' : 'Normale',
          rendu: (_, r) => _vrai(r['urgent'])
              ? const BadgeSigh('Urgent', ton: TonSigh.danger)
              : Text('Normale', style: _st(12, couleur: JetonsShell.slate400))),
      ColonneTableau(
          cle: 'etatAnalyse',
          libelle: 'État',
          texte: (r) => '${statutsMetier['${r['etatAnalyse']}']?.$1 ?? r['etatAnalyse'] ?? '—'}',
          rendu: (_, r) => statutBadge(r['etatAnalyse'])),
    ];

bool _vrai(Object? v) => v != null && v != false && v != '' && v != 0;

String _origineTexte(Fiche r) {
  if (r['origine'] == 'ordonnance') return 'Ordonnance';
  if (r['origine'] == 'service') return 'Fiche de service';
  if (r['origine'] == 'accueil-externe') return 'Accueil — externe';
  return 'Manuelle';
}

/// Le badge de conclusion : « Normal » en vert, toute autre valeur en orange.
Widget badgeConclusion(Object? c) => c == 'Normal'
    ? const BadgeSigh('Normal', ton: TonSigh.succes)
    : BadgeSigh(c == null || c == '' ? '—' : '$c', ton: TonSigh.attention);

/// Le badge du règlement : réglée / règlement dû / sans pièce liée.
Widget badgeReglement(ReglementDemande g) => switch (g.statut) {
      'regle' => const BadgeSigh('Réglée', ton: TonSigh.succes),
      'du' => const BadgeSigh('Règlement dû', ton: TonSigh.danger),
      _ => const BadgeSigh('Sans pièce liée', ton: TonSigh.neutre),
    };

/// `.btn { white-space: nowrap }` : la largeur MINIMALE d'une commande de tableau est sa largeur pleine. Sans cela la colonne d'actions
/// (largeur intrinsèque) se resserre sous le plus long mot du libellé et la rangée déborde.
Widget commandeLigne(Widget w) => _PleineLargeur(child: w);

class _PleineLargeur extends SingleChildRenderObjectWidget {
  const _PleineLargeur({required Widget child}) : super(child: child);
  @override
  RenderObject createRenderObject(BuildContext context) => _RenduPleineLargeur();
}

class _RenduPleineLargeur extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double hauteur) =>
      child?.getMaxIntrinsicWidth(hauteur) ?? 0;
}

/// Une commande présente mais VERROUILLÉE : visible, atténuée, qui dit pourquoi — jamais masquée (un bouton absent laisserait croire à un
/// défaut d'affichage). Le clic n'agit pas : il EXPLIQUE.
Widget commandeVerrouillee(
        {required Key cle,
        required String libelle,
        required String raison,
        required VoidCallback alClic,
        IconData icone = LucideIcons.lock,
        TailleBouton taille = TailleBouton.sm}) =>
    commandeLigne(Tooltip(
        message: raison,
        child: Semantics(
            key: cle,
            enabled: false,
            child: Opacity(
                opacity: 0.5,
                child: BoutonSigh(
                    libelle: libelle,
                    icone: icone,
                    taille: taille,
                    variante: VarianteBouton.secondaire,
                    onPressed: alClic)))));

/// Le détail d'une demande (tiroir) : identité de la demande, puis son résultat — ou la mention qu'il n'est pas encore saisi.
Widget detailDemande(Fiche r) {
  final aResultat = _vrai(r['resultat']);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DescListeSigh([
      (
        'Référence',
        Text('${r['reference']}', style: _st(14, police: 'monospace'))
      ),
      (
        'Code d’analyse',
        r['codeAnalyse'] != null && r['codeAnalyse'] != ''
            ? Text('${r['codeAnalyse']}',
                style: _st(14,
                    couleur: JetonsShell.navy800,
                    poids: FontWeight.w600,
                    police: 'monospace'))
            : Text('antérieur à la série annuelle',
                style: _st(12, couleur: JetonsShell.slate400))
      ),
      (
        'Date de la demande',
        dateHeureFr(r['dateHeure'])
      ),
      ('Patient', r['patient']),
      (
        'Dossier',
        Text('${r['patientCode']}', style: _st(14, police: 'monospace'))
      ),
      ('Analyse', r['analyse']),
      (
        'Code',
        Text('${r['analyseCode'] ?? ''}', style: _st(14, police: 'monospace'))
      ),
      ('Catégorie', r['categorie']),
      ('Échantillon', r['echantillon']),
      ('Tarif', money(r['prix'])),
      ('Prescripteur', r['prescripteur']),
      ('Laborantin', r['laborantin']),
      (
        'Priorité',
        _vrai(r['urgent'])
            ? const BadgeSigh('Urgent', ton: TonSigh.danger)
            : const BadgeSigh('Normale')
      ),
      ('État', statutBadge(r['etatAnalyse'])),
    ]),
    const SizedBox(height: 16),
    if (aResultat)
      CarteSigh(
          titre: 'Résultat',
          child: DescListeSigh([
            (
              'Valeur mesurée',
              Text('${r['resultat']}',
                  style: _st(16,
                      couleur: JetonsShell.navy900, poids: FontWeight.w600))
            ),
            ('Conclusion', badgeConclusion(r['conclusion'])),
          ]))
    else
      const VideSigh('Résultat non encore saisi.', icone: LucideIcons.hourglass),
  ]);
}

/// `C.dateHeure` d'une date ISO (« 10/08/2026 à 09h00 »).
String dateHeureFr(Object? v) {
  final d = dateLocale(v);
  return d == null ? 'NaN/NaN/NaN à NaNhNaN' : dateHeure(d);
}

/// `K.ranking` : une barre par entrée, la plus longue vaut 100 %, jamais moins de 2 %.
class ClassementLabo extends StatelessWidget {
  const ClassementLabo(this.entrees, {super.key, this.unite = ''});
  final List<(String, int)> entrees;

  /// Texte après la valeur (« demande(s) »).
  final String unite;

  @override
  Widget build(BuildContext context) {
    if (entrees.isEmpty) {
      return const VideSigh('Aucune donnée.', icone: LucideIcons.chartColumn);
    }
    final max = entrees.fold<int>(1, (a, e) => e.$2 > a ? e.$2 : a);
    return Column(key: const Key('res:classement'), children: [
      for (final (i, e) in entrees.indexed)
        Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(
                    child: Text(e.$1,
                        overflow: TextOverflow.ellipsis, style: _st(14))),
                const SizedBox(width: 12),
                Text(unite.isEmpty ? nombre(e.$2) : '${nombre(e.$2)} $unite',
                    style: _st(14,
                        couleur: JetonsShell.slate900, poids: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                      height: 6,
                      child: LayoutBuilder(
                          builder: (_, k) => Stack(children: [
                                Container(color: JetonsShell.slate100),
                                Container(
                                    width: k.maxWidth *
                                        ((e.$2 / max * 100).round().clamp(2, 100)) /
                                        100,
                                    color: JetonsShell.navy500),
                              ])))),
            ])),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Impression
// ---------------------------------------------------------------------------------------------------------------------

String _reference(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

/// `etatResultat(r)` : la pièce d'UN résultat.
Future<void> imprimerResultat(BuildContext ctx, Fiche r) {
  final c = ContexteEcran.of(ctx);
  final p = patientDe(c, r['patientId']);
  return afficherApercu(
      ctx,
      PieceA4(
        titre: 'Résultat d’analyse de laboratoire',
        sousTitre: '${r['reference']}',
        reference: _reference(c),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        cartouche: [
          ('Patient', '${r['patient']}'),
          ('Dossier', '${r['patientCode']}'),
          ('Âge', ageTexte(p, c.aujourdhui)),
          ('Date de prélèvement', dateFrJs(r['dateHeure'])),
          ('Prescripteur', '${r['prescripteur'] ?? ''}'),
          ('Laborantin', '${r['laborantin'] ?? ''}'),
        ],
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Code', valeur: (l) => l['analyseCode']),
            ColonneEtat(libelle: 'Analyse', valeur: (l) => l['analyse']),
            ColonneEtat(libelle: 'Échantillon', valeur: (l) => l['echantillon']),
            ColonneEtat(
                libelle: 'Résultat',
                valeur: (l) => _vrai(l['resultat']) ? l['resultat'] : 'En cours'),
            ColonneEtat(
                libelle: 'Conclusion',
                valeur: (l) => _vrai(l['conclusion']) ? l['conclusion'] : '—'),
          ], lignes: [
            r
          ])),
          const BlocTexte(
              'Les résultats doivent être interprétés par le médecin prescripteur en fonction du contexte clinique. Ce document est archivé au dossier patient conformément à la politique de conservation de l’établissement.',
              italique: true),
        ],
        signatures: [
          Signature('Le Laborantin', nom: '${r['laborantin'] ?? ''}'),
          const Signature('Le Biologiste responsable',
              nom: 'KINNOU Addoul Ganiou'),
        ],
      ));
}

/// `compteRendu(patientId, demandes)` : LE COMPTE RENDU d'un patient — tous ses examens, groupés par section du bulletin, valeurs hors bornes
/// signalées, bornes du lot en service à la date de chaque demande. Porté dans le gabarit A4 du poste : le gras par cellule n'existe pas
/// dans ce gabarit, une valeur hors bornes est suivie de « * » (écart consigné).
Future<void> imprimerCompteRendu(
    BuildContext ctx, Object? patientId, List<Fiche> demandes) async {
  final c = ContexteEcran.of(ctx);
  final pat = patientDe(c, patientId);
  final rendus = [
    for (final d in demandes)
      if (d['etatAnalyse'] == 'valide' ||
          (d['valeurs'] is Map && (d['valeurs'] as Map).isNotEmpty))
        d
  ];
  if (rendus.isEmpty) {
    ToastsSigh.afficher(ctx, 'Aucun résultat à imprimer.',
        type: TypeToast.erreur,
        detail:
            'Le compte rendu ne reprend que les examens dont le résultat a été saisi.');
    return;
  }
  final examens = examensLabo(c);
  final plages = plagesLabo(c);
  final vars = variablesLabo(c);
  final parSection = <String, List<({Fiche demande, Fiche? examen, String? code})>>{};
  for (final d in rendus) {
    final code = codeExamenDe(d, examens);
    final ex = code == null ? null : examenParCode(code, examens);
    final sec = ex != null ? '${ex['sectionResultat']}' : 'autres';
    (parSection[sec] ??= []).add((demande: d, examen: ex, code: code));
  }
  final ordre = [for (final s in sectionsLabo) s.$1, 'autres'];
  var anormales = 0;
  final blocs = <BlocPiece>[];
  final premiere = rendus.first;
  blocs.add(BlocTexte(
      'Renseignements cliniques : ${premiere['indication'] ?? premiere['motif'] ?? ''}'));
  for (final sec in ordre) {
    final groupe = parSection[sec];
    if (groupe == null || groupe.isEmpty) continue;
    final lignes = <Map<String, Object?>>[];
    for (final g in groupe) {
      final d = g.demande;
      lignes.add({
        'a': g.examen != null ? '${g.examen!['designation']}' : '${d['analyse']}',
        'r': '',
        'ref': '',
        'ant': ''
      });
      final variables = g.code == null
          ? <Fiche>[]
          : [
              for (final v in variablesExamen(g.code, vars))
                if (v['actif'] != false) v
            ];
      final valeurs = (d['valeurs'] as Map?)?.cast<String, Object?>() ?? const {};
      if (variables.isEmpty) {
        lignes.add({
          'a': '${d['analyse']}',
          'r': _vrai(d['resultat']) ? '${d['resultat']}' : '—',
          'ref': '',
          'ant': ''
        });
        continue;
      }
      for (final v in variables) {
        final val = valeurs[v['code']];
        if (val == null || val == '') continue;
        final e = ecart(
            variableALaDate(v, plages, d['dateHeure'], aujourdhui: c.aujourdhui),
            val);
        if (e != null) anormales++;
        final u = symbole(c, v['unite']);
        lignes.add({
          'a': '${v['libelle']}',
          'r': '${chaineJs(val)}${u == '—' ? '' : ' $u'}${e != null ? ' *' : ''}',
          'ref': referenceALaDate(v, plages, d['dateHeure'],
              aujourdhui: c.aujourdhui),
          'ant': ''
        });
      }
    }
    blocs.add(BlocTableau(
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'ANALYSE', valeur: (l) => l['a']),
          ColonneEtat(libelle: 'RESULTAT', valeur: (l) => l['r'], droite: true),
          ColonneEtat(libelle: 'Références', valeur: (l) => l['ref']),
          ColonneEtat(libelle: 'Antériorités', valeur: (l) => l['ant']),
        ], lignes: lignes),
        titre: sec == 'autres' ? 'Autres examens' : libelleSection(sec)));
  }
  final commentaires = [
    for (final d in rendus)
      if (_vrai(d['commentaireGeneral'])) '${d['commentaireGeneral']}'
  ];
  if (commentaires.isNotEmpty) {
    blocs.add(BlocTexte('Commentaire du laboratoire : ${commentaires.join(' — ')}'));
  }
  blocs.add(BlocTexte(
      '${anormales > 0 ? '* valeur hors des bornes de référence. ' : ''}Les valeurs en gras sont hors des bornes de référence. Les résultats doivent être interprétés par le clinicien en fonction du contexte. Les valeurs de référence dépendent du réactif et de l’automate employés.',
      italique: true));
  final valides = rendus.where((d) => d['etatAnalyse'] == 'valide').length;
  final age = pat != null && pat['dateNaissance'] != null && pat['dateNaissance'] != ''
      ? '${ageAnnees(pat['dateNaissance'], c.aujourdhui)} ans'
      : 'Âge non renseigné';
  await afficherApercu(
      ctx,
      PieceA4(
        titre: 'Compte rendu',
        sousTitre:
            '${pat != null ? '${pat['nom']} ${pat['prenom']}' : ''} — ${nombre(rendus.length)} examen(s)',
        reference: _reference(c),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        filigrane: valides < rendus.length ? 'PROVISOIRE' : null,
        cartouche: [
          (
            'Dossier',
            '${pat?['code'] ?? '—'}   Code ${premiere['codeAnalyse'] ?? premiere['reference'] ?? ''}'
          ),
          (
            'Patient',
            pat != null ? '${pat['nom']} ${pat['prenom']}'.toUpperCase() : '—'
          ),
          (
            'Âge et sexe',
            '$age  ${pat != null ? (pat['sexe'] == 'F' ? 'Féminin' : 'Masculin') : ''}'
          ),
          (
            'Examen prescrit',
            'le ${dateFrJs(premiere['dateHeure'] ?? premiere['date'])} par ${premiere['prescripteur'] ?? '—'}'
          ),
          (
            'Enregistré le',
            dateFrJs(premiere['dateHeure'] ?? premiere['date'])
          ),
          ('Édité le', dateFR(c.aujourdhui)),
        ],
        blocs: blocs,
        signatures: const [
          Signature('Le Biologiste médical', mention: 'Validation biologique')
        ],
      ));
}
