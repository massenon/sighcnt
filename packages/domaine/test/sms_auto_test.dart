// LES ENVOIS AUTOMATIQUES DE SMS (lot SMS-R, ADR-0008) : les règles pures rejouées sur les vecteurs tirés de la maquette (`build/vecteurs-sms-auto.js`), plus ce que les vecteurs ne disent pas :
// les défauts semés, la famille réservée à la mère, les bornes du réglage, le numéro E.164, les heures calmes.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

ReglageSmsAuto _reglage(Map<String, Object?> j) => ReglageSmsAuto(
      rappelHeure: j['rappelHeure'] as int,
      rappelJoursAvant: j['rappelJoursAvant'] as int,
      anniversaireHeure: j['anniversaireHeure'] as int,
      calmeDebut: j['calmeDebut'] as int,
      calmeFin: j['calmeFin'] as int,
      horizonJours: j['horizonJours'] as int,
      toleranceMinutes: j['toleranceMinutes'] as int,
      modeleRappel: j['modeleRappel'] as String,
      modeleAnniversairePatient: j['modeleAnniversairePatient'] as String,
      modeleAnniversairePersonnel: j['modeleAnniversairePersonnel'] as String,
    );

List<Map<String, Object?>> _fiches(Object? l) => [for (final x in liste(l)) (x as Map).cast<String, Object?>()];

void main() {
  final cas = liste(lireVecteurs('sms_auto')['cas']);

  group('vecteurs de la maquette (${cas.length} cas)', () {
    for (final c in cas) {
      final e = (c['entree'] as Map).cast<String, Object?>();
      test('${c['op']} : ${c['nom']}', () {
        if (c['op'] == 'planifier') {
          final plan = smsPlanifier(
            maintenant: DateTime.parse('${e['maintenant']}:00'),
            reglage: _reglage((e['reglage'] as Map).cast<String, Object?>()),
            consultations: _fiches(e['consultations']),
            patients: _fiches(e['patients']),
            deces: _fiches(e['deces']),
            employes: _fiches(e['employes']),
            clinique: '${e['clinique']}',
            telephone: '${e['telephone']}',
          );
          memes({'envois': [for (final x in plan.envois) x.toJson()], 'ecartes': [for (final x in plan.ecartes) x.toJson()]}, c['attendu'], 'plan');
        } else {
          final r = smsVerifierModele('${e['modele']}');
          final att = (c['attendu'] as Map?)?.cast<String, Object?>();
          expect(r?.code, att?['code'], reason: '${c['nom']}');
        }
      });
    }
  });

  group('défauts semés et réglage', () {
    test('les défauts validés par la Direction (AQ 27 et 28)', () {
      const r = ReglageSmsAuto();
      expect([r.rappelHeure, r.rappelJoursAvant, r.anniversaireHeure, r.calmeDebut, r.calmeFin], [18, 1, 9, 21, 7]);
      expect(r.actif, isFalse, reason: 'désactivés par défaut : proposition à valider');
      expect(smsVerifierReglage(r), isNull, reason: 'les modèles par défaut sont valides');
    });

    test('la famille sms est déclarée, réservée à la mère, jamais vers un téléphone', () {
      final defs = definitionsParametres.where((d) => d.famille == smsFamille).toList();
      expect(defs.length, 11);
      for (final d in defs) {
        expect(d.mobile, isFalse);
        expect(definitionDeParametre(d.cle), isNotNull);
      }
      expect(parFamillesJamaisMobile, contains('sms'));
      expect(parFamillesReglageDedie, contains('sms'));
      expect(definitionDeParametre(smsCleRappelHeure)!.defaut, 18);
      expect(definitionDeParametre(smsCleAnniversaireHeure)!.defaut, 9);
    });

    test('les bornes du réglage sont refusées en les nommant', () {
      expect(smsVerifierReglage(const ReglageSmsAuto(rappelHeure: 24))?.code, 'HEURE_HORS_BORNES');
      expect(smsVerifierReglage(const ReglageSmsAuto(rappelJoursAvant: 8))?.code, 'JOURS_HORS_BORNES');
      expect(smsVerifierReglage(const ReglageSmsAuto(horizonJours: 0))?.code, 'HORIZON_HORS_BORNES');
      expect(smsVerifierReglage(const ReglageSmsAuto(toleranceMinutes: 181))?.code, 'TOLERANCE_HORS_BORNES');
      expect(smsVerifierReglage(const ReglageSmsAuto(modeleRappel: 'Rendez-vous avec {{medecin}}'))?.code, 'VARIABLE_INCONNUE');
      expect(smsVerifierReglage(const ReglageSmsAuto(modeleAnniversairePersonnel: 'Votre résultat est positif'))?.code, 'MOT_MEDICAL');
    });
  });

  group('numéro, masque, heures calmes', () {
    test('E.164', () {
      expect(smsNumeroE164('01 97 00 00 01'), '+2290197000001');
      expect(smsNumeroE164('00229 97000001'), '+22997000001');
      expect(smsNumeroE164('+229 97 00 00 01'), '+22997000001');
      expect(smsNumeroE164('97000001'), isNull, reason: 'sans indicatif ni préfixe 01 : refusé, jamais deviné');
      expect(smsNumeroE164(null), isNull);
      expect(smsMasquer('+22997000001'), '••••0001');
    });

    test('heures calmes à cheval sur minuit', () {
      expect(smsApresHeuresCalmes(DateTime(2026, 11, 16, 22), 21, 7), DateTime(2026, 11, 17, 7));
      expect(smsApresHeuresCalmes(DateTime(2026, 11, 16, 3), 21, 7), DateTime(2026, 11, 16, 7));
      expect(smsApresHeuresCalmes(DateTime(2026, 11, 16, 18), 21, 7), DateTime(2026, 11, 16, 18));
      expect(smsApresHeuresCalmes(DateTime(2026, 11, 16, 7), 21, 7), DateTime(2026, 11, 16, 7), reason: 'la fin est ouverte');
    });

    test('un rappel ne peut pas nommer le médecin : aucune variable pour lui', () {
      expect(smsVariables, ['nom', 'date', 'heure', 'clinique', 'telephone']);
      final t = smsComposer('Dr {{medecin}} vous attend', {'medecin': 'SECRET'});
      expect(t, 'Dr  vous attend');
    });
  });
}
