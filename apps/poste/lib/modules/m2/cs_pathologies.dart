import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m5/res_commun.dart' show ClassementLabo;
import 'cs_commun.dart';
import 'cs_modale.dart';

/// `m2-pathologies` — « Pathologies & morbidité » : le référentiel des pathologies de la clinique et le tableau de morbidité issu des consultations.
/// La PATHOLOGIE est un code que la clinique compte ; le DIAGNOSTIC est la phrase que le médecin rédige. Les deux coexistent sur la consultation.
/// Une pathologie notifiable est signalée : le logiciel la repère, il ne la déclare pas.
class EcranPathologies extends StatelessWidget with EcranMaquette {
  const EcranPathologies({super.key});

  @override
  String get titre => 'Pathologies & morbidité';

  @override
  String get description =>
      'Référentiel des pathologies de la clinique et tableau de morbidité issu des consultations.';

  @override
  String get regle =>
      'La pathologie est un code que la clinique compte ; le diagnostic est la phrase que le médecin rédige. Les deux coexistent sur la consultation — n’avoir que le second rendrait toute statistique impossible. La liste est administrable : c’est le tableau de morbidité qui doit la faire évoluer, pas une mise à jour du logiciel. Les libellés proposés restent à arrêter par le Directeur Médical.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: Listenable.merge([
          c.magasin.collection('pathologies'),
          c.magasin.collection('consultations'),
        ]),
        builder: (ctx, _) => _Corps(c: c, ecran: ctx));
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.c, required this.ecran});
  final ContexteEcran c;
  final BuildContext ecran;

  CollectionMagasin get _col => c.magasin.collection('pathologies');

  List<ChampDef> _champs() => [
        const ChampDef(
            nom: 'code',
            libelle: 'Code',
            requis: true,
            aide: 'Court, stable — il sert au comptage.'),
        const ChampDef(
            nom: 'libelle',
            libelle: 'Intitulé de la pathologie',
            requis: true,
            col: ColChamp.plein),
        ChampDef(
            nom: 'chapitre',
            libelle: 'Chapitre',
            type: TypeChamp.select,
            requis: true,
            options: [
              for (final x in csChapitresPathologie)
                OptionChamp('${x['id']}', '${x['label']}')
            ]),
        const ChampDef(
            nom: 'notifiable',
            libelle: 'Déclaration obligatoire',
            type: TypeChamp.case_,
            aide:
                'Pathologie à déclarer aux autorités sanitaires. Le logiciel la signale ; il ne la transmet pas.'),
      ];

  void _ouvrir(Fiche? r) => modaleFormulaire(ecran,
      titre: r == null ? 'Nouvelle pathologie' : 'Modifier la pathologie',
      champs: _champs(),
      libelleOk: r == null ? 'Créer' : 'Enregistrer',
      initial: r == null
          ? {'chapitre': 'autres', 'notifiable': false}
          : {...r, 'notifiable': vrai(r['notifiable'])},
      valider: (v) {
        if (r != null) {
          _col.mettreAJour(r['id'], {...v, 'notifiable': v['notifiable'] == true});
          ToastsSigh.afficher(ecran, 'Pathologie modifiée.', type: TypeToast.succes);
          return null;
        }
        final u = _col.inserer({
          'statut': 'actif',
          ...v,
          'notifiable': v['notifiable'] == true,
          'aValider': true,
          'source':
              'Ajoutée dans l’application le ${dateFR(c.aujourdhui)} — à arrêter par le Directeur Médical',
        }, prefixe: 'PATH');
        ToastsSigh.afficher(ecran, 'Pathologie créée.',
            type: TypeToast.succes, annuler: u.annuler);
        return null;
      });

  void _archiver(Fiche r) async {
    final ok = await confirmerSigh(ecran,
        titre: 'Archiver cet enregistrement ?',
        message:
            'Archivage logique : les données restent consultables dans l’onglet « Archivés » et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (!ok || !ecran.mounted) return;
    ToastsSigh.afficher(ecran, 'Enregistrement archivé.',
        type: TypeToast.succes, annuler: _col.archiver(r['id']));
  }

  void _imprimer(List<Fiche> rows) {
    final total = rows.fold<int>(0, (n, x) => n + (x['cas'] as int));
    final notif = rows.where((x) => vrai(x['notifiable'])).fold<int>(0, (n, x) => n + (x['cas'] as int));
    afficherApercu(
        ecran,
        PieceA4(
          titre: 'Tableau de morbidité',
          sousTitre: 'Consultations enregistrées — situation au ${dateFR(c.aujourdhui)}',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Pathologies rencontrées', nombre(rows.length)),
            ('Cas totaux', nombre(total)),
            ('Dont à déclaration obligatoire', nombre(notif)),
            ('Établi par', c.utilisateur),
            ('Date d’édition', dateFR(c.aujourdhui)),
          ],
          blocs: [
            BlocTableau(TableauEtat(
              colonnes: [
                ColonneEtat(libelle: 'Code', valeur: (x) => x['code']),
                ColonneEtat(libelle: 'Pathologie', valeur: (x) => x['libelle']),
                ColonneEtat(libelle: 'Chapitre', valeur: (x) => x['chapitreLabel']),
                ColonneEtat(
                    libelle: 'Déclaration',
                    valeur: (x) => vrai(x['notifiable']) ? 'Obligatoire' : ''),
                ColonneEtat(
                    libelle: 'Cas',
                    droite: true,
                    valeur: (x) => nombre(x['cas']),
                    somme: (x) => (x['cas'] as int)),
                ColonneEtat(
                    libelle: 'Part',
                    droite: true,
                    valeur: (x) {
                      if (total == 0) return '';
                      final p = arrondiJs((x['cas'] as int) / total * 1000) / 10;
                      return '${p == p.truncateToDouble() ? p.toInt() : p} %';
                    }),
              ],
              lignes: rows,
              mentions: const {'Part': '100 %'},
            )),
            const BlocTexte(
                'Le comptage porte sur les pathologies codées à la consultation. Les consultations antérieures à la mise en place du référentiel ne portent qu’un diagnostic rédigé et ne peuvent pas être comptées rétrospectivement. Les pathologies à déclaration obligatoire sont signalées ; leur déclaration aux autorités sanitaires relève de la clinique.',
                italique: true),
          ],
          signatures: const [
            Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko'),
            Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _col.actives;
    final cas = csComptagePathologies(c.magasin.collection('consultations').actives);
    final totalCas = cas.values.fold<int>(0, (a, b) => a + b);
    final notifiables = rows.where((x) => vrai(x['notifiable'])).toList();
    final casNotifiables =
        notifiables.fold<int>(0, (n, x) => n + (cas['${x['code']}'] ?? 0));
    final lignesMorb = csMorbidite(rows, cas);
    final lignesRef = [for (final x in rows) csLignePathologie(x, cas)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Pathologies au référentiel',
            valeur: nombre(rows.length),
            icone: LucideIcons.list,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Chapitres couverts',
            valeur: nombre(csChapitresPathologie.length),
            icone: LucideIcons.layers,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Cas enregistrés',
            valeur: nombre(totalCas),
            icone: LucideIcons.activity,
            ton: TonSigh.succes,
            indice: 'sur ${nombre(c.magasin.collection('consultations').actives.length)} consultations'),
        KpiSigh(
            libelle: 'Cas à déclaration obligatoire',
            valeur: nombre(casNotifiables),
            icone: LucideIcons.siren,
            ton: casNotifiables > 0 ? TonSigh.danger : TonSigh.neutre,
            indice: '${nombre(notifiables.length)} pathologies notifiables'),
      ]),
      const SizedBox(height: 16),
      const NoteSigh(
          'Une pathologie notifiable relève de la déclaration obligatoire aux autorités sanitaires. Le signaler permet de repérer les cas à déclarer sans relire tout le registre — la clinique reste responsable de la déclaration elle-même, que le logiciel ne transmet pas.',
          ton: TonSigh.attention,
          icone: LucideIcons.siren),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'morbidite',
            libelle: 'Tableau de morbidité',
            compte: cas.length,
            construire: (_) => _morbidite(lignesMorb)),
        OngletDef(
            id: 'referentiel',
            libelle: 'Référentiel',
            compte: rows.length,
            construire: (_) => _referentiel(lignesRef)),
      ]),
    ]);
  }

  Widget _morbidite(List<Fiche> rows) {
    if (rows.isEmpty) {
      return const CarteSigh(
          titre: 'Tableau de morbidité',
          child: VideSigh('Aucun cas rattaché à une pathologie.',
              indice:
                  'Les consultations enregistrées avant la mise en place du référentiel ne portent qu’un diagnostic rédigé : elles ne peuvent pas être comptées rétrospectivement.',
              icone: LucideIcons.activity));
    }
    final parChapitre = <String, int>{};
    for (final x in rows) {
      parChapitre['${x['chapitreLabel']}'] =
          (parChapitre['${x['chapitreLabel']}'] ?? 0) + (x['cas'] as int);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (_, w) {
        final gauche = CarteSigh(
            titre: 'Les pathologies les plus fréquentes',
            child: ClassementLabo([
              for (final x in rows.take(12)) ('${x['libelle']}', x['cas'] as int)
            ], unite: 'cas'));
        final droite = CarteSigh(
            titre: 'Répartition par chapitre',
            child: GraphiqueAnneau(
                etiquettes: parChapitre.keys.toList(),
                valeurs: parChapitre.values.map((e) => e.toDouble()).toList(),
                hauteur: 300));
        return w.maxWidth >= 1024
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: gauche),
                const SizedBox(width: 16),
                Expanded(child: droite),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [gauche, const SizedBox(height: 16), droite]);
      }),
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Tableau de morbidité',
        lignes: rows,
        taillePage: 20,
        triInitial: 'cas',
        sensInitial: 'desc',
        nomExport: 'morbidite',
        colonnes: [
          ColonneTableau(
              cle: 'code',
              libelle: 'Code',
              sansCoupure: true,
              rendu: (_, x) => Text('${x['code']}', style: styleMonoCs)),
          ColonneTableau(
              cle: 'libelle',
              libelle: 'Pathologie',
              rendu: (_, x) => Text('${x['libelle']}',
                  style: const TextStyle(
                      color: JetonsShell.slate800,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w500))),
          const ColonneTableau(cle: 'chapitreLabel', libelle: 'Chapitre'),
          _colDeclaration(),
          ColonneTableau(
              cle: 'cas',
              libelle: 'Cas',
              droite: true,
              texte: (x) => nombre(x['cas']),
              rendu: (_, x) => Text(nombre(x['cas']),
                  style: const TextStyle(
                      color: JetonsShell.slate900, fontSize: 14, fontWeight: FontWeight.w600))),
        ],
        actions: [
          BoutonSigh(
              libelle: 'Imprimer le tableau',
              icone: LucideIcons.printer,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () => _imprimer(rows)),
        ],
      ),
    ]);
  }

  ColonneTableau _colDeclaration() => ColonneTableau(
      cle: 'notifiable',
      libelle: 'Déclaration',
      texte: (x) => vrai(x['notifiable']) ? 'obligatoire' : '',
      valeur: (x) => vrai(x['notifiable']) ? 'obligatoire' : '',
      rendu: (_, x) => vrai(x['notifiable'])
          ? const BadgeSigh('Obligatoire', ton: TonSigh.danger)
          : const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 12)));

  Widget _referentiel(List<Fiche> rows) => TableauSigh(
        titre: 'Référentiel des pathologies',
        lignes: rows,
        taillePage: 25,
        triInitial: 'chapitreLabel',
        nomExport: 'pathologies',
        filtres: [
          FiltreTableau(nom: 'chapitre', libelle: 'Chapitre', options: [
            for (final x in csChapitresPathologie)
              OptionChamp('${x['id']}', '${x['label']}')
          ]),
          FiltreTableau(
              nom: 'notifiable',
              libelle: 'Déclaration obligatoire',
              options: const [
                OptionChamp('oui', 'Notifiable'),
                OptionChamp('non', 'Non notifiable')
              ],
              correspond: (r, v) => v == 'oui' ? vrai(r['notifiable']) : !vrai(r['notifiable'])),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'code',
              libelle: 'Code',
              sansCoupure: true,
              rendu: (_, x) => Text('${x['code']}', style: styleMonoCs)),
          const ColonneTableau(cle: 'libelle', libelle: 'Pathologie'),
          ColonneTableau(
              cle: 'chapitreLabel',
              libelle: 'Chapitre',
              rendu: (_, x) => BadgeSigh('${x['chapitreLabel']}', ton: TonSigh.navy)),
          _colDeclaration(),
          const ColonneTableau(cle: 'cas', libelle: 'Cas enregistrés', droite: true),
          ColonneTableau(
              cle: 'aValider',
              libelle: 'Provenance',
              droite: true,
              texte: (x) => vrai(x['aValider']) ? 'à valider' : 'arrêtée',
              rendu: (_, x) => vrai(x['aValider'])
                  ? const BadgeSigh('À valider', ton: TonSigh.attention)
                  : const BadgeSigh('Arrêtée', ton: TonSigh.succes)),
        ],
        actions: [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Nouvelle pathologie',
                icone: LucideIcons.plus,
                taille: TailleBouton.sm,
                onPressed: () => _ouvrir(null)),
        ],
        actionsLigne: (context, r) => [
          if (c.droit.editer)
            BoutonIcone(
                icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _ouvrir(r)),
          if (c.droit.annuler)
            BoutonIcone(
                icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(r)),
        ],
      );
}
