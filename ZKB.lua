--------------------------------------------------------------------------------
-- Zürcher Kantonalbank (ZKB) Extension for MoneyMoney https://moneymoney-app.com
-- Copyright 2024-2026 Ansgar Scheffold
--------------------------------------------------------------------------------
WebBanking{
    version     = 1.05,
    url         = "https://onba.zkb.ch",
    services    = {"Zürcher Kantonalbank"},
    description = "Abfrage des ZKB Kontos mit Foto-TAN-Authentifizierung"
}

--------------------------------------------------------------------------------
-- Constants and global variables
--------------------------------------------------------------------------------
local BASE_URL = "https://onba.zkb.ch"
local connection = Connection()
local modifiedGlobalData = nil

-- HTML entity mapping table
local HTML_ENTITIES = {
    ["&auml;"] = "ä", ["&Auml;"] = "Ä",
    ["&ouml;"] = "ö", ["&Ouml;"] = "Ö",
    ["&uuml;"] = "ü", ["&Uuml;"] = "Ü",
    ["&szlig;"] = "ß",
    ["&amp;"]  = "&",
    ["&quot;"] = "\"",
    ["&apos;"] = "'",
    ["&lt;"]   = "<",
    ["&gt;"]   = ">"
}

-- Default headers
local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"]       = "application/json",
    ["User-Agent"]   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.81 Safari/537.36",
    ["Referer"]      = BASE_URL .. "/ciam-auth/ui/login",
    ["Origin"]       = BASE_URL
}

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------
-- Update headers with cookies and extract XSRF token
local function updateHeadersFromCookies()
    local cookies = connection:getCookies() or ""
    headers["Cookie"] = cookies
    
    -- Extract XSRF token
    local xsrf = cookies:match("XSRF%-TOKEN=([^;]+)")
    if xsrf then
        headers["X-XSRF-TOKEN"] = xsrf
    end
end

-- Fetch and modify globalData
local function getModifiedGlobalData()
    local globalDataUrl = BASE_URL .. "/ciam-auth/api/web/webAuth/globalData"
    local response = connection:request("GET", globalDataUrl, nil, nil, headers)
    
    if not response then
        error("Failed to fetch globalData API")
    end
    
    -- Replace hostname in the response
    local modifiedResponse = response:gsub(
        '"zkbChHostName"%s*:%s*"https://www%.zkb%.ch"',
        '"zkbChHostName":"' .. BASE_URL .. '"'
    )
    
    modifiedGlobalData = JSON(modifiedResponse):dictionary()
    return modifiedGlobalData
end

-- Get base URL from globalData or use default
function HomePage()
    return (modifiedGlobalData and modifiedGlobalData["zkbChHostName"]) or BASE_URL
end

-- Decode HTML entities in text
local function decodeHtmlEntities(text)
    return text:gsub("(&%a+;)", function(entity)
        return HTML_ENTITIES[entity] or entity
    end)
end

-- Clean and extract text from HTML
local function extractText(html)
    if not html then return "" end
    local text = html:gsub("<.->", ""):gsub("^%s*(.-)%s*$", "%1")
    return decodeHtmlEntities(text)
end

-- Clean account number by removing spaces
local function cleanAccountNumber(number)
    return number:gsub("%s+", "")
end

-- Parse amount string to number
local function parseAmount(str)
    if not str then return 0 end
    
    -- Remove unwanted characters and format number
    str = str:gsub("[%z\194\160]", "")  -- Remove non-breaking spaces
             :gsub("'", "")             -- Remove thousand separators
             :gsub(",", ".")            -- Convert comma to decimal point
             :gsub("CHF%s*", "")        -- Remove currency indicator
             :gsub("%s+", "")           -- Remove all spaces
    
    return tonumber(str) or 0
end

-- Split transaction text into title and purpose
local function splitTransactionText(text)
    -- First try to split by colon
    local title, desc = text:match("^(.-):%s*(.+)$")
    if title then return title, desc end
    
    -- Then try to split by comma
    title, desc = text:match("^(.-),%s*(.+)$")
    if title then return title, desc end
    
    -- No separator found: entire text as title, empty description
    return text, ""
end

-- Parse date string in format DD.MM.YYYY to timestamp
local function parseDate(dateStr)
    local day, month, year = dateStr:match("(%d%d)%.(%d%d)%.(%d%d%d%d)")
    if day and month and year then
        return os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
    end
    return nil
end

--------------------------------------------------------------------------------
-- TAN handling functions
--------------------------------------------------------------------------------
-- Poll TAN verification status using the new API
function pollTanStatus()
    local tanStatusUrl = HomePage() .. "/ciam-auth/api/web/webAuth/checkPhotoTanPending"
    local retryInterval, maxRetries = 2, 30

    for attempt = 1, maxRetries do
        MM.sleep(retryInterval)
        updateHeadersFromCookies()

        local response = connection:request("POST", tanStatusUrl, "", "application/json", headers)
        if not response then
            if attempt == maxRetries then
                error("No response from TAN verification API after multiple attempts")
            end
            print("No response from TAN status API. Retrying...")
            goto continue
        end

        -- Parse the response
        local ok, decoded = pcall(function() return JSON(response):dictionary() end)
        if not ok then
            print("Invalid JSON response from TAN status API: " .. response)
            goto continue
        end

        -- Check if this is an error response
        if decoded["error"] then
            print("Error response from TAN status API: " .. response)
            goto continue
        end

        -- Check the action class
        local actionClass = decoded["_class"]
        if actionClass == "auth.ConfirmationDoneAction" then
            return true
        elseif actionClass == "auth.NoneAction" then
            -- Still pending, continue polling
            goto continue
        else
            print("Unexpected action class: " .. (actionClass or "null"))
            goto continue
        end

        ::continue::
    end

    error("TAN verification timed out after " .. maxRetries .. " attempts")
end

--------------------------------------------------------------------------------
-- Handle post-TAN authentication actions
--------------------------------------------------------------------------------
function handlePostTanActions()
    local maxRetries = 5

    for attempt = 1, maxRetries do
        updateHeadersFromCookies()

        local nextActionUrl = HomePage() .. "/ciam-auth/api/web/webAuth/getNextActionAfterOnlineTanVerification"
        local response = connection:request("POST", nextActionUrl, "", "application/json", headers)

        if not response then
            print("No response from getNextActionAfterOnlineTanVerification")
            return false
        end

        local ok, actionData = pcall(function() return JSON(response):dictionary() end)
        if not ok then
            print("Invalid JSON response from getNextActionAfterOnlineTanVerification: " .. response)
            return false
        end

        local actionClass = actionData["_class"]

        if not actionClass then
            print("No action class in response")
            return false
        end

        print("Post-TAN action: " .. actionClass)

        if actionClass == "auth.ConfirmOrRemoveOrSkipRecoveryPhoneNumberAction" then
            -- Skip the recovery phone number confirmation
            local skipUrl = HomePage() .. "/ciam-auth/api/web/webAuth/skipRecoveryPhoneNumber"
            updateHeadersFromCookies()
            local skipResponse = connection:request("POST", skipUrl, "", "application/json", headers)

            if not skipResponse then
                print("Failed to skip recovery phone number")
                return false
            end

            local ok, skipData = pcall(function() return JSON(skipResponse):dictionary() end)
            if ok and skipData["_class"] == "auth.DoneAction" then
                print("Skipped recovery phone number confirmation successfully")
                -- After skipping, login should be complete - don't call getNextAction again
                return true
            else
                print("Unexpected response after skipping recovery phone: " .. skipResponse)
                return false
            end

        elseif actionClass == "auth.NoneAction" then
            -- No more actions needed, login complete
            print("Post-TAN actions completed successfully")
            return true

        elseif actionClass == "slx.global.ServiceException" then
            -- This can happen after skipping recovery phone - treat as login complete
            print("Service exception after post-TAN actions - treating as login complete")
            return true

        else
            print("Unhandled post-TAN action: " .. actionClass)
            -- For unknown actions, we'll assume login is complete for now
            -- This prevents infinite loops while allowing the extension to work
            return true
        end

        -- Small delay before next iteration
        MM.sleep(1)
    end

    print("Too many post-TAN action attempts")
    return false
end

--------------------------------------------------------------------------------
-- Core banking functions
--------------------------------------------------------------------------------
-- Check if this extension is responsible for the given bank access
function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Zürcher Kantonalbank"
end

-- Perform two-step login process
function InitializeSession2(protocol, bankCode, step, credentials, interactive)
    if step == 1 then
        -- Step 1: Start login and retrieve photo TAN challenge
        getModifiedGlobalData()
        updateHeadersFromCookies()
        
        local loginUrl = HomePage() .. "/ciam-auth/api/web/webAuth/startLogin"
        local loginBody = JSON():set({
            loginName = credentials[1],
            password = credentials[2]
        }):json()
        
        local response = connection:request("POST", loginUrl, loginBody, "application/json", headers)
        if not response then
            error("No response from login request")
        end
        
        local responseData = JSON(response):dictionary()
        if responseData["action"] and responseData["action"]["_class"] == "auth.VerifyPhotoTanAction" then
            return {
                title = "Scannen Sie die Grafik mit der ZKB-Access App",
                challenge = MM.base64decode(responseData["action"]["challengePngImageBase64"]),
            }
        else
            error("Unexpected response or no photo TAN required")
        end
        
    elseif step == 2 then
        -- Step 2: Poll TAN status and complete login
        updateHeadersFromCookies()

        if pollTanStatus() then
            -- After TAN verification, handle any additional actions
            if not handlePostTanActions() then
                error("Failed to complete post-TAN authentication steps")
            end

            return nil -- Login successful
        else
            error("Login failed")
        end
    else
        error("Unknown step: " .. tostring(step))
    end
end

-- List all accounts
function ListAccounts(knownAccounts)
    -- 1) Primär: bekannte Startseite (mit Parametern)
    local tryUrls = {
        BASE_URL .. "/page/meinefinanzen/startseite.page?dswid=2820&hn=2&firstwindow=true",
        -- 2) Fallback: gleiche Seite ohne volatile Parameter (oft genügt das)
        BASE_URL .. "/page/meinefinanzen/startseite.page"
    }

    local function fetch(url)
        updateHeadersFromCookies()
        return connection:request("GET", url, nil, nil, headers)
    end

    local response, html
    for _, url in ipairs(tryUrls) do
        response = fetch(url)
        if response and response:find("<html", 1, true) then
            html = response
            break
        end
    end

    if not html then
        error("Failed to retrieve accounts (no HTML received from start page or fallback)")
    end

    local accounts = {}

    -- Account-Sektionen extrahieren
    for section in html:gmatch('<section%s+class="account%-table">(.-)</section>') do
        local accountUrl = section:match('<div%s+class="headerName">.-<a%s+href="([^"]+)"')
        local name       = section:match('<div%s+class="headerName">.-<a%s+href="[^"]+"[^>]*>(.-)</a>')
        local number     = section:match('<div%s+class="headerNumber">.-<a[^>]*>(.-)</a>')
        local balance    = section:match('<div%s+class="headerWert">.-<a[^>]*>(.-)</a>')

        -- Falls Saldo nicht im sichtbaren HTML steht: aus data-options JSON ziehen (falls vorhanden)
        if (not balance or balance == "") then
            local jsonString = html:match('data%-options="({.-})"')
            if jsonString then
                jsonString = jsonString:gsub("&quot;", '"')
                local ok, jsonData = pcall(JSON, jsonString)
                if ok and jsonData then
                    local data = jsonData:dictionary()
                    if data.inhaber then
                        for _, inhaber in ipairs(data.inhaber) do
                            if inhaber.geschaefte then
                                for _, konto in ipairs(inhaber.geschaefte) do
                                    if konto.iban == (number and cleanAccountNumber(extractText(number)) or "") then
                                        balance = konto.saldo
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        if accountUrl and name and number then
            name   = extractText(name)
            number = extractText(number)
            balance = parseAmount(extractText(balance) or "0")

            local fullUrl = accountUrl
            if not accountUrl:match("^https?://") then
                fullUrl = HomePage() .. accountUrl
            end

            local kontoId = fullUrl:match("kontoId=(%d+)")
            local cleanedNumber = cleanAccountNumber(number)
            if kontoId then
                LocalStorage["kontoId_" .. cleanedNumber] = kontoId
            end

            local accountType = AccountTypeSavings
            if name:find("Girokonto") then
                accountType = AccountTypeGiro
            end

            table.insert(accounts, {
                name = name,
                owner = "",
                accountNumber = cleanedNumber,
                balance = balance,
                transactionsUrl = fullUrl,
                kontoId = kontoId,
                bankCode = "",
                currency = "CHF",
                type = accountType
            })
        end
    end

    -- Wenn immer noch nichts gefunden wurde, nicht hart abbrechen, sondern klarer Fehlerhinweis
    if #accounts == 0 then
        error("Could not extract any account data from HTML. Tipp: Die ZKB zeigt Konten nicht auf jeder Startseite – Fallback versucht. Bitte Startseite 'Meine Finanzen' verwenden, falls weiterhin leer.")
    end

    return accounts
end

-- Refresh account transactions
function RefreshAccount(account, since)
    local kontoId = account.kontoId or LocalStorage["kontoId_" .. account.accountNumber]
    if not kontoId then
        error("No kontoId found for account " .. account.accountNumber)
    end
    
    local transactionsUrl = HomePage() .. "/page/kontozahlungen/konto.page?dswid=2820&kontoId=" .. kontoId .. "&activeTabId=kontoauszug&hn=1"
    updateHeadersFromCookies()
    
    local response = connection:request("GET", transactionsUrl, nil, nil, headers)
    if not response then
        error("Failed to retrieve transactions")
    end
    
    -- Extract current balance
    local balanceExtract = response:match('<span%s+class="font%-size%-24%s+nospace">%s*<span>CHF%s*([^<]+)</span>') or
                           response:match('<span%s+class="saldo%s+ng%-binding%s+ng%-scope"[^>]*>CHF%s*([^<]+)</span>')
    local balance = balanceExtract and parseAmount(balanceExtract) or (account.balance or 0)
    
    -- Extract transactions table
    local transactions = {}
    local tableHtml = response:match('<table%s+class="tbl%s+tbl%-data%s+kontoauszug%-brushup%-table".-</table>')
    
    if not tableHtml then
        return { balance = balance, transactions = transactions, pendingBalance = 0 }
    end
    
    -- Parse transactions using the working pattern from the old code
    local pattern = '<tr>%s*<td[^>]*>.-</td>%s*' ..
                    '<td%s+headers="th1">.-<a[^>]*>(.-)</a>.-</td>%s*' ..
                    '<td%s+headers="th2">.-<a[^>]*>(.-)</a>(.-)</td>%s*' ..
                    '<td%s+headers="th3"[^>]*>(.-)</td>%s*' ..
                    '<td%s+headers="th4"[^>]*>(.-)</td>%s*' ..
                    '<td%s+headers="th5">(.-)</td>%s*' ..
                    '<td%s+headers="th6"[^>]*>(.-)</td>%s*</tr>'
    
    for dateStr, titlePart, extraText, debitStr, creditStr, valutaStr, _ in tableHtml:gmatch(pattern) do
        local bookingDate = parseDate(dateStr)
        if not bookingDate then
            goto continue
        end
        
        -- Process transaction text
        local part1 = extractText(titlePart)
        local part2 = extractText(extraText)
        local fullText = part1
        if part2 ~= "" then
            fullText = fullText .. " " .. part2
        end
        
        local transTitle, transPurpose = splitTransactionText(fullText)
        
        -- Process amount
        local debitAmt = parseAmount(debitStr)
        local creditAmt = parseAmount(creditStr)
        local amount = (debitAmt > 0 and -debitAmt) or creditAmt
        
        -- Process value date
        local valueDate = parseDate(valutaStr)
        local booked = valueDate ~= nil
        if not booked then
            valueDate = bookingDate
        end
        
        table.insert(transactions, {
            bookingDate = bookingDate,
            valueDate = valueDate,
            name = transTitle,
            purpose = transPurpose,
            amount = amount,
            currency = "CHF",
            booked = booked
        })
        
        ::continue::
    end
    
    -- Check for expandable Dauerauftrag transactions and fetch details
    -- Build a map of buchungId -> parent booking/value dates so detail items can inherit booking info
    local dauerauftragMap = {}

    for row in tableHtml:gmatch('<tr>([%s%S]-)</tr>') do
        if row:match('Dauerauftrag') then
            local buchungId = row:match('buchungId=(%d+)')
            -- Try to extract booking date from typical columns (th1 or th2)
            local dateStr = row:match('<td[^>]-headers="th1">.-<a[^>]->(.-)</a>') or row:match('<td[^>]-headers="th2">.-<a[^>]->(.-)</a>')
            -- Try to extract value date from expected columns (th5 or th6)
            local valutaStr = row:match('<td[^>]-headers="th5">.-<a[^>]->(.-)</a>') or row:match('<td[^>]-headers="th6">.-<a[^>]->(.-)</a>') or row:match('<td[^>]-headers="th5">([^<]-)</td>') or row:match('<td[^>]-headers="th6">([^<]-)</td>')

            local parentBookingDate = dateStr and parseDate(extractText(dateStr))
            local parentValueDate = (valutaStr and parseDate(extractText(valutaStr))) or parentBookingDate

            if buchungId then
                dauerauftragMap[buchungId] = {
                    bookingDate = parentBookingDate,
                    valueDate = parentValueDate
                }
            end
        end
    end

    -- Only fetch details for actual Dauerauftrag transactions
    if next(dauerauftragMap) then
        local dswid = response and response:match('meta name="dswid"%s+content="([%-]?%d+)"') or "2820"
        for buchungId, parentInfo in pairs(dauerauftragMap) do
            local bookingUrl = HomePage() .. "/page/kontozahlungen/buchung.page?dswid=" .. dswid .. "&buchungId=" .. buchungId .. "&hn=1"
            updateHeadersFromCookies()
            local detailResp = connection:request('GET', bookingUrl, nil, nil, headers)

            if detailResp then
                -- Look for beneficiary table in the detail page
                local tbl = detailResp:match('<table%s+class="tbl"([%s%S]-)</table>')
                if tbl then
                    -- Parse beneficiary rows
                    for row in tbl:gmatch('<tr>([%s%S]-)</tr>') do
                        local ben = row:match('<td[^>]-headers="th1"[^>]->([%s%S]-)</td>') or row:match('<td%s+headers="th1">([%s%S]-)</td>')
                        local amtStr = row:match('<td[^>]-headers="th3"[^>]->([%s%S]-)</td>') or row:match('<td%s+headers="th3">([%s%S]-)</td>')

                        if ben and amtStr then
                            local name = extractText(ben:gsub('<br%s*/?>','\n'))
                            local amt = parseAmount(extractText(amtStr))
                            if amt ~= 0 then
                                amt = -math.abs(amt) -- details are debits

                                -- Extract dates from detail page (if present)
                                local bookingDateStr = detailResp:match('Buchungsdatum</dt>%s*<dd>.-?(%d%d%.%d%d%.%d%d%d%d)')
                                local valueDateStr = detailResp:match('Valuta</dt>%s*<dd>.-?(%d%d%.%d%d%.%d%d%d%d)')

                                local bookingDate = bookingDateStr and parseDate(bookingDateStr) or parentInfo.bookingDate or os.time()
                                local valueDate = valueDateStr and parseDate(valueDateStr) or parentInfo.valueDate or bookingDate
                                local booked = (bookingDateStr ~= nil) or (parentInfo.bookingDate ~= nil)

                                -- Add individual beneficiary transaction
                                table.insert(transactions, {
                                    bookingDate = bookingDate,
                                    valueDate = valueDate,
                                    name = "Belastung Dauerauftrag",
                                    purpose = name,
                                    amount = amt,
                                    currency = "CHF",
                                    booked = booked
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Calculate pending balance
    local pendingTotal = 0
    for _, t in ipairs(transactions) do
        if not t.booked then
            pendingTotal = pendingTotal + t.amount
        end
    end
    
    return { 
        balance = balance,
        transactions = transactions,
        pendingBalance = pendingTotal
    }
end

-- Close the connection
function EndSession()
    connection:close()
end
