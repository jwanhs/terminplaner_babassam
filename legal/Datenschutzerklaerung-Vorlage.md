# Datenschutzerklärung — Vorlage für die Buchungsseite des Salons

> **Entwurf.** Keine Rechtsberatung; anwaltlich nicht geprüft.
>
> Diese Erklärung gibt der **Salon** ab, nicht wir — er ist Verantwortlicher
> im Sinne der DSGVO. Wir liefern sie ausgefüllt mit, weil sonst niemand sie
> schreibt und die Buchungsseite ohne sie nicht online gehen sollte.
>
> Alle `[…]`-Stellen ausfüllen. Vor der Veröffentlichung prüfen lassen.
>
> **Zwei Abschnitte stimmen erst nach Änderungen am Code** — sie sind unten
> mit ⚠ markiert. Solange sie nicht zutreffen, darf die Erklärung so nicht
> veröffentlicht werden.

---

## 1. Verantwortlicher

    [Name des Salons]
    [Straße, Hausnummer]
    [PLZ, Ort]
    Telefon: [...]
    E-Mail: [...]

## 2. Wofür wir Ihre Daten verwenden

Wenn Sie über diese Seite einen Termin buchen, verarbeiten wir Ihre Daten,
um den Termin zu vereinbaren, ihn zu verwalten und Sie bei Rückfragen
erreichen zu können.

| Was wir speichern | Wozu |
| --- | --- |
| Ihr Name | damit wir wissen, wer kommt |
| Ihre Telefonnummer | um Sie bei Änderungen oder Rückfragen zu erreichen und damit Sie Ihren Termin auf einem neuen Gerät wiederfinden |
| Gewählte Leistung, Datum und Uhrzeit | um den Termin einzuplanen |
| Ihre Notiz, falls Sie eine hinterlassen | um Ihren Wunsch zu berücksichtigen |
| Zahlungsstatus und Betrag, falls Sie online anzahlen | zur Zuordnung der Zahlung |

**Rechtsgrundlage** ist Art. 6 Abs. 1 lit. b DSGVO — die Verarbeitung ist zur
Durchführung des Termins erforderlich, den Sie mit uns vereinbaren.

Bitte tragen Sie in das Notizfeld **keine Gesundheitsangaben** ein. Wenn für
Ihren Termin etwas Gesundheitliches wichtig ist, sagen Sie es uns bitte
persönlich vor Ort.

## 3. Wie wir Ihren Termin Ihnen zuordnen

Sie brauchen kein Benutzerkonto. Beim Buchen erhält Ihr Gerät einen geheimen
Schlüssel, mit dem Sie Ihren Termin ansehen, verschieben oder absagen können.
Bei uns wird von diesem Schlüssel nur eine nicht rückrechenbare Prüfsumme
gespeichert.

Öffnen Sie Ihre Termine auf einem anderen Gerät, bestätigen wir Ihre
Telefonnummer stattdessen mit einem Code per SMS. Die alleinige Kenntnis einer
Telefonnummer gibt keine Auskunft über Termine.

## 4. Wer Ihre Daten außerdem verarbeitet

- **Technischer Betrieb.** Unsere Terminverwaltung wird betrieben von
  `[Firmierung]`, `[Anschrift]`, auf Grundlage eines
  Auftragsverarbeitungsvertrages nach Art. 28 DSGVO. Serverstandort:
  `[…]`. ⚠ *Vor Veröffentlichung tatsächlich prüfen — siehe
  `Anlage-2-Unterauftragsverarbeiter.md`.*
- **Zahlungen.** Zahlen Sie online an, wird die Zahlung von Stripe abgewickelt.
  Ihre Kartendaten werden ausschließlich dort verarbeitet und erreichen weder
  uns noch unseren Dienstleister. Es gilt die Datenschutzerklärung von Stripe.
- **SMS-Versand.** Für den Bestätigungscode setzen wir `[Anbieter]` ein.
  *(Streichen, falls kein SMS-Versand aktiv ist.)*

Darüber hinaus geben wir Ihre Daten nicht weiter. Ihre Daten werden nicht für
Werbung ausgewertet und nicht an Vermittlungsportale übermittelt.

## 5. Wie lange wir Ihre Daten speichern

⚠ *Dieser Abschnitt ist erst zutreffend, wenn eine Frist festgelegt und die
automatische Löschung eingerichtet ist — siehe `legal/README.md`, Punkt 3.
Bis dahin darf hier keine Frist behauptet werden.*

Wir speichern Ihre Termindaten `[…]` Monate nach dem Termin und löschen sie
anschließend automatisch. Rechnungsbezogene Angaben bewahren wir so lange auf,
wie das Steuerrecht es verlangt.

## 6. Ihre Rechte

Sie haben das Recht auf Auskunft (Art. 15), Berichtigung (Art. 16), Löschung
(Art. 17), Einschränkung der Verarbeitung (Art. 18) und Datenübertragbarkeit
(Art. 20 DSGVO). Melden Sie sich dafür einfach bei uns — die Kontaktdaten
stehen oben.

Außerdem haben Sie das Recht, sich bei einer Datenschutz-Aufsichtsbehörde zu
beschweren. Zuständig ist die Behörde Ihres Wohnorts oder
`[zuständige Landesbehörde des Salons]`.

## 7. Keine Cookies zur Analyse

Diese Seite verwendet keine Analyse- oder Werbe-Cookies und bindet keine
Tracking-Dienste ein. Damit Ihr Termin auf Ihrem Gerät wiederfindbar bleibt,
wird der unter Punkt 3 beschriebene Schlüssel lokal in Ihrem Browser
gespeichert. Sie können ihn jederzeit löschen, indem Sie die Websitedaten
Ihres Browsers löschen; Ihren Termin finden Sie dann per SMS-Bestätigung
wieder.

Schriftarten werden mit der Seite ausgeliefert und nicht von einem fremden
Server nachgeladen.

⚠ *Vor Veröffentlichung einmal prüfen, dass der Build tatsächlich keine
Google-Adresse mehr enthält — `build_shop.sh` bricht in diesem Fall ab. Siehe
`legal/README.md`, Punkt 2.*

---

Stand: `[Datum]`
