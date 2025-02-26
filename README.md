# ZKB Web Banking Extension for MoneyMoney

Diese Web Banking Extension ermöglicht den Zugriff auf Konten der Zürcher Kantonalbank (ZKB) in MoneyMoney (CH).

## Funktionen

- **Login mit Foto-TAN:**  
  Sicherer Login per Foto-TAN-Authentifizierung, wie beim manuellen Zugriff.

- **Konten-Rundruf und Kontostand:**  
  Alle verfügbaren Konten (Girokonto, Sparkonto) werden per Web Scraping abgerufen – inklusive aktueller Salden.

- **Transaktionen:**  
  Es werden Transaktionen importiert, inklusive vorgemerkter Zahlungen.  
  Der Buchungstext wird automatisch in Titel und Verwendungszweck aufgeteilt:  
  - **Mit Doppelpunkt:** Alles vor dem Doppelpunkt wird als Titel verwendet, der Rest als Verwendungszweck.  
  - **Ohne Doppelpunkt:** Falls kein Doppelpunkt vorhanden ist, wird nach dem ersten Komma getrennt (alles vor dem Komma = Titel, danach = Verwendungszweck).

## Aktuelle Einschränkungen

- **Pagination:**  
  Momentan werden nur die letzten 48 Transaktionen geladen, da die AJAX-Pagination noch nicht vollständig unterstützt wird.

- **Sitzungsmanagement:**  
  Bei jedem Abruf ist aktuell eine erneute Authentifizierung (Foto-TAN) notwendig – eine dauerhafte Sitzungsaufrechterhaltung wird noch nicht aktiv gehalten.
  
- **Fehlermanagement:**  
  Wird eine Foto-TAN nicht bestätigt, fehlt aktuell noch die entsprechende Fehlermeldung.

## Installation und Nutzung

### Betaversion installieren

Diese Extension funktioniert ausschließlich mit Beta-Versionen von MoneyMoney.  
Um eine Beta-Version zu erhalten, aktiviere in den allgemeinen Einstellungen die Option **"Participate in beta tests"** und **"Display pre-release versions"**.

### Extension aktivieren

1. **Öffne MoneyMoney** und öffne die Einstellungen (Cmd + ,).
2. Gehe in den Reiter **Extensions** und deaktiviere den Haken bei **"Verify digital signatures of extensions"**.
3. Wähle im Menü **Help > Show Database in Finder**.
4. Kopiere die Datei `ZKB.lua` aus diesem Repository in den Extensions-Ordner:
   `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
5. In MoneyMoney sollte nun beim Hinzufügen eines neuen Kontos der Service-Typ **ZKB** erscheinen.

## Lizenz

Diese Software wird unter der **MIT License mit dem Commons Clause Zusatz** bereitgestellt.  
Das bedeutet, dass Änderungen und Weiterverteilungen (auch modifizierte Versionen) erlaubt sind – eine kommerzielle Nutzung bzw. der Verkauf der Software oder abgeleiteter Werke ist jedoch ohne die ausdrückliche Zustimmung des Autors untersagt.
