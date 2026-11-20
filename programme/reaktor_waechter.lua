-- =====================================================
--  CORVELYX // REAKTOR-WAECHTER  v1.3
--  Ueberwacht den Mekanism-Fission-Reaktor und loest
--  bei kritischen Werten eine Notabschaltung (SCRAM) aus.
--
--  Aufbau: Computer DIREKT an einen Fission Reactor
--  Logic Adapter (Modus "Activation") setzen.
--  Tasten:  R = Reset nach SCRAM   T = Test-SCRAM
-- =====================================================

local CFG = {
  -- Grenzwerte (Anteile 0.0 - 1.0, Temperatur in Kelvin)
  -- Abgestimmt auf: Wasserkuehlung, Burn Rate bis 1000 mB/t
  TEMP_WARN     = 850,    -- Normalbetrieb ca. 650-700 K
  TEMP_SCRAM    = 1000,   -- Schaden beginnt ab 1200 K
  KUEHL_WARN    = 0.80,   -- Wasser sollte immer fast voll sein
  KUEHL_SCRAM   = 0.60,
  HEISS_WARN    = 0.50,   -- Dampf staut sich = Turbine kommt nicht hinterher
  HEISS_SCRAM   = 0.80,
  MUELL_WARN    = 0.50,
  MUELL_SCRAM   = 0.80,
  BRENN_WARN    = 0.10,   -- nur Warnung, kein SCRAM

  -- Redstone
  SCRAM_SEITE   = "back", -- Seite, die den Logic Adapter beruehrt
  SCRAM_SIGNAL  = true,   -- true: Signal AN = Reaktor AUS
                          -- false: Signal AUS = Reaktor AUS
  ALARM_SEITE   = "top",  -- Lampen / Glocke (nil = keine)

  -- Funknetz + Fernsteuerung: MUSS auf allen eigenen PCs
  -- (v.a. im Control Center) genau gleich eingetragen sein!
  NETZ          = "Hier-Netzname-Eintragen",
  PASSWORT      = "Hier-Netzpasswort-Eintragen",

  -- Sonstiges
  INTERVALL     = 0.5,    -- Sekunden zwischen Pruefungen
  MAX_FEHLER    = 3,      -- Lesefehler in Folge bis SCRAM
  LOGDATEI      = "reaktor.log",
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
CFG.PROTOKOLL = CFG.NETZ .. "/reaktor"

-- ---------- Zustand ----------
local reaktor      = nil
local gesperrt     = false    -- SCRAM eingerastet?
local scramGrund   = ""
local warnungen    = {}
local daten        = nil
local fehlerFolge  = 0
local meldung      = ""
local blink        = false
local funkAktiv    = false

-- ---------- Hilfsfunktionen ----------
local function log(text)
  local zeit = textutils.formatTime(os.time(), true)
  local f = fs.open(CFG.LOGDATEI, "a")
  if f then
    f.writeLine("[Tag " .. os.day() .. " " .. zeit .. "] " .. text)
    f.close()
  end
end

-- Manche Versionen liefern 0-1, andere 0-100
local function anteil(v)
  if type(v) ~= "number" then return 0 end
  if v > 1.0001 then return v / 100 end
  return v
end

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

local function suchen()
  reaktor = peripheral.find("fissionReactorLogicAdapter")
         or peripheral.find("fissionReactorPort")
  return reaktor ~= nil
end

local function lesen()
  if not reaktor and not suchen() then error("kein Reaktor gefunden") end
  local r = reaktor
  local d = {}
  if r.isFormed and not r.isFormed() then error("Reaktor nicht geformt") end
  d.aktiv    = r.getStatus()
  d.temp     = r.getTemperature()
  d.schaden  = r.getDamagePercent()
  d.kuehl    = anteil(r.getCoolantFilledPercentage())
  d.heiss    = anteil(r.getHeatedCoolantFilledPercentage())
  d.muell    = anteil(r.getWasteFilledPercentage())
  d.brenn    = anteil(r.getFuelFilledPercentage())
  d.burn     = r.getBurnRate()
  d.burnIst  = r.getActualBurnRate()
  d.burnMax  = r.getMaxBurnRate()
  return d
end

-- Liefert Liste der SCRAM-Gruende und der Warnungen
local function pruefen(d)
  local s, w = {}, {}
  if d.schaden > 0 then s[#s+1] = string.format("Schaden %.2f", d.schaden) end
  if d.temp >= CFG.TEMP_SCRAM then s[#s+1] = string.format("Temperatur %.0f K", d.temp)
  elseif d.temp >= CFG.TEMP_WARN then w[#w+1] = string.format("Temperatur %.0f K", d.temp) end
  if d.kuehl <= CFG.KUEHL_SCRAM then s[#s+1] = string.format("Kuehlmittel %.0f%%", d.kuehl * 100)
  elseif d.kuehl <= CFG.KUEHL_WARN then w[#w+1] = string.format("Kuehlmittel %.0f%%", d.kuehl * 100) end
  if d.heiss >= CFG.HEISS_SCRAM then s[#s+1] = string.format("Heisses Kuehlm. %.0f%%", d.heiss * 100)
  elseif d.heiss >= CFG.HEISS_WARN then w[#w+1] = string.format("Heisses Kuehlm. %.0f%%", d.heiss * 100) end
  if d.muell >= CFG.MUELL_SCRAM then s[#s+1] = string.format("Atommuell %.0f%%", d.muell * 100)
  elseif d.muell >= CFG.MUELL_WARN then w[#w+1] = string.format("Atommuell %.0f%%", d.muell * 100) end
  -- Brennstoff: nur relevant, wenn der Reaktor eingeschaltet ist
  if d.aktiv then
    if d.brenn <= 0.001 then w[#w+1] = "Kein Brennstoff - Reaktor steht"
    elseif d.brenn <= CFG.BRENN_WARN then w[#w+1] = string.format("Brennstoff niedrig %.0f%%", d.brenn * 100) end
  end
  return s, w
end

local function redstoneNormal()
  redstone.setOutput(CFG.SCRAM_SEITE, not CFG.SCRAM_SIGNAL)
end

local function scram(grund)
  -- 1. Redstone-Weg (wirkt auch ohne Peripheral)
  redstone.setOutput(CFG.SCRAM_SEITE, CFG.SCRAM_SIGNAL)
  -- 2. Direkter Befehl (Fehler, wenn schon aus -> egal)
  if reaktor then pcall(reaktor.scram) end
  if not gesperrt then
    gesperrt = true
    scramGrund = grund
    log("SCRAM: " .. grund)
  end
end

local function reset()
  if not gesperrt then meldung = "Kein SCRAM aktiv." return end
  local ok, d = pcall(lesen)
  if not ok then meldung = "Reset abgelehnt: keine Daten." return end
  local s = pruefen(d)
  if #s > 0 then
    meldung = "Reset abgelehnt: " .. s[1]
    return
  end
  gesperrt = false
  scramGrund = ""
  redstoneNormal()
  log("Reset durch Bediener")
  meldung = "Reset ok. Reaktor manuell starten."
end

-- ---------- Anzeige ----------
local function zeile(y, text, farbe)
  term.setCursorPos(1, y)
  term.setTextColor(farbe or colors.white)
  term.clearLine()
  term.write(text)
end

local function zeichnen()
  term.setBackgroundColor(colors.black)
  term.clear()
  zeile(1, "CORVELYX // REAKTOR-WAECHTER", colors.cyan)

  if gesperrt then
    zeile(3, "!! SCRAM AKTIV !!", colors.red)
    zeile(4, "Grund: " .. scramGrund, colors.red)
  elseif #warnungen > 0 then
    local mehr = #warnungen > 1 and ("  (+" .. (#warnungen - 1) .. " weitere)") or ""
    zeile(3, "WARNUNG" .. mehr, colors.orange)
    zeile(4, warnungen[1], colors.orange)
  else
    zeile(3, "Status: OK", colors.lime)
  end

  if daten then
    local d = daten
    if d.aktiv and d.burnIst <= 0 and d.brenn <= 0.001 then
      zeile(6, "Reaktor:     AN (steht, kein Brennstoff)", colors.orange)
    else
      zeile(6, "Reaktor:     " .. (d.aktiv and "AN" or "AUS"), d.aktiv and colors.lime or colors.lightGray)
    end
    zeile(7,  string.format("Temperatur:  %.0f K", d.temp))
    zeile(8,  string.format("Schaden:     %.2f", d.schaden))
    zeile(9,  string.format("Kuehlmittel: %.0f%%", d.kuehl * 100))
    zeile(10, string.format("Heiss:       %.0f%%", d.heiss * 100))
    zeile(11, string.format("Atommuell:   %.0f%%", d.muell * 100))
    zeile(12, string.format("Brennstoff:  %.0f%%", d.brenn * 100))
    zeile(13, string.format("Burn Rate:   %.1f / %.1f mB/t", d.burnIst, d.burn))
  else
    zeile(6, "Keine Reaktordaten!", colors.red)
  end

  zeile(15, "Funk: " .. (funkAktiv and "an" or "kein Ender Modem"), colors.gray)
  zeile(16, meldung, colors.yellow)
  zeile(18, "[R] Reset   [T] Test-SCRAM", colors.lightGray)
end

-- ---------- Schleifen ----------
local function ueberwachung()
  -- Beim Start bis zu 10 s auf den Reaktor warten (Chunk laedt)
  for _ = 1, 20 do
    if pcall(lesen) then break end
    sleep(0.5)
  end

  while true do
    local ok, d = pcall(lesen)
    if ok then
      fehlerFolge = 0
      daten = d
      local s, w = pruefen(d)
      warnungen = w
      if #s > 0 then
        scram(table.concat(s, ", "))
      elseif gesperrt and d.aktiv then
        -- jemand hat waehrend SCRAM manuell gestartet
        scram(scramGrund)
      end
    else
      fehlerFolge = fehlerFolge + 1
      reaktor = nil
      daten = nil
      if fehlerFolge >= CFG.MAX_FEHLER then
        scram("Verbindung verloren: " .. tostring(d))
      end
    end

    if not gesperrt then redstoneNormal() end

    -- Alarm: Dauerlicht bei SCRAM, Blinken bei Warnung
    if CFG.ALARM_SEITE then
      blink = not blink
      local an = gesperrt or (#warnungen > 0 and blink)
      redstone.setOutput(CFG.ALARM_SEITE, an)
    end

    zeichnen()
    sleep(CFG.INTERVALL)
  end
end

local function tastatur()
  while true do
    local _, taste = os.pullEvent("key")
    if taste == keys.r then
      reset()
    elseif taste == keys.t then
      scram("TEST durch Bediener")
      meldung = "Test-SCRAM ausgeloest."
    end
  end
end

-- ---------- Fernbefehle ----------
-- Jede Statusmeldung enthaelt eine Einmal-Nummer (Nonce).
-- Ein Befehl gilt nur mit sha256(PASSWORT|befehl|nonce)
-- und jede Nonce nur einmal -> Mithoeren nuetzt nichts.
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
    rednet.send(id, signieren({ typ = "antwort", ok = ok, text = text }), CFG.PROTOKOLL)
  end
  if type(msg.befehl) ~= "string" or type(msg.nonce) ~= "string"
     or type(msg.sig) ~= "string" then return end

  local erwartet = sha256(CFG.PASSWORT .. "|" .. msg.befehl .. "|" .. msg.nonce)
  if not nonceEinloesen(msg.nonce) or msg.sig ~= erwartet then
    log("Abgelehnter Fernbefehl von PC #" .. id)
    antwort(false, "Zugriff verweigert")
    return
  end

  if msg.befehl == "notaus" then
    scram("Fern-NOT-AUS von PC #" .. id)
    antwort(true, "NOT-AUS ausgefuehrt")

  elseif msg.befehl == "stop" then
    if reaktor and daten and daten.aktiv then
      pcall(reaktor.scram)
      log("Fern-Stopp von PC #" .. id)
      antwort(true, "Reaktor gestoppt")
    else
      antwort(false, "Reaktor ist bereits aus")
    end

  elseif msg.befehl == "start" then
    if gesperrt then
      antwort(false, "Abgelehnt: SCRAM aktiv - Reset vor Ort")
      return
    end
    local ok, d = pcall(lesen)
    if not ok then antwort(false, "Abgelehnt: keine Reaktordaten") return end
    local s = pruefen(d)
    if #s > 0 then antwort(false, "Abgelehnt: " .. s[1]) return end
    if d.kuehl < CFG.KUEHL_WARN then
      antwort(false, string.format("Abgelehnt: Kuehlmittel %.0f%%", d.kuehl * 100))
      return
    end
    if d.aktiv then antwort(false, "Reaktor laeuft bereits") return end
    local ok2, err = pcall(reaktor.activate)
    if ok2 then
      log("Fern-Start von PC #" .. id)
      meldung = "Fern-Start von PC #" .. id
      antwort(true, "Reaktor gestartet")
    else
      antwort(false, "Start fehlgeschlagen: " .. tostring(err))
    end
  end
end

local function funk()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then
    while true do sleep(3600) end
  end
  rednet.open(peripheral.getName(modem))
  funkAktiv = true
  math.randomseed(os.epoch("utc"))

  local timer = os.startTimer(1)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == timer then
      rednet.broadcast(signieren({
        typ = "status",
        scram = gesperrt,
        grund = scramGrund,
        warnungen = warnungen,
        daten = daten,
        nonce = neueNonce(),
      }), CFG.PROTOKOLL)
      timer = os.startTimer(1)
    elseif ev[1] == "rednet_message" and ev[4] == CFG.PROTOKOLL then
      if type(ev[3]) == "table" and ev[3].befehl then
        befehl(ev[2], ev[3])
      end
    end
  end
end

-- ---------- Start ----------
log("Waechter gestartet")
redstoneNormal()
parallel.waitForAny(ueberwachung, tastatur, funk)
