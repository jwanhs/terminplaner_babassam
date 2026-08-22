# Anlage 2 — Unterauftragsverarbeiter

> **Entwurf mit offenen Feldern.** Keine Rechtsberatung; anwaltlich nicht
> geprüft.
>
> Die Felder „Ort der Verarbeitung" sind bewusst leer. Sie hängen davon ab,
> in welcher Region das jeweilige Konto tatsächlich angelegt wurde, und dürfen
> **nicht aus der Erinnerung ausgefüllt werden** — die Angabe entscheidet
> darüber, ob eine Drittlandsübermittlung vorliegt und ob die
> Datenschutzerklärung des Auftraggebers stimmt. Vor dem ersten Kundenvertrag
> im jeweiligen Konto nachsehen und eintragen.

Stand: `[Datum]`

---

## 1. Eingesetzte Unterauftragsverarbeiter

### 1.1 Serverbetrieb

Datenbank, Serverfunktionen und Authentifizierung laufen auf **einem eigenen
Server** (selbst betriebene Appwrite-Installation), nicht in einer fremden
Cloud. Die Appwrite-Entwickler sind damit **kein** Auftragsverarbeiter — es
besteht keine Vertragsbeziehung, in der sie Daten verarbeiten. Der einzige
Unterauftragsverarbeiter auf dieser Ebene ist der Rechenzentrumsbetreiber.

| | |
| --- | --- |
| Unternehmen | OVH SAS |
| Anschrift | `[…]`, Frankreich |
| Leistung | Bereitstellung des Servers (Housing/Hosting), kein Zugriff auf Anwendungsdaten im Normalbetrieb |
| Verarbeitete Daten | sämtliche in § 2 Abs. 4 des AVV genannten Kategorien, soweit sie auf dem Server gespeichert sind |
| Ort der Verarbeitung | `[Rechenzentrum eintragen — im OVH-Konto nachsehen]`, EU |
| Grundlage bei Drittland | entfällt, solange das Rechenzentrum in der EU liegt |

> **Zu bestätigen:** in welchem Rechenzentrum der Server tatsächlich steht. Die
> Angabe „EU" ist erst dann belastbar, wenn sie im Konto nachgesehen wurde.

### 1.2 Zahlungsabwicklung

| | |
| --- | --- |
| Unternehmen | Stripe Payments Europe, Ltd. |
| Anschrift | `[…]`, Irland |
| Leistung | Abwicklung von Anzahlungen |
| Verarbeitete Daten | Zahlungsbetrag, Vorgangskennung, Zahlungsmittel- und Kartendaten des Kunden |
| Ort der Verarbeitung | `[…]` |
| Hinweis | Kartendaten werden **ausschließlich** dort verarbeitet und erreichen die Systeme des Auftragnehmers nicht. Stripe ist für diese Daten teilweise eigener Verantwortlicher; die Rollenverteilung ist bei der Prüfung zu klären. |

### 1.3 SMS-Versand (optional)

| | |
| --- | --- |
| Unternehmen | `[Twilio Ireland Limited o. a. — nur eintragen, wenn eingesetzt]` |
| Leistung | Versand der Einmalcodes zur Bestätigung einer Rufnummer |
| Verarbeitete Daten | Telefonnummer, Inhalt der Kurznachricht |
| Ort der Verarbeitung | `[…]` |
| Hinweis | Entfällt, solange der Betrieb ohne SMS-Versand erfolgt (`OTP_DEV_MODE`). Wird der Versand aktiviert, ist diese Zeile vor der Aktivierung auszufüllen. |

---

## 2. Nicht eingesetzt

Zur Klarstellung, weil bei Terminbuchungssystemen regelmäßig danach gefragt
wird:

- **Kein Marktplatz und keine Vermittlungsplattform.** Die Daten des
  Auftraggebers werden nicht in ein Portal eingestellt und nicht an andere
  Betriebe weitergegeben.
- **Keine Werbe-, Tracking- oder Analysedienste.** Es sind keine
  Analysewerkzeuge, Werbenetzwerke oder Nutzungsstatistiken eingebunden.
- **Keine Auswertung zu eigenen Zwecken** des Auftragnehmers (§ 4 Nr. 1 AVV).

---

## 3. Zu klären vor der ersten Unterschrift

1. **Schriftarten — erledigt.** Die Anwendung lud Schriftarten zur Laufzeit
   von einem Google-Server nach; damit wurde bei jedem Seitenaufruf die
   IP-Adresse des Besuchers an Google übertragen. Die Schriften werden jetzt
   mitgeliefert, ein Eintrag für Google entfällt hier ersatzlos.

   **Offen bleibt der CanvasKit-Renderer**, den die eingesetzte Web-Technik
   ebenfalls von einem Google-Server nachladen kann. Der Build bricht ab, wenn
   das Ergebnis eine Google-Adresse enthält; ob die Prüfung anschlägt, ist an
   einem echten Build noch zu verifizieren. Siehe `legal/README.md`, Punkt 2.
2. **AVV mit jedem der oben genannten Anbieter.** Für jeden eingesetzten
   Dienst muss ein eigener Auftragsverarbeitungsvertrag vorliegen, bevor der
   erste Kundendatensatz verarbeitet wird. Die Anbieter stellen diese in der
   Regel im Konto bereit; Abschluss dokumentieren und ablegen.
3. **Prüfung der Zusagen zur Verfügbarkeit**, auf die Anlage 1 Abschnitt 3
   verweist.
