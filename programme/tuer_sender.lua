-- =====================================================
--  CORVELYX // TUER-SENDER  v1
--  Betretungslog: Ein Player Detector an der Tuer erkennt,
--  wer hindurchgeht. Spieler, die NICHT im Team sind,
--  werden mit Datum und deutscher Uhrzeit protokolliert
--  und ans Control Center gefunkt.
--
--  Aufbau: Computer + Ender Modem, Player Detector
--  (Advanced Peripherals) direkt am Computer, nahe der Tuer.
-- =====================================================

local CFG = {
  NETZ        = "Hier-Netzname-Eintragen",
  PASSWORT    = "Hier-Netzpasswort-Eintragen",
  NAME        = "Haustuer",   -- Name dieser Tuer
  TEAM        = {},           -- Spieler, die NICHT protokolliert werden, z.B. { "Name1", "Name2" }
  BEREICH     = { 3, 3, 3 },  -- Erkennungsbox um den Detector: Breite, Hoehe, Tiefe (Bloecke)
  REICHWEITE  = 2,            -- Ersatz, falls die Box nicht geht: Radius in Bloecken
  INTERVALL   = 0.5,          -- Sekunden zwischen Abfragen
  WIEDER_NACH = 60,           -- Sekunden: wer so lange weg war, zaehlt beim naechsten Mal neu
  MAX_EINTRAEGE = 300,        -- so viele Eintraege bleiben gespeichert
  SENDEN      = 5,            -- Sekunden zwischen Statusmeldungen
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
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

local DATEI = "betreten.txt"

local function signieren(inhalt)
  local s = textutils.serialize(inhalt, { compact = true })
  local t = os.epoch("utc")
  return { v = 2, t = t, s = s, sig = sha256(CFG.PASSWORT .. "|" .. CFG.NETZ .. "|" .. tostring(t) .. "|" .. s) }
end

-- ---------- Deutsche Zeit (MEZ/MESZ) aus UTC ----------
local function zivil(tage)          -- Tage seit 1970-01-01 -> Jahr, Monat, Tag
  local z = tage + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  return y, m, d
end
local function tageVon(y, m, d)     -- Jahr, Monat, Tag -> Tage seit 1970-01-01
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = m > 2 and m - 3 or m + 9
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
local function letzterSonntag(y, m) -- Tag (seit 1970) des letzten Sonntags im Monat
  local t = tageVon(y, m, 31)
  return t - (t + 4) % 7
end
-- Sekunden UTC -> "21.11.2026", "18:05:12", Tagesnummer (deutsch)
local function deutsch(sek)
  local y = zivil(math.floor(sek / 86400))
  local start = letzterSonntag(y, 3) * 86400 + 3600    -- Sommerzeit ab 01:00 UTC
  local ende  = letzterSonntag(y, 10) * 86400 + 3600   -- Winterzeit ab 01:00 UTC
  local lokal = sek + ((sek >= start and sek < ende) and 7200 or 3600)
  local tag = math.floor(lokal / 86400)
  local yy, mm, dd = zivil(tag)
  local rest = lokal - tag * 86400
  return string.format("%02d.%02d.%04d", dd, mm, yy),
    string.format("%02d:%02d:%02d", math.floor(rest / 3600), math.floor(rest % 3600 / 60), rest % 60), tag
end

-- ---------- Speicher ----------
local eintraege = {}
do
  if fs.exists(DATEI) then
    local f = fs.open(DATEI, "r")
    local t = textutils.unserialize(f.readAll() or "")
    f.close()
    if type(t) == "table" then eintraege = t end
  end
end
local function speichern()
  local f = fs.open(DATEI, "w")
  f.write(textutils.serialize(eintraege, { compact = true }))
  f.close()
end

local team = {}
for _, n in ipairs(type(CFG.TEAM) == "table" and CFG.TEAM or {}) do team[tostring(n):lower()] = true end

-- ---------- Geraete ----------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Kein Ender Modem gefunden!", 0) end
rednet.open(peripheral.getName(modem))
local det = peripheral.find("playerDetector") or peripheral.find("player_detector")
if not det then error("Kein Player Detector gefunden!", 0) end

local function spielerJetzt()
  local b = CFG.BEREICH
  local ok, l = pcall(det.getPlayersInCubic, b[1], b[2], b[3])
  if not ok or type(l) ~= "table" then ok, l = pcall(det.getPlayersInRange, CFG.REICHWEITE) end
  if not ok or type(l) ~= "table" then return nil, tostring(l) end
  local r = {}
  for _, n in ipairs(l) do
    if type(n) == "table" then n = n.name or n.username end
    if type(n) == "string" then r[n] = true end
  end
  return r
end

-- ---------- Funk ----------
local fehler = nil
local function heuteZahl()
  local _, _, heute = deutsch(math.floor(os.epoch("utc") / 1000))
  local n = 0
  for _, e in ipairs(eintraege) do if e.tag == heute then n = n + 1 end end
  return n
end
local function senden()
  local liste = {}
  for i = 1, math.min(60, #eintraege) do liste[i] = eintraege[i] end
  rednet.broadcast(signieren({ typ = "status", quelle = "tuer", name = CFG.NAME,
    schluessel = os.getComputerID() .. ":" .. CFG.NAME,
    daten = { eintraege = liste, heute = heuteZahl(), gesamt = #eintraege, fehler = fehler } }), CFG.PROTOKOLL)
end

-- ---------- Anzeige ----------
local function zeigen()
  local w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  local function z(y, text, f) term.setCursorPos(1, y) term.setTextColor(f or colors.white) term.write(text:sub(1, w)) end
  z(1, "CORVELYX // BETRETUNGSLOG", colors.cyan)
  z(2, CFG.NAME .. "  -  heute: " .. heuteZahl() .. "  gesamt: " .. #eintraege, colors.lightGray)
  if fehler then z(3, "Detector: " .. fehler, colors.red) end
  for i = 1, math.min(#eintraege, h - 4) do
    local e = eintraege[i]
    z(4 + i, e.datum .. " " .. e.uhr .. "  " .. e.spieler, colors.white)
  end
end

-- ---------- Hauptschleife ----------
local drin = {}       -- [name] = true (gerade im Bereich)
local zuletzt = {}    -- [name] = os.clock() zuletzt gesehen
local naechstesSenden = 0
zeigen()
senden()
local takt = os.startTimer(CFG.INTERVALL)
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == takt then
    takt = os.startTimer(CFG.INTERVALL)
    local jetzt = os.clock()
    local spieler, err = spielerJetzt()
    fehler = spieler and nil or err
    local neu = false
    if spieler then
      for n in pairs(spieler) do
        if not drin[n] and not team[n:lower()] and (not zuletzt[n] or jetzt - zuletzt[n] > CFG.WIEDER_NACH) then
          local sek = math.floor(os.epoch("utc") / 1000)
          local datum, uhr, tag = deutsch(sek)
          table.insert(eintraege, 1, { spieler = n, datum = datum, uhr = uhr, tag = tag, zeit = sek, tuer = CFG.NAME })
          while #eintraege > CFG.MAX_EINTRAEGE do table.remove(eintraege) end
          neu = true
        end
        zuletzt[n] = jetzt
      end
      drin = spieler
    end
    if neu then speichern() zeigen() senden() naechstesSenden = jetzt + CFG.SENDEN end
    if jetzt >= naechstesSenden then senden() naechstesSenden = jetzt + CFG.SENDEN end
  elseif ev[1] == "term_resize" then
    zeigen()
  end
end
