-- =====================================================
--  CORVELYX // CONTROL CENTER  v3.6
--
--  Aufbau:
--   - Advanced Computer mit Ender Modem
--   - Hauptmonitor 8x5 (Advanced Monitor)
--   - Menue-Monitor 2x5 daneben (optional)
--   Beide Monitore direkt am Computer oder per
--   Wired Modem + Kabel. Der groessere wird automatisch
--   zum Hauptmonitor.
--
--  Empfaengt:
--   - Reaktor-Waechter (Protokoll "corvelyx_reaktor")
--   - Sender fuer Matrix, Turbine, ME, Wetter, Flux und Lager
-- =====================================================

local CFG = {
  LILA          = 0x9D4EDD,  -- Akzentfarbe (Titel, Knoepfe, Balken)
  -- Funknetz: MUSS auf allen eigenen PCs genau gleich lauten!
  NETZ          = "Hier-Netzname-Eintragen",
  PASSWORT      = "Hier-Netzpasswort-Eintragen",

  HAUPT_SKALA   = 1,      -- Textgroesse Hauptmonitor (0.5 - 5)
  MENU_SKALA    = 1,      -- Textgroesse Menue-Monitor
  ZEITLIMIT     = 5,      -- Sekunden ohne Daten = "keine Verbindung"
  VERGESSEN     = 600,    -- Sekunden ohne Daten = Anlage gilt als abgebaut
                          -- (wird ausgeblendet, Alarm verschwindet)

  -- Alarmgrenzen im Control Center
  STROM_WARN    = 0.10,   -- Matrix unter 10 %
  DAMPF_WARN    = 0.80,   -- Turbine: Dampf staut sich
  ME_WARN       = 0.90,   -- ME-Speicher ueber 90 %
  LAGER_WARN    = 0.95,   -- Drawer ab 95 % = "fast voll"
  LAGER_ZEIT    = 15,     -- Lager-Sender meldet nur alle 5 s

  VERLAUF_TAKT  = 5,      -- Sekunden pro Punkt im Energie-Graph
  LOGDATEI      = "corvelyx.log",
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
CFG.PROT_REAKTOR = CFG.NETZ .. "/reaktor"
CFG.PROT_DATEN   = CFG.NETZ .. "/daten"
CFG.PROT_WETTER  = CFG.NETZ .. "/wetter"
CFG.PROT_XTREME  = CFG.NETZ .. "/xtreme"
CFG.PROT_FUSION  = CFG.NETZ .. "/fusion"
CFG.PROT_STEUER  = CFG.NETZ .. "/steuer"

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

-- ---------- Peripherie ----------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Kein Ender Modem gefunden!") end
rednet.open(peripheral.getName(modem))

local monitore = { peripheral.find("monitor") }
if #monitore == 0 then error("Kein Monitor gefunden!") end
for _, m in ipairs(monitore) do m.setTextScale(1) end
table.sort(monitore, function(a, b)
  local aw, ah = a.getSize()
  local bw, bh = b.getSize()
  return aw * ah > bw * bh
end)

-- ---------- Farben (Corvelyx-Palette) ----------
local function palette(t)
  t.setPaletteColour(colors.black,     0x0B0F14)
  t.setPaletteColour(colors.gray,      0x1A212C)
  t.setPaletteColour(colors.lightGray, 0x8592A6)
  t.setPaletteColour(colors.white,     0xE6EDF3)
  t.setPaletteColour(colors.cyan,      CFG.LILA)   -- Akzentfarbe (Lila)
  t.setPaletteColour(colors.lime,      0x4ADE80)
  t.setPaletteColour(colors.orange,    0xF5A524)
  t.setPaletteColour(colors.red,       0xEF4444)
  t.setPaletteColour(colors.green,     0x15803D)
  t.setPaletteColour(colors.brown,     0x7F1D1D)
end

-- Jeder Monitor bekommt einen unsichtbaren Puffer (kein Flackern)
local function puffer(mon, skala)
  mon.setTextScale(skala)
  local w, h = mon.getSize()
  local win = window.create(mon, 1, 1, w, h, false)
  palette(win)
  return { mon = mon, win = win, w = w, h = h, name = peripheral.getName(mon), skala = skala }
end

local HAUPT = puffer(monitore[1], CFG.HAUPT_SKALA)
local MENU  = monitore[2] and puffer(monitore[2], CFG.MENU_SKALA) or nil

-- ---------- Zustand ----------
local quellen = {
  reaktor = {}, me = {}, wetter = {}, update = {},
}
local turbinen = {}   -- beliebig viele, Schluessel = Sender-PC + Valve
local fluxSender = {} -- [schluessel] = { ort, plugs, zeit }
local fluxSeite, fluxSort = 1, "leistung"
local lagerSender = {} -- [schluessel] = { ort, faecher, slots, zeit }
local tueren = {}      -- [schluessel] = { name, daten, zeit, id } (Betretungslog)
local tuerGesehen = {} -- bereits gemeldete Eintraege
local mobfarmen = {}   -- [schluessel] = { name, daten, zeit, id }
local laser = {}       -- [schluessel] = { name, daten, zeit, id } (Laser-Zuender)
local laserFrage = nil -- Sicherheitsabfrage "Zuenden"
local tuerLeeren = nil -- Sicherheitsabfrage "Log leeren" (Ablaufzeit)
local lagerSeite, lagerSort = 1, "fuell"
local xtreme = {}     -- Extreme Reactors: [schluessel] = { name, daten, zeit, id }
local xtremeAuswahl = 1
local fusion = {}     -- Mekanism-Fusion: [schluessel] = { name, daten, zeit, id }
local fusionAuswahl = 1
local fusionStopp = nil   -- Bestaetigung fuer STOPP: { key, bis }
local seite        = "uebersicht"
local logListe     = {}
local verlauf      = {}   -- Gesamt-Fuellstand aller Matrizen
local matrizen     = {}   -- [schluessel] = { name, daten, zeit, id, verlauf }
local energieAuswahl = 0  -- 0 = GESAMT, sonst Nummer der Matrix
local letzterPunkt = -1000
local alarme       = {}
local alteAlarme   = {}
local knoepfe      = {}
local bestaetigung = nil   -- { aktion, bis }
local rueckmeldung = nil   -- { text, farbe, bis }
local blink        = false
local startZeit    = os.clock()

local SEITEN = {
  { id = "uebersicht", name = "UEBERSICHT", kurz = "HOME" },
  { id = "energie",    name = "MATRIX", kurz = "MATRIX" },
  { id = "reaktor",    name = "FISSION", kurz = "FISS." },
  { id = "xtreme",     name = "XTREME" },
  { id = "fusion",     name = "FUSION" },
  { id = "turbine",    name = "TURBINE", kurz = "TURB." },
  { id = "me",         name = "ME-SYSTEM", kurz = "ME" },
  { id = "wetter",     name = "WETTER" },
  { id = "flux",       name = "FLUX" },
  { id = "lager",      name = "LAGER" },
  { id = "mobfarm",    name = "MOBFARM", kurz = "MOBS" },
  { id = "besucher",   name = "BESUCHER", kurz = "T\220R" },
  { id = "log",        name = "LOG" },
}

-- ---------- Hilfsfunktionen ----------
local function kurz(n, einheit)
  if type(n) ~= "number" then return "--" end
  local a, s = math.abs(n), nil
  if a >= 1e15 then s = string.format("%.2fP", n / 1e15)
  elseif a >= 1e12 then s = string.format("%.2fT", n / 1e12)
  elseif a >= 1e9 then s = string.format("%.2fG", n / 1e9)
  elseif a >= 1e6 then s = string.format("%.2fM", n / 1e6)
  elseif a >= 1e3 then s = string.format("%.1fk", n / 1e3)
  else s = string.format("%.0f", n) end
  return s .. (einheit or "")
end

local function pz(a)
  if type(a) ~= "number" then return "--%" end
  return string.format("%.1f%%", a * 100)
end

local function dauer(s)
  if type(s) ~= "number" or s ~= s or s == math.huge or s < 0 then return "--" end
  if s >= 86400 then return string.format("%.1f Tage", s / 86400) end
  if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), math.floor(s % 60)) end
  return string.format("%ds", math.floor(s))
end

local function quote(a, b)
  if type(a) ~= "number" or type(b) ~= "number" or b <= 0 then return nil end
  return a / b
end

local function frisch(q)
  local z = quellen[q].zeit
  return z ~= nil and (os.clock() - z) < CFG.ZEITLIMIT
end

local function log(text, farbe)
  local zeit = textutils.formatTime(os.time(), true)
  table.insert(logListe, 1, { zeit = zeit, text = text, farbe = farbe or colors.white })
  if #logListe > 200 then table.remove(logListe) end
  local f = fs.open(CFG.LOGDATEI, "a")
  if f then f.writeLine("[Tag " .. os.day() .. " " .. zeit .. "] " .. text) f.close() end
end

local function melden(text, farbe)
  rueckmeldung = { text = text, farbe = farbe or colors.white, bis = os.clock() + 8 }
end

-- ---------- Zeichnen: Grundbausteine ----------
local function fuell(t, x, y, w, h, farbe)
  if w <= 0 or h <= 0 then return end
  t.win.setBackgroundColor(farbe)
  local leer = string.rep(" ", w)
  for i = 0, h - 1 do
    t.win.setCursorPos(x, y + i)
    t.win.write(leer)
  end
end

local function schreib(t, x, y, s, fg, bg, maxB)
  s = tostring(s)
  if maxB and #s > maxB then s = s:sub(1, math.max(0, maxB)) end
  t.win.setBackgroundColor(bg or colors.black)
  t.win.setTextColor(fg or colors.white)
  t.win.setCursorPos(x, y)
  t.win.write(s)
end

local function rechts(t, xEnde, y, s, fg, bg)
  s = tostring(s)
  schreib(t, xEnde - #s + 1, y, s, fg, bg)
end

-- ---------- Abgerundete Formen (Pixelzeichen, 2x3 Punkte pro Zelle) ----------
local HEX = "0123456789abcdef"
local function zuBlit(c)
  local n = 0
  while c > 1 do c = c / 2 n = n + 1 end
  return HEX:sub(n + 1, n + 1)
end
-- Hintergrundfarbe, die gerade an (x, y) steht
local function hinter(t, x, y)
  if not t.win.getLine then return colors.black end
  local ok, _, _, bg = pcall(t.win.getLine, y)
  if not ok or type(bg) ~= "string" then return colors.black end
  local n = HEX:find(bg:sub(x, x), 1, true)
  return n and 2 ^ (n - 1) or colors.black
end
-- Ein Pixelzeichen: p = { oben-l, oben-r, mitte-l, mitte-r, unten-l, unten-r }
-- true = Farbe a, false = Farbe b
local function pix(t, x, y, p, a, b)
  local n, fg, bg = 0, a, b
  if p[6] then
    fg, bg = b, a
    for i = 1, 5 do if not p[i] then n = n + 2 ^ (i - 1) end end
  else
    for i = 1, 5 do if p[i] then n = n + 2 ^ (i - 1) end end
  end
  t.win.setCursorPos(x, y)
  t.win.blit(string.char(128 + n), zuBlit(fg), zuBlit(bg))
end
local ECKE = {
  ol = { false, true, true, true, true, true }, orr = { true, false, true, true, true, true },
  ul = { true, true, true, true, false, true }, ur = { true, true, true, true, true, false },
}
local function ecken(t, x, y, w, h, farbe, aussen)
  if w < 2 or aussen == farbe then return end
  if h == 1 then return end   -- einzeilig: eckig lassen (sonst "Nasen")
  pix(t, x, y, ECKE.ol, farbe, aussen)
  pix(t, x + w - 1, y, ECKE.orr, farbe, aussen)
  pix(t, x, y + h - 1, ECKE.ul, farbe, aussen)
  pix(t, x + w - 1, y + h - 1, ECKE.ur, farbe, aussen)
end

-- Schlanker Balken (2/3 Zellenhoehe), optional mehrere Zeilen dick
local function balken(t, x, y, w, anteil, farbe, hoehe)
  if w <= 0 then return end
  hoehe = hoehe or 1
  local aussen = hinter(t, x, y)
  anteil = math.max(0, math.min(1, anteil or 0))
  local voll = math.floor(w * anteil + 0.5)
  if anteil > 0 and voll == 0 then voll = 1 end
  for i = 0, w - 1 do
    local f = (i < voll) and farbe or colors.black
    -- oben Hintergrund, Mitte + unten Balken
    pix(t, x + i, y, { false, false, true, true, true, true }, f, aussen)
  end
  if hoehe > 1 then fuell(t, x, y + 1, voll, hoehe - 1, farbe) fuell(t, x + voll, y + 1, w - voll, hoehe - 1, colors.black) end
end

-- Panel: abgerundete Karte mit schmaler Akzentleiste und Titel
local function panel(t, x, y, w, h, titel, akzent)
  akzent = akzent or colors.cyan
  local aussen = hinter(t, x, y)
  fuell(t, x, y, w, h, colors.gray)
  ecken(t, x, y, w, h, colors.gray, aussen)
  for i = 1, h - 2 do pix(t, x, y + i, { true, false, true, false, true, false }, akzent, colors.gray) end
  if titel then schreib(t, x + 2, y, titel, akzent, colors.gray, w - 3) end
end

-- Knopf: abgerundet (Pille)
local function knopf(t, x, y, w, h, text, bg, fg, aktion)
  local aussen = hinter(t, x, y)
  fuell(t, x, y, w, h, bg)
  if w >= 4 then ecken(t, x, y, w, h, bg, aussen) end
  local tx = x + math.max(0, math.floor((w - #text) / 2))
  local ty = y + math.floor((h - 1) / 2)
  schreib(t, tx, ty, text, fg or colors.white, bg, w)
  knoepfe[#knoepfe + 1] = { name = t.name, x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1, aktion = aktion }
end

-- Zeile "Name ......... Wert" in einem Panel
local function wertZeile(t, x, y, w, name, wert, farbe)
  schreib(t, x, y, name, colors.lightGray, colors.gray)
  rechts(t, x + w - 1, y, wert, farbe or colors.white, colors.gray)
end

local function farbeFuer(anteil, gelb, rot, umgekehrt)
  if type(anteil) ~= "number" then return colors.lightGray end
  if umgekehrt then
    if anteil <= rot then return colors.red end
    if anteil <= gelb then return colors.orange end
  else
    if anteil >= rot then return colors.red end
    if anteil >= gelb then return colors.orange end
  end
  return colors.lime
end

-- ---------- Daten der Quellen ----------
local function reaktorInfo()
  local q = quellen.reaktor
  if not frisch("reaktor") then return nil, "KEINE DATEN", colors.lightGray end
  local st = q.daten
  local d = st.daten
  if st.scram then return st, "SCRAM", colors.red end
  if not d then return st, "KEINE WERTE", colors.orange end
  if d.aktiv and (d.burnIst or 0) <= 0 then return st, "AN - STEHT", colors.orange end
  if d.aktiv then return st, "LAEUFT", colors.lime end
  return st, "AUS", colors.lightGray
end

-- Alle Matrizen, natuerlich sortiert ("Matrix 2" vor "Matrix 10")
local function natKey(x) return (tostring(x):lower():gsub("%d+", function(d) return string.rep("0", 10 - #d) .. d end)) end
local function matrixListe()
  local l = {}
  for key, m in pairs(matrizen) do
    m.key = key
    m.frisch = (os.clock() - m.zeit) < CFG.ZEITLIMIT
    l[#l + 1] = m
  end
  table.sort(l, function(a, b) return natKey(a.name) < natKey(b.name) end)
  return l
end

-- Summe ueber alle Matrizen mit aktuellen Daten (nil = keine)
local function matrixDaten()
  local s = { energie = 0, max = 0, rein = 0, raus = 0, limit = 0, anzahl = 0, gesamt = 0 }
  for _, m in ipairs(matrixListe()) do
    s.gesamt = s.gesamt + 1
    local d = m.daten
    if m.frisch and not d.fehler and type(d.energie) == "number" then
      s.anzahl = s.anzahl + 1
      s.energie = s.energie + d.energie
      s.max = s.max + (d.max or 0)
      s.rein = s.rein + (d.rein or 0)
      s.raus = s.raus + (d.raus or 0)
      s.limit = s.limit + (d.limit or 0)
    end
  end
  if s.anzahl == 0 then return nil, s end
  s.anteil = s.max > 0 and s.energie / s.max or 0
  return s, s
end
-- Alle bekannten Turbinen, nach Namen sortiert
local function turbinenListe()
  local liste = {}
  for _, e in pairs(turbinen) do
    e.frisch = (os.clock() - e.zeit) < CFG.ZEITLIMIT
    liste[#liste + 1] = e
  end
  table.sort(liste, function(a, b) return a.name < b.name end)
  return liste
end

-- Summe ueber alle Turbinen mit aktuellen Daten
local function turbineDaten()
  local sum = { produktion = 0, maxProd = 0, dampf = 0, puffer = 0, anzahl = 0, gesamt = 0 }
  for _, e in ipairs(turbinenListe()) do
    sum.gesamt = sum.gesamt + 1
    local d = e.daten
    if e.frisch and not d.fehler then
      sum.anzahl = sum.anzahl + 1
      sum.produktion = sum.produktion + (d.produktion or 0)
      sum.maxProd = sum.maxProd + (d.maxProd or 0)
      sum.dampf = math.max(sum.dampf, d.dampf or 0)
      sum.puffer = math.max(sum.puffer, d.puffer or 0)
    end
  end
  if sum.anzahl == 0 then return nil, sum end
  return sum, sum
end
local function wetterDaten()
  if not frisch("wetter") or quellen.wetter.daten.fehler then return nil end
  return quellen.wetter.daten
end
local function wetterText(w)
  if not w then return "--", colors.lightGray end
  if w.gewitter then return "GEWITTER", colors.red end
  if w.regen then return "REGEN", colors.cyan end
  return "KLAR", colors.lime
end
local function meDaten()
  if not frisch("me") or quellen.me.daten.fehler then return nil end
  return quellen.me.daten
end

-- ---------- Abgebaute Anlagen vergessen ----------
-- Was VERGESSEN Sekunden lang nichts sendet, gilt als abgebaut.
local NAMEN_QUELLEN = { reaktor = "Fission-Waechter", me = "ME-System", wetter = "Wetter-PC", update = "Update-Computer" }
local function aufraeumen()
  local jetzt = os.clock()
  for q, e in pairs(quellen) do
    if e.zeit and jetzt - e.zeit > CFG.VERGESSEN then
      quellen[q] = {}
      log((NAMEN_QUELLEN[q] or q) .. " entfernt (keine Daten mehr)", colors.lightGray)
    end
  end
  local function tabelle(t, art)
    for key, e in pairs(t) do
      if e.zeit and jetzt - e.zeit > CFG.VERGESSEN then
        t[key] = nil
        log(tostring(e.name or e.ort or art) .. " entfernt (keine Daten mehr)", colors.lightGray)
      end
    end
  end
  tabelle(turbinen, "Turbine")
  tabelle(matrizen, "Matrix")
  tabelle(fluxSender, "Flux-Sender")
  tabelle(lagerSender, "Lager")
  tabelle(tueren, "T\252r")
  tabelle(mobfarmen, "Mobfarm")
  tabelle(laser, "Laser")
  tabelle(xtreme, "Xtreme")
  tabelle(fusion, "Fusion")
end

-- Welche Seiten gibt es gerade? (nur Anlagen, die gesendet haben)
local function vorhanden(id)
  if id == "uebersicht" or id == "log" then return true end
  if id == "reaktor" then return quellen.reaktor.zeit ~= nil end
  if id == "energie" then return next(matrizen) ~= nil end
  if id == "me" then return quellen.me.zeit ~= nil end
  if id == "wetter" then return quellen.wetter.zeit ~= nil end
  if id == "turbine" then return next(turbinen) ~= nil end
  if id == "flux" then return next(fluxSender) ~= nil end
  if id == "lager" then
    -- nur anzeigen, wenn wirklich Drawer angeschlossen sind
    for _, e in pairs(lagerSender) do
      if type(e.faecher) == "table" and #e.faecher > 0 then return true end
    end
    return false
  end
  if id == "besucher" then return next(tueren) ~= nil end
  if id == "mobfarm" then return next(mobfarmen) ~= nil end
  if id == "xtreme" then return next(xtreme) ~= nil end
  if id == "fusion" then return next(fusion) ~= nil end
  return true
end

local function sichtbareSeiten()
  local l = {}
  for _, s in ipairs(SEITEN) do if vorhanden(s.id) then l[#l + 1] = s end end
  return l
end

-- ---------- Alarme ----------
local function alarmeBerechnen()
  local liste = {}
  local function add(id, text, stufe) liste[#liste + 1] = { id = id, text = text, stufe = stufe } end

  -- Reaktor
  if frisch("reaktor") then
    local st = quellen.reaktor.daten
    if st.scram then add("r_scram", "FISSION SCRAM: " .. tostring(st.grund), 2) end
    for _, w in ipairs(st.warnungen or {}) do
      local id = "r_w_" .. tostring(w):gsub("[%d%.%%%s]", "")
      add(id, "Fission: " .. tostring(w), 1)
    end
  elseif quellen.reaktor.zeit then
    add("r_verb", "Fission-Waechter: keine Verbindung", 2)
  end

  -- Matrix
  for key, l in pairs(laser) do
    if l.daten.fehler and (os.clock() - l.zeit) < 15 then add("laser_" .. key, l.name .. ": " .. tostring(l.daten.fehler), 1) end
  end
  local up = quellen.update
  if up.zeit and (os.clock() - quellen.update.zeit < 30) and up.daten.fehler then
    add("upd_err", "Update-Computer: " .. tostring(up.daten.fehler), 1)
  end
  local m = matrixDaten()
  if m then
    if type(m.anteil) == "number" and m.anteil < CFG.STROM_WARN then
      add("m_low", "Strom niedrig (alle Matrizen): " .. pz(m.anteil), 2)
    end
  end
  for _, mx in ipairs(matrixListe()) do
    if not mx.frisch then
      add("m_verb_" .. mx.key, mx.name .. ": keine Daten", 1)
    elseif mx.daten.fehler then
      add("m_err_" .. mx.key, mx.name .. ": " .. tostring(mx.daten.fehler), 1)
    end
  end

  -- Turbinen (jede einzeln)
  local tl = turbinenListe()
  if #tl > 0 then
    for _, e in ipairs(tl) do
      local d = e.daten
      if not e.frisch then
        add("t_verb_" .. e.schluessel, e.name .. ": keine Daten", 1)
      elseif d.fehler then
        add("t_err_" .. e.schluessel, e.name .. ": " .. tostring(d.fehler), 1)
      elseif type(d.dampf) == "number" and d.dampf >= CFG.DAMPF_WARN then
        add("t_dampf_" .. e.schluessel, e.name .. ": Dampfstau " .. pz(d.dampf), 1)
      end
    end
  end

  -- Wetter (nur melden, wenn der Wetter-PC schon einmal da war)
  if quellen.wetter.zeit and not frisch("wetter") then
    add("w_verb", "Wetter-PC: keine Daten", 1)
  end

  -- Extreme Reactors
  for key, x in pairs(xtreme) do
    local d = x.daten
    if (os.clock() - x.zeit) >= CFG.ZEITLIMIT then
      add("x_verb_" .. key, x.name .. ": keine Daten", 1)
    elseif d.fehler then
      add("x_err_" .. key, x.name .. ": " .. tostring(d.fehler), 1)
    elseif type(d.brenn) == "number" and (d.brennMax or 0) > 0 and d.brenn / d.brennMax < (x.brennWarn or 0.1) then
      add("x_brenn_" .. key, x.name .. ": Brennstoff niedrig " .. pz(d.brenn / d.brennMax), 1)
    end
  end

  -- Mekanism-Fusion
  for key, x in pairs(fusion) do
    local d = x.daten
    if (os.clock() - x.zeit) >= CFG.ZEITLIMIT then
      add("f_verb_" .. key, x.name .. ": keine Daten", 1)
    elseif d.fehler then
      add("f_err_" .. key, x.name .. ": " .. tostring(d.fehler), 1)
    else
      if d.gezuendet then x.warGezuendet = true end
      if x.warGezuendet and d.gezuendet == false then
        add("f_aus_" .. key, x.name .. ": Fusion erloschen", 2)
      end
      if type(d.dt) == "number" and (d.dtMax or 0) > 0 and d.dt / d.dtMax < (x.brennWarn or 0.1) then
        add("f_brenn_" .. key, x.name .. ": D-T-Brennstoff niedrig " .. pz(d.dt / d.dtMax), 1)
      end
    end
  end

  -- Lager (Functional Storage)
  for key, ls in pairs(lagerSender) do
    if (os.clock() - ls.zeit) >= CFG.LAGER_ZEIT then
      add("l_verb_" .. key, tostring(ls.ort) .. ": keine Daten", 1)
    else
      local voll = 0
      for _, f in ipairs(ls.faecher) do
        if (f.limit or 0) > 0 and f.menge / f.limit >= CFG.LAGER_WARN then voll = voll + 1 end
      end
      if voll > 0 then add("l_voll_" .. key, tostring(ls.ort) .. ": " .. voll .. " Drawer fast voll", 1) end
    end
  end

  -- ME
  local me = meDaten()
  if me then
    local qi = quote(me.itemsBenutzt, me.itemsGesamt)
    if qi and qi >= CFG.ME_WARN then add("me_items", "ME-Items fast voll: " .. pz(qi), 1) end
    local qf = quote(me.fluidBenutzt, me.fluidGesamt)
    if qf and qf >= CFG.ME_WARN then add("me_fluid", "ME-Fluids fast voll: " .. pz(qf), 1) end
    local qc = quote(me.chemBenutzt, me.chemGesamt)
    if qc and qc >= CFG.ME_WARN then add("me_chem", "ME-Chemicals fast voll: " .. pz(qc), 1) end
  elseif quellen.me.zeit then
    add("me_verb", "ME-System: keine Daten", 1)
  end

  -- Aenderungen ins Log
  local neu = {}
  for _, a in ipairs(liste) do
    neu[a.id] = a.text
    if not alteAlarme[a.id] then
      log("ALARM: " .. a.text, a.stufe == 2 and colors.red or colors.orange)
    end
  end
  for id, text in pairs(alteAlarme) do
    if not neu[id] then log("Behoben: " .. text, colors.lime) end
  end
  alteAlarme = neu
  table.sort(liste, function(a, b) return a.stufe > b.stufe end)
  alarme = liste
end

-- ---------- Reaktor-Befehle ----------
-- Jede Einmal-Nummer (Nonce) gilt nur fuer einen Befehl. Kommt ein
-- zweiter Befehl, bevor die naechste Statusmeldung da ist, wartet er
-- kurz und wird dann automatisch gesendet.
local ausstehend = {}

local function reaktorBefehl(befehl)
  local q = quellen.reaktor
  if not frisch("reaktor") then melden("Kein Kontakt zum Waechter", colors.red) return end
  local nonce = q.daten.nonce
  if nonce == false then
    ausstehend.reaktor = function() reaktorBefehl(befehl) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then
    melden("Waechter braucht Update (v1.2)", colors.red)
    return
  end
  local sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. nonce)
  rednet.send(q.id, { befehl = befehl, nonce = nonce, sig = sig }, CFG.PROT_REAKTOR)
  q.daten.nonce = false
  log("Befehl an Reaktor: " .. befehl:upper(), colors.cyan)
  melden("Gesendet: " .. befehl:upper() .. " ...", colors.lightGray)
end

local function xtremeBefehl(key, befehl, wert)
  local x = xtreme[key]
  if not x or (os.clock() - x.zeit) >= CFG.ZEITLIMIT then melden("Kein Kontakt zum Reaktor", colors.red) return end
  local nonce = x.daten.nonce
  if nonce == false then
    ausstehend["x:" .. key] = function() xtremeBefehl(key, befehl, wert) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then melden("Reaktor-PC braucht Update", colors.red) return end
  wert = tostring(wert or "")
  local sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. wert .. "|" .. nonce)
  rednet.send(x.id, { befehl = befehl, wert = wert, nonce = nonce, sig = sig }, CFG.PROT_XTREME)
  x.daten.nonce = false
  log("Befehl an " .. x.name .. ": " .. befehl:upper() .. (wert ~= "" and (" " .. wert) or ""), colors.cyan)
  melden("Gesendet ...", colors.lightGray)
end

local function fusionBefehl(key, befehl, wert)
  local x = fusion[key]
  if not x or (os.clock() - x.zeit) >= CFG.ZEITLIMIT then melden("Kein Kontakt zum Reaktor", colors.red) return end
  local nonce = x.daten.nonce
  if nonce == false then
    ausstehend["f:" .. key] = function() fusionBefehl(key, befehl, wert) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then melden("Fusion-PC braucht Update", colors.red) return end
  wert = tostring(wert or "")
  local sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. wert .. "|" .. nonce)
  rednet.send(x.id, { befehl = befehl, wert = wert, nonce = nonce, sig = sig }, CFG.PROT_FUSION)
  x.daten.nonce = false
  log("Befehl an " .. x.name .. ": " .. befehl:upper() .. (wert ~= "" and (" " .. wert) or ""), colors.cyan)
  melden("Gesendet ...", colors.lightGray)
end

-- Allgemeine Steuerbefehle (Tuer, Mobfarm ...) ueber NETZ/steuer
local function steuerBefehl(liste, key, befehl, wert)
  local x = liste[key]
  if not x or (os.clock() - x.zeit) >= 15 then melden("Kein Kontakt zu " .. (x and x.name or "Computer"), colors.red) return end
  local nonce = x.daten.nonce
  if nonce == false then
    ausstehend["s:" .. key] = function() steuerBefehl(liste, key, befehl, wert) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then melden(x.name .. " braucht ein Update", colors.red) return end
  wert = tostring(wert or "")
  local sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. wert .. "|" .. nonce)
  rednet.send(x.id, { befehl = befehl, wert = wert, nonce = nonce, sig = sig }, CFG.PROT_STEUER)
  x.daten.nonce = false
  log("Befehl an " .. x.name .. ": " .. befehl:upper(), colors.cyan)
  melden("Gesendet ...", colors.lightGray)
end

-- ---------- Seiten ----------
local ZEICHNE = {}

local function kachel(t, x, y, w, h, titel, status, sFarbe, anteil, bFarbe, z1, z2, ziel)
  panel(t, x, y, w, h, titel, sFarbe)
  if h >= 9 then
    -- grosszuegig (z.B. 8x5-Monitor)
    schreib(t, x + 2, y + 2, status, sFarbe, colors.gray, w - 3)
    balken(t, x + 2, y + 4, w - 4, anteil, bFarbe or sFarbe)
    if z1 then schreib(t, x + 2, y + 6, z1, colors.lightGray, colors.gray, w - 3) end
    if z2 then schreib(t, x + 2, y + 7, z2, colors.lightGray, colors.gray, w - 3) end
  else
    -- kompakt (z.B. 8x4-Monitor): alles enger zusammen
    schreib(t, x + 2, y + 1, status, sFarbe, colors.gray, w - 3)
    if h >= 4 then balken(t, x + 2, y + 2, w - 4, anteil, bFarbe or sFarbe) end
    if z1 and h >= 5 then schreib(t, x + 2, y + 3, z1, colors.lightGray, colors.gray, w - 3) end
    if z2 and h >= 6 then schreib(t, x + 2, y + 4, z2, colors.lightGray, colors.gray, w - 3) end
  end
  knoepfe[#knoepfe + 1] = { name = t.name, x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1,
    aktion = function() seite = ziel end }
end

function ZEICHNE.uebersicht(t, x0, y0, W, H)
  -- Kacheln nur fuer Anlagen, die Daten senden (oder gesendet haben)
  local kacheln = {}

  if vorhanden("reaktor") then
    local st, rText, rFarbe = reaktorInfo()
    local d = st and st.daten
    kacheln[#kacheln + 1] = { "FISSION", rText, rFarbe, d and d.temp and d.temp / 1200, rFarbe,
      d and string.format("Temp: %.0f K", d.temp or 0),
      d and string.format("Burn: %.1f mB/t", d.burnIst or 0), "reaktor" }
  end

  if vorhanden("energie") then
    local m, ms = matrixDaten()
    local eTitel = ms.gesamt > 1 and ("MATRIX (" .. ms.anzahl .. "/" .. ms.gesamt .. ")") or "MATRIX"
    kacheln[#kacheln + 1] = { eTitel, m and ((ms.gesamt > 1 and "Gesamt " or "Matrix ") .. pz(m.anteil)) or "KEINE DATEN",
      m and farbeFuer(m.anteil, 0.25, CFG.STROM_WARN, true) or colors.lightGray, m and m.anteil, nil,
      m and ("Rein: " .. kurz(m.rein, " FE/t")), m and ("Raus: " .. kurz(m.raus, " FE/t")), "energie" }
  end

  if vorhanden("turbine") then
    local tu, tsum = turbineDaten()
    local tq = tu and quote(tu.produktion, tu.maxProd)
    local tFarbe = not tu and colors.lightGray
      or (tu.dampf >= CFG.DAMPF_WARN and colors.orange)
      or (tu.produktion > 0 and colors.lime) or colors.lightGray
    local tTitel = tsum.gesamt > 1 and ("TURBINEN (" .. tsum.anzahl .. "/" .. tsum.gesamt .. ")") or "TURBINE"
    kacheln[#kacheln + 1] = { tTitel, tu and (((tu.produktion or 0) > 0) and "PRODUZIERT" or "STILL") or "KEINE DATEN",
      tFarbe, tq, nil, tu and ("Leistung: " .. kurz(tu.produktion, " FE/t")),
      tu and ("Dampf max: " .. pz(tu.dampf)), "turbine" }
  end

  if vorhanden("me") then
    local me = meDaten()
    local qi = me and quote(me.itemsBenutzt, me.itemsGesamt)
    kacheln[#kacheln + 1] = { "ME-SYSTEM", me and ("Items " .. pz(qi)) or "KEINE DATEN",
      me and farbeFuer(qi, 0.75, CFG.ME_WARN) or colors.lightGray, qi, nil,
      me and ("Bytes: " .. kurz(me.itemsBenutzt) .. " / " .. kurz(me.itemsGesamt)),
      me and ("Fluids: " .. pz(quote(me.fluidBenutzt, me.fluidGesamt))
        .. "   Chem: " .. pz(quote(me.chemBenutzt, me.chemGesamt))), "me" }
  end

  if vorhanden("xtreme") then
    local an, alle, prod, minBrenn = 0, 0, 0, nil
    for _, x in pairs(xtreme) do
      alle = alle + 1
      local d = x.daten
      if (os.clock() - x.zeit) < CFG.ZEITLIMIT and not d.fehler then
        if d.aktiv then an = an + 1 end
        prod = prod + (d.prod or 0)
        local q = quote(d.brenn, d.brennMax)
        if q and (not minBrenn or q < minBrenn) then minBrenn = q end
      end
    end
    kacheln[#kacheln + 1] = { "XTREME (" .. an .. "/" .. alle .. ")", an > 0 and (an .. " LAUFEN") or "AUS",
      an > 0 and colors.lime or colors.lightGray, minBrenn, nil,
      "Leistung: " .. kurz(prod, " FE/t"), "Brennstoff min: " .. pz(minBrenn), "xtreme" }
  end

  if vorhanden("fusion") then
    local an, alle, prod, minDT = 0, 0, 0, nil
    for _, x in pairs(fusion) do
      alle = alle + 1
      local d = x.daten
      if (os.clock() - x.zeit) < CFG.ZEITLIMIT and not d.fehler then
        if d.gezuendet then an = an + 1 end
        prod = prod + (d.prod or 0)
        local q = quote(d.dt, d.dtMax)
        if q and (not minDT or q < minDT) then minDT = q end
      end
    end
    kacheln[#kacheln + 1] = { "FUSION (" .. an .. "/" .. alle .. ")", an > 0 and (an .. " GEZ\220NDET") or "NICHT GEZ\220NDET",
      an > 0 and colors.lime or colors.orange, minDT, nil,
      "Leistung: " .. kurz(prod, " FE/t"), "D-T min: " .. pz(minDT), "fusion" }
  end

  -- Raster: 1 Kachel = volle Breite, bis 4 = 2 Spalten, mehr = 3 Spalten
  local n = #kacheln
  local alarmH = math.max(4, math.min(9, math.floor(H / 3)))
  local flaecheH = 0
  if n > 0 then
    local spalten = (n == 1) and 1 or ((n <= 4) and 2 or 3)
    local zeilen = math.ceil(n / spalten)
    flaecheH = H - alarmH - 1
    local kH = math.floor(flaecheH / zeilen)
    local kW = math.floor((W - (spalten - 1)) / spalten)
    for i, k in ipairs(kacheln) do
      local sp = (i - 1) % spalten
      local zl = math.floor((i - 1) / spalten)
      local x = x0 + sp * (kW + 1)
      local w = (sp == spalten - 1) and (x0 + W - x) or kW
      kachel(t, x, y0 + zl * kH, w, kH - 1, k[1], k[2], k[3], k[4], k[5], k[6], k[7], k[8])
    end
    flaecheH = kH * zeilen
  end

  -- Alarme
  local ay = y0 + flaecheH
  local aH = H - flaecheH
  local akzent = #alarme > 0 and (alarme[1].stufe == 2 and colors.red or colors.orange) or colors.lime
  panel(t, x0, ay, W, aH, "AKTIVE ALARME (" .. #alarme .. ")", akzent)
  if n == 0 then
    schreib(t, x0 + 2, ay + 2, "Noch keine Anlagen gemeldet - Sender gestartet?", colors.lightGray, colors.gray, W - 3)
  elseif #alarme == 0 then
    schreib(t, x0 + 2, ay + 2, "Alles in Ordnung.", colors.lime, colors.gray)
  else
    for i = 1, math.min(#alarme, aH - 2) do
      local a = alarme[i]
      schreib(t, x0 + 2, ay + 1 + i, (a.stufe == 2 and "! " or "- ") .. a.text,
        a.stufe == 2 and colors.red or colors.orange, colors.gray, W - 3)
    end
  end
end

-- Verlaufsgraph (Fuellstand)
local function verlaufZeichnen(t, x0, y0, W, H, werte, titel)
  if H < 5 then return end
  local minuten = math.floor((W - 4) * CFG.VERLAUF_TAKT / 60)
  panel(t, x0, y0, W, H, titel .. " (" .. minuten .. " MIN)", colors.cyan)
  local bx, by, bw, bh = x0 + 2, y0 + 2, W - 4, H - 3
  fuell(t, bx, by, bw, bh, colors.black)
  local start = math.max(1, #werte - bw + 1)
  local spalte = bw - (#werte - start)
  for i = start, #werte do
    local v = werte[i]
    local hoehe = math.floor(v * bh + 0.5)
    if v > 0 and hoehe == 0 then hoehe = 1 end
    fuell(t, bx + spalte - 1, by + bh - hoehe, 1, hoehe, farbeFuer(v, 0.25, CFG.STROM_WARN, true))
    spalte = spalte + 1
  end
  if #werte == 0 then schreib(t, bx + 1, by, "Sammle Daten ...", colors.lightGray, colors.black) end
end

-- Kopf-Panel mit Fuellstand, Ein-/Ausgang, Netto, Zeit bis voll/leer
local function energiePanel(t, x0, y0, W, oH, m, titel, fehlerText)
  panel(t, x0, y0, W, oH, titel, colors.cyan)
  if not m then
    schreib(t, x0 + 2, y0 + 2, fehlerText or "Keine Daten.", colors.lightGray, colors.gray, W - 3)
    return
  end
  local bF = farbeFuer(m.anteil, 0.25, CFG.STROM_WARN, true)
  schreib(t, x0 + 2, y0 + 1, pz(m.anteil), bF, colors.gray)
  rechts(t, x0 + W - 2, y0 + 1, kurz(m.energie, " FE") .. " / " .. kurz(m.max, " FE"), colors.white, colors.gray)
  balken(t, x0 + 2, y0 + 2, W - 4, m.anteil, bF, oH >= 9 and 2 or 1)
  local netto = (m.rein or 0) - (m.raus or 0)
  local sp = math.floor((W - 4) / 2)
  local ly = y0 + (oH >= 9 and 5 or 4)
  if ly < y0 + oH then
    wertZeile(t, x0 + 2, ly, sp - 2, "Eingang", kurz(m.rein, " FE/t"), colors.lime)
    wertZeile(t, x0 + 2 + sp, ly, sp - 1, "Ausgang", kurz(m.raus, " FE/t"), colors.orange)
  end
  ly = ly + 1
  if ly < y0 + oH then
    wertZeile(t, x0 + 2, ly, sp - 2, "Netto", (netto >= 0 and "+" or "") .. kurz(netto, " FE/t"),
      netto >= 0 and colors.lime or colors.red)
    wertZeile(t, x0 + 2 + sp, ly, sp - 1, "Limit", kurz(m.limit, " FE/t"))
  end
  ly = ly + 1
  if ly < y0 + oH then
    local txt, zeit
    if netto > 0 and m.max and m.energie then
      txt, zeit = "Voll in", ((m.max - m.energie) / netto) / 20
    elseif netto < 0 and m.energie then
      txt, zeit = "Leer in", (m.energie / -netto) / 20
    else
      txt, zeit = "Bilanz", nil
    end
    wertZeile(t, x0 + 2, ly, sp - 2, txt, zeit and dauer(zeit) or "ausgeglichen", netto < 0 and colors.orange or colors.white)
  end
end

function ZEICHNE.energie(t, x0, y0, W, H)
  local liste = matrixListe()
  local summe, s = matrixDaten()
  local y = y0

  -- Reiter: GESAMT + jede Matrix (nur bei mehreren Matrizen)
  if #liste > 1 then
    if energieAuswahl > #liste then energieAuswahl = 0 end
    local n = #liste + 1
    local tw = math.min(16, math.floor((W + 1) / n) - 1)
    knopf(t, x0, y0, tw, 1, "GESAMT", energieAuswahl == 0 and colors.cyan or colors.gray,
      energieAuswahl == 0 and colors.black or colors.white, function() energieAuswahl = 0 end)
    for i, mx in ipairs(liste) do
      local aktiv = (energieAuswahl == i)
      local f = not mx.frisch and colors.red or colors.white
      knopf(t, x0 + i * (tw + 1), y0, tw, 1, mx.name:sub(1, tw), aktiv and colors.cyan or colors.gray,
        aktiv and colors.black or f, function() energieAuswahl = i end)
    end
    y = y0 + 2
  else
    energieAuswahl = (#liste == 1) and 1 or 0
  end
  local hH = H - (y - y0)

  -- Einzelne Matrix
  if energieAuswahl > 0 then
    local mx = liste[energieAuswahl]
    local d = mx and mx.daten or {}
    local m = (mx and mx.frisch and not d.fehler and type(d.energie) == "number") and d or nil
    if m then
      local k = {}
      for a, b in pairs(m) do k[a] = b end
      k.anteil = quote(m.energie, m.max) or 0
      m = k
    end
    local oH = math.min(10, math.floor(hH / 2))
    local fehler = not mx and "Keine Daten." or (not mx.frisch and "Keine aktuellen Daten." or (d.fehler and ("Fehler: " .. tostring(d.fehler))))
    energiePanel(t, x0, y, W, oH, m, (mx and mx.name:upper() or "MATRIX"), fehler)
    verlaufZeichnen(t, x0, y + oH + 1, W, hH - oH - 1, mx and mx.verlauf or {}, "VERLAUF " .. (mx and mx.name:upper() or ""))
    return
  end

  -- GESAMT
  local oH = math.min(9, math.max(6, math.floor(hH / 3)))
  energiePanel(t, x0, y, W, oH, summe, "GESAMT (" .. s.anzahl .. " VON " .. s.gesamt .. " MATRIZEN)",
    "Keine aktuellen Daten von den Matrix-Sendern.")
  y = y + oH + 1

  -- Kompakte Liste aller Matrizen
  local lH = math.min(#liste + 2, y0 + H - y)
  panel(t, x0, y, W, lH, "MATRIZEN", colors.cyan)
  local nameB = math.min(16, math.max(8, math.floor(W * 0.18)))
  local textB = 26
  local bx = x0 + 2 + nameB + 1
  local bB = (x0 + W - 2) - textB - 7 - bx
  for i, mx in ipairs(liste) do
    local ry = y + i
    if ry >= y + lH - 1 + 1 then break end
    local d = mx.daten
    local ok = mx.frisch and not d.fehler and type(d.energie) == "number"
    local q = ok and quote(d.energie, d.max) or nil
    local f = ok and farbeFuer(q, 0.25, CFG.STROM_WARN, true) or colors.red
    schreib(t, x0 + 2, ry, mx.name, ok and colors.white or colors.red, colors.gray, nameB)
    if bB > 2 then balken(t, bx, ry, bB, q or 0, f) end
    rechts(t, bx + math.max(bB, 0) + 6, ry, ok and pz(q) or "--", f, colors.gray)
    rechts(t, x0 + W - 2, ry, ok and ("+" .. kurz(d.rein) .. " / -" .. kurz(d.raus) .. " FE/t") or "keine Daten",
      ok and colors.lightGray or colors.red, colors.gray)
    knoepfe[#knoepfe + 1] = { name = t.name, x1 = x0, y1 = ry, x2 = x0 + W - 1, y2 = ry,
      aktion = function() energieAuswahl = i end }
  end
  y = y + lH + 1

  -- Verlauf gesamt (wenn Platz ist)
  verlaufZeichnen(t, x0, y, W, y0 + H - y, verlauf, "VERLAUF GESAMT")
end

function ZEICHNE.reaktor(t, x0, y0, W, H)
  local st, rText, rFarbe = reaktorInfo()
  local d = st and st.daten
  local lW = math.floor(W * 0.6)
  local rW = W - lW - 1

  -- Links: Messwerte
  panel(t, x0, y0, lW, H, "MESSWERTE", rFarbe)
  if not d then
    schreib(t, x0 + 2, y0 + 2, st and "Waechter liefert keine Werte." or "Keine Verbindung zum Waechter.",
      colors.lightGray, colors.gray, lW - 3)
  else
    local bw = lW - 4
    local zeilen = {
      { "Temperatur", string.format("%.0f K", d.temp or 0), (d.temp or 0) / 1200, farbeFuer(d.temp or 0, 850, 1000) },
      { "Kuehlmittel", pz(d.kuehl), d.kuehl, farbeFuer(d.kuehl, 0.80, 0.60, true) },
      { "Dampf", pz(d.heiss), d.heiss, farbeFuer(d.heiss, 0.50, 0.80) },
      { "Atommuell", pz(d.muell), d.muell, farbeFuer(d.muell, 0.50, 0.80) },
      { "Brennstoff", pz(d.brenn), d.brenn, farbeFuer(d.brenn, 0.10, 0.001, true) },
    }
    local y = y0 + 2
    for _, z in ipairs(zeilen) do
      if y + 1 >= y0 + H then break end
      wertZeile(t, x0 + 2, y, bw, z[1], z[2], z[4])
      balken(t, x0 + 2, y + 1, bw, z[3], z[4])
      y = y + 3
    end
    if y < y0 + H then
      wertZeile(t, x0 + 2, y, bw, "Schaden", string.format("%.2f", d.schaden or 0),
        (d.schaden or 0) > 0 and colors.red or colors.lime)
      y = y + 1
    end
    if y < y0 + H then
      wertZeile(t, x0 + 2, y, bw, "Burn Rate",
        string.format("%.1f / %.1f mB/t", d.burnIst or 0, d.burn or 0))
    end
  end

  -- Rechts: Steuerung
  local rx = x0 + lW + 1
  panel(t, rx, y0, rW, H, "STEUERUNG", rFarbe)
  schreib(t, rx + 2, y0 + 2, rText, rFarbe, colors.gray, rW - 3)
  local y = y0 + 3
  if st and st.scram then
    -- Gruende einzeln untereinander
    for teil in (tostring(st.grund) .. ","):gmatch("%s*([^,]+),") do
      schreib(t, rx + 2, y, teil, colors.red, colors.gray, rW - 3)
      y = y + 1
    end
    schreib(t, rx + 2, y, "Reset nur vor Ort (Taste R)", colors.lightGray, colors.gray, rW - 3)
    y = y + 2
  end
  y = math.max(y, y0 + 6)
  local bw = rW - 4

  if bestaetigung and os.clock() > bestaetigung.bis then bestaetigung = nil end
  if bestaetigung then
    schreib(t, rx + 2, y, "Fission wirklich STARTEN?", colors.orange, colors.gray, rW - 3)
    local hb = math.floor((bw - 1) / 2)
    knopf(t, rx + 2, y + 2, hb, 3, "JA", colors.green, colors.white, function()
      bestaetigung = nil
      reaktorBefehl("start")
    end)
    knopf(t, rx + 3 + hb, y + 2, bw - hb - 1, 3, "NEIN", colors.black, colors.white, function()
      bestaetigung = nil
    end)
    y = y + 6
  else
    knopf(t, rx + 2, y, bw, 3, "START", colors.green, colors.white, function()
      bestaetigung = { aktion = "start", bis = os.clock() + 8 }
    end)
    knopf(t, rx + 2, y + 4, bw, 3, "STOP", colors.black, colors.white, function()
      reaktorBefehl("stop")
    end)
    y = y + 8
  end
  if y + 2 < y0 + H then
    knopf(t, rx + 2, y, bw, 3, "NOT-AUS", colors.red, colors.white, function()
      reaktorBefehl("notaus")
    end)
    y = y + 4
  end

  if rueckmeldung and os.clock() > rueckmeldung.bis then rueckmeldung = nil end
  if rueckmeldung and y < y0 + H then
    schreib(t, rx + 2, y, rueckmeldung.text, rueckmeldung.farbe, colors.gray, rW - 3)
  end
  -- Warnungen des Waechters
  if st and st.warnungen and #st.warnungen > 0 then
    local wy = y0 + H - #st.warnungen - 1
    for i, w in ipairs(st.warnungen) do
      if wy + i > y + 1 and wy + i < y0 + H then
        schreib(t, rx + 2, wy + i, "- " .. tostring(w), colors.orange, colors.gray, rW - 3)
      end
    end
  end
end

local function turbinePanel(t, x0, y0, W, H, e)
  local tu = e.daten
  local akzent = not e.frisch and colors.lightGray or (tu.fehler and colors.red) or colors.cyan
  panel(t, x0, y0, W, H, e.name:upper(), akzent)
  if not e.frisch then
    schreib(t, x0 + 2, y0 + 2, "Keine aktuellen Daten.", colors.lightGray, colors.gray, W - 3)
    return
  end
  if tu.fehler then
    schreib(t, x0 + 2, y0 + 2, "Fehler: " .. tostring(tu.fehler), colors.red, colors.gray, W - 3)
    return
  end
  local bw = W - 4
  local tq = quote(tu.produktion, tu.maxProd)
  local fq = quote(tu.fluss, tu.maxFluss)
  local zeilen = {
    { "Leistung", kurz(tu.produktion, " FE/t") .. " / " .. kurz(tu.maxProd, " FE/t"), tq, colors.lime },
    { "Dampf im Tank", pz(tu.dampf), tu.dampf, farbeFuer(tu.dampf, 0.5, CFG.DAMPF_WARN) },
    { "Dampffluss", kurz(tu.fluss, " mB/t") .. " / " .. kurz(tu.maxFluss, " mB/t"), fq, colors.cyan },
    { "Energiepuffer", pz(tu.puffer), tu.puffer, farbeFuer(tu.puffer, 0.8, 0.95) },
  }
  local gross = H >= 20
  local y = y0 + 2
  for _, z in ipairs(zeilen) do
    if y + 1 >= y0 + H then break end
    wertZeile(t, x0 + 2, y, bw, z[1], z[2], z[4])
    balken(t, x0 + 2, y + 1, bw, z[3], z[4], (gross and y + 2 < y0 + H) and 2 or 1)
    y = y + (gross and 5 or 3)
  end
  if y < y0 + H and type(tu.puffer) == "number" and tu.puffer >= 0.95 then
    schreib(t, x0 + 2, y, "Puffer voll!", colors.orange, colors.gray, W - 3)
  end
end

function ZEICHNE.turbine(t, x0, y0, W, H)
  local liste = turbinenListe()
  if #liste == 0 then
    panel(t, x0, y0, W, H, "TURBINEN", colors.cyan)
    schreib(t, x0 + 2, y0 + 2, "Keine Daten von Turbinen-Sendern.", colors.lightGray, colors.gray, W - 3)
    return
  end

  -- Gesamtzeile oben
  local sum = turbineDaten()
  local oben = 0
  if #liste > 1 then
    oben = 5
    panel(t, x0, y0, W, 4, "GESAMT (" .. #liste .. " TURBINEN)", colors.cyan)
    if sum then
      wertZeile(t, x0 + 2, y0 + 1, W - 4, "Leistung",
        kurz(sum.produktion, " FE/t") .. " / " .. kurz(sum.maxProd, " FE/t"), colors.lime)
      balken(t, x0 + 2, y0 + 2, W - 4, quote(sum.produktion, sum.maxProd), colors.lime)
    else
      schreib(t, x0 + 2, y0 + 2, "Keine aktuellen Daten.", colors.lightGray, colors.gray)
    end
  end

  -- Eine Spalte pro Turbine (max. 3 nebeneinander)
  local n = math.min(#liste, 3)
  local sw = math.floor((W - (n - 1)) / n)
  for i = 1, n do
    local x = x0 + (i - 1) * (sw + 1)
    local w = (i == n) and (W - (sw + 1) * (n - 1)) or sw
    turbinePanel(t, x, y0 + oben, w, H - oben, liste[i])
  end
end

function ZEICHNE.me(t, x0, y0, W, H)
  local me = meDaten()
  panel(t, x0, y0, W, H, "ME-SYSTEM", colors.cyan)
  if not me then
    local f = frisch("me") and quellen.me.daten.fehler
    schreib(t, x0 + 2, y0 + 2, f and ("Fehler: " .. f) or "Keine Daten vom ME-Sender.", colors.lightGray, colors.gray, W - 3)
    return
  end
  local bw = W - 4
  local qi = quote(me.itemsBenutzt, me.itemsGesamt)
  local qf = quote(me.fluidBenutzt, me.fluidGesamt)
  local qc = quote(me.chemBenutzt, me.chemGesamt)
  local zeilen = {
    { "Item-Speicher", kurz(me.itemsBenutzt) .. " / " .. kurz(me.itemsGesamt) .. " Bytes  (" .. pz(qi) .. ")",
      qi, farbeFuer(qi, 0.75, CFG.ME_WARN) },
    { "Fluid-Speicher", kurz(me.fluidBenutzt) .. " / " .. kurz(me.fluidGesamt) .. " Bytes  (" .. pz(qf) .. ")",
      qf, farbeFuer(qf, 0.75, CFG.ME_WARN) },
    { "Chemical-Speicher", kurz(me.chemBenutzt) .. " / " .. kurz(me.chemGesamt) .. " Bytes  (" .. pz(qc) .. ")",
      qc, farbeFuer(qc, 0.75, CFG.ME_WARN) },
  }
  -- Drei grosse Balken, gleichmaessig ueber die Hoehe verteilt
  local abstand = math.max(3, math.floor((H - 2) / 3))
  local dicke = math.max(1, math.min(4, abstand - 3))
  local y = y0 + 2
  for _, z in ipairs(zeilen) do
    if y + 1 >= y0 + H then break end
    wertZeile(t, x0 + 2, y, bw, z[1], z[2], z[4])
    balken(t, x0 + 2, y + 1, bw, z[3], z[4], math.max(1, math.min(dicke, y0 + H - 1 - y)))
    y = y + abstand
  end
end

local function wetterInfo(t, x0, y0, W, H)
  local w = wetterDaten()
  local wt, wf = wetterText(w)
  panel(t, x0, y0, W, H, "ZEIT & WETTER", w and wf or colors.lightGray)
  if not w then
    schreib(t, x0 + 2, y0 + 2, "Keine Daten vom Wetter-PC.", colors.lightGray, colors.gray, W - 3)
    return
  end
  local bw = W - 4
  local y = y0 + 2

  -- Uhrzeit und Tag/Nacht
  schreib(t, x0 + 2, y, textutils.formatTime(w.uhr or 0, true) .. " Uhr", colors.white, colors.gray)
  rechts(t, x0 + W - 2, y, w.nacht and "NACHT" or "TAG", w.nacht and colors.cyan or colors.orange, colors.gray)
  y = y + 1
  schreib(t, x0 + 2, y, "Tag " .. tostring(w.tag), colors.lightGray, colors.gray)
  y = y + 2

  -- Tagesleiste 0-24 Uhr mit Markierung
  if y + 3 < y0 + H then
    local ab, bis = w.nachtAb or 18.5, w.nachtBis or 5.5
    for i = 0, bw - 1 do
      local h = i / bw * 24
      local nacht = h >= ab or h < bis
      fuell(t, x0 + 2 + i, y, 1, 2, nacht and colors.black or colors.orange)
    end
    local pos = math.floor((w.uhr or 0) / 24 * bw)
    fuell(t, x0 + 2 + math.min(bw - 1, pos), y, 1, 2, colors.white)
    y = y + 2
    schreib(t, x0 + 2, y, "0", colors.lightGray, colors.gray)
    schreib(t, x0 + 2 + math.floor(bw / 4) - 1, y, "6", colors.lightGray, colors.gray)
    schreib(t, x0 + 2 + math.floor(bw / 2) - 1, y, "12", colors.lightGray, colors.gray)
    schreib(t, x0 + 2 + math.floor(bw * 3 / 4) - 1, y, "18", colors.lightGray, colors.gray)
    rechts(t, x0 + W - 2, y, "24", colors.lightGray, colors.gray)
    y = y + 3
  end

  -- Naechster Wechsel Tag/Nacht (in Ingame-Stunden)
  local uhr = w.uhr or 0
  local ziel = w.nacht and (w.nachtBis or 5.5) or (w.nachtAb or 18.5)
  local rest = (ziel - uhr) % 24
  local wechsel = string.format("%dh %02dm", math.floor(rest), math.floor(rest % 1 * 60))

  local spawn = w.nacht or w.gewitter
  local zeilen = {
    { "Wetter", wt, wf },
    { w.nacht and "Tag beginnt in" or "Nacht beginnt in", wechsel, colors.white },
    { "Monster-Spawn draussen", spawn and "MOEGLICH" or "nein", spawn and colors.orange or colors.lime },
    { "Mond", tostring(w.mondName), w.mond == 0 and colors.orange or colors.white },
    { "Himmelslicht", tostring(w.licht or "--") .. " / 15", colors.white },
    { "Biom", tostring(w.biom or "--"):gsub("^.-:", ""), colors.lightGray },
  }
  for _, z in ipairs(zeilen) do
    if y >= y0 + H then break end
    wertZeile(t, x0 + 2, y, bw, z[1], z[2], z[3])
    y = y + 2
  end
  if w.mond == 0 and w.nacht and y < y0 + H then
    schreib(t, x0 + 2, y, "Vollmondnacht: mehr Monster!", colors.orange, colors.gray, W - 3)
  end
end

-- Befehl an den Wetter-PC (Command Computer), gesichert wie beim Reaktor
local function wetterBefehl(befehl, wert)
  local q = quellen.wetter
  if not frisch("wetter") then melden("Kein Kontakt zum Wetter-PC", colors.red) return end
  local nonce = q.daten.nonce
  if nonce == false then
    ausstehend.wetter = function() wetterBefehl(befehl, wert) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then melden("Wetter-PC braucht Update (v3)", colors.red) return end
  local sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. wert .. "|" .. nonce)
  rednet.send(q.id, { befehl = befehl, wert = wert, nonce = nonce, sig = sig }, CFG.PROT_WETTER)
  q.daten.nonce = false
  melden("Gesendet ...", colors.lightGray)
end

local function wetterSteuerung(t, x0, y0, W, H, w)
  panel(t, x0, y0, W, H, "STEUERUNG", colors.cyan)
  local bw = W - 4
  local y = y0 + 2
  -- Welche Celestial Manipulators sind verbaut?
  local da = {}
  for _, f in ipairs(type(w.funktionen) == "table" and w.funktionen or {}) do da[f] = true end
  local function fehlt() melden("Dafuer ist kein Manipulator verbaut", colors.orange) end

  -- Wetter-Knoepfe
  schreib(t, x0 + 2, y, "Wetter", colors.lightGray, colors.gray)
  y = y + 1
  local wk = {
    { "KLAR", "clear", colors.green }, { "REGEN", "rain", colors.black }, { "GEWITTER", "thunder", colors.brown },
  }
  local kb = math.floor((bw - 2) / 3)
  for i, k in ipairs(wk) do
    local x = x0 + 2 + (i - 1) * (kb + 1)
    local wbreite = (i == 3) and (bw - 2 * (kb + 1)) or kb
    if da[k[2]] then
      knopf(t, x, y, wbreite, 3, k[1], k[3], colors.white, function() wetterBefehl("wetter", k[2]) end)
    else
      knopf(t, x, y, wbreite, 3, k[1], colors.black, colors.gray, fehlt)
    end
  end
  y = y + 4

  -- Zeit-Knoepfe
  schreib(t, x0 + 2, y, "Uhrzeit", colors.lightGray, colors.gray)
  y = y + 1
  local zk = { { "MORGEN", "morgen" }, { "MITTAG", "mittag" }, { "ABEND", "abend" }, { "NACHT", "nacht" } }
  local zb = math.floor((bw - 3) / 4)
  for i, k in ipairs(zk) do
    local x = x0 + 2 + (i - 1) * (zb + 1)
    local wbreite = (i == 4) and (bw - 3 * (zb + 1)) or zb
    if da[k[2]] then
      knopf(t, x, y, wbreite, 3, k[1], colors.black, colors.white, function() wetterBefehl("zeit", k[2]) end)
    else
      knopf(t, x, y, wbreite, 3, k[1], colors.black, colors.gray, fehlt)
    end
  end
  y = y + 4

  -- Automatik-Schalter
  schreib(t, x0 + 2, y, "Automatik", colors.lightGray, colors.gray)
  y = y + 1
  local auto = type(w.auto) == "table" and w.auto or {}
  local sk = {
    { "Regen -> klar", "regen", "clear" }, { "Gewitter -> klar", "gewitter", "clear" },
    { "Nacht ueberspringen", "nacht", "morgen" },
  }
  for _, k in ipairs(sk) do
    if y + 1 >= y0 + H then break end
    local an = auto[k[2]] == true
    local moeglich = da[k[3]] == true
    fuell(t, x0 + 2, y, bw, 1, colors.black)
    schreib(t, x0 + 3, y, k[1], moeglich and colors.white or colors.lightGray, colors.black, bw - 8)
    local pill = not moeglich and "  --  " or (an and "  AN  " or " AUS  ")
    schreib(t, x0 + 2 + bw - #pill, y, pill, colors.black, an and colors.lime or colors.lightGray)
    knoepfe[#knoepfe + 1] = { name = t.name, x1 = x0 + 2, y1 = y, x2 = x0 + 1 + bw, y2 = y,
      aktion = moeglich and function() wetterBefehl("auto", k[2] .. "=" .. (an and "0" or "1")) end or fehlt }
    y = y + 2
  end

  -- Rueckmeldung
  if rueckmeldung and os.clock() > rueckmeldung.bis then rueckmeldung = nil end
  if rueckmeldung and y + 1 < y0 + H then
    schreib(t, x0 + 2, y + 1, rueckmeldung.text, rueckmeldung.farbe, colors.gray, bw)
  end
end

function ZEICHNE.wetter(t, x0, y0, W, H)
  local w = wetterDaten()
  if w and w.steuerbar then
    local lW = math.floor(W * 0.52)
    wetterInfo(t, x0, y0, lW, H)
    wetterSteuerung(t, x0 + lW + 1, y0, W - lW - 1, H, w)
  else
    wetterInfo(t, x0, y0, W, H)
  end
end

-- ---------- Flux-Netz ----------
local function fluxListe()
  local liste, summe, aktiv = {}, 0, 0
  for _, sd in pairs(fluxSender) do
    local ok = (os.clock() - sd.zeit) < CFG.ZEITLIMIT
    for _, pl in ipairs(sd.plugs) do
      local rate = ok and pl.rate or nil
      liste[#liste + 1] = { name = tostring(pl.name), ort = tostring(sd.ort), rate = rate, frisch = ok }
      if rate then
        summe = summe + rate
        if rate > 0 then aktiv = aktiv + 1 end
      end
    end
  end
  if fluxSort == "leistung" then
    table.sort(liste, function(a, b)
      if (a.rate or -1) ~= (b.rate or -1) then return (a.rate or -1) > (b.rate or -1) end
      return a.name < b.name
    end)
  else
    -- "Dyson 2" vor "Dyson 10" (Zahlen richtig sortieren)
    local function nat(x) return (x:gsub("%d+", function(d) return string.rep("0", 10 - #d) .. d end)) end
    table.sort(liste, function(a, b)
      if a.ort ~= b.ort then return a.ort < b.ort end
      return nat(a.name) < nat(b.name)
    end)
  end
  return liste, summe, aktiv
end

function ZEICHNE.flux(t, x0, y0, W, H)
  local liste, summe, aktiv = fluxListe()

  -- Kopf-Panel mit Summe
  panel(t, x0, y0, W, 4, "FLUX-NETZ", colors.cyan)
  schreib(t, x0 + 2, y0 + 1, "Gesamt-Eingang", colors.lightGray, colors.gray)
  schreib(t, x0 + 2, y0 + 2, kurz(summe, " FE/t"), colors.lime, colors.gray)
  rechts(t, x0 + W - 2, y0 + 1, "Plugs", colors.lightGray, colors.gray)
  rechts(t, x0 + W - 2, y0 + 2, aktiv .. " aktiv / " .. #liste, colors.white, colors.gray)

  -- Liste
  local ly = y0 + 5
  local lH = H - 5
  panel(t, x0, ly, W, lH, nil, colors.cyan)
  local nameB = math.max(10, math.floor(W * 0.28))
  local ortB = math.max(6, math.floor(W * 0.16))
  local wertB = 12
  local nx = x0 + 2
  local ox = nx + nameB + 1
  local bx = ox + ortB + 1
  local bB = (x0 + W - 2) - bx - wertB
  schreib(t, nx, ly, "PLUG", colors.cyan, colors.gray)
  schreib(t, ox, ly, "ORT", colors.cyan, colors.gray)
  rechts(t, x0 + W - 2, ly, "FE/t", colors.cyan, colors.gray)

  local zeilen = lH - 3
  local seiten = math.max(1, math.ceil(#liste / zeilen))
  if fluxSeite > seiten then fluxSeite = seiten end
  local maxRate = 0
  for _, pl in ipairs(liste) do if (pl.rate or 0) > maxRate then maxRate = pl.rate end end

  if #liste == 0 then
    schreib(t, nx, ly + 2, "Noch keine Daten von Flux-Sendern.", colors.lightGray, colors.gray)
  end
  for i = 1, zeilen do
    local pl = liste[(fluxSeite - 1) * zeilen + i]
    if not pl then break end
    local y = ly + i
    local bg = (i % 2 == 0) and colors.black or colors.gray
    fuell(t, x0 + 1, y, W - 1, 1, bg)
    local f = not pl.frisch and colors.red or ((pl.rate or 0) > 0 and colors.white or colors.lightGray)
    schreib(t, nx, y, pl.name, f, bg, nameB)
    schreib(t, ox, y, pl.ort, colors.lightGray, bg, ortB)
    if bB > 2 then
      local anteil = maxRate > 0 and (pl.rate or 0) / maxRate or 0
      local voll = math.floor(bB * anteil + 0.5)
      if (pl.rate or 0) > 0 and voll == 0 then voll = 1 end
      fuell(t, bx, y, voll, 1, colors.lime)
    end
    rechts(t, x0 + W - 2, y, not pl.frisch and "keine Daten" or kurz(pl.rate),
      not pl.frisch and colors.red or ((pl.rate or 0) > 0 and colors.lime or colors.lightGray), bg)
  end

  -- Blaettern + Sortierung
  local fy = ly + lH - 1
  fuell(t, x0 + 1, fy, W - 1, 1, colors.gray)
  knopf(t, x0 + 2, fy, 11, 1, "< ZURUECK", fluxSeite > 1 and colors.cyan or colors.black,
    fluxSeite > 1 and colors.black or colors.lightGray, function() if fluxSeite > 1 then fluxSeite = fluxSeite - 1 end end)
  knopf(t, x0 + W - 12, fy, 10, 1, "WEITER >", fluxSeite < seiten and colors.cyan or colors.black,
    fluxSeite < seiten and colors.black or colors.lightGray, function() if fluxSeite < seiten then fluxSeite = fluxSeite + 1 end end)
  local mitte = "Seite " .. fluxSeite .. "/" .. seiten
  schreib(t, x0 + 15, fy, mitte, colors.white, colors.gray)
  local sortTxt = fluxSort == "leistung" and "SORT: LEISTUNG" or "SORT: ORT/NAME"
  knopf(t, x0 + 15 + #mitte + 2, fy, #sortTxt + 2, 1, sortTxt, colors.black, colors.white, function()
    fluxSort = (fluxSort == "leistung") and "name" or "leistung"
    fluxSeite = 1
  end)
end

-- ---------- Extreme Reactors ----------
local function xtremeListe()
  local l = {}
  for key, x in pairs(xtreme) do
    x.key = key
    x.frisch = (os.clock() - x.zeit) < CFG.ZEITLIMIT
    l[#l + 1] = x
  end
  table.sort(l, function(a, b) return a.name < b.name end)
  return l
end

function ZEICHNE.xtreme(t, x0, y0, W, H)
  local l = xtremeListe()
  if #l == 0 then
    panel(t, x0, y0, W, H, "EXTREME REACTORS", colors.cyan)
    schreib(t, x0 + 2, y0 + 2, "Keine Daten von Xtreme-Reaktoren.", colors.lightGray, colors.gray, W - 3)
    return
  end
  if xtremeAuswahl > #l then xtremeAuswahl = 1 end

  -- Reiter, wenn es mehrere Reaktoren gibt
  local y = y0
  if #l > 1 then
    local tw = math.min(20, math.floor((W + 1) / #l) - 1)
    for i, e in ipairs(l) do
      local aktiv = (i == xtremeAuswahl)
      knopf(t, x0 + (i - 1) * (tw + 1), y0, tw, 1, e.name:sub(1, tw),
        aktiv and colors.cyan or colors.gray, aktiv and colors.black or colors.white,
        function() xtremeAuswahl = i end)
    end
    y = y0 + 2
  end
  local e = l[xtremeAuswahl]
  local d = e.daten or {}
  local hH = H - (y - y0)
  local lW = math.floor(W * 0.58)
  local rW = W - lW - 1

  -- Links: Messwerte
  local sFarbe = not e.frisch and colors.lightGray or (d.fehler and colors.red or (d.aktiv and colors.lime or colors.lightGray))
  panel(t, x0, y, lW, hH, "MESSWERTE - " .. e.name:upper(), sFarbe)
  if not e.frisch or d.fehler or d.energie == nil and d.brenn == nil then
    local txt = not e.frisch and "Keine aktuellen Daten." or (d.fehler and ("Fehler: " .. tostring(d.fehler)) or "Startet ...")
    schreib(t, x0 + 2, y + 2, txt, d.fehler and colors.red or colors.lightGray, colors.gray, lW - 3)
  else
    local bw = lW - 4
    local gross = hH >= 24
    local yy = y + 1
    local zeilen = {}
    if d.aktivKuehl then
      zeilen[#zeilen + 1] = { "Dampf im Tank", kurz(d.dampf, " mB") .. " / " .. kurz(d.dampfMax, " mB"),
        quote(d.dampf, d.dampfMax), colors.cyan }
      zeilen[#zeilen + 1] = { "Kuehlmittel", kurz(d.kuehl, " mB") .. " / " .. kurz(d.kuehlMax, " mB"),
        quote(d.kuehl, d.kuehlMax), farbeFuer(quote(d.kuehl, d.kuehlMax), 0.5, 0.2, true) }
    else
      zeilen[#zeilen + 1] = { "Energiespeicher", kurz(d.energie, " FE") .. " / " .. kurz(d.kapazitaet, " FE"),
        quote(d.energie, d.kapazitaet), colors.lime }
    end
    local qb = quote(d.brenn, d.brennMax)
    zeilen[#zeilen + 1] = { "Brennstoff", kurz(d.brenn, " mB") .. " / " .. kurz(d.brennMax, " mB"),
      qb, farbeFuer(qb, 0.25, e.brennWarn or 0.1, true) }
    zeilen[#zeilen + 1] = { "Abfall", kurz(d.abfall, " mB"), quote(d.abfall, d.brennMax), colors.orange }
    zeilen[#zeilen + 1] = { "Steuerstaebe", tostring(d.staebe or "--") .. " % drin  (" .. tostring(d.stabAnzahl or "?") .. ")",
      (d.staebe or 0) / 100, colors.cyan }
    for _, z in ipairs(zeilen) do
      if yy + 2 > y + hH - 1 then break end
      wertZeile(t, x0 + 2, yy, bw, z[1], z[2], z[4])
      balken(t, x0 + 2, yy + 1, bw, z[3], z[4])
      yy = yy + (gross and 4 or 3)
    end
    local texte = {
      { d.aktivKuehl and "Dampf-Produktion" or "Produktion",
        d.aktivKuehl and kurz(d.dampfProd, " mB/t") or kurz(d.prod, " FE/t"), colors.lime },
      { "Temperatur", string.format("%.0f C  (Gehaeuse %.0f C)", d.tempBrenn or 0, d.tempGehaeuse or 0), colors.white },
      { "Verbrauch", string.format("%.3f mB/t", d.verbrauch or 0), colors.white },
      { "Reaktivitaet", string.format("%.0f %%", d.reaktivitaet or 0), colors.white },
    }
    for _, z in ipairs(texte) do
      if yy > y + hH - 1 then break end
      wertZeile(t, x0 + 2, yy, bw, z[1], z[2], z[3])
      yy = yy + 1
    end
  end

  -- Rechts: Steuerung
  local rx = x0 + lW + 1
  panel(t, rx, y, rW, hH, "STEUERUNG", sFarbe)
  local bw = rW - 4
  local yy = y + 1
  local status = not e.frisch and "KEINE DATEN" or (d.fehler and "FEHLER" or (d.aktiv and "LAEUFT" or "AUS"))
  schreib(t, rx + 2, yy, status, sFarbe, colors.gray)
  rechts(t, rx + rW - 2, yy, d.aktivKuehl and "aktiv gekuehlt" or "passiv", colors.lightGray, colors.gray)
  yy = yy + 2
  local hb = math.floor((bw - 1) / 2)
  knopf(t, rx + 2, yy, hb, 2, "AN", colors.green, colors.white, function() xtremeBefehl(e.key, "an", "") end)
  knopf(t, rx + 3 + hb, yy, bw - hb - 1, 2, "AUS", colors.black, colors.white, function() xtremeBefehl(e.key, "aus", "") end)
  yy = yy + 3

  schreib(t, rx + 2, yy, "Steuerstaebe", colors.lightGray, colors.gray)
  rechts(t, rx + rW - 2, yy, tostring(d.staebe or "--") .. " %", colors.cyan, colors.gray)
  yy = yy + 1
  local schritte = { -10, -1, 1, 10 }
  local kb = math.floor((bw - 3) / 4)
  for i, sch in ipairs(schritte) do
    local x = rx + 2 + (i - 1) * (kb + 1)
    local w = (i == 4) and (rx + rW - 2 - x) or kb
    knopf(t, x, yy, w, 1, (sch > 0 and "+" or "") .. sch, colors.black, colors.white, function()
      local v = math.max(0, math.min(100, (d.staebe or 0) + sch))
      xtremeBefehl(e.key, "stab", tostring(v))
    end)
  end
  yy = yy + 2

  local an = d.auto == true
  fuell(t, rx + 2, yy, bw, 1, colors.black)
  schreib(t, rx + 3, yy, "Automatik", colors.white, colors.black, bw - 7)
  local pill = an and "  AN  " or " AUS  "
  schreib(t, rx + 2 + bw - #pill, yy, pill, colors.black, an and colors.lime or colors.lightGray)
  knoepfe[#knoepfe + 1] = { name = t.name, x1 = rx + 2, y1 = yy, x2 = rx + 1 + bw, y2 = yy,
    aktion = function() xtremeBefehl(e.key, "auto", an and "0" or "1") end }
  yy = yy + 2

  if yy + 1 < y + hH then
    knopf(t, rx + 2, yy, bw, 1, "ABFALL AUSWERFEN", colors.brown, colors.white, function() xtremeBefehl(e.key, "abfall", "") end)
    yy = yy + 2
  end
  if rueckmeldung and os.clock() > rueckmeldung.bis then rueckmeldung = nil end
  if rueckmeldung and yy < y + hH then
    schreib(t, rx + 2, yy, rueckmeldung.text, rueckmeldung.farbe, colors.gray, bw)
  end
end

-- ---------- Mekanism-Fusion ----------
local function fusionListe()
  local l = {}
  for key, x in pairs(fusion) do
    x.key = key
    x.frisch = (os.clock() - x.zeit) < CFG.ZEITLIMIT
    l[#l + 1] = x
  end
  table.sort(l, function(a, b) return a.name < b.name end)
  return l
end

local function laserFuer(fusionName)
  local nr = tostring(fusionName):match("(%d+)%s*$")
  if not nr then return nil end
  for key, l in pairs(laser) do
    if l.name:match("(%d+)%s*$") == nr then l.key = key return l end
  end
end

function ZEICHNE.fusion(t, x0, y0, W, H)
  local l = fusionListe()
  if #l == 0 then
    panel(t, x0, y0, W, H, "FUSIONSREAKTOR", colors.cyan)
    schreib(t, x0 + 2, y0 + 2, "Keine Daten von Fusion-Reaktoren.", colors.lightGray, colors.gray, W - 3)
    return
  end
  if fusionAuswahl > #l then fusionAuswahl = 1 end

  -- Reiter fuer mehrere Reaktoren
  local y = y0
  if #l > 1 then
    local tw = math.min(20, math.floor((W + 1) / #l) - 1)
    for i, e in ipairs(l) do
      local aktiv = (i == fusionAuswahl)
      local farbe = (e.frisch and e.daten.gezuendet) and colors.lime or colors.lightGray
      knopf(t, x0 + (i - 1) * (tw + 1), y0, tw, 1, e.name:sub(1, tw),
        aktiv and colors.cyan or colors.gray, aktiv and colors.black or farbe,
        function() fusionAuswahl = i fusionStopp = nil end)
    end
    y = y0 + 2
  end
  local e = l[fusionAuswahl]
  local d = e.daten or {}
  local hH = H - (y - y0)
  local lW = math.floor(W * 0.58)
  local rW = W - lW - 1

  local sFarbe = not e.frisch and colors.lightGray or (d.fehler and colors.red or (d.gezuendet and colors.lime or colors.orange))
  panel(t, x0, y, lW, hH, "MESSWERTE - " .. e.name:upper(), sFarbe)
  if not e.frisch or d.fehler or d.plasma == nil then
    local txt = not e.frisch and "Keine aktuellen Daten." or (d.fehler and ("Fehler: " .. tostring(d.fehler)) or "Startet ...")
    schreib(t, x0 + 2, y + 2, txt, d.fehler and colors.red or colors.lightGray, colors.gray, lW - 3)
  else
    local bw = lW - 4
    local gross = hH >= 24
    local yy = y + 1
    local qP = quote(d.plasma, d.plasmaMax)
    local qG = quote(d.gehaeuse, d.gehaeuseMax)
    local qD = quote(d.dt, d.dtMax)
    local zeilen = {
      { "Plasma", kurz(d.plasma, " K") .. " / " .. kurz(d.plasmaMax, " K"), qP, farbeFuer(qP, 0.85, 0.95) },
      { "Gehaeuse", kurz(d.gehaeuse, " K") .. " / " .. kurz(d.gehaeuseMax, " K"), qG, farbeFuer(qG, 0.85, 0.95) },
      { "D-T-Brennstoff", kurz(d.dt, " mB") .. " / " .. kurz(d.dtMax, " mB"), qD, farbeFuer(qD, 0.25, e.brennWarn or 0.1, true) },
      { "Injection Rate", tostring(d.rate or "--") .. " / 98  (min " .. tostring(d.rateMin or "?") .. ")",
        (d.rate or 0) / 98, colors.cyan },
    }
    for _, z in ipairs(zeilen) do
      if yy + 2 > y + hH - 1 then break end
      wertZeile(t, x0 + 2, yy, bw, z[1], z[2], z[4])
      balken(t, x0 + 2, yy + 1, bw, z[3], z[4])
      yy = yy + (gross and 4 or 3)
    end
    local texte = {
      { "Produktion", kurz(d.prod, " FE/t"), colors.lime },
      { "Deuterium / Tritium", kurz(d.deut, " mB") .. " / " .. kurz(d.trit, " mB"), colors.white },
      { "Matrix (fuer Automatik)", type(d.matrix) == "number" and pz(d.matrix) or "keine Daten",
        type(d.matrix) == "number" and colors.white or colors.lightGray },
    }
    for _, z in ipairs(texte) do
      if yy > y + hH - 1 then break end
      wertZeile(t, x0 + 2, yy, bw, z[1], z[2], z[3])
      yy = yy + 1
    end
  end

  -- Rechts: Steuerung
  local rx = x0 + lW + 1
  panel(t, rx, y, rW, hH, "STEUERUNG", sFarbe)
  local bw = rW - 4
  local yy = y + 1
  local status = not e.frisch and "KEINE DATEN" or (d.fehler and "FEHLER" or (d.gezuendet and "GEZ\220NDET" or "NICHT GEZ\220NDET"))
  schreib(t, rx + 2, yy, status, sFarbe, colors.gray, bw)
  yy = yy + 1
  yy = yy + 1

  schreib(t, rx + 2, yy, "Injection Rate", colors.lightGray, colors.gray)
  rechts(t, rx + rW - 2, yy, tostring(d.rate or "--"), colors.cyan, colors.gray)
  yy = yy + 1
  local schritte = { -10, -2, 2, 10 }
  local kb = math.floor((bw - 3) / 4)
  for i, sch in ipairs(schritte) do
    local x = rx + 2 + (i - 1) * (kb + 1)
    local w = (i == 4) and (rx + rW - 2 - x) or kb
    knopf(t, x, yy, w, 1, (sch > 0 and "+" or "") .. sch, colors.black, colors.white, function()
      local v = math.max(0, math.min(98, (d.rate or 0) + sch))
      fusionBefehl(e.key, "rate", tostring(v))
    end)
  end
  yy = yy + 2

  local an = d.auto == true
  fuell(t, rx + 2, yy, bw, 1, colors.black)
  schreib(t, rx + 3, yy, "Automatik", colors.white, colors.black, bw - 7)
  local pill = an and "  AN  " or " AUS  "
  schreib(t, rx + 2 + bw - #pill, yy, pill, colors.black, an and colors.lime or colors.lightGray)
  knoepfe[#knoepfe + 1] = { name = t.name, x1 = rx + 2, y1 = yy, x2 = rx + 1 + bw, y2 = yy,
    aktion = function() fusionBefehl(e.key, "auto", an and "0" or "1") end }
  yy = yy + 2

  -- STOPP mit Bestaetigung (Fusion erlischt!)
  if fusionStopp and (os.clock() > fusionStopp.bis or fusionStopp.key ~= e.key) then fusionStopp = nil end
  if yy + 1 < y + hH then
    if fusionStopp then
      local hb = math.floor((bw - 1) / 2)
      knopf(t, rx + 2, yy, hb, 1, "JA, STOPP", colors.red, colors.white, function()
        fusionStopp = nil
        fusionBefehl(e.key, "stopp", "")
      end)
      knopf(t, rx + 3 + hb, yy, bw - hb - 1, 1, "NEIN", colors.black, colors.white, function() fusionStopp = nil end)
      yy = yy + 1
      if yy < y + hH then schreib(t, rx + 2, yy, "Fusion erlischt!", colors.orange, colors.gray, bw) end
      yy = yy + 1
    else
      knopf(t, rx + 2, yy, bw, 1, "STOPP (Injection 0)", colors.brown, colors.white, function()
        fusionStopp = { key = e.key, bis = os.clock() + 8 }
      end)
      yy = yy + 2
    end
  end
  -- Laser-Zuendung (Laser N gehoert zu Fusion N)
  local l = laserFuer(e.name)
  if yy + 5 < y + hH then
    local ld = l and l.daten or {}
    local lFrisch = l and (os.clock() - l.zeit) < 15
    schreib(t, rx + 2, yy, (l and l.name:upper() or "LASER") .. " (Z\220NDUNG)", colors.cyan, colors.gray, bw)
    yy = yy + 1
    if not l then
      schreib(t, rx + 2, yy, "Kein Laser-Computer f\252r " .. e.name, colors.lightGray, colors.gray, bw)
      yy = yy + 2
    elseif not lFrisch then
      schreib(t, rx + 2, yy, "Laser: keine Verbindung", colors.red, colors.gray, bw)
      yy = yy + 2
    else
      local q = quote(ld.energie, ld.ziel) or 0
      local voll = q >= 1
      balken(t, rx + 2, yy, bw - 12, math.min(1, q), voll and colors.lime or colors.orange)
      rechts(t, rx + rW - 2, yy, kurz(ld.energie, "") .. "/" .. kurz(ld.ziel, ""), voll and colors.lime or colors.orange, colors.gray)
      yy = yy + 1
      local kein = (d.hohlraum == false)
      local lst, sf
      if ld.signal then lst, sf = "Signal AN - Laser feuert ...", colors.orange
      elseif d.gezuendet then lst, sf = "Signal aus (gez\252ndet)", colors.lime
      elseif ld.fehler then lst, sf = tostring(ld.fehler), colors.red
      elseif kein then lst, sf = "Kein Hohlraum im Reaktor!", colors.red
      elseif voll then lst, sf = "Bereit zum Z\252nden", colors.lime
      else lst, sf = "L\228dt ...", colors.lightGray end
      schreib(t, rx + 2, yy, lst, sf, colors.gray, bw)
      yy = yy + 1
      if d.hohlraum ~= nil and not d.gezuendet then
        schreib(t, rx + 2, yy, "Hohlraum: " .. (d.hohlraum and "eingelegt" or "FEHLT"),
          d.hohlraum and colors.lightGray or colors.red, colors.gray, bw)
      end
      yy = yy + 1
      -- Auto-Zuendung
      local aan = ld.auto == true
      fuell(t, rx + 2, yy, bw, 1, colors.black)
      schreib(t, rx + 3, yy, "Auto-Z\252ndung", colors.white, colors.black, bw - 7)
      local ap = aan and "  AN  " or " AUS  "
      schreib(t, rx + 2 + bw - #ap, yy, ap, colors.black, aan and colors.lime or colors.lightGray)
      local lkey = l.key
      knoepfe[#knoepfe + 1] = { name = t.name, x1 = rx + 2, y1 = yy, x2 = rx + 1 + bw, y2 = yy,
        aktion = function() steuerBefehl(laser, lkey, "auto", aan and "0" or "1") end }
      yy = yy + 2
      if laserFrage and (os.clock() > laserFrage.bis or laserFrage.key ~= l.key) then laserFrage = nil end
      if not d.gezuendet and not ld.signal and yy < y + hH then
        if laserFrage then
          local hb = math.floor((bw - 1) / 2)
          knopf(t, rx + 2, yy, hb, 1, "JA, Z\220NDEN", colors.green, colors.white, function()
            laserFrage = nil
            steuerBefehl(laser, l.key, "zuenden", "")
          end)
          knopf(t, rx + 3 + hb, yy, bw - hb - 1, 1, "NEIN", colors.black, colors.white, function() laserFrage = nil end)
        else
          local bereit = voll and not kein
          knopf(t, rx + 2, yy, bw, 1, bereit and "Z\220NDEN" or (kein and "Z\220NDEN (Hohlraum fehlt)" or "Z\220NDEN (wartet auf Ladung)"),
            bereit and colors.green or colors.black, bereit and colors.white or colors.lightGray, function()
              if bereit then laserFrage = { key = l.key, bis = os.clock() + 8 } end
            end)
        end
        yy = yy + 2
      elseif ld.signal and yy < y + hH then
        knopf(t, rx + 2, yy, bw, 1, "ABBRECHEN (Signal aus)", colors.black, colors.white, function()
          steuerBefehl(laser, l.key, "abbrechen", "")
        end)
        yy = yy + 2
      end
    end
  end
  if rueckmeldung and os.clock() > rueckmeldung.bis then rueckmeldung = nil end
  if rueckmeldung and yy < y + hH then
    schreib(t, rx + 2, yy, rueckmeldung.text, rueckmeldung.farbe, colors.gray, bw)
  end
end

-- ---------- Lager (Functional Storage) ----------
local function lagerListe()
  local liste, summe, belegt, slots, voll = {}, 0, 0, 0, 0
  local mehrere = 0
  for _ in pairs(lagerSender) do mehrere = mehrere + 1 end
  for _, ls in pairs(lagerSender) do
    local ok = (os.clock() - ls.zeit) < CFG.LAGER_ZEIT
    slots = slots + (ls.slots or 0)
    for _, f in ipairs(ls.faecher) do
      local q = (f.limit or 0) > 0 and f.menge / f.limit or 0
      liste[#liste + 1] = { name = tostring(f.name), menge = f.menge, limit = f.limit, q = q, frisch = ok,
        ort = mehrere > 1 and tostring(ls.ort) or nil }
      summe = summe + (f.menge or 0)
      belegt = belegt + 1
      if q >= CFG.LAGER_WARN then voll = voll + 1 end
    end
  end
  local function nat(x) return (x:lower():gsub("%d+", function(d) return string.rep("0", 10 - #d) .. d end)) end
  if lagerSort == "fuell" then
    table.sort(liste, function(a, b) if a.q ~= b.q then return a.q > b.q end return nat(a.name) < nat(b.name) end)
  elseif lagerSort == "menge" then
    table.sort(liste, function(a, b) if a.menge ~= b.menge then return a.menge > b.menge end return nat(a.name) < nat(b.name) end)
  else
    table.sort(liste, function(a, b) return nat(a.name) < nat(b.name) end)
  end
  return liste, summe, belegt, slots, voll
end

function ZEICHNE.lager(t, x0, y0, W, H)
  local liste, summe, belegt, slots, voll = lagerListe()

  panel(t, x0, y0, W, 4, "LAGER (FUNCTIONAL STORAGE)", voll > 0 and colors.orange or colors.cyan)
  schreib(t, x0 + 2, y0 + 1, "Items gesamt", colors.lightGray, colors.gray)
  schreib(t, x0 + 2, y0 + 2, kurz(summe), colors.white, colors.gray)
  local mx = x0 + math.floor(W / 2) - 8
  schreib(t, mx, y0 + 1, "Faecher belegt", colors.lightGray, colors.gray)
  schreib(t, mx, y0 + 2, belegt .. " / " .. slots, colors.white, colors.gray)
  rechts(t, x0 + W - 2, y0 + 1, "Fast voll", colors.lightGray, colors.gray)
  rechts(t, x0 + W - 2, y0 + 2, tostring(voll), voll > 0 and colors.orange or colors.lime, colors.gray)

  local ly = y0 + 5
  local lH = H - 5
  panel(t, x0, ly, W, lH, nil, colors.cyan)
  local nameB = math.max(12, math.floor(W * 0.32))
  local nx = x0 + 2
  local mengeEnde = nx + nameB + 10
  local limitEnde = mengeEnde + 11
  local bx = limitEnde + 2
  local bB = (x0 + W - 2) - 7 - bx
  schreib(t, nx, ly, "ITEM", colors.cyan, colors.gray)
  rechts(t, mengeEnde, ly, "MENGE", colors.cyan, colors.gray)
  rechts(t, limitEnde, ly, "VON", colors.cyan, colors.gray)
  rechts(t, x0 + W - 2, ly, "%", colors.cyan, colors.gray)

  local zeilen = lH - 3
  local seiten = math.max(1, math.ceil(#liste / zeilen))
  if lagerSeite > seiten then lagerSeite = seiten end
  if #liste == 0 then
    schreib(t, nx, ly + 2, "Noch keine Daten vom Lager-Sender.", colors.lightGray, colors.gray)
  end
  for i = 1, zeilen do
    local f = liste[(lagerSeite - 1) * zeilen + i]
    if not f then break end
    local y = ly + i
    local bg = (i % 2 == 0) and colors.black or colors.gray
    fuell(t, x0 + 1, y, W - 1, 1, bg)
    local fb = not f.frisch and colors.red or farbeFuer(f.q, 0.80, CFG.LAGER_WARN)
    local name = f.ort and (f.name .. " (" .. f.ort .. ")") or f.name
    schreib(t, nx, y, name, f.frisch and colors.white or colors.red, bg, nameB)
    rechts(t, mengeEnde, y, kurz(f.menge), colors.white, bg)
    rechts(t, limitEnde, y, kurz(f.limit), colors.lightGray, bg)
    if bB > 2 then
      local v = math.floor(bB * math.min(1, f.q) + 0.5)
      if f.q > 0 and v == 0 then v = 1 end
      fuell(t, bx, y, v, 1, fb)
    end
    rechts(t, x0 + W - 2, y, string.format("%.1f%%", f.q * 100), fb, bg)
  end

  local fy = ly + lH - 1
  fuell(t, x0 + 1, fy, W - 1, 1, colors.gray)
  knopf(t, x0 + 2, fy, 11, 1, "< ZURUECK", lagerSeite > 1 and colors.cyan or colors.black,
    lagerSeite > 1 and colors.black or colors.lightGray, function() if lagerSeite > 1 then lagerSeite = lagerSeite - 1 end end)
  knopf(t, x0 + W - 12, fy, 10, 1, "WEITER >", lagerSeite < seiten and colors.cyan or colors.black,
    lagerSeite < seiten and colors.black or colors.lightGray, function() if lagerSeite < seiten then lagerSeite = lagerSeite + 1 end end)
  local mitte = "Seite " .. lagerSeite .. "/" .. seiten
  schreib(t, x0 + 15, fy, mitte, colors.white, colors.gray)
  local sortTxt = lagerSort == "fuell" and "SORT: FUELLSTAND" or (lagerSort == "menge" and "SORT: MENGE" or "SORT: NAME")
  knopf(t, x0 + 15 + #mitte + 2, fy, #sortTxt + 2, 1, sortTxt, colors.black, colors.white, function()
    lagerSort = (lagerSort == "fuell") and "menge" or (lagerSort == "menge" and "name" or "fuell")
    lagerSeite = 1
  end)
end

function ZEICHNE.log(t, x0, y0, W, H)
  -- Update-Computer (nur wenn vorhanden)
  local up = quellen.update
  if up.zeit then
    panel(t, x0, y0, W, 4, "UPDATES (GITHUB)", colors.cyan)
    local d = up.daten
    local txt, f
    if not (os.clock() - quellen.update.zeit < 30) then txt, f = "Update-Computer: keine Verbindung", colors.red
    elseif d.fehler then txt, f = "Fehler: " .. tostring(d.fehler), colors.red
    elseif d.letzte then
      local min = math.max(0, math.floor((os.epoch("utc") - d.letzte) / 60000))
      txt, f = (d.anzahl or 0) .. " Programme - geprueft vor " .. min .. " min", colors.lime
    else txt, f = "Pruefe GitHub ...", colors.yellow end
    schreib(t, x0 + 2, y0 + 1, txt, f, colors.gray, W - 20)
    if type(d.zuletzt) == "table" and #d.zuletzt > 0 and d.zuletztZeit then
      local min = math.max(0, math.floor((os.epoch("utc") - d.zuletztZeit) / 60000))
      schreib(t, x0 + 2, y0 + 2, "Zuletzt (vor " .. min .. " min): " .. table.concat(d.zuletzt, ", "),
        colors.lightGray, colors.gray, W - 20)
    end
    knopf(t, x0 + W - 16, y0 + 1, 14, 2, "UPDATE", colors.cyan, colors.black, function()
      rednet.broadcast(signieren({ typ = "pruefen" }), CFG.NETZ .. "/update")
      melden("Update-Pruefung angefordert", colors.cyan)
      log("Update-Pruefung angefordert", colors.cyan)
    end)
    y0, H = y0 + 5, H - 5
  end
  panel(t, x0, y0, W, H, "EREIGNISPROTOKOLL", colors.cyan)
  if #logListe == 0 then
    schreib(t, x0 + 2, y0 + 2, "Noch keine Eintraege.", colors.lightGray, colors.gray)
    return
  end
  for i = 1, math.min(#logListe, H - 2) do
    local e = logListe[i]
    schreib(t, x0 + 2, y0 + 1 + i, e.zeit, colors.lightGray, colors.gray)
    schreib(t, x0 + 9, y0 + 1 + i, e.text, e.farbe, colors.gray, W - 10)
  end
end

-- ---------- Betretungslog ----------
function ZEICHNE.besucher(t, x0, y0, W, H)
  local alle, heute, gesamt, mehrere, fehler = {}, 0, 0, 0, nil
  for _, tu in pairs(tueren) do
    mehrere = mehrere + 1
    local d = tu.daten
    heute = heute + (d.heute or 0)
    gesamt = gesamt + (d.gesamt or 0)
    if d.fehler then fehler = tu.name .. ": " .. tostring(d.fehler) end
    for _, e in ipairs(type(d.eintraege) == "table" and d.eintraege or {}) do
      alle[#alle + 1] = { e = e, tuer = tu.name }
    end
  end
  table.sort(alle, function(a, b) return (a.e.zeit or 0) > (b.e.zeit or 0) end)
  panel(t, x0, y0, W, H, "BETRETUNGSLOG", colors.cyan)
  -- Log leeren (mit Sicherheitsabfrage)
  if tuerLeeren and os.clock() > tuerLeeren then tuerLeeren = nil end
  if tuerLeeren then
    schreib(t, x0 + W - 38, y0, "Wirklich l\246schen?", colors.orange, colors.gray)
    knopf(t, x0 + W - 18, y0, 7, 1, "JA", colors.red, colors.white, function()
      tuerLeeren = nil
      for key in pairs(tueren) do steuerBefehl(tueren, key, "leeren", "") end
    end)
    knopf(t, x0 + W - 10, y0, 8, 1, "NEIN", colors.black, colors.white, function() tuerLeeren = nil end)
  else
    knopf(t, x0 + W - 16, y0, 14, 1, "LOG LEEREN", colors.black, colors.white, function()
      tuerLeeren = os.clock() + 8
    end)
  end
  schreib(t, x0 + 2, y0 + 1, "Heute: " .. heute .. "   Gesamt: " .. gesamt .. "   (nur Spieler au\223erhalb des Teams)",
    colors.lightGray, colors.gray, W - 3)
  if fehler then schreib(t, x0 + 2, y0 + 2, fehler, colors.red, colors.gray, W - 3) end
  local sp = { x0 + 2, x0 + 14, x0 + 25 }
  local spTuer = x0 + math.max(45, math.floor(W * 0.6))
  local y = y0 + 3
  schreib(t, sp[1], y, "DATUM", colors.cyan, colors.gray)
  schreib(t, sp[2], y, "UHRZEIT", colors.cyan, colors.gray)
  schreib(t, sp[3], y, "SPIELER", colors.cyan, colors.gray)
  if mehrere > 1 then schreib(t, spTuer, y, "T\220R", colors.cyan, colors.gray) end
  if #alle == 0 then
    schreib(t, sp[1], y + 2, "Noch niemand Fremdes ist durch die T\252r gegangen.", colors.lime, colors.gray, W - 3)
    return
  end
  local heuteDatum = alle[1].e.datum
  for i, a in ipairs(alle) do
    local ry = y + i
    if ry > y0 + H - 2 then break end
    local e = a.e
    local f = (i == 1) and colors.orange or colors.white
    schreib(t, sp[1], ry, tostring(e.datum), colors.lightGray, colors.gray)
    schreib(t, sp[2], ry, tostring(e.uhr), colors.lightGray, colors.gray)
    schreib(t, sp[3], ry, tostring(e.spieler), f, colors.gray, (mehrere > 1 and spTuer - sp[3] - 1) or (x0 + W - 2 - sp[3]))
    if mehrere > 1 then schreib(t, spTuer, ry, a.tuer, colors.lightGray, colors.gray, x0 + W - 2 - spTuer) end
  end
end

-- ---------- Mobfarmen ----------
function ZEICHNE.mobfarm(t, x0, y0, W, H)
  local liste = {}
  for key, m in pairs(mobfarmen) do m.key = key liste[#liste + 1] = m end
  table.sort(liste, function(a, b) return a.name < b.name end)
  local kH = math.max(6, math.min(9, math.floor((H + 1) / math.max(1, #liste)) - 1))
  local y = y0
  for _, m in ipairs(liste) do
    if y + kH - 1 > y0 + H - 1 then break end
    local d = m.daten
    local frisch = (os.clock() - m.zeit) < 15
    local an = d.an and true or false
    local akzent = not frisch and colors.red or (an and colors.lime or colors.lightGray)
    panel(t, x0, y, W, kH, m.name:upper(), akzent)
    local status = not frisch and "KEINE VERBINDUNG" or (an and "AN - Farmen laufen" or "AUS - Farmen gestoppt")
    schreib(t, x0 + 2, y + 2, status, akzent, colors.gray, W - 30)
    if d.seit then
      schreib(t, x0 + 2, y + 4, "Seit " .. tostring(d.seit) .. (d.wer and (" (" .. tostring(d.wer) .. ")") or ""),
        colors.lightGray, colors.gray, W - 30)
    end
    local bw = 22
    local key = m.key
    if an then
      knopf(t, x0 + W - bw - 2, y + 2, bw, 3, "AUSSCHALTEN", colors.black, colors.white,
        function() steuerBefehl(mobfarmen, key, "aus", "") end)
    else
      knopf(t, x0 + W - bw - 2, y + 2, bw, 3, "EINSCHALTEN", colors.green, colors.white,
        function() steuerBefehl(mobfarmen, key, "an", "") end)
    end
    y = y + kH + 1
  end
end

-- ---------- Rahmen: Kopfzeile, Menue ----------
-- ---------- Echte Uhrzeit (Berlin, MEZ/MESZ) ----------
local function zivilTag(tage)
  local z = tage + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  return y
end
local function tageVon(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = m > 2 and m - 3 or m + 9
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end
local function letzterSonntag(y, m) local t = tageVon(y, m, 31) return t - (t + 4) % 7 end
local function berlinUhr()
  local sek = math.floor(os.epoch("utc") / 1000)
  local y = zivilTag(math.floor(sek / 86400))
  local start = letzterSonntag(y, 3) * 86400 + 3600
  local ende  = letzterSonntag(y, 10) * 86400 + 3600
  local lokal = sek + ((sek >= start and sek < ende) and 7200 or 3600)
  local rest = lokal % 86400
  return string.format("%02d:%02d", math.floor(rest / 3600), math.floor(rest % 3600 / 60))
end

local function kopf(t, y)
  fuell(t, 1, y, t.w, 1, colors.gray)
  schreib(t, 2, y, "CORVELYX", colors.cyan, colors.gray)
  schreib(t, 11, y, "CONTROL CENTER", colors.lightGray, colors.gray)
  local name = ""
  for _, s in ipairs(SEITEN) do if s.id == seite then name = s.name end end
  local w = wetterDaten()
  local zeit = textutils.formatTime(w and w.uhr or os.time(), true)
  local rechtsText = name .. "  |  IG: " .. zeit .. " | RL: " .. berlinUhr()
  rechts(t, t.w - 1, y, rechtsText, colors.white, colors.gray)
  if w then
    local wt, wf = wetterText(w)
    rechts(t, t.w - 1 - #rechtsText - 3, y, (w.nacht and "NACHT" or "TAG") .. " " .. wt, wf, colors.gray)
  end
end

local VORRANG = { [colors.cyan] = 5, [colors.red] = 4, [colors.brown] = 4, [colors.orange] = 3, [colors.green] = 3, [colors.gray] = 1 }
-- Pixel-Leinwand (2x3 Punkte pro Zelle) auf den Monitor bringen
local function leinwandAusgeben(t, cv, W, H)
  for cy = 1, H do
    local ch, fg, bg = {}, {}, {}
    for cx = 1, W do
      local p, zaehl = {}, {}
      for i = 1, 6 do
        local px = (cx - 1) * 2 + 1 + (i - 1) % 2
        local py = (cy - 1) * 3 + 1 + math.floor((i - 1) / 2)
        local f = cv[py][px]
        p[i] = f
        zaehl[f] = (zaehl[f] or 0) + 1
      end
      local a, b
      local anzahl = 0
      for _ in pairs(zaehl) do anzahl = anzahl + 1 end
      if anzahl > 2 then
        -- Zelle mit 3+ Farben: Schwarz + wichtigste Farbe behalten
        local best
        for f in pairs(zaehl) do
          if f ~= colors.black and (not best or (VORRANG[f] or 0) > (VORRANG[best] or 0)) then best = f end
        end
        for i = 1, 6 do if p[i] ~= best then p[i] = colors.black end end
        zaehl = { [best] = 0, [colors.black] = 0 }
        for i = 1, 6 do zaehl[p[i]] = zaehl[p[i]] + 1 end
      end
      for f, n in pairs(zaehl) do
        if n > 0 then
          if not a or n > zaehl[a] then b = a a = f elseif not b or n > zaehl[b] then b = f end
        end
      end
      if not b then
        ch[cx], fg[cx], bg[cx] = " ", zuBlit(a), zuBlit(a)
      else
        -- unten rechts muss Hintergrund sein
        local vorne, hinten = a, b
        if p[6] == a then vorne, hinten = b, a end
        local n = 0
        for i = 1, 5 do if p[i] == vorne then n = n + 2 ^ (i - 1) end end
        ch[cx], fg[cx], bg[cx] = string.char(128 + n), zuBlit(vorne), zuBlit(hinten)
      end
    end
    t.win.setCursorPos(1, cy)
    t.win.blit(table.concat(ch), table.concat(fg), table.concat(bg))
  end
end

local function menueMonitor(t)
  t.win.setVisible(false)
  local W, H = t.w, t.h
  local cv = {}
  for py = 1, H * 3 do
    cv[py] = {}
    for px = 1, W * 2 do cv[py][px] = colors.black end
  end
  local function rechteck(px1, py1, px2, py2, f)
    for py = math.max(1, py1), math.min(H * 3, py2) do
      for px = math.max(1, px1), math.min(W * 2, px2) do cv[py][px] = f end
    end
  end
  -- Pille: Textzeile ty, Zellen x..x+w-1, pad = 1 Punkt Rand oben/unten mit runden Ecken
  local function pille(x, ty, w, f, pad)
    local px1, px2 = x * 2 - 1, (x + w - 1) * 2
    local py1, py2 = (ty - 1) * 3 + 1 - pad, ty * 3 + pad
    rechteck(px1, py1, px2, py2, f)
  end
  local texte = {}

  -- Kopf: Name + feine Linie
  texte[#texte + 1] = { math.floor((W - 8) / 2) + 1, 1, "CORVELYX", colors.cyan, colors.black }
  rechteck(3, 5, W * 2 - 2, 5, colors.gray)

  -- Alarm-/Statusfeld unten (Pille)
  local rot = #alarme > 0 and alarme[1].stufe == 2
  local abg
  if #alarme == 0 then abg = colors.green
  elseif rot then abg = blink and colors.red or colors.brown
  else abg = colors.orange end
  local atxt = #alarme == 0 and "SYSTEM OK" or (#alarme .. (#alarme == 1 and " ALARM" or " ALARME"))
  local aty = H - 1
  pille(2, aty, W - 2, abg, 1)
  texte[#texte + 1] = { 2 + math.floor((W - 2 - #atxt) / 2), aty, atxt, colors.white, abg }
  knoepfe[#knoepfe + 1] = { name = t.name, x1 = 1, y1 = aty - 1, x2 = W, y2 = H, aktion = function() seite = "uebersicht" end }

  -- Seitenknoepfe
  local oben, unten = 3, H - 4
  local platz = unten - oben + 1
  local seiten = sichtbareSeiten()
  local spalten = (math.floor(platz / #seiten) >= 2) and 1 or 2
  local proSpalte = math.ceil(#seiten / spalten)
  local schritt = math.max(1, math.min(4, math.floor(platz / proSpalte)))
  local pad = schritt >= 2 and 1 or 0
  local versatz = (schritt >= 2) and 1 or 0
  local sw = (spalten == 1) and (W - 2) or math.floor((W - 3) / 2)
  for i, s in ipairs(seiten) do
    local sp = (spalten == 1) and 1 or (((i - 1) % 2) + 1)
    local zeileNr = (spalten == 1) and (i - 1) or math.floor((i - 1) / 2)
    local x = (sp == 1) and 2 or (3 + sw)
    local bw = (sp == 2) and (W - 1 - x) or sw
    local ty = oben + zeileNr * schritt + versatz
    if ty <= unten then
      local aktiv = (s.id == seite)
      local f = aktiv and colors.cyan or colors.gray
      local label = (#s.name <= bw) and s.name or (s.kurz or s.name:sub(1, bw))
      pille(x, ty, bw, f, pad)
      texte[#texte + 1] = { x + math.floor((bw - #label) / 2), ty, label, aktiv and colors.black or colors.white, f }
      knoepfe[#knoepfe + 1] = { name = t.name, x1 = x, y1 = ty - pad, x2 = x + bw - 1, y2 = ty + pad,
        aktion = function() seite = s.id end }
    end
  end

  leinwandAusgeben(t, cv, W, H)
  for _, tx in ipairs(texte) do schreib(t, tx[1], tx[2], tx[3], tx[4], tx[5]) end
  t.win.setVisible(true)
end

local function menueLeiste(t, y)
  local seiten = sichtbareSeiten()
  local bw = math.floor(t.w / #seiten)
  for i, s in ipairs(seiten) do
    local aktiv = (s.id == seite)
    local w = (i == #seiten) and (t.w - bw * (#seiten - 1)) or bw
    local label = (#s.name <= w - 1) and s.name or (s.kurz or s.name:sub(1, w - 1))
    knopf(t, 1 + (i - 1) * bw, y, w, 1, label,
      aktiv and colors.cyan or colors.black, aktiv and colors.black or colors.white,
      function() seite = s.id end)
  end
end

local function zeichnen()
  knoepfe = {}
  local t = HAUPT
  t.win.setVisible(false)
  fuell(t, 1, 1, t.w, t.h, colors.black)
  kopf(t, 1)
  local y0 = 3
  if not MENU then
    menueLeiste(t, 2)
    y0 = 4
  end
  if not vorhanden(seite) then seite = "uebersicht" end
  ZEICHNE[seite](t, 2, y0, t.w - 2, t.h - y0)
  -- Widmung im unteren Rand
  local herz = string.char(3)
  local widmung = "In Zusammenarbeit mit den beiden wundervollsten Menschen: Annie & Emi "
  if #widmung + 1 > t.w - 2 then widmung = "Mit Annie & Emi " end
  local wx = math.floor((t.w - #widmung - 1) / 2) + 1
  schreib(t, wx, t.h, widmung, colors.lightGray, colors.black)
  schreib(t, wx + #widmung, t.h, herz, colors.cyan, colors.black)
  t.win.setVisible(true)
  if MENU then menueMonitor(MENU) end
end

-- ---------- Ereignisse ----------
local verworfenGemeldet = {}
local function empfangen(id, roh, prot)
  if prot ~= CFG.PROT_REAKTOR and prot ~= CFG.PROT_DATEN and prot ~= CFG.PROT_WETTER
     and prot ~= CFG.PROT_XTREME and prot ~= CFG.PROT_FUSION and prot ~= CFG.PROT_STEUER then return end
  local msg = auspacken(id, roh)
  if not msg then
    -- Einmal pro Computer melden (z.B. falsches Passwort)
    if type(roh) == "table" and not roh.befehl and not verworfenGemeldet[id] then
      verworfenGemeldet[id] = true
      log("Ungueltige Nachricht von PC #" .. id .. " verworfen", colors.orange)
    end
    return
  end
  if prot == CFG.PROT_REAKTOR then
    if msg.typ == "status" then
      quellen.reaktor = { daten = msg, zeit = os.clock(), id = id }
      if ausstehend.reaktor then local f = ausstehend.reaktor ausstehend.reaktor = nil f() end
    elseif msg.typ == "antwort" then
      local farbe = msg.ok and colors.lime or colors.red
      melden(tostring(msg.text), farbe)
      log("Waechter: " .. tostring(msg.text), msg.ok and colors.lime or colors.orange)
    end
  elseif (prot == CFG.PROT_XTREME or prot == CFG.PROT_FUSION or prot == CFG.PROT_STEUER) and msg.typ == "antwort" then
    melden(tostring(msg.text), msg.ok and colors.lime or colors.red)
    log(tostring(msg.text), msg.ok and colors.lime or colors.orange)
  elseif prot == CFG.PROT_WETTER and msg.typ == "antwort" then
    melden(tostring(msg.text), msg.ok and colors.lime or colors.red)
    log("Wetter-PC: " .. tostring(msg.text), msg.ok and colors.lime or colors.orange)
  elseif prot == CFG.PROT_DATEN and msg.typ == "status" then
    local q = msg.quelle
    if q == "fusion" and type(msg.daten) == "table" then
      local key = tostring(msg.schluessel or id)
      local alt = fusion[key]
      fusion[key] = { name = tostring(msg.name or ("Fusion PC" .. id)), daten = msg.daten, zeit = os.clock(),
        id = id, brennWarn = msg.brennWarn, warGezuendet = alt and alt.warGezuendet }
      if ausstehend["f:" .. key] then local f = ausstehend["f:" .. key] ausstehend["f:" .. key] = nil f() end
    elseif q == "xtreme" and type(msg.daten) == "table" then
      local key = tostring(msg.schluessel or id)
      xtreme[key] = { name = tostring(msg.name or ("Xtreme PC" .. id)), daten = msg.daten, zeit = os.clock(),
        id = id, brennWarn = msg.brennWarn }
      if ausstehend["x:" .. key] then local f = ausstehend["x:" .. key] ausstehend["x:" .. key] = nil f() end
    elseif q == "tuer" and type(msg.daten) == "table" then
      local key = tostring(msg.schluessel or id)
      local erstes = (tueren[key] == nil)
      local name = tostring(msg.name or ("T\252r PC" .. id))
      tueren[key] = { name = name, daten = msg.daten, zeit = os.clock(), id = id }
      if ausstehend["s:" .. key] then local f = ausstehend["s:" .. key] ausstehend["s:" .. key] = nil f() end
      local liste = type(msg.daten.eintraege) == "table" and msg.daten.eintraege or {}
      for i = #liste, 1, -1 do
        local e = liste[i]
        local k = key .. "|" .. tostring(e.zeit) .. "|" .. tostring(e.spieler)
        if not tuerGesehen[k] then
          tuerGesehen[k] = true
          if not erstes then
            log("Besucher: " .. tostring(e.spieler) .. " (" .. name .. ", " .. tostring(e.datum) .. " " .. tostring(e.uhr) .. ")", colors.orange)
          end
        end
      end
    elseif q == "laser" and type(msg.daten) == "table" then
      local key = tostring(msg.schluessel or id)
      laser[key] = { name = tostring(msg.name or ("Laser PC" .. id)), daten = msg.daten, zeit = os.clock(), id = id }
      if ausstehend["s:" .. key] then local f = ausstehend["s:" .. key] ausstehend["s:" .. key] = nil f() end
    elseif q == "mobfarm" and type(msg.daten) == "table" then
      local key = tostring(msg.schluessel or id)
      local alt = mobfarmen[key]
      local name = tostring(msg.name or ("Mobfarm PC" .. id))
      if alt and alt.daten.an ~= msg.daten.an then
        log(name .. ": " .. (msg.daten.an and "AN" or "AUS") .. (msg.daten.wer and (" (" .. tostring(msg.daten.wer) .. ")") or ""),
          msg.daten.an and colors.lime or colors.lightGray)
      end
      mobfarmen[key] = { name = name, daten = msg.daten, zeit = os.clock(), id = id }
      if ausstehend["s:" .. key] then local f = ausstehend["s:" .. key] ausstehend["s:" .. key] = nil f() end
    elseif q == "lager" and type(msg.faecher) == "table" then
      lagerSender[tostring(msg.schluessel or id)] = { ort = msg.ort or ("PC" .. id), faecher = msg.faecher,
        slots = msg.slots, zeit = os.clock() }
    elseif q == "flux" and type(msg.plugs) == "table" then
      fluxSender[tostring(msg.schluessel or id)] = { ort = msg.ort or ("PC" .. id), plugs = msg.plugs, zeit = os.clock() }
    elseif q == "turbine" and type(msg.daten) == "table" then
      local key = tostring(msg.schluessel or id)
      turbinen[key] = { daten = msg.daten, zeit = os.clock(), id = id, schluessel = key,
        name = tostring(msg.name or ("Turbine PC" .. id)) }
    elseif q == "matrix" and type(msg.daten) == "table" then
      local key = tostring(msg.schluessel or id)
      local alt = matrizen[key]
      local name = msg.name
      if not name or name == "matrix" then name = "Matrix PC" .. id end
      matrizen[key] = { name = tostring(name), daten = msg.daten, zeit = os.clock(), id = id,
        verlauf = alt and alt.verlauf or {} }
    elseif q and quellen[q] and q ~= "reaktor" and type(msg.daten) == "table" then
      if q == "update" and msg.daten.zuletztZeit and quellen.update.daten
          and quellen.update.daten.zuletztZeit and msg.daten.zuletztZeit ~= quellen.update.daten.zuletztZeit then
        log("Update verteilt: " .. table.concat(msg.daten.zuletzt or {}, ", "), colors.cyan)
      end
      quellen[q] = { daten = msg.daten, zeit = os.clock(), id = id }
      if q == "wetter" and ausstehend.wetter then local f = ausstehend.wetter ausstehend.wetter = nil f() end
    end
  end
end

local function beruehrt(name, x, y)
  for i = #knoepfe, 1, -1 do
    local k = knoepfe[i]
    if k.name == name and x >= k.x1 and x <= k.x2 and y >= k.y1 and y <= k.y2 then
      k.aktion()
      return
    end
  end
end

local function terminalInfo()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  print("CORVELYX // CONTROL CENTER")
  term.setTextColor(colors.white)
  print("Hauptmonitor: " .. HAUPT.name .. " (" .. HAUPT.w .. "x" .. HAUPT.h .. ")")
  print("Menue: " .. (MENU and (MENU.name .. " (" .. MENU.w .. "x" .. MENU.h .. ")") or "keins - Leiste oben"))
  print("PC #" .. os.getComputerID())
  print("Netz: " .. CFG.NETZ)
  if CFG.PASSWORT:find("^Hier%-") or CFG.NETZ:find("^Hier%-") then
    term.setTextColor(colors.orange)
    print("")
    print("Hinweis: NETZ und PASSWORT eintragen!")
  end
  term.setTextColor(colors.gray)
  print("")
  print("Strg+T = Beenden")
end

-- ---------- Hauptschleife ----------
log("Control Center gestartet", colors.cyan)
terminalInfo()
local timer = os.startTimer(1)
while true do
  local ev = { os.pullEvent() }
  local typ = ev[1]
  if typ == "rednet_message" then
    empfangen(ev[2], ev[3], ev[4])
  elseif typ == "timer" and ev[2] == timer then
    blink = not blink
    if os.clock() - letzterPunkt >= CFG.VERLAUF_TAKT then
      local m = matrixDaten()
      if m and type(m.anteil) == "number" then
        verlauf[#verlauf + 1] = m.anteil
        if #verlauf > 400 then table.remove(verlauf, 1) end
        letzterPunkt = os.clock()
      end
      for _, mx in ipairs(matrixListe()) do
        local d = mx.daten
        if mx.frisch and type(d.energie) == "number" and (d.max or 0) > 0 then
          mx.verlauf[#mx.verlauf + 1] = d.energie / d.max
          if #mx.verlauf > 400 then table.remove(mx.verlauf, 1) end
        end
      end
    end
    aufraeumen()
    alarmeBerechnen()
    local ok, err = pcall(zeichnen)
    if not ok then
      term.setTextColor(colors.red)
      print("Zeichenfehler: " .. tostring(err))
    end
    timer = os.startTimer(1)
  elseif typ == "monitor_touch" then
    beruehrt(ev[2], ev[3], ev[4])
    pcall(zeichnen)
  elseif typ == "monitor_resize" then
    -- Monitor wurde umgebaut: Puffer neu anlegen
    HAUPT = puffer(HAUPT.mon, CFG.HAUPT_SKALA)
    if MENU then MENU = puffer(MENU.mon, CFG.MENU_SKALA) end
    pcall(zeichnen)
  end
end
