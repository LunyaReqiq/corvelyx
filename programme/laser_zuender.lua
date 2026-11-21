-- =====================================================
--  CORVELYX // LASER-ZUENDER  v1.2
--  Zuendet einen Mekanism-Fusionsreaktor: gibt dem Laser
--  Amplifier ein Redstone-Signal, bis der zugehoerige
--  Reaktor "gezuendet" meldet, und schaltet es dann ab.
--  "Laser 1" gehoert zu "Fusion 1", "Laser 2" zu "Fusion 2" ...
--
--  Aufbau: Computer + Ender Modem, Laser Amplifier direkt
--  am Computer (das Signal geht an genau diese Seite).
-- =====================================================

local CFG = {
  NETZ        = "Hier-Netzname-Eintragen",
  PASSWORT    = "Hier-Netzpasswort-Eintragen",
  NAME        = "Laser 1",   -- gehoert automatisch zu "Fusion 1"
  FUSION      = nil,         -- nur setzen, wenn der Reaktor anders heisst
  ZUENDEN_AB  = 2e9,         -- FE im Laser, ab denen gezuendet werden darf
  ZEITLIMIT   = 60,          -- Sekunden Signal ohne Zuendung -> abbrechen + Alarm
  PAUSE_AUTO  = 300,         -- Sekunden Pause der Auto-Zuendung nach Fehlschlag
  MODUS       = "HIGH",      -- Redstone-Modus, der am Amplifier eingestellt wird
  SENDEN      = 2,           -- Sekunden zwischen Statusmeldungen
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
-- Sprache (de/en) - wird vom Update-Computer fuers ganze Netz vorgegeben
local EN = {
  ["   Auto-Z\252ndung: "] = "   Auto ignition: ",
  ["  (Seite "] = "  (side ",
  [" gez\252ndet"] = " ignited",
  [" s (Hohlraum leer?)"] = " s (hohlraum empty?)",
  ["AN"] = "ON",
  ["AUS"] = "OFF",
  ["Auto-Z\252ndung"] = "Auto ignition",
  ["FEHLT"] = "MISSING",
  ["Kein Ender Modem gefunden!"] = "No Ender Modem found!",
  ["Kein Hohlraum im Reaktor"] = "No hohlraum in the reactor",
  ["Kein Laser Amplifier am Computer gefunden!"] = "No Laser Amplifier at the computer!",
  ["Keine Z\252ndung nach "] = "No ignition after ",
  ["Ladung: %.2f G / %.2f G FE"] = "Charge: %.2f G / %.2f G FE",
  ["Laser Amplifier muss DIREKT am Computer sitzen (nicht per Kabel)"] = "The Laser Amplifier must touch the computer DIRECTLY (no cable)",
  ["Laser noch nicht voll genug"] = "Laser not charged enough yet",
  ["Reaktor ist schon gez\252ndet"] = "Reactor is already ignited",
  ["Reaktor: "] = "Reactor: ",
  ["Signal AN"] = "Signal ON",
  ["Signal aus"] = "Signal off",
  ["Unbekannter Befehl"] = "Unknown command",
  ["Z\252ndung gestartet"] = "Ignition started",
  ["Zeitlimit"] = "Time limit",
  ["Zugriff verweigert"] = "Access denied",
  ["abgebrochen"] = "cancelled",
  ["gez\252ndet"] = "ignited",
  ["keine Daten"] = "no data",
}
local function L(s) if CFG.SPRACHE == "en" then return EN[s] or s end return s end
CFG.PROTOKOLL   = CFG.NETZ .. "/daten"
CFG.PROT_STEUER = CFG.NETZ .. "/steuer"
if not CFG.FUSION then
  local nr = tostring(CFG.NAME):match("(%d+)%s*$")
  CFG.FUSION = "Fusion " .. (nr or "1")
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

local DATEI = "laser_zustand.txt"

local function signieren(inhalt)
  local s = textutils.serialize(inhalt, { compact = true })
  local t = os.epoch("utc")
  return { v = 2, t = t, s = s, sig = sha256(CFG.PASSWORT .. "|" .. CFG.NETZ .. "|" .. tostring(t) .. "|" .. s) }
end
local letzteZeit = {}
local function auspacken(id, msg)
  if type(msg) ~= "table" or msg.v ~= 2 or type(msg.s) ~= "string"
     or type(msg.t) ~= "number" or type(msg.sig) ~= "string" then return nil end
  if math.abs(os.epoch("utc") - msg.t) > 30000 then return nil end
  if msg.sig ~= sha256(CFG.PASSWORT .. "|" .. CFG.NETZ .. "|" .. tostring(msg.t) .. "|" .. msg.s) then return nil end
  local inhalt = textutils.unserialize(msg.s)
  if type(inhalt) ~= "table" then return nil end
  local key = id .. "/" .. tostring(inhalt.schluessel or inhalt.quelle or inhalt.typ)
  if letzteZeit[key] and msg.t < letzteZeit[key] then return nil end
  letzteZeit[key] = msg.t
  return inhalt
end

-- ---------- Geraete ----------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error(L("Kein Ender Modem gefunden!"), 0) end
rednet.open(peripheral.getName(modem))
local amp = peripheral.find("laserAmplifier")
if not amp then error(L("Kein Laser Amplifier am Computer gefunden!"), 0) end
local SEITE = peripheral.getName(amp)
local SEITEN = { top = true, bottom = true, left = true, right = true, front = true, back = true }
if not SEITEN[SEITE] then error(L("Laser Amplifier muss DIREKT am Computer sitzen (nicht per Kabel)"), 0) end

local function inFE(j)
  if type(j) ~= "number" then return nil end
  if mekanismEnergyHelper and mekanismEnergyHelper.joulesToFE then
    local ok, v = pcall(mekanismEnergyHelper.joulesToFE, j)
    if ok and type(v) == "number" then return v end
  end
  return j / 2.5
end

pcall(amp.setRedstoneMode, CFG.MODUS)

-- ---------- Zustand ----------
local zustand = { auto = false }
if fs.exists(DATEI) then
  local f = fs.open(DATEI, "r")
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) == "table" then zustand = t end
end
local function speichern()
  local f = fs.open(DATEI, "w") f.write(textutils.serialize(zustand)) f.close()
end

local signal, signalSeit = false, nil
local fehler, fehlerBis = nil, 0
local fusion = { gezuendet = nil, hohlraum = nil, zeit = nil }
local log = {}
local function notiz(text)
  table.insert(log, 1, textutils.formatTime(os.time(), true) .. " " .. text)
  if #log > 12 then table.remove(log) end
end

local function setzeSignal(an, grund)
  signal = an
  signalSeit = an and os.clock() or nil
  rs.setOutput(SEITE, an)
  notiz((an and L("Signal AN") or L("Signal aus")) .. (grund and (" - " .. grund) or ""))
end
rs.setOutput(SEITE, false)   -- nach Neustart immer aus

-- Werte des Amplifiers: werden von einem eigenen Leser-Ablauf geholt.
-- (Mekanism-Abfragen warten auf den Spiel-Thread; in der Zeit wuerden
--  sonst Funknachrichten und Timer verloren gehen.)
local cache = { e = nil, m = nil }
local function energie() return cache.e, cache.m end
local function lesen()
  local ok, e = pcall(amp.getEnergy)
  local ok2, m = pcall(amp.getMaxEnergy)
  cache.e = ok and inFE(e) or nil
  cache.m = ok2 and inFE(m) or nil
end
local function ziel()
  local _, m = energie()
  return math.min(CFG.ZUENDEN_AB, m or CFG.ZUENDEN_AB)
end
local function fusionFrisch() return fusion.zeit and (os.clock() - fusion.zeit) < 15 end

-- Darf gezuendet werden? (nil oder Grund)
local function hindernis()
  local e = energie()
  if fusionFrisch() and fusion.gezuendet then return L("Reaktor ist schon gez\252ndet") end
  if fusionFrisch() and fusion.hohlraum == false then return L("Kein Hohlraum im Reaktor") end
  if not e or e < ziel() then return L("Laser noch nicht voll genug") end
  return nil
end

local function zuenden(wer)
  local h = hindernis()
  if h then return false, h end
  fehler = nil
  setzeSignal(true, wer)
  return true, L("Z\252ndung gestartet")
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

local function senden()
  local e = energie()
  rednet.broadcast(signieren({ typ = "status", quelle = "laser", name = CFG.NAME,
    schluessel = os.getComputerID() .. ":" .. CFG.NAME,
    daten = { energie = e, ziel = ziel(), signal = signal, fusion = CFG.FUSION,
      gezuendet = fusionFrisch() and fusion.gezuendet or nil,
      hohlraum = fusionFrisch() and fusion.hohlraum or nil,
      auto = zustand.auto, fehler = fehler, nonce = neueNonce() } }), CFG.PROTOKOLL)
end

-- ---------- Anzeige ----------
local function zeigen()
  local w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  local function z(y, text, f) term.setCursorPos(1, y) term.setTextColor(f or colors.white) term.write(text:sub(1, w)) end
  z(1, "CORVELYX // LASER-Z\220NDER", colors.cyan)
  z(2, CFG.NAME .. " -> " .. CFG.FUSION .. L("  (Seite ") .. SEITE .. ")", colors.lightGray)
  local e = energie()
  z(4, string.format(L("Ladung: %.2f G / %.2f G FE"), (e or 0) / 1e9, ziel() / 1e9), (e or 0) >= ziel() and colors.lime or colors.orange)
  z(5, L("Reaktor: ") .. (not fusionFrisch() and L("keine Daten") or (fusion.gezuendet and L("gez\252ndet") or (L("AUS")):lower())),
    fusion.gezuendet and colors.lime or colors.lightGray)
  if fusionFrisch() and fusion.hohlraum ~= nil then
    z(6, L("Hohlraum: ") .. (fusion.hohlraum and "eingelegt" or L("FEHLT")), fusion.hohlraum and colors.lime or colors.red)
  end
  z(7, L("Signal: ") .. (signal and L("AN") or (L("AUS")):lower()) .. L("   Auto-Z\252ndung: ") .. (zustand.auto and L("AN") or (L("AUS")):lower()),
    signal and colors.orange or colors.white)
  if fehler then z(8, fehler, colors.red) end
  for i, l in ipairs(log) do if 9 + i <= h then z(9 + i, l, colors.gray) end end
end

-- ---------- Hauptschleife ----------
lesen()
zeigen()
senden()

local function leser()
  while true do
    lesen()
    sleep(1)
  end
end

local function haupt()
local takt = os.startTimer(1)
local naechstesSenden = os.clock() + CFG.SENDEN
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == takt then
    takt = os.startTimer(1)
    -- Signal beenden: gezuendet oder Zeitlimit
    if signal then
      if fusionFrisch() and fusion.gezuendet then
        setzeSignal(false, CFG.FUSION .. L(" gez\252ndet"))
      elseif os.clock() - signalSeit > CFG.ZEITLIMIT then
        setzeSignal(false, L("Zeitlimit"))
        fehler = L("Keine Z\252ndung nach ") .. CFG.ZEITLIMIT .. L(" s (Hohlraum leer?)")
        fehlerBis = os.clock() + CFG.PAUSE_AUTO
      end
    elseif zustand.auto and fusionFrisch() and fusion.gezuendet == false and os.clock() > fehlerBis then
      local ok = zuenden(L("Auto-Z\252ndung"))
    end
    rs.setOutput(SEITE, signal)
    if os.clock() >= naechstesSenden then senden() naechstesSenden = os.clock() + CFG.SENDEN end
    zeigen()
  elseif ev[1] == "rednet_message" and ev[4] == CFG.PROTOKOLL then
    local a = auspacken(ev[2], ev[3])
    if a and a.typ == "status" and a.quelle == "fusion" and a.name == CFG.FUSION and type(a.daten) == "table" then
      fusion.gezuendet = a.daten.gezuendet == true
      if fusion.gezuendet then fehler = nil end
      fusion.hohlraum = a.daten.hohlraum
      fusion.zeit = os.clock()
    end
  elseif ev[1] == "rednet_message" and ev[4] == CFG.PROT_STEUER then
    local id, msg = ev[2], ev[3]
    if type(msg) == "table" and type(msg.befehl) == "string" and type(msg.wert) == "string"
       and type(msg.nonce) == "string" and type(msg.sig) == "string" then
      local ok = nonceEinloesen(msg.nonce)
        and msg.sig == sha256(CFG.PASSWORT .. "|" .. msg.befehl .. "|" .. msg.wert .. "|" .. msg.nonce)
      local text
      if not ok then text = L("Zugriff verweigert")
      elseif msg.befehl == "zuenden" then ok, text = zuenden(L("Control Center"))
      elseif msg.befehl == "abbrechen" then setzeSignal(false, L("abgebrochen")) text = L("Signal aus")
      elseif msg.befehl == "auto" then
        zustand.auto = msg.wert == "1" speichern()
        text = "Auto-Z\252ndung " .. (zustand.auto and L("AN") or (L("AUS")):lower())
      else ok, text = false, L("Unbekannter Befehl") end
      rednet.send(id, signieren({ typ = "antwort", ok = ok, text = CFG.NAME .. ": " .. text }), CFG.PROT_STEUER)
      senden()
      zeigen()
    end
  elseif ev[1] == "term_resize" then
    zeigen()
  end
end
end

parallel.waitForAny(leser, haupt)
