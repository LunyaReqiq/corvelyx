-- =====================================================
--  CORVELYX // SENDER  v1.9
--  Liest eine Anlage aus und funkt die Werte per
--  Ender Modem an das Control Center.
--
--  Erkennt automatisch, woran der Computer haengt:
--    Induction Port  -> "matrix"
--    Turbine Valve   -> "turbine"
--    ME Bridge       -> "me"
--
--  Aufbau: Computer direkt an den Port/Valve/Bridge,
--  Ender Modem an eine freie Seite.
-- =====================================================

local CFG = {
  -- Funknetz: alle eigenen Computer brauchen GLEICHEN Namen + Passwort
  NETZ      = "Hier-Netzname-Eintragen",
  PASSWORT  = "Hier-Netzpasswort-Eintragen",
  INTERVALL = 1,          -- Sekunden zwischen Sendungen
  -- Mekanism liefert Joule. 1 FE = 2.5 J.
  -- nil = automatisch (Mekanism-Helfer, sonst / 2.5)
  J_PRO_FE  = nil,
  -- Anzeigename im Control Center, z.B. "Turbine 1"
  -- (wichtig bei mehreren Turbinen; nil = automatisch)
  NAME      = nil,
  -- Fehler (z.B. "Turbine nicht geformt") erst melden, wenn sie
  -- laenger als so viele Sekunden anhalten. Ueberbrueckt das
  -- Neu-Formen der Multiblocks nach Chunk-Laden / Relog.
  FEHLER_PUFFER = 60,
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
-- Sprache (de/en) - wird vom Update-Computer fuers ganze Netz vorgegeben
local EN = {
  [" s. Strg+T = Ende"] = " s. Ctrl+T = quit",
  ["Fehler: "] = "Error: ",
  ["Kein Ender Modem gefunden!"] = "No Ender Modem found!",
  ["Keine Anlage gefunden! (Induction Port, Turbine Valve oder ME Bridge)"] = "No device found! (Induction Port, Turbine Valve or ME Bridge)",
  ["Matrix nicht geformt"] = "Matrix not formed",
  ["Quelle: "] = "Source: ",
  ["Sendet jede "] = "Sending every ",
  ["Startet: "] = "Starting: ",
  ["Turbine nicht geformt"] = "Turbine not formed",
}
local function L(s) if CFG.SPRACHE == "en" then return EN[s] or s end return s end

CFG.PROTOKOLL = CFG.NETZ .. "/daten"

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

local TYPEN = {
  { quelle = "matrix",  typen = { "inductionPort" } },
  { quelle = "turbine", typen = { "turbineValve" } },
  { quelle = "me",      typen = { "me_bridge", "meBridge" } },
}

-- ---------- Hilfsfunktionen ----------
local function anteil(v)
  if type(v) ~= "number" then return nil end
  if v > 1.0001 then return v / 100 end
  return v
end

-- Funktion aufrufen, falls vorhanden; Fehler -> nil.
-- Wichtig: jedes Mal FRISCH beim Geraet nachfragen (peripheral.call).
-- Mekanism-Multiblocks melden manche Funktionen (z.B. getLastInput)
-- erst, wenn sie geformt sind - eine beim Start gemerkte Liste
-- wuerde diese Funktionen sonst bis zum Neustart nie sehen.
local function p(dev, fn, ...)
  if not dev then return nil end
  local okN, name = pcall(peripheral.getName, dev)
  if okN and name then
    local ok, v = pcall(peripheral.call, name, fn, ...)
    if ok then return v end
    return nil
  end
  if type(dev[fn]) == "function" then
    local ok, v = pcall(dev[fn], ...)
    if ok then return v end
  end
  return nil
end

local function fe(j)
  if type(j) ~= "number" then return nil end
  if CFG.J_PRO_FE then return j / CFG.J_PRO_FE end
  if mekanismEnergyHelper and mekanismEnergyHelper.joulesToFE then
    local ok, v = pcall(mekanismEnergyHelper.joulesToFE, j)
    if ok and type(v) == "number" then return v end
  end
  return j / 2.5
end

local function kurz(n)
  if type(n) ~= "number" then return "--" end
  local a = math.abs(n)
  if a >= 1e15 then return string.format("%.2fP", n / 1e15) end
  if a >= 1e12 then return string.format("%.2fT", n / 1e12) end
  if a >= 1e9  then return string.format("%.2fG", n / 1e9) end
  if a >= 1e6  then return string.format("%.2fM", n / 1e6) end
  if a >= 1e3  then return string.format("%.1fk", n / 1e3) end
  return string.format("%.0f", n)
end

-- ---------- Anlage finden ----------
local quelle, dev
for _, eintrag in ipairs(TYPEN) do
  for _, typ in ipairs(eintrag.typen) do
    local d = peripheral.find(typ)
    if d then quelle, dev = eintrag.quelle, d break end
  end
  if quelle then break end
end
if not quelle then
  error(L("Keine Anlage gefunden! (Induction Port, Turbine Valve oder ME Bridge)"))
end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error(L("Kein Ender Modem gefunden!")) end
rednet.open(peripheral.getName(modem))

-- ---------- Auslesen ----------
local LESER = {}

function LESER.matrix(d)
  if p(d, "isFormed") == false then error(L("Matrix nicht geformt")) end
  return {
    energie = fe(p(d, "getEnergy")),
    max     = fe(p(d, "getMaxEnergy")),
    anteil  = anteil(p(d, "getEnergyFilledPercentage")),
    rein    = fe(p(d, "getLastInput")),
    raus    = fe(p(d, "getLastOutput")),
    limit   = fe(p(d, "getTransferCap")),
  }
end

function LESER.turbine(d)
  if p(d, "isFormed") == false then error(L("Turbine nicht geformt")) end
  return {
    produktion = fe(p(d, "getProductionRate")),
    maxProd    = fe(p(d, "getMaxProduction")),
    dampf      = anteil(p(d, "getSteamFilledPercentage")),
    puffer     = anteil(p(d, "getEnergyFilledPercentage")),
    fluss      = p(d, "getFlowRate"),
    maxFluss   = p(d, "getMaxFlowRate"),
  }
end

function LESER.me(d)
  -- Gesamt = benutzt + frei, falls "Max"/"Total" nichts liefert
  local function speicher(art)
    local benutzt = p(d, "getUsed" .. art .. "Storage")
    local gesamt  = p(d, "getMax" .. art .. "Storage") or p(d, "getTotal" .. art .. "Storage")
    local frei    = p(d, "getAvailable" .. art .. "Storage")
    if type(gesamt) ~= "number" and type(benutzt) == "number" and type(frei) == "number" then
      gesamt = benutzt + frei
    end
    if type(benutzt) ~= "number" and type(gesamt) == "number" and type(frei) == "number" then
      benutzt = gesamt - frei
    end
    return benutzt, gesamt
  end
  local itemsBenutzt, itemsGesamt = speicher("Item")
  local fluidBenutzt, fluidGesamt = speicher("Fluid")
  local chemBenutzt, chemGesamt = speicher("Chemical")
  return {
    itemsBenutzt = itemsBenutzt, itemsGesamt = itemsGesamt,
    fluidBenutzt = fluidBenutzt, fluidGesamt = fluidGesamt,
    chemBenutzt  = chemBenutzt,  chemGesamt  = chemGesamt,
  }
end

-- ---------- Geraete und Namen ----------
-- Bei Turbinen werden ALLE angeschlossenen Valves gelesen
-- (z.B. zwei Turbinen per Wired Modem an einem PC).
local geraete = { dev }
if quelle == "turbine" then geraete = { peripheral.find("turbineValve") } end

local eintraege = {}
for i, g in ipairs(geraete) do
  local name
  if CFG.NAME then
    name = (#geraete > 1) and (CFG.NAME .. " " .. i) or CFG.NAME
  elseif quelle == "turbine" then
    name = "Turbine PC" .. os.getComputerID() .. ((#geraete > 1) and ("-" .. i) or "")
  elseif quelle == "matrix" then
    name = "Matrix PC" .. os.getComputerID() .. ((#geraete > 1) and ("-" .. i) or "")
  else
    name = quelle
  end
  eintraege[i] = {
    dev = g,
    name = name,
    schluessel = os.getComputerID() .. ":" .. peripheral.getName(g),
  }
end

-- ---------- Anzeige auf dem eigenen Bildschirm ----------
local function anzeigen()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  print("CORVELYX // SENDER")
  term.setTextColor(colors.white)
  print(L("Quelle: ") .. quelle .. "   PC #" .. os.getComputerID())
  for _, e in ipairs(eintraege) do
    print("")
    term.setTextColor(colors.white)
    print("[" .. e.name .. "]")
    if e.fehler and e.puffer then
      term.setTextColor(colors.orange)
      print(L("Startet: ") .. tostring(e.fehler) .. " (" .. e.puffer .. " s)")
    elseif e.fehler then
      term.setTextColor(colors.red)
      print(L("Fehler: ") .. tostring(e.fehler))
    elseif e.daten then
      term.setTextColor(colors.lightGray)
      local namen = {}
      for k in pairs(e.daten) do namen[#namen + 1] = k end
      table.sort(namen)
      for _, k in ipairs(namen) do
        print(string.format("%-14s %s", k, kurz(e.daten[k])))
      end
    end
  end
  term.setTextColor(colors.gray)
  print("")
  print(L("Sendet jede ") .. CFG.INTERVALL .. L(" s. Strg+T = Ende"))
end

-- ---------- Hauptschleife ----------
while true do
  for _, e in ipairs(eintraege) do
    local ok, daten = pcall(LESER[quelle], e.dev)
    if ok then
      e.daten, e.fehler, e.fehlerSeit, e.puffer = daten, nil, nil, nil
      e.letzteGute = daten
    else
      -- "/startup.lua:188: Turbine nicht geformt" -> "Turbine nicht geformt"
      local text = tostring(daten):gsub("^.-:%d+: ", "")
      e.fehler = text
      e.fehlerSeit = e.fehlerSeit or os.clock()
      local dauer = os.clock() - e.fehlerSeit
      if dauer < CFG.FEHLER_PUFFER then
        -- Noch im Puffer: letzte gute Werte (oder leer) senden, kein Alarm
        e.puffer = math.ceil(CFG.FEHLER_PUFFER - dauer)
        e.daten = e.letzteGute or {}
      else
        e.puffer = nil
        e.daten = { fehler = text }
      end
    end
    rednet.broadcast(signieren({ typ = "status", quelle = quelle, name = e.name,
      schluessel = e.schluessel, daten = e.daten }), CFG.PROTOKOLL)
  end
  anzeigen()
  sleep(CFG.INTERVALL)
end
