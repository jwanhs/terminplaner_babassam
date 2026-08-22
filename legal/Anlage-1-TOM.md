# Anlage 1 — Technische und organisatorische Maßnahmen (Art. 32 DSGVO)

> **Entwurf.** Keine Rechtsberatung; anwaltlich nicht geprüft.
>
> Diese Anlage beschreibt, was die Software tatsächlich tut, mit Verweis auf
> die Stelle im Quelltext. Sie ist bewusst keine Ankreuzliste: Maßnahmen, die
> nicht umgesetzt sind, stehen unter „Offene Punkte" und nicht im Fließtext.
> Wer sie fortschreibt, ändert zuerst den Code und dann diesen Text.

Stand: `[Datum]` · Version der Software: `[Git-Commit oder Release]`

---

## 1. Vertraulichkeit (Art. 32 Abs. 1 lit. b DSGVO)

### 1.1 Zugriffskontrolle — Trennung von Kundenanwendung und Datenbestand

Die Kundenanwendung besitzt **keinerlei Zugriff auf die Termintabelle**. Die
Tabelle `appointments`, die Name, Telefonnummer und Aufenthaltszeit jedes
Kunden enthält, ist ausschließlich für das Team `staff` berechtigt; für
anonyme Nutzer besteht keine Berechtigung — weder lesend noch schreibend
(`infra/setup_barber_db.sh`).

Jeder Zugriff eines Kunden läuft stattdessen über eine einzige serverseitige
Schnittstelle (`booking-api`), die einen Server-Schlüssel hält, der die
Anwendung nie erreicht. Die Schnittstelle entscheidet für jede Anfrage
eigenständig über die Berechtigung; die Anwendung kann die Prüfung nicht
umgehen, weil sie den Datenbestand nicht direkt erreichen kann.

Eine automatisierte Prüfung in der Continuous Integration bricht den Build ab,
sobald die Termintabelle eine öffentliche Berechtigung erhielte
(`.github/workflows/ci.yml`).

### 1.2 Zugangskontrolle — Nachweis der Berechtigung ohne Benutzerkonto

Kunden buchen ohne Registrierung. Die Berechtigung an einer Buchung wird
stattdessen so nachgewiesen:

- Bei der Buchung erzeugt der Server ein Verwaltungs-Token mit 256 Bit
  Entropie, gibt es einmalig zurück und speichert **ausschließlich dessen
  SHA-256-Hash** (`infra/functions/booking-api/src/tokens.js`). Aus dem
  gespeicherten Bestand lässt sich das Token nicht rekonstruieren.
- Auf einem neuen Gerät wird stattdessen die Rufnummer per Einmalcode (SMS)
  bestätigt. Die Kenntnis einer Telefonnummer allein gibt keine Auskunft über
  Termine — dies ist durch Tests abgesichert
  (`infra/functions/booking-api/test/api.test.js`).

Mitarbeitende melden sich mit E-Mail-Adresse und Passwort an. Der Zugriff auf
das Personal-Panel setzt die Mitgliedschaft im Team `staff` voraus; die
Tabellenberechtigungen sind an genau dieses Team gebunden.

### 1.3 Trennungskontrolle

Jeder Auftraggeber wird in einem **eigenen, getrennten Projekt** mit eigenem
Datenbestand betrieben. Eine mandantenübergreifende Abfrage ist nicht
vorgesehen und technisch nicht möglich, da die Systeme keine gemeinsame
Datenbank teilen.

Interne Tabellen für Einmalcodes (`otp_codes`) und Anfragebegrenzung
(`rate_limits`) sind ohne jede Berechtigung angelegt und damit ausschließlich
über den Server-Schlüssel erreichbar.

### 1.4 Pseudonymisierung und Verschlüsselung

- Verwaltungs-Token werden ausschließlich als SHA-256-Hash gespeichert (s. 1.2).
- Passwörter der Mitarbeitenden werden vom eingesetzten Backend-Dienst
  ausschließlich als Hash gespeichert.
- **Kartendaten werden zu keinem Zeitpunkt verarbeitet oder gespeichert.** Die
  Zahlungsabwicklung erfolgt vollständig beim Zahlungsdienstleister; gespeichert
  wird nur dessen Vorgangskennung sowie der Zahlungsstatus.

## 2. Integrität (Art. 32 Abs. 1 lit. b DSGVO)

### 2.1 Weitergabekontrolle — Transportverschlüsselung

Die gesamte Kommunikation erfolgt über TLS. Eine Freigabe-Version der Anwendung
**verweigert den Start**, wenn sie mit unverschlüsseltem Endpunkt oder mit
abgeschalteter Zertifikatsprüfung gebaut wurde (`Env.assertSafe()` in
`lib/core/env.dart`). Eine Fehlkonfiguration führt damit zu einem sofortigen,
sichtbaren Abbruch statt zu unbemerkt ungeschütztem Datenverkehr.

### 2.2 Eingabekontrolle — serverseitige Entscheidung über alle Fakten

Sicherheitsrelevante Tatsachen werden nicht von der Anwendung übernommen,
sondern serverseitig festgestellt:

| Tatsache | Wo entschieden |
| --- | --- |
| Ob ein Termin frei ist | serverseitig, erneut zum Schreibzeitpunkt geprüft, zusätzlich durch einen eindeutigen Datenbankindex auf `slot_key` abgesichert |
| Was eine Leistung kostet | serverseitig aus der Leistungstabelle, nie aus der Anfrage |
| Ob bezahlt wurde | ausschließlich durch den signaturgeprüften Webhook des Zahlungsdienstleisters |
| Ob eine Stornofrist eingehalten ist | serverseitig aus den Einstellungen des Auftraggebers |
| Ob eine Prämie zusteht | serverseitig aus der Buchungshistorie neu berechnet |

Doppelbuchungen werden durch einen eindeutigen Index auf Datenbankebene
verhindert, nicht durch Anwendungslogik.

Zeitberechnungen erfolgen serverseitig in der Zeitzone des Auftraggebers, nicht
in der Gerätezeitzone des Kunden; Zeitumstellungen sind ausdrücklich behandelt
und durch Tests abgedeckt.

### 2.3 Keine Zugriffsprotokolle des Webservers

Der Webserver, der die Buchungsseite ausliefert, führt **kein
Zugriffsprotokoll**. Es wird also nicht festgehalten, welche IP-Adresse wann
welche Seite abgerufen hat. Protokolliert werden ausschließlich Start- und
Fehlermeldungen des Dienstes selbst, ohne Bezug zu einzelnen Besuchern.

### 2.4 Begrenzung missbräuchlicher Zugriffe

Anfragen werden serverseitig gezählt und begrenzt
(`infra/functions/booking-api/src/ratelimit.js`), um automatisiertes Ausprobieren
von Rufnummern oder Einmalcodes zu erschweren.

## 3. Verfügbarkeit und Belastbarkeit (Art. 32 Abs. 1 lit. c DSGVO)

Betrieb, Redundanz und Sicherung der Infrastruktur erfolgen durch den in
Anlage 2 genannten Hosting-Dienstleister nach dessen Zusagen. Die dortigen
Angaben sind maßgeblich und vor Vertragsschluss zu prüfen.

## 4. Verfahren zur regelmäßigen Überprüfung (Art. 32 Abs. 1 lit. d DSGVO)

- Die Zugriffsregeln sind durch eine automatisierte Testsuite abgedeckt, die
  bei jeder Änderung ausgeführt wird: dass ein Fremder eine Buchung nicht
  stornieren kann, dass eine Rufnummer allein nichts preisgibt, dass der
  Client keinen Preis diktieren kann, dass zwei Personen nicht denselben
  Termin belegen können und dass eine Prämie ohne die zugehörigen Besuche
  nicht eingelöst werden kann.
- Die Continuous Integration bricht ab, wenn die Termintabelle eine
  öffentliche Berechtigung erhielte (s. 1.1).
- Änderungen erfolgen über Versionsverwaltung und sind nachvollziehbar.

---

## Offene Punkte

Diese Maßnahmen sind **nicht** umgesetzt. Sie stehen hier, damit niemand sie
aus dem Fließtext oben herausliest, und sind vor einer Zusage gegenüber
Auftraggebern zu schließen:

1. **Automatische Löschung.** Es existiert weder eine festgelegte
   Aufbewahrungsfrist noch ein Löschlauf für Termindaten. § 10 Abs. 4 des AVV
   ist bis dahin nicht erfüllbar.
2. **Protokollierung von Zugriffen des Personals.** Es wird nicht
   protokolliert, welche Mitarbeitenden welche Kundendatensätze eingesehen
   haben. Für eine nachträgliche Aufklärung eines Missbrauchsverdachts fehlt
   damit die Grundlage.
3. **Eigenes Sicherungs- und Wiederherstellungskonzept.** Derzeit wird
   vollständig auf den Hosting-Dienstleister vertraut; eine eigene
   Wiederherstellungsprüfung findet nicht statt.
4. **Verfahren zur Erkennung von Störungen.** Eine Fehler- und
   Absturzerfassung ist nicht eingerichtet.
5. **Schriftliche Verpflichtung auf Vertraulichkeit.** § 4 Nr. 2 des AVV setzt
   sie voraus; ein Formular dafür existiert noch nicht.
