--------------------------------------------------------------------------------
-- Zürcher Kantonalbank (ZKB) Extension for MoneyMoney (https://moneymoney-app.com)
-- Copyright 2024-2025 Ansgar Scheffold
--------------------------------------------------------------------------------
WebBanking{
    version     = 1.00,
    url         = "https://onba.zkb.ch",
    services    = {"Zürcher Kantonalbank"},
    description = "Abfrage des ZKB Kontos mit Foto-TAN-Authentifizierung"
}

--------------------------------------------------------------------------------
-- Verbindungsobjekt und globale Variablen
--------------------------------------------------------------------------------
local connection = Connection()
local modifiedGlobalData = nil  -- Speichert die modifizierte globalData

--------------------------------------------------------------------------------
-- Standard-Header für alle HTTP-Anfragen
--------------------------------------------------------------------------------
local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"]       = "application/json",
    ["User-Agent"]   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, wie Gecko) Chrome/94.0.4606.81 Safari/537.36",
    ["Referer"]      = "https://onba.zkb.ch/ciam-auth/ui/login",
    ["Origin"]       = "https://onba.zkb.ch"
}

--------------------------------------------------------------------------------
-- Aktualisiert den Header mit den aktuellen Cookies und extrahiert ggf. den XSRF-TOKEN.
--------------------------------------------------------------------------------
local function updateHeadersFromCookies()
    local cookies = connection:getCookies() or ""
    headers["Cookie"] = cookies
    local xsrf = cookies:match("XSRF%-TOKEN=([^;]+)")
    if xsrf then
        headers["X-XSRF-TOKEN"] = xsrf
    else
        print("Kein XSRF-TOKEN gefunden.")
    end
end

--------------------------------------------------------------------------------
-- Ruft globalData vom Server ab und ersetzt den Hostnamen.
--------------------------------------------------------------------------------
local function getModifiedGlobalData()
    local preLoginUrl = "https://onba.zkb.ch/ciam-auth/api/web/webAuth/globalData"
    local globalResponse, charset = connection:request("GET", preLoginUrl, nil, nil, headers)
    if not globalResponse then
        error("Keine Antwort von der globalData-API")
    end
    
    local modifiedResponse = globalResponse:gsub(
        '"zkbChHostName"%s*:%s*"https://www%.zkb%.ch"',
        '"zkbChHostName":"https://onba.zkb.ch"'
    )
    
    modifiedGlobalData = JSON(modifiedResponse):dictionary()
end

--------------------------------------------------------------------------------
-- Liefert die Basis-URL, entweder aus modifiedGlobalData oder als Standard.
--------------------------------------------------------------------------------
function HomePage()
    return (modifiedGlobalData and modifiedGlobalData["zkbChHostName"]) or "https://onba.zkb.ch"
end

--------------------------------------------------------------------------------
-- Prüft, ob diese Extension für den angegebenen Bankzugang zuständig ist.
--------------------------------------------------------------------------------
function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Zürcher Kantonalbank"
end

--------------------------------------------------------------------------------
-- Fragt den TAN-Status ab und wartet, bis die TAN bestätigt ist.
--------------------------------------------------------------------------------
function pollTanStatus()
    print("TAN-Statusprüfung gestartet...")
    local tanStatusUrl = HomePage() .. "/ciam-auth/api/web/webAuth/getOnlineTanVerificationState"
    
    local retryInterval, maxRetries = 2, 30

    for attempt = 1, maxRetries do
        MM.sleep(retryInterval)
        updateHeadersFromCookies()
        local response = connection:request("POST", tanStatusUrl, "", "application/json", headers)
        
        if response then
            local state = response
            local ok, decoded = pcall(function() return JSON(response):dictionary() end)
            if ok and type(decoded) == "table" and decoded["state"] then
                state = decoded["state"]
            end
            if type(state) == "string" then
                state = state:gsub('^"(.*)"$', '%1')
            end
            
            if state == "CORRECT" then
                print("TAN erfolgreich bestätigt.")
                return true
            elseif state == "NOT_VERIFIED" then
                print("TAN noch nicht bestätigt. Wiederholen...")
            elseif state == "FAILED" then
                error("TAN-Überprüfung fehlgeschlagen. Bitte erneut versuchen.")
            else
                error("Unerwarteter TAN-Status: " .. (state or "null"))
            end
        else
            print("Keine Antwort von TAN-Status-API.")
        end
    end

    error("TAN-Bestätigung fehlgeschlagen: Zeitüberschreitung.")
end


--------------------------------------------------------------------------------
-- Führt den Zwei-Schritte-Login durch: 
-- Schritt 1: Startet den Login und liefert die Foto-TAN-Challenge.
-- Schritt 2: Pollt den TAN-Status und schließt den Login ab.
--------------------------------------------------------------------------------
function InitializeSession2(protocol, bankCode, step, credentials, interactive)
    if step == 1 then
        getModifiedGlobalData()  -- Hole und modifiziere globalData
        local loginUrl = HomePage() .. "/ciam-auth/api/web/webAuth/startLogin"
        
        -- Optional: Eine zusätzliche globalData-Anfrage (falls benötigt)
        local gdResponse = connection:request("GET", HomePage() .. "/ciam-auth/api/web/webAuth/globalData", nil, nil, headers)
        updateHeadersFromCookies()
        
        local loginBody = JSON():set({
            loginName = credentials[1],
            password = credentials[2]
        }):json()
        local response = connection:request("POST", loginUrl, loginBody, "application/json", headers)
        if not response then
            error("Keine Antwort vom Login-Request")
        end
        local responseData = JSON(response):dictionary()
        
        if responseData["action"] and responseData["action"]["_class"] == "auth.VerifyPhotoTanAction" then
            return {
                title = "Scannen Sie die Grafik mit der ZKB-Access App",
                challenge = MM.base64decode(responseData["action"]["challengePngImageBase64"]),
            }
        else
            error("Unbekannte Antwort oder keine Foto-TAN erforderlich. Response: " .. response)
        end

    elseif step == 2 then
        updateHeadersFromCookies()
        if pollTanStatus() then
            local nextActionUrl = HomePage() .. "/ciam-auth/api/web/webAuth/getNextActionAfterOnlineTanVerification"
            updateHeadersFromCookies()
            local response = connection:request("POST", nextActionUrl, "", "application/json", headers)
            if not response then
                error("Fehler beim Abschluss des Logins: Keine Antwort erhalten")
            end
            print("Login erfolgreich.")
            return nil
        else
            error("Login fehlgeschlagen.")
        end
    else
        error("Unbekannter Schritt: " .. tostring(step))
    end
end


--------------------------------------------------------------------------------
-- Entfernt HTML-Tags und trimmt Leerzeichen.
--------------------------------------------------------------------------------
local function extractText(html)
    return html:gsub("<.->", ""):gsub("^%s*(.-)%s*$", "%1")
end

--------------------------------------------------------------------------------
-- Entfernt Leerzeichen aus einer Kontonummer.
--------------------------------------------------------------------------------
local function cleanAccountNumber(number)
    return number:gsub("%s+", "")
end

--------------------------------------------------------------------------------
-- Konvertiert einen Textbetrag in eine numerische Zahl.
--------------------------------------------------------------------------------
local function parseAmount(str)
    if not str then return 0 end
    -- Entferne unerwünschte Zeichen und formatiere das Zahlenformat
    str = str:gsub("[%z\194\160]", "")
             :gsub("'", "")
             :gsub(",", ".")
             :gsub("CHF%s*", "")
             :gsub("%s+", "")
    local amount = tonumber(str)
    return amount or 0
end

--------------------------------------------------------------------------------
-- Teilt den Transaktionstext in Titel und Verwendungszweck auf
--------------------------------------------------------------------------------
local function splitTransactionText(text)
    -- Suche zuerst nach einem Doppelpunkt
    local title, desc = text:match("^(.-):%s*(.+)$")
    if title then 
        return title, desc
    end
    -- Falls kein Doppelpunkt gefunden wurde, nach dem ersten Komma
    title, desc = text:match("^(.-),%s*(.+)$")
    if title then 
        return title, desc
    end
    -- Kein Trenner gefunden: Gesamter Text als Titel, leere Beschreibung
    return text, ""
end

--------------------------------------------------------------------------------
-- Liest die Kontenliste aus der Kontoübersichtsseite aus.
--------------------------------------------------------------------------------
function ListAccounts(knownAccounts)
    print("Kontenliste abrufen...")
    local accountsUrl = "https://onba.zkb.ch/page/meinefinanzen/startseite.page?dswid=2820&hn=2&firstwindow=true"
    updateHeadersFromCookies()
    local response = connection:request("GET", accountsUrl, nil, nil, headers)
    if not response then
        error("Fehler beim Abrufen der Konten.")
    end
    if not response:lower():find("<!doctype html>") then
        error("Erwarteter HTML-Inhalt wurde nicht empfangen.")
    end

    local accounts = {}
    for section in response:gmatch('<section%s+class="account%-table">(.-)</section>') do
        local accountUrl = section:match('<div%s+class="headerName">.-<a%s+href="([^"]+)"')
        local name       = section:match('<div%s+class="headerName">.-<a%s+href="[^"]+"[^>]*>(.-)</a>')
        local number     = section:match('<div%s+class="headerNumber">.-<a[^>]*>(.-)</a>')
        local balance    = section:match('<div%s+class="headerWert">.-<a[^>]*>(.-)</a>')

        -- Falls kein Saldo gefunden wurde, versuche einen JSON-Datensatz zu nutzen
        if not balance or balance == "" then
            local jsonString = response:match('data%-options="({.-})"')
            if jsonString then
                local jsonData = json.decode(jsonString)
                for _, inhaber in ipairs(jsonData) do
                    for _, konto in ipairs(inhaber.geschaefte) do
                        if konto.iban == number then
                            balance = konto.saldo
                            break
                        end
                    end
                end
            end
        end

        if not balance or balance == "" then
            print("WARNUNG: Kein Saldo für Konto " .. tostring(number) .. " gefunden!")
        end

        if accountUrl and name and number and balance then
            name    = extractText(name)
            number  = extractText(number)
            balance = parseAmount(extractText(balance) or "0")
            local fullUrl = accountUrl
            if not accountUrl:match("^https?://") then
                fullUrl = HomePage() .. accountUrl
            end
            -- Extrahiere die eindeutige Konto-ID aus dem Link
            local kontoId = fullUrl:match("kontoId=(%d+)")
            print(string.format("Konto-Link: %s | Name: %s | Nummer: %s | Balance: %s | kontoId: %s", 
                  fullUrl, name, number, balance, tostring(kontoId)))
            local cleanedNumber = cleanAccountNumber(number)
            LocalStorage["kontoId_" .. cleanedNumber] = kontoId
            table.insert(accounts, {
                name = name,
                owner = "",
                accountNumber = cleanedNumber,
                balance = balance,
                transactionsUrl = fullUrl,
                kontoId = kontoId,
                bankCode = "",
                currency = "CHF",
                type = (name:find("Girokonto") and AccountTypeGiro) or AccountTypeSavings
            })
        end
    end

    if #accounts == 0 then
        error("Konnte keine Kontodaten im HTML extrahieren.")
    end

    return accounts
end


--------------------------------------------------------------------------------
-- Ruft den aktuellen Kontostand und die Transaktionen eines Kontos ab.
--------------------------------------------------------------------------------
function RefreshAccount(account, since)
    print("Umsätze abrufen für Konto: " .. account.accountNumber)
    local kontoId = account.kontoId or LocalStorage["kontoId_" .. account.accountNumber]
    if not kontoId then
        error("Kein kontoId gefunden für Konto " .. account.accountNumber)
    end

    local transactionsUrl = HomePage() .. "/page/kontozahlungen/konto.page?dswid=2820&kontoId=" .. kontoId .. "&activeTabId=kontoauszug&hn=1"
    updateHeadersFromCookies()
    local response = connection:request("GET", transactionsUrl, nil, nil, headers)
    if not response then
        error("Fehler beim Abrufen der Transaktionen. URL: " .. tostring(transactionsUrl))
    end

    local balanceExtract = response:match('<span%s+class="font%-size%-24%s+nospace">%s*<span>CHF%s*([^<]+)</span>')
                          or response:match('<span%s+class="saldo%s+ng%-binding%s+ng%-scope"[^>]*>CHF%s*([^<]+)</span>')
    local balance = balanceExtract and parseAmount(balanceExtract) or (account.balance or 0)
    
    local transactions = {}
    local tableHtml = response:match('<table%s+class="tbl%s+tbl%-data%s+kontoauszug%-brushup%-table".-</table>')
    if not tableHtml then
        error("Konnte die Transaktionstabelle nicht finden. Response: " .. tostring(response:sub(1,500)))
    end

    for dateStr, titlePart, extraText, debitStr, creditStr, valutaStr, _ in tableHtml:gmatch(
        '<tr>%s*<td[^>]*>.-</td>%s*' ..
        '<td%s+headers="th1">.-<a[^>]*>(.-)</a>.-</td>%s*' ..
        '<td%s+headers="th2">.-<a[^>]*>(.-)</a>(.-)</td>%s*' ..
        '<td%s+headers="th3"[^>]*>(.-)</td>%s*' ..
        '<td%s+headers="th4"[^>]*>(.-)</td>%s*' ..
        '<td%s+headers="th5">(.-)</td>%s*' ..
        '<td%s+headers="th6"[^>]*>(.-)</td>%s*</tr>'
    ) do
        local day, month, year = dateStr:match("(%d%d)%.(%d%d)%.(%d%d%d%d)")
        local bookingDate = os.time({year = year, month = month, day = day})
        local part1 = extractText(titlePart)
        local part2 = extractText(extraText)
        -- Kombiniere beide Teile (falls extraText vorhanden ist)
        local fullText = part1
        if part2 ~= "" then
            fullText = fullText .. " " .. part2
        end
        -- Teile den kombinierten Text in Titel und Verwendungszweck auf
        local transTitle, transPurpose = splitTransactionText(fullText)
        
        local function parseAmt(str)
            local cleaned = str:gsub("'", ""):gsub("CHF%.", ""):gsub("%s", "")
            return tonumber(cleaned) or 0
        end
        local debitAmt = parseAmt(debitStr)
        local creditAmt = parseAmt(creditStr)
        local amount = (debitAmt > 0 and -debitAmt) or creditAmt
        local booked = true
        local valueDate = nil
        local d2, m2, y2 = valutaStr:match("(%d%d)%.(%d%d)%.(%d%d%d%d)")
        if d2 and m2 and y2 then
            valueDate = os.time({year = y2, month = m2, day = d2})
        else
            booked = false
            valueDate = bookingDate
        end
        table.insert(transactions, {
            bookingDate = bookingDate,
            valueDate = valueDate,
            name = transTitle,         -- Verwende den aufgeteilten Titel
            purpose = transPurpose,    -- und den aufgeteilten Verwendungszweck
            amount = amount,
            currency = "CHF",
            booked = booked
        })
    end

    local pendingTotal = 0
    for _, t in ipairs(transactions) do
        if not t.booked then
            pendingTotal = pendingTotal + t.amount
        end
    end

    print("Saldo: " .. tostring(balance))
    return { balance = balance, transactions = transactions, pendingBalance = pendingTotal }
end

--------------------------------------------------------------------------------
-- Schliesst die Verbindung.
--------------------------------------------------------------------------------
function EndSession()
    print("Session beenden")
    connection:close()
end
