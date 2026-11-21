-- =====================================================
--  CORVELYX // XTREME-REAKTOR  v1.1
--  Steuerung fuer einen Extreme-Reactors-Reaktor.
--  Liest alle Werte, funkt sie an Control Center und
--  Pocket und nimmt gesicherte Befehle an:
--    AN / AUS, Steuerstaebe, Automatik, Abfall auswerfen.
--
--  Automatik: Die Steuerstaebe folgen dem internen
--  Energiespeicher (Speicher 30 % voll -> Staebe 30 % drin).
--  So verbrennt der Reaktor nur, was abgenommen wird.
--  (Extreme Reactors koennen nicht schmelzen - hier geht
--  es um Effizienz, nicht um Notabschaltung.)
--
--  Aufbau: Reactor Computer Port in die Reaktorwand,
--  Computer direkt davor, dazu ein Ender Modem.
-- =====================================================

local CFG = {
  -- Funknetz: alle eigenen Computer brauchen GLEICHEN Namen + Passwort
  NETZ      = "Hier-Netzname-Eintragen",
  PASSWORT  = "Hier-Netzpasswort-Eintragen",
  NAME      = "Xtreme 1",   -- Anzeigename (bei mehreren Reaktoren aendern!)
  INTERVALL = 1,            -- Sekunden zwischen Sendungen

  -- Automatik: Staebe = Speicher-Fuellstand, begrenzt auf MIN..MAX
  STAB_MIN  = 0,            -- Staebe nie weiter raus als ... %
  STAB_MAX  = 100,          -- Staebe nie weiter rein als ... %

  BRENN_WARN    = 0.10,     -- Warnung: Brennstoff unter 10 %
  FEHLER_PUFFER = 60,       -- "nicht zusammengebaut" erst nach 60 s melden
  DATEI     = "xtreme.cfg", -- speichert die Automatik-Einstellung
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
-- Sprache (de/en) - wird vom Update-Computer fuers ganze Netz vorgegeben
local EN = {
  ["  (aktiv gekuehlt)"] = "  (actively cooled)",
  ["  (passiv)"] = "  (passive)",
  [" (Automatik aus)"] = " (automatic off)",
  [" Stueck)"] = " pcs)",
  [" mB   Abfall: "] = " mB   Waste: ",
  ["AN"] = "ON",
  ["AN (PC #"] = "ON (PC #",
  ["AUS"] = "OFF",
  ["AUS (PC #"] = "OFF (PC #",
  ["Abfall ausgeworfen"] = "Waste ejected",
  ["Abfall wird ausgeworfen"] = "Ejecting waste",
  ["Abgelehnt: PC #"] = "Refused: PC #",
  ["Automatik "] = "Automatic ",
  ["Automatik: "] = "Automatic: ",
  ["Brennstoff: "] = "Fuel: ",
  ["Energie: "] = "Energy: ",
  ["Fehler: "] = "Error: ",
  ["Funk an   Strg+T = Ende"] = "Radio on   Ctrl+T = quit",
  ["Kein Ender Modem gefunden!"] = "No Ender Modem found!",
  ["Kein Reactor Computer Port gefunden!"] = "No Reactor Computer Port found!",
  ["Produktion: "] = "Production: ",
  ["Reaktor nicht zusammengebaut"] = "Reactor not assembled",
  ["Reaktor: "] = "Reactor: ",
  ["Staebe "] = "Rods ",
  ["Staebe: "] = "Rods: ",
  ["Startet: "] = "Starting: ",
  ["Temperatur: %.0f C (Gehaeuse %.0f C)"] = "Temperature: %.0f C (casing %.0f C)",
  ["Unbekannter Befehl"] = "Unknown command",
  ["Ungueltiger Wert"] = "Invalid value",
  ["Zugriff verweigert"] = "Access denied",
  ["ausgeschaltet"] = "switched off",
  ["eingeschaltet"] = "switched on",
}
local function L(s) if CFG.SPRACHE == "en" then return EN[s] or s end return s end
CFG.PROT_DATEN  = CFG.NETZ .. "/daten"
CFG.PROT_XTREME = CFG.NETZ .. "/xtreme"

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

-- ---------- Reaktor finden ----------
local function finden()
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "BigReactors-Reactor") then return n end
  end
end
local port = finden()
if not port then error(L("Kein Reactor Computer Port gefunden!")) end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error(L("Kein Ender Modem gefunden!")) end
rednet.open(peripheral.getName(modem))

-- Jedes Mal frisch beim Reaktor nachfragen (Multiblock kann neu formen)
local function r(fn, ...)
  local ok, v = pcall(peripheral.call, port, fn, ...)
  if ok then return v end
  return nil
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
  if r("mbIsAssembled") == false then error(L("Reaktor nicht zusammengebaut")) end
  local d = {}
  local e = r("getEnergyStats") or {}
  local f = r("getFuelStats") or {}
  d.aktiv      = r("getActive") == true
  d.aktivKuehl = r("isActivelyCooled") == true
  d.energie    = e.energyStored or r("getEnergyStored")
  d.kapazitaet = e.energyCapacity or r("getEnergyCapacity")
  d.prod       = e.energyProducedLastTick or r("getEnergyProducedLastTick")
  d.brenn      = f.fuelAmount or r("getFuelAmount")
  d.brennMax   = f.fuelCapacity or r("getFuelAmountMax")
  d.abfall     = f.wasteAmount or r("getWasteAmount")
  d.tempBrenn  = f.fuelTemperature or r("getFuelTemperature")
  d.tempGehaeuse = r("getCasingTemperature")
  d.verbrauch  = f.fuelConsumedLastTick or r("getFuelConsumedLastTick")
  d.reaktivitaet = f.fuelReactivity or r("getFuelReactivity")
  -- Steuerstaebe (Durchschnitt)
  local staebe = r("getControlRodsLevels")
  local summe, anzahl = 0, 0
  if type(staebe) == "table" then
    for _, v in pairs(staebe) do summe = summe + v anzahl = anzahl + 1 end
  end
  d.staebe = anzahl > 0 and math.floor(summe / anzahl + 0.5) or nil
  d.stabAnzahl = r("getNumberOfControlRods") or anzahl
  if d.aktivKuehl then
    local h = r("getHotFluidStats") or {}
    local c = r("getCoolantFluidStats") or {}
    d.dampfProd   = h.fluidProducedLastTick
    d.dampf       = h.fluidAmount
    d.dampfMax    = h.fluidCapacity
    d.kuehl       = c.fluidAmount
    d.kuehlMax    = c.fluidCapacity
  end
  return d
end

-- ---------- Automatik ----------
local letzterStab = nil
local function automatik(d)
  if not auto or not d.aktiv then return end
  local anteil
  if d.aktivKuehl then
    -- aktiv gekuehlt: nach Dampf-Fuellstand regeln
    anteil = (d.dampfMax or 0) > 0 and (d.dampf or 0) / d.dampfMax or 0
  else
    anteil = (d.kapazitaet or 0) > 0 and (d.energie or 0) / d.kapazitaet or 0
  end
  local ziel = math.floor(anteil * 100 + 0.5)
  ziel = math.max(CFG.STAB_MIN, math.min(CFG.STAB_MAX, ziel))
  if ziel ~= letzterStab and ziel ~= d.staebe then
    r("setAllControlRodLevels", ziel)
    letzterStab = ziel
  end
end

-- ---------- Fernbefehle (wie beim Mekanism-Waechter) ----------
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
    rednet.send(id, signieren({ typ = "antwort", ok = ok, text = CFG.NAME .. ": " .. text }), CFG.PROT_XTREME)
  end
  if type(msg.befehl) ~= "string" or type(msg.wert) ~= "string"
     or type(msg.nonce) ~= "string" or type(msg.sig) ~= "string" then return end
  local erwartet = sha256(CFG.PASSWORT .. "|" .. msg.befehl .. "|" .. msg.wert .. "|" .. msg.nonce)
  if not nonceEinloesen(msg.nonce) or msg.sig ~= erwartet then
    log(L("Abgelehnt: PC #") .. id)
    antwort(false, L("Zugriff verweigert"))
    return
  end
  if msg.befehl == "an" then
    r("setActive", true) log(L("AN (PC #") .. id .. ")") antwort(true, L("eingeschaltet"))
  elseif msg.befehl == "aus" then
    r("setActive", false) log(L("AUS (PC #") .. id .. ")") antwort(true, L("ausgeschaltet"))
  elseif msg.befehl == "stab" then
    local v = tonumber(msg.wert)
    if not v then antwort(false, L("Ungueltiger Wert")) return end
    v = math.max(0, math.min(100, math.floor(v)))
    r("setAllControlRodLevels", v)
    letzterStab = v
    local hinweis = ""
    if auto then auto = false speichern() hinweis = L(" (Automatik aus)") end
    log(L("Staebe ") .. v .. "%" .. hinweis)
    antwort(true, L("Staebe ") .. v .. "%" .. hinweis)
  elseif msg.befehl == "auto" then
    auto = (msg.wert == "1")
    speichern()
    letzterStab = nil
    log(L("Automatik ") .. (auto and L("AN") or L("AUS")))
    antwort(true, L("Automatik ") .. (auto and L("AN") or L("AUS")))
  elseif msg.befehl == "abfall" then
    r("doEjectWaste") log(L("Abfall ausgeworfen")) antwort(true, L("Abfall wird ausgeworfen"))
  else
    antwort(false, L("Unbekannter Befehl"))
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
  zeile(1, "CORVELYX // XTREME-REAKTOR   " .. CFG.NAME, colors.cyan)
  if fehler then
    zeile(3, (puffer and L("Startet: ") or L("Fehler: ")) .. tostring(fehler) .. (puffer and (" (" .. puffer .. " s)") or ""),
      puffer and colors.orange or colors.red)
  elseif d then
    zeile(3, L("Reaktor: ") .. (d.aktiv and L("AN") or L("AUS")) .. (d.aktivKuehl and L("  (aktiv gekuehlt)") or L("  (passiv)")),
      d.aktiv and colors.lime or colors.lightGray)
    zeile(4, L("Energie: ") .. kurz(d.energie) .. " / " .. kurz(d.kapazitaet) .. " FE")
    zeile(5, L("Produktion: ") .. kurz(d.prod) .. " FE/t")
    zeile(6, L("Brennstoff: ") .. kurz(d.brenn) .. " / " .. kurz(d.brennMax) .. L(" mB   Abfall: ") .. kurz(d.abfall))
    zeile(7, string.format(L("Temperatur: %.0f C (Gehaeuse %.0f C)"), d.tempBrenn or 0, d.tempGehaeuse or 0))
    zeile(8, L("Staebe: ") .. tostring(d.staebe or "--") .. " %  (" .. tostring(d.stabAnzahl) .. L(" Stueck)"))
  end
  zeile(10, L("Automatik: ") .. (auto and L("AN") or (L("AUS")):lower()), auto and colors.lime or colors.gray)
  for i, l in ipairs(logZeilen) do zeile(11 + i, l, colors.lightGray) end
  zeile(18, L("Funk an   Strg+T = Ende"), colors.gray)
end

-- ---------- Hauptschleife ----------
laden()
math.randomseed(os.epoch("utc"))
local fehlerSeit, letzteGute = nil, nil

local timer = os.startTimer(0)
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == timer then
    local ok, d = pcall(lesen)
    local daten, fehlerText, puffer
    if ok then
      fehlerSeit, letzteGute = nil, d
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
    daten.nonce = neueNonce()
    rednet.broadcast(signieren({ typ = "status", quelle = "xtreme", name = CFG.NAME,
      schluessel = "xtreme-" .. os.getComputerID(), brennWarn = CFG.BRENN_WARN, daten = daten }), CFG.PROT_DATEN)
    anzeigen(ok and d or nil, not ok and fehlerText or nil, puffer)
    timer = os.startTimer(CFG.INTERVALL)
  elseif ev[1] == "rednet_message" and ev[4] == CFG.PROT_XTREME then
    if type(ev[3]) == "table" and ev[3].befehl then befehl(ev[2], ev[3]) end
  end
end
