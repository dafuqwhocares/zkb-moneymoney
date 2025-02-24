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

## Installation und Nutzung

1. Speichere die Extension-Datei im Extensions-Verzeichnis von MoneyMoney:  
   `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
2. Lege einen neuen Bankzugang mit dem Service "ZKB" an und gib Deine Zugangsdaten ein.
3. Folge der Anleitung zur Foto-TAN-Authentifizierung.

## Lizenz

Diese Software wird unter der **MIT License mit dem Commons Clause Zusatz** bereitgestellt.  
Das bedeutet, dass Änderungen und Weiterverteilungen (auch modifizierte Versionen) erlaubt sind – eine kommerzielle Nutzung bzw. der Verkauf der Software oder abgeleiteter Werke ist jedoch ohne die ausdrückliche Zustimmung des Autors untersagt.
