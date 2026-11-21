-- =====================================================
--  CORVELYX // FUSION-REAKTOR  v1.2
--  Steuerung fuer den Mekanism-Fusionsreaktor.
--  Liest alle Werte, funkt sie an Control Center und
--  Pocket und nimmt gesicherte Befehle an:
--    Injection Rate, Automatik, Stopp (Injection 0).
--
--  Automatik: Die Injection Rate folgt dem Fuellstand der
--  Induction Matrix (Daten vom Matrix-Sender im Funknetz).
--  Matrix leer -> volle Rate, Matrix voll -> Minimum.
--  Sie geht NIE unter das Minimum, das der Reaktor meldet,
--  damit die Fusion nicht erlischt (Neuzuendung nur per Laser).
--
--  Aufbau: Fusion Reactor Logic Adapter in die Wand,
--  Computer direkt davor, dazu ein Ender Modem.
-- =====================================================

local CFG = {
  -- Funknetz: alle eigenen Computer brauchen GLEICHEN Namen + Passwort
  NETZ      = "Hier-Netzname-Eintragen",
  PASSWORT  = "Hier-Netzpasswort-Eintragen",
  NAME      = "Fusion 1",    -- Anzeigename (bei mehreren Reaktoren aendern!)
  INTERVALL = 1,             -- Sekunden zwischen Sendungen

  -- Automatik (nach Matrix-Fuellstand)
  RATE_MAX   = 98,           -- hoechste Injection Rate (gerade Zahl, max 98)
  RATE_MIN   = 2,            -- niedrigste Rate (Reaktor-Minimum gilt zusaetzlich)
  MATRIX_LEER = 0.20,        -- bis hierhin: volle Rate
  MATRIX_VOLL = 0.90,        -- ab hier: minimale Rate

  BRENN_WARN    = 0.10,      -- Warnung: D-T-Brennstoff unter 10 %
  FEHLER_PUFFER = 60,        -- "nicht geformt" erst nach 60 s melden
  DATEI     = "fusion.cfg",  -- speichert die Automatik-Einstellung
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
CFG.PROT_DATEN  = CFG.NETZ .. "/daten"
CFG.PROT_FUSION = CFG.NETZ .. "/fusion"

-- ---------- SHA-256 (fuer gesicherte Fernbefehle) ----------
local sha256
do
  local band, bnot, bxor = bit32.band, bit32.bnot, bit32.bxor
  local rrot, rshift = bit32.rrotate, bit32.rshift
  local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }
  local M32 = 0xffffffff

  local function zahlZuBytes(n, laenge)
    local s = ""
    for _ = 1, laenge do
      local rest = n % 256
      s = string.char(rest) .. s
      n = math.floor(n / 256)
    end
    return s
  end

  local function block(msg, i, H)
    local w = {}
    for j = 1, 16 do
      local a, b, c, d = string.byte(msg, i + (j - 1) * 4, i + (j - 1) * 4 + 3)
      w[j] = ((a * 256 + b) * 256 + c) * 256 + d
    end
    for j = 17, 64 do
      local v = w[j - 15]
      local s0 = bxor(rrot(v, 7), rrot(v, 18), rshift(v, 3))
      v = w[j - 2]
      local s1 = bxor(rrot(v, 17), rrot(v, 19), rshift(v, 10))
      w[j] = band(w[j - 16] + s0 + w[j - 7] + s1, M32)
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for j = 1, 64 do
      local S1 = bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = h + S1 + ch + K[j] + w[j]
      local S0 = bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      local t2 = S0 + maj
      h, g, f, e = g, f, e, band(d + t1, M32)
      d, c, b, a = c, b, a, band(t1 + t2, M32)
    end
    H[1] = band(H[1] + a, M32); H[2] = band(H[2] + b, M32)
    H[3] = band(H[3] + c, M32); H[4] = band(H[4] + d, M32)
    H[5] = band(H[5] + e, M32); H[6] = band(H[6] + f, M32)
    H[7] = band(H[7] + g, M32); H[8] = band(H[8] + h, M32)
  end

  sha256 = function(msg)
    local laenge = #msg
    local extra = 64 - ((laenge + 9) % 64)
    if extra == 64 then extra = 0 end
    msg = msg .. "\128" .. string.rep("\0", extra) .. zahlZuBytes(laenge * 8, 8)
    local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
    for i = 1, #msg, 64 do block(msg, i, H) end
    local out = {}
    for i = 1, 8 do out[i] = string.format("%08x", H[i]) end
    return table.concat(out)
  end
end


-- ---------- Signierte Funknachrichten ----------
-- Jede Nachricht = Inhalt als Text + Zeitstempel + Signatur
-- sha256(PASSWORT|NETZ|zeit|inhalt). Ohne Passwort keine
-- gueltige Signatur; alte Nachrichten verfallen nach 30 s.
local function signieren(inhalt)
  local s = textutils.serialize(inhalt, { compact = true })
  local t = os.epoch("utc")
  return { v = 2, t = t, s = s,
    sig = sha256(CFG.PASSWORT .. "|" .. CFG.NETZ .. "|" .. tostring(t) .. "|" .. s) }
end

local letzteZeit = {}
local function auspacken(id, msg)
  if type(msg) ~= "table" or msg.v ~= 2 or type(msg.s) ~= "string"
     or type(msg.t) ~= "number" or type(msg.sig) ~= "string" then return nil end
  if math.abs(os.epoch("utc") - msg.t) > 30000 then return nil end
  local erwartet = sha256(CFG.PASSWORT .. "|" .. CFG.NETZ .. "|" .. tostring(msg.t) .. "|" .. msg.s)
  if msg.sig ~= erwartet then return nil end
  local inhalt = textutils.unserialize(msg.s)
  if type(inhalt) ~= "table" then return nil end
  -- Wiederholte (abgefangene) Nachrichten verwerfen
  local key = id .. "/" .. tostring(inhalt.schluessel or inhalt.quelle or inhalt.typ)
  if letzteZeit[key] and msg.t <= letzteZeit[key] then return nil end
  letzteZeit[key] = msg.t
  return inhalt
end


-- ---------- Reaktor finden ----------
local port
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.hasType(n, "fusionReactorLogicAdapter") or peripheral.hasType(n, "fusionReactorPort") then
    port = n break
  end
end
if not port then error("Kein Fusion Reactor Logic Adapter gefunden!") end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Kein Ender Modem gefunden!") end
rednet.open(peripheral.getName(modem))

-- Jedes Mal frisch nachfragen (Multiblock kann neu formen)
local function r(fn, ...)
  local ok, v = pcall(peripheral.call, port, fn, ...)
  if ok then return v end
  return nil
end

-- Mekanism liefert Joule -> FE
local function fe(j)
  if type(j) ~= "number" then return nil end
  if mekanismEnergyHelper and mekanismEnergyHelper.joulesToFE then
    local ok, v = pcall(mekanismEnergyHelper.joulesToFE, j)
    if ok and type(v) == "number" then return v end
  end
  return j / 2.5
end

local function menge(t) return type(t) == "table" and t.amount or nil end
local function anteil(v)
  if type(v) ~= "number" or v ~= v then return nil end
  if v > 1.0001 then return v / 100 end
  return v
end

-- ---------- Einstellungen ----------
local auto = false
local function laden()
  if not fs.exists(CFG.DATEI) then return end
  local f = fs.open(CFG.DATEI, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  if type(t) == "table" and type(t.auto) == "boolean" then auto = t.auto end
end
local function speichern()
  local f = fs.open(CFG.DATEI, "w")
  f.write(textutils.serialize({ auto = auto }))
  f.close()
end

local logZeilen = {}
local function log(text)
  table.insert(logZeilen, 1, textutils.formatTime(os.time(), true) .. " " .. text)
  if #logZeilen > 4 then table.remove(logZeilen) end
end

-- ---------- Auslesen ----------
local function lesen()
  if r("isFormed") == false then error("Reaktor nicht geformt") end
  local d = {}
  local aktiv = r("isActiveCooledLogic") == true
  d.aktivKuehl   = aktiv
  d.gezuendet    = r("isIgnited") == true
  -- Hohlraum im Reaktor? (nil = nicht abfragbar)
  local h = r("getHohlraum")
  if type(h) == "table" then
    d.hohlraum = (tonumber(h.count) or 0) > 0 and tostring(h.name or ""):find("hohlraum") ~= nil
  end
  d.plasma       = r("getPlasmaTemperature")
  d.gehaeuse     = r("getCaseTemperature")
  d.plasmaMax    = r("getMaxPlasmaTemperature", aktiv)
  d.gehaeuseMax  = r("getMaxCasingTemperature", aktiv)
  d.zuendTemp    = r("getIgnitionTemperature", aktiv)
  d.rate         = r("getInjectionRate")
  d.rateMin      = r("getMinInjectionRate", aktiv)
  d.prod         = fe(r("getProductionRate"))
  d.passiv       = fe(r("getPassiveGeneration", aktiv))
  d.dt           = menge(r("getDTFuel"))
  d.dtMax        = r("getDTFuelCapacity")
  d.deut         = menge(r("getDeuterium"))
  d.deutMax      = r("getDeuteriumCapacity")
  d.trit         = menge(r("getTritium"))
  d.tritMax      = r("getTritiumCapacity")
  if aktiv then
    d.wasser    = anteil(r("getWaterFilledPercentage"))
    d.dampf     = anteil(r("getSteamFilledPercentage"))
  end
  return d
end

-- ---------- Matrix-Fuellstand aus dem Funknetz ----------
-- Alle Induction Matrizen (je Sender ein Eintrag), Automatik nutzt die Summe
local matrizenFz = {}   -- [schluessel] = { energie, max, zeit }
local matrix = { anteil = nil }
local function matrixFrisch()
  local e, m = 0, 0
  for k, v in pairs(matrizenFz) do
    if os.clock() - v.zeit < 10 then e, m = e + v.energie, m + v.max
    elseif os.clock() - v.zeit > 600 then matrizenFz[k] = nil end
  end
  if m <= 0 then matrix.anteil = nil return false end
  matrix.anteil = e / m
  return true
end

-- ---------- Automatik ----------
local function gerade(x) return math.floor(x / 2 + 0.5) * 2 end

local function automatik(d)
  if not auto or not d.gezuendet then return end
  if not matrixFrisch() then return end      -- ohne Matrix-Daten nichts aendern
  local q = matrix.anteil
  local t
  if q <= CFG.MATRIX_LEER then t = 1
  elseif q >= CFG.MATRIX_VOLL then t = 0
  else t = 1 - (q - CFG.MATRIX_LEER) / (CFG.MATRIX_VOLL - CFG.MATRIX_LEER) end
  -- Untergrenze: eigenes Minimum UND Reaktor-Minimum, aufgerundet auf gerade Zahl
  local minimum = math.max(CFG.RATE_MIN, d.rateMin or 0)
  if minimum % 2 == 1 then minimum = minimum + 1 end
  local ziel = gerade(minimum + t * (CFG.RATE_MAX - minimum))
  ziel = math.max(minimum, math.min(CFG.RATE_MAX, ziel))
  if ziel ~= d.rate then r("setInjectionRate", ziel) end
end

-- ---------- Fernbefehle ----------
local nonceListe = {}
local function neueNonce()
  local n = tostring(os.epoch("utc")) .. "-" .. tostring(math.random(100000, 999999))
  table.insert(nonceListe, n)
  if #nonceListe > 3 then table.remove(nonceListe, 1) end
  return n
end
local function nonceEinloesen(n)
  for i, v in ipairs(nonceListe) do
    if v == n then table.remove(nonceListe, i) return true end
  end
  return false
end

local function befehl(id, msg)
  local function antwort(ok, text)
    rednet.send(id, signieren({ typ = "antwort", ok = ok, text = CFG.NAME .. ": " .. text }), CFG.PROT_FUSION)
  end
  if type(msg.befehl) ~= "string" or type(msg.wert) ~= "string"
     or type(msg.nonce) ~= "string" or type(msg.sig) ~= "string" then return end
  local erwartet = sha256(CFG.PASSWORT .. "|" .. msg.befehl .. "|" .. msg.wert .. "|" .. msg.nonce)
  if not nonceEinloesen(msg.nonce) or msg.sig ~= erwartet then
    log("Abgelehnt: PC #" .. id)
    antwort(false, "Zugriff verweigert")
    return
  end
  if msg.befehl == "rate" then
    local v = tonumber(msg.wert)
    if not v then antwort(false, "Ungueltiger Wert") return end
    v = math.max(0, math.min(98, gerade(v)))
    r("setInjectionRate", v)
    local hinweis = ""
    if auto then auto = false speichern() hinweis = " (Automatik aus)" end
    log("Injection " .. v .. hinweis)
    antwort(true, "Injection Rate " .. v .. hinweis)
  elseif msg.befehl == "stopp" then
    r("setInjectionRate", 0)
    if auto then auto = false speichern() end
    log("STOPP (PC #" .. id .. ")")
    antwort(true, "Injection 0 - Fusion erlischt (Neuzuendung per Laser)")
  elseif msg.befehl == "auto" then
    auto = (msg.wert == "1")
    speichern()
    log("Automatik " .. (auto and "AN" or "AUS"))
    antwort(true, "Automatik " .. (auto and "AN" or "AUS") ..
      ((auto and not matrixFrisch()) and " - wartet auf Matrix-Daten" or ""))
  else
    antwort(false, "Unbekannter Befehl")
  end
end

-- ---------- Anzeige ----------
local function kurz(n)
  if type(n) ~= "number" then return "--" end
  local a = math.abs(n)
  if a >= 1e9 then return string.format("%.2fG", n / 1e9) end
  if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if a >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return string.format("%.0f", n)
end
local function zeile(y, text, farbe)
  term.setCursorPos(1, y)
  term.setTextColor(farbe or colors.white)
  term.clearLine()
  term.write(text)
end
local function anzeigen(d, fehler, puffer)
  term.setBackgroundColor(colors.black)
  term.clear()
  zeile(1, "CORVELYX // FUSION-REAKTOR   " .. CFG.NAME, colors.cyan)
  if fehler then
    zeile(3, (puffer and "Startet: " or "Fehler: ") .. tostring(fehler) .. (puffer and (" (" .. puffer .. " s)") or ""),
      puffer and colors.orange or colors.red)
  elseif d then
    zeile(3, d.gezuendet and "GEZUENDET" or "NICHT GEZUENDET (Laser noetig)", d.gezuendet and colors.lime or colors.orange)
    zeile(4, "Plasma: " .. kurz(d.plasma) .. " K   Gehaeuse: " .. kurz(d.gehaeuse) .. " K")
    zeile(5, "Injection: " .. tostring(d.rate) .. "  (min " .. tostring(d.rateMin or "?") .. ")")
    zeile(6, "Produktion: " .. kurz(d.prod) .. " FE/t")
    zeile(7, "D-T: " .. kurz(d.dt) .. " / " .. kurz(d.dtMax) .. " mB")
  end
  zeile(9, "Automatik: " .. (auto and "AN" or "aus") .. "   Matrix: " ..
    (matrixFrisch() and string.format("%.0f %%", matrix.anteil * 100) or "keine Daten"),
    auto and colors.lime or colors.gray)
  for i, l in ipairs(logZeilen) do zeile(10 + i, l, colors.lightGray) end
  zeile(18, "Funk an   Strg+T = Ende", colors.gray)
end

-- ---------- Hauptschleife ----------
laden()
math.randomseed(os.epoch("utc"))
local fehlerSeit, letzteGute = nil, nil
local zuletztGezuendet = nil

local timer = os.startTimer(0)
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == timer then
    local ok, d = pcall(lesen)
    local daten, fehlerText, puffer
    if ok then
      fehlerSeit, letzteGute = nil, d
      if zuletztGezuendet == true and not d.gezuendet then log("Fusion ERLOSCHEN") end
      zuletztGezuendet = d.gezuendet
      automatik(d)
      daten = d
    else
      fehlerText = tostring(d):gsub("^.-:%d+: ", "")
      fehlerSeit = fehlerSeit or os.clock()
      local dauer = os.clock() - fehlerSeit
      if dauer < CFG.FEHLER_PUFFER then
        puffer = math.ceil(CFG.FEHLER_PUFFER - dauer)
        daten = letzteGute or {}
      else
        daten = { fehler = fehlerText }
      end
    end
    daten.auto = auto
    daten.matrix = matrixFrisch() and matrix.anteil or nil
    daten.nonce = neueNonce()
    rednet.broadcast(signieren({ typ = "status", quelle = "fusion", name = CFG.NAME,
      schluessel = "fusion-" .. os.getComputerID(), brennWarn = CFG.BRENN_WARN, daten = daten }), CFG.PROT_DATEN)
    anzeigen(ok and d or nil, not ok and fehlerText or nil, puffer)
    timer = os.startTimer(CFG.INTERVALL)
  elseif ev[1] == "rednet_message" and ev[4] == CFG.PROT_FUSION then
    if type(ev[3]) == "table" and ev[3].befehl then befehl(ev[2], ev[3]) end
  elseif ev[1] == "rednet_message" and ev[4] == CFG.PROT_DATEN then
    -- Matrix-Fuellstand mitlesen (nur signierte Nachrichten)
    local msg = auspacken(ev[2], ev[3])
    if msg and msg.quelle == "matrix" and type(msg.daten) == "table" and type(msg.daten.energie) == "number"
        and type(msg.daten.max) == "number" and msg.daten.max > 0 then
      matrizenFz[tostring(msg.schluessel or ev[2])] = { energie = msg.daten.energie, max = msg.daten.max, zeit = os.clock() }
    end
  end
end
