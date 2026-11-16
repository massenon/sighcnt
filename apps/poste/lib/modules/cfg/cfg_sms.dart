import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:sigh_domaine/sigh_domaine.dart' show smsGesteRegler;

import '../../core/jetons_shell.dart';
import '../../donnees/sms_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';

/// `cfg-sms` : la PASSERELLE SMS (lot SMS-R, ADR-0008). L'état se lit au relais par la mère (`/admin/sms/etat`) : fournisseur, identifiants « défini » ou « non défini » (jamais leur valeur),
/// plafond du jour. La mère CALCULE les envois automatiques (rappel la veille d'un rendez-vous, vœux d'anniversaire) et les DÉPOSE au relais, qui les envoie puis efface le clair.
/// Les commandes (activer, calculer et déposer maintenant, tester l'envoi) sont ABSENTES sans le geste réservé `regler_passerelle_sms` et hors du poste mère ; le moteur refuse aussi.
class EcranPasserelleSms extends StatefulWidget with EcranMaquette {
  const EcranPasserelleSms({super.key});
  @override
  String get titre => 'Passerelle SMS';
  @override
  String get description => 'Fournisseur de SMS de la clinique (Twilio ou Vonage), plafond, heures calmes et test d’envoi : les patients, et le personnel qui y consent, reçoivent des SMS.';
  @override
  String get regle =>
      'Le relais ne voit un SMS que le temps de l’envoi (numéro, texte, heure, type, identifiant opaque) puis efface le clair. Les identifiants du fournisseur sont dans le .env du relais : l’écran dit seulement « défini » ou « non défini ».';

  @override
  State<EcranPasserelleSms> createState() => _EtatPasserelleSms();
}

class _EtatPasserelleSms extends State<EcranPasserelleSms> {
  ControleurFormulaire? _test, _reglage;
  bool _demande = false;
  Map<String, Object?>? _resultatTest;
  SmsPoste? _transitoire;

  @override
  void initState() {
    super.initState();
    _test = ControleurFormulaire(const [
      ChampDef(nom: 'numero', libelle: 'Numéro de test (format international)', requis: true, col: ColChamp.plein, aide: 'Par exemple +22900000000. Un message de contrôle imposé y est envoyé.'),
    ], {'numero': ''});
    _reglage = ControleurFormulaire(const [
      ChampDef(nom: 'actif', libelle: 'Passerelle active', type: TypeChamp.case_, col: ColChamp.plein, aide: 'Active les envois automatiques (rappel de rendez-vous, vœux d’anniversaire) : la mère les calcule et les dépose au relais. Désactivée, seul le test envoie.'),
    ], {'actif': false});
  }

  @override
  void dispose() {
    _test?.dispose();
    _reglage?.dispose();
    super.dispose();
  }

  static String _hm(Object? iso) => '$iso'.replaceFirst('T', ' à ');

  static const _types = {'rappel_rdv': 'Rappel de rendez-vous', 'anniversaire_patient': 'Anniversaire d’un patient', 'anniversaire_personnel': 'Anniversaire du personnel', 'test': 'Test'};

  void _toast(BuildContext ctx, RefusSmsPoste r) => ToastsSigh.afficher(ctx, '${r.code} : ${r.motif} ${r.geste}', type: TypeToast.erreur);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    // Écran ouvert hors d'un poste équipé (tests de parité) : une passerelle transitoire sans source dit « lue au poste mère », sans rien installer.
    final s = SmsPoste.de(c.magasin) ?? (_transitoire ??= SmsPoste(c.magasin));
    if (!_demande) {
      _demande = true;
      _reglage!.poser('actif', s.actif);
      WidgetsBinding.instance.addPostFrameCallback((_) => s.rafraichir());
    }
    return ListenableBuilder(listenable: Listenable.merge([s, _test!, _reglage!]), builder: (ctx, _) => _corps(ctx, c, s));
  }

  Widget _corps(BuildContext ctx, ContexteEcran c, SmsPoste s) {
    final e = s.etatMere;
    final pass = (e?['passerelle'] as Map?);
    final mere = s.source != null;
    // Une commande est ABSENTE sans le geste réservé de la fiche RBAC (lu à chaud) et sur un fileul rattaché ; le moteur (SmsPoste et la mère) refuse aussi.
    final droit = c.donnees?.matrice.droitGeste(c.role, smsGesteRegler) ?? s.peutRegler(c.role);
    final regle = droit && !s.estFileul();
    final defini = pass?['identifiantsDefinis'] == true;
    final prete = pass?['configuree'] == true;
    final reglages = (pass?['reglages'] as Map?);
    final planifies = [for (final p in ((e?['planifies'] as List?) ?? const [])) (p as Map).cast<String, Object?>()];
    final dernier = (e?['dernier'] as Map?);
    final erreur = (e?['erreur'] as Map?);
    final rt = _resultatTest;
    final fournisseur = pass == null || '${pass['fournisseur']}'.isEmpty ? 'Non choisi' : '${pass['fournisseur']}'[0].toUpperCase() + '${pass['fournisseur']}'.substring(1);
    final secret = pass == null ? 'Lu au poste mère' : (defini ? 'Défini dans le .env du relais' : 'Non défini dans le .env du relais');
    return cfaPile([
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Passerelle', valeur: !mere ? 'Lue au poste mère' : (pass == null ? 'Relais non joint' : (prete ? 'Prête' : 'Non configurée')), icone: LucideIcons.messageSquare, ton: prete ? TonSigh.succes : TonSigh.attention),
        KpiSigh(libelle: 'Activation', valeur: s.reglageRecu ? (s.actif ? 'Active' : 'Désactivée') : 'Non reçue', icone: LucideIcons.power, ton: s.actif ? TonSigh.succes : TonSigh.neutre),
        KpiSigh(libelle: 'Dernier test', valeur: rt == null ? 'Jamais fait' : (rt['ok'] == true ? 'Réussi' : 'Échoué'), icone: LucideIcons.send, ton: rt == null ? TonSigh.neutre : (rt['ok'] == true ? TonSigh.succes : TonSigh.danger)),
        KpiSigh(libelle: 'Envois aujourd’hui', valeur: pass == null ? 'Inconnu' : '${pass['envoyesAujourdhui']} sur ${reglages?['plafond_jour']}', icone: LucideIcons.gauge, ton: TonSigh.navy),
      ]),
      if (s.estFileul()) cfbNote('Ce poste lit le réglage de la clinique : la passerelle se règle sur le poste mère.', ton: 'info', icone: LucideIcons.lock),
      if (!mere && !s.estFileul()) cfbNote('L’état de la passerelle et ses gestes se lisent sur le poste mère.', ton: 'info', icone: LucideIcons.info),
      if (s.erreurEtat != null) cfbNote('${s.erreurEtat!.code} : ${s.erreurEtat!.motif} ${s.erreurEtat!.geste}', ton: 'warning', icone: LucideIcons.triangleAlert),
      if (e?['erreurRelais'] != null) cfbNote('Relais : ${(e!['erreurRelais'] as Map)['code']} : ${(e['erreurRelais'] as Map)['motif']} ${(e['erreurRelais'] as Map)['geste']}', ton: 'warning', icone: LucideIcons.cloudOff),
      CarteSigh(
          titre: 'Réglages de la passerelle',
          child: cfaPile([
            // Le fournisseur, le plafond et les identifiants sont ceux du RELAIS (.env et réglages du relais) : lus, jamais saisis ici ; un secret ne s'affiche jamais.
            DescListeSigh([
              ('Fournisseur *', pass == null ? 'Lu au poste mère' : fournisseur),
              ('Plafond par jour *', reglages == null ? 'Lu au poste mère' : '${reglages['plafond_jour']} messages (réglé au panneau du relais)'),
              ('Account SID Twilio', secret),
              ('Jeton d’authentification Twilio', secret),
              ('Messaging Service SID Twilio (facultatif)', 'Non utilisé : un seul numéro expéditeur'),
              ('Expéditeur', pass == null ? 'Lu au poste mère' : (pass['expediteurDefini'] == true ? 'Défini dans le .env du relais' : 'Non défini dans le .env du relais')),
              ('Début des heures calmes (heure)', '${s.calmeDebut} h'),
              ('Fin des heures calmes (heure)', '${s.calmeFin} h'),
              ('État des envois automatiques', s.reglageRecu ? (s.actif ? 'ACTIFS' : 'Désactivés') : 'Réglage non encore reçu du poste mère'),
              ('Rappel de rendez-vous', 'la veille à ${s.rappelHeure} h'),
              ('Rappel du matin même', 'à ${s.rappelHeureMatin} h le jour du rendez-vous, si celui-ci n’a été connu de la mère qu’après l’envoi de la veille ; jamais à l’heure du rendez-vous ni après'),
              ('Vœux d’anniversaire', 'à ${s.anniversaireHeure} h (patients, et personnel qui y consent)'),
              if (dernier != null) ('Dernier calcul', '${dernier['calcules']} calculé(s), ${dernier['planifies']} déposé(s), ${dernier['retires']} retiré(s), ${(dernier['ecartes'] as Map).values.fold<int>(0, (a, b) => a + (b as int))} écarté(s)'),
            ]),
            if (erreur != null) cfbNote('Dernier calcul refusé : ${erreur['code']} : ${erreur['motif']} ${erreur['geste']}', ton: 'warning', icone: LucideIcons.triangleAlert),
            const NoteSigh('Le consentement est contrôlé à la mère : un patient qui retire le sien, un rendez-vous annulé ou déplacé, un numéro corrigé retire l’envoi planifié au relais. Un envoi déjà parti ne se retire pas.', key: Key('sms:consentement'), ton: TonSigh.info),
            if (regle) FormulaireSigh(controleur: _reglage!),
            if (regle)
              Wrap(spacing: 8, runSpacing: 8, children: [
                BoutonSigh(
                    key: const Key('sms:enregistrer'),
                    libelle: 'Enregistrer la passerelle',
                    icone: LucideIcons.save,
                    onPressed: () {
                      final r = s.definirActif(role: c.role, actif: _reglage!['actif'] == true);
                      if (r != null) {
                        _toast(ctx, r);
                      } else {
                        ToastsSigh.afficher(ctx, 'Passerelle enregistrée.', type: TypeToast.succes);
                      }
                    }),
                if (s.actif)
                  BoutonSigh(
                      key: const Key('sms:calculer'),
                      libelle: s.enCours ? 'En cours…' : 'Calculer et déposer maintenant',
                      icone: LucideIcons.cloudUpload,
                      variante: VarianteBouton.secondaire,
                      onPressed: s.enCours
                          ? null
                          : () async {
                              final (r, refus) = await s.calculerMaintenant(role: c.role);
                              if (!ctx.mounted) return;
                              if (refus != null) {
                                _toast(ctx, refus);
                              } else {
                                ToastsSigh.afficher(ctx, '${r!['calcules']} envoi(s) calculé(s), ${r['planifies']} déposé(s) au relais, ${r['retires']} retiré(s).');
                              }
                            }),
              ]),
          ])),
      CarteSigh(
          titre: 'Test d’envoi',
          child: cfaPile([
            if (regle) ...[
              FormulaireSigh(controleur: _test!),
              Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonSigh(
                      key: const Key('sms:tester'),
                      libelle: s.enCours ? 'En cours…' : 'Tester l’envoi',
                      icone: LucideIcons.send,
                      onPressed: s.enCours
                          ? null
                          : () async {
                              final v = _test!.valider();
                              if (v == null) return;
                              final (r, refus) = await s.tester(role: c.role, numero: '${v['numero']}'.trim());
                              if (!mounted) return;
                              setState(() => _resultatTest = refus != null ? {'ok': false, 'code': refus.code, 'motif': refus.motif, 'geste': refus.geste} : r);
                            })),
            ] else
              const Text('Le test d’envoi se lance depuis le poste mère par un agent habilité (droit réservé « Régler la passerelle SMS »).', key: Key('sms:test-absent'), style: TextStyle(fontSize: 14, color: JetonsShell.slate600)),
            if (rt != null)
              cfbNote(rt['ok'] == true ? 'Accepté par le fournisseur (identifiant ${rt['idFournisseur']}).' : '${rt['code']} : ${rt['motif']} ${rt['geste']}',
                  ton: rt['ok'] == true ? 'success' : 'danger', icone: rt['ok'] == true ? LucideIcons.circleCheck : LucideIcons.circleX),
          ])),
      CarteSigh(
          titre: 'Envois automatiques planifiés',
          sansRemplissage: true,
          child: MiniTableauSigh(
              vide: 'Aucun envoi planifié.',
              colonnes: [
                ColonneMini('Heure d’envoi', (m) => _hm(m['heure'])),
                ColonneMini('Type', (m) => _types['${m['type']}'] ?? '${m['type']}'),
                ColonneMini('Numéro', (m) => '${m['numeroMasque']}'),
              ],
              lignes: planifies)),
      const NoteSigh('Ce que le relais ne voit jamais : l’annuaire, une date de naissance, un code de patient, un rendez-vous, le médecin, le service, le motif, une donnée de santé.', key: Key('sms:opaque'), ton: TonSigh.info, icone: LucideIcons.eyeOff),
    ]);
  }
}

/// `m13-sms-journal` : le JOURNAL des envois, en lecture seule, lu au relais par la mère. Le numéro est MASQUÉ (quatre derniers chiffres), le texte n'y est jamais.
class EcranJournalSms extends StatefulWidget with EcranMaquette {
  const EcranJournalSms({super.key});
  @override
  String get titre => 'Journal des envois SMS';
  @override
  String get description => 'Les envois de la passerelle SMS : motif, statut, refus nommé, numéro masqué et identifiant chez le fournisseur.';
  @override
  String get regle => 'Lecture seule. Le journal ne garde ni le numéro en clair ni le texte du message : le relais les efface dès l’envoi.';

  @override
  State<EcranJournalSms> createState() => _EtatJournalSms();
}

class _EtatJournalSms extends State<EcranJournalSms> {
  bool _demande = false;
  ControleurFormulaire? _du, _au;
  SmsPoste? _transitoire;

  @override
  void initState() {
    super.initState();
    _du = ControleurFormulaire(const [ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date)], {'du': ''});
    _au = ControleurFormulaire(const [ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date)], {'au': ''});
  }

  @override
  void dispose() {
    _du?.dispose();
    _au?.dispose();
    super.dispose();
  }

  static String _quand(Object? ms) => ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal().toString().substring(0, 16) : '';
  static String _jour(Object? ms) => _quand(ms).split(' ').first;

  static const _etats = {'envoye': 'Accepté', 'refuse': 'Refusé', 'planifie': 'Reporté (planifié)', 'encours': 'En cours', 'retire': 'Retiré'};
  static const _types = {'rappel_rdv': 'Rappel de rendez-vous', 'anniversaire_patient': 'Anniversaire d’un patient', 'anniversaire_personnel': 'Anniversaire du personnel', 'test': 'Test'};

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final s = SmsPoste.de(c.magasin) ?? (_transitoire ??= SmsPoste(c.magasin));
    if (!_demande) {
      _demande = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => s.rafraichirJournal());
    }
    return ListenableBuilder(
        listenable: Listenable.merge([s, _du!, _au!]),
        builder: (ctx, _) {
          final tout = s.journalMere ?? const <Map<String, Object?>>[];
          final du = '${_du!['du'] ?? ''}', au = '${_au!['au'] ?? ''}';
          final lignes = [
            for (final m in tout)
              if ((du.isEmpty || _jour(m['maj']).compareTo(du) >= 0) && (au.isEmpty || _jour(m['maj']).compareTo(au) <= 0)) m
          ];
          int n(String etat) => lignes.where((m) => m['etat'] == etat).length;
          final auj = c.aujourdhui;
          String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          void poser(String a, String b) {
            _du!.poser('du', a);
            _au!.poser('au', b);
          }

          return cfaPile([
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Envois journalisés', valeur: '${lignes.length}', icone: LucideIcons.messagesSquare, ton: TonSigh.navy),
              KpiSigh(libelle: 'Acceptés', valeur: '${n('envoye')}', icone: LucideIcons.circleCheck, ton: TonSigh.succes),
              KpiSigh(libelle: 'Refusés', valeur: '${n('refuse')}', icone: LucideIcons.circleX, ton: n('refuse') > 0 ? TonSigh.danger : TonSigh.neutre),
              KpiSigh(libelle: 'Reportés', valeur: '${n('planifie')}', icone: LucideIcons.clock, ton: TonSigh.attention),
            ]),
            if (s.source == null) cfbNote(s.estFileul() ? 'Ce poste est rattaché : le journal des envois se lit sur le poste mère.' : 'Le journal des envois se lit sur le poste mère.', ton: 'info', icone: LucideIcons.info),
            if (s.erreurEtat != null) cfbNote('${s.erreurEtat!.code} : ${s.erreurEtat!.motif} ${s.erreurEtat!.geste}', ton: 'warning', icone: LucideIcons.triangleAlert),
            CarteSigh(
                child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
              SizedBox(width: 170, child: FormulaireSigh(controleur: _du!)),
              SizedBox(width: 170, child: FormulaireSigh(controleur: _au!)),
              BoutonSigh(libelle: 'Aujourd’hui', icone: LucideIcons.calendar, variante: VarianteBouton.secondaire, onPressed: () => poser(iso(auj), iso(auj))),
              BoutonSigh(libelle: 'Sept derniers jours', icone: LucideIcons.calendarDays, variante: VarianteBouton.secondaire, onPressed: () => poser(iso(auj.subtract(const Duration(days: 6))), iso(auj))),
              BoutonSigh(libelle: 'Toute la période', icone: LucideIcons.calendarOff, variante: VarianteBouton.secondaire, onPressed: () => poser('', '')),
            ])),
            OngletsSigh(onglets: [
              OngletDef(
                  id: 'tous',
                  libelle: 'Tous les envois',
                  compte: lignes.length,
                  construire: (_) => TableauSigh(
                      nomExport: 'journal-sms',
                      selectionnable: false,
                      messageVide: 'Aucun envoi.',
                      colonnes: [
                        ColonneTableau(cle: 'maj', libelle: 'Mis à jour', valeur: (m) => _quand(m['maj'])),
                        ColonneTableau(cle: 'type', libelle: 'Motif', valeur: (m) => _types['${m['type']}'] ?? '${m['type']}'),
                        ColonneTableau(cle: 'numeroMasque', libelle: 'Numéro'),
                        ColonneTableau(cle: 'etat', libelle: 'Statut', valeur: (m) => _etats['${m['etat']}'] ?? '${m['etat']}'),
                        ColonneTableau(cle: 'code', libelle: 'Refus nommé', valeur: (m) => '${m['code'] ?? ''}'),
                        ColonneTableau(cle: 'idFournisseur', libelle: 'Identifiant fournisseur', valeur: (m) => '${m['idFournisseur'] ?? ''}'),
                      ],
                      lignes: lignes)),
              OngletDef(
                  id: 'archives',
                  libelle: 'Archivés',
                  compte: 0,
                  construire: (_) => const NoteSigh('Aucun envoi archivé : le relais garde le journal 12 mois (sans numéro ni texte), puis le purge.', ton: TonSigh.info, icone: LucideIcons.archive)),
            ]),
          ]);
        });
  }
}
