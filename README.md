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

### Installation

1. **Öffne MoneyMoney** und gehe zu den Einstellungen (Cmd + ,).
2. Gehe in den Reiter **Extensions** und deaktiviere den Haken bei **"Verify digital signatures of extensions"**.
3. Wähle im Menü **Help > Show Database in Finder**.
4. Kopiere die Datei `ZKB.lua` aus diesem Repository in den Extensions-Ordner:
   `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
5. In MoneyMoney sollte nun beim Hinzufügen eines neuen Kontos der Service-Typ **ZKB** erscheinen.

### Screenshots
![1](https://github.com/user-attachments/assets/0dacaead-c257-4dd1-bce7-86c3cade6a76)
![2](https://github.com/user-attachments/assets/473180c6-b791-4e07-ab18-3aea7b6cfffc)
![3](https://github.com/user-attachments/assets/52306cc5-9662-4c5f-bf72-2c6cf29b2be0)
![4](https://github.com/user-attachments/assets/74ac0f8a-5420-4034-8c8b-82514a9c78dc)
![5](https://github.com/user-attachments/assets/5e89e457-be1a-45e7-9126-1cf3bb12b754)

## Lizenz

Diese Software wird unter der **MIT License mit dem Commons Clause Zusatz** bereitgestellt.  
Das bedeutet, dass Änderungen und Weiterverteilungen (auch modifizierte Versionen) erlaubt sind – eine kommerzielle Nutzung bzw. der Verkauf der Software oder abgeleiteter Werke ist jedoch ohne die ausdrückliche Zustimmung des Autors untersagt.
