-- =====================================================
--  CORVELYX // POCKET  v1.7
--  Das Control Center fuer die Hosentasche.
--  Laeuft auf einem ADVANCED POCKET COMPUTER mit
--  ENDER MODEM (beides in der Werkbank kombinieren).
--
--  Hoert direkt alle Corvelyx-Sender mit:
--  Reaktor, Matrix, Turbinen, ME, Wetter, Flux.
--  Bedienung per Klick/Touch, Pfeiltasten blaettern.
-- =====================================================

local CFG = {
  LILA          = 0x9D4EDD,  -- Akzentfarbe
  -- Funknetz: alle eigenen Computer brauchen GLEICHEN Namen + Passwort
  NETZ          = "Hier-Netzname-Eintragen",
  PASSWORT      = "Hier-Netzpasswort-Eintragen",
  ZEITLIMIT     = 5,      -- Sekunden ohne Daten = "keine Verbindung"
  STROM_WARN    = 0.10,
  DAMPF_WARN    = 0.80,
  ME_WARN       = 0.90,
  LAGER_WARN    = 0.95,
  LAGER_ZEIT    = 15,
  VERGESSEN     = 600,    -- Sekunden ohne Daten = Anlage gilt als abgebaut
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
CFG.PROT_REAKTOR = CFG.NETZ .. "/reaktor"
CFG.PROT_DATEN   = CFG.NETZ .. "/daten"
CFG.PROT_WETTER  = CFG.NETZ .. "/wetter"
CFG.PROT_XTREME  = CFG.NETZ .. "/xtreme"
CFG.PROT_FUSION  = CFG.NETZ .. "/fusion"
CFG.PROT_STEUER  = CFG.NETZ .. "/steuer"
CFG.PROT_UPDATE  = CFG.NETZ .. "/update"

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


-- ---------- Funk ----------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Kein (Ender) Modem im Pocket Computer!") end
rednet.open(peripheral.getName(modem))

-- ---------- Bildschirm ----------
local W, H = term.getSize()
local win = window.create(term.current(), 1, 1, W, H, false)
win.setPaletteColour(colors.black,     0x0B0F14)
win.setPaletteColour(colors.gray,      0x1A212C)
win.setPaletteColour(colors.lightGray, 0x8592A6)
win.setPaletteColour(colors.white,     0xE6EDF3)
win.setPaletteColour(colors.cyan,      CFG.LILA)   -- Akzentfarbe (Lila)
win.setPaletteColour(colors.lime,      0x4ADE80)
win.setPaletteColour(colors.orange,    0xF5A524)
win.setPaletteColour(colors.red,       0xEF4444)
win.setPaletteColour(colors.green,     0x15803D)
win.setPaletteColour(colors.brown,     0x7F1D1D)

-- ---------- Zustand ----------
local quellen = { reaktor = {}, me = {}, wetter = {}, update = {} }
local turbinen, flux, lager, xtreme, fusion, matrizen = {}, {}, {}, {}, {}, {}
local matrixSeite = 0   -- 0 = Gesamt, sonst Nummer der Matrix
local SEITEN = { "UEBERSICHT", "FISSION", "MATRIX", "TURBINEN", "ME-SYSTEM", "WETTER", "FLUX", "LAGER", "XTREME", "FUSION",
  "MOBFARM", "BESUCHER", "UPDATES" }
local tueren, mobfarmen = {}, {}
local mobAuswahl = 1
local tuerLeeren = nil
local seite = 1
local knoepfe = {}
local alarme = {}
local meldung = nil
local bestaetigung = nil
local fluxSeite = 1
local lagerSeite, lagerSort = 1, "fuell"
local xtremeAuswahl = 1
local fusionAuswahl = 1
local fusionStopp = nil
local blink = false
local ausstehend = {}

-- ---------- Hilfen ----------
local function kurz(n, e)
  if type(n) ~= "number" then return "--" end
  local a, s = math.abs(n), nil
  if a >= 1e15 then s = string.format("%.1fP", n / 1e15)
  elseif a >= 1e12 then s = string.format("%.1fT", n / 1e12)
  elseif a >= 1e9 then s = string.format("%.1fG", n / 1e9)
  elseif a >= 1e6 then s = string.format("%.1fM", n / 1e6)
  elseif a >= 1e3 then s = string.format("%.1fk", n / 1e3)
  else s = string.format("%.0f", n) end
  return s .. (e or "")
end
local function pz(a) if type(a) ~= "number" then return "--%" end return string.format("%.0f%%", a * 100) end
local function quote(a, b) if type(a) ~= "number" or type(b) ~= "number" or b <= 0 then return nil end return a / b end
local function dauer(s)
  if type(s) ~= "number" or s ~= s or s == math.huge or s < 0 then return "--" end
  if s >= 86400 then return string.format("%.1f Tage", s / 86400) end
  if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), math.floor(s % 60)) end
  return string.format("%ds", math.floor(s))
end
local function farbe(anteil, gelb, rot, umgekehrt)
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
local function frisch(z) return z ~= nil and (os.clock() - z) < CFG.ZEITLIMIT end
local function daten(q)
  local e = quellen[q]
  if not frisch(e.zeit) or type(e.daten) ~= "table" or e.daten.fehler then return nil end
  return e.daten
end
local function melden(t, f) meldung = { text = t, farbe = f or colors.white, bis = os.clock() + 6 } end

local function fuell(x, y, w, h, f)
  if w <= 0 or h <= 0 then return end
  win.setBackgroundColor(f)
  local l = string.rep(" ", w)
  for i = 0, h - 1 do win.setCursorPos(x, y + i) win.write(l) end
end
local function schreib(x, y, s, fg, bg, maxB)
  s = tostring(s)
  if maxB and #s > maxB then s = s:sub(1, math.max(0, maxB)) end
  win.setBackgroundColor(bg or colors.black)
  win.setTextColor(fg or colors.white)
  win.setCursorPos(x, y)
  win.write(s)
end
local function rechts(xE, y, s, fg, bg) s = tostring(s) schreib(xE - #s + 1, y, s, fg, bg) end
local function zeile(y, name, wert, f) schreib(2, y, name, colors.lightGray) rechts(W - 1, y, wert, f or colors.white) end
local function balken(y, anteil, f)
  local bw = W - 2
  anteil = math.max(0, math.min(1, anteil or 0))
  local v = math.floor(bw * anteil + 0.5)
  fuell(2, y, v, 1, f)
  fuell(2 + v, y, bw - v, 1, colors.gray)
end
local function knopf(x, y, w, h, text, bg, fg, aktion)
  fuell(x, y, w, h, bg)
  schreib(x + math.max(0, math.floor((w - #text) / 2)), y + math.floor((h - 1) / 2), text, fg, bg, w)
  knoepfe[#knoepfe + 1] = { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1, aktion = aktion }
end
local function bereich(x1, y1, x2, y2, aktion)
  knoepfe[#knoepfe + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, aktion = aktion }
end

-- ---------- Turbinen / Flux zusammenfassen ----------
local function turbinenListe()
  local l = {}
  for _, e in pairs(turbinen) do e.frisch = frisch(e.zeit) l[#l + 1] = e end
  table.sort(l, function(a, b) return a.name < b.name end)
  return l
end
local function natKey(x) return (tostring(x):lower():gsub("%d+", function(d) return string.rep("0", 10 - #d) .. d end)) end
local function matrixListe()
  local l = {}
  for _, e in pairs(matrizen) do
    local d = e.daten
    e.frisch = frisch(e.zeit)
    e.ok = e.frisch and not d.fehler and type(d.energie) == "number"
    e.anteil = e.ok and quote(d.energie, d.max) or nil
    l[#l + 1] = e
  end
  table.sort(l, function(a, b) return natKey(a.name) < natKey(b.name) end)
  return l
end
-- Summe aller Matrizen (nil = keine aktuellen Daten)
local function matrixGesamt()
  local s = { energie = 0, max = 0, rein = 0, raus = 0, anzahl = 0, alle = 0 }
  for _, e in ipairs(matrixListe()) do
    s.alle = s.alle + 1
    if e.ok then
      s.anzahl = s.anzahl + 1
      s.energie = s.energie + e.daten.energie
      s.max = s.max + (e.daten.max or 0)
      s.rein = s.rein + (e.daten.rein or 0)
      s.raus = s.raus + (e.daten.raus or 0)
    end
  end
  s.anteil = s.max > 0 and s.energie / s.max or 0
  return s.anzahl > 0 and s or nil, s
end
local function turbinenSumme()
  local s = { prod = 0, max = 0, dampf = 0, an = 0, alle = 0 }
  for _, e in ipairs(turbinenListe()) do
    s.alle = s.alle + 1
    if e.frisch and not e.daten.fehler then
      s.an = s.an + 1
      s.prod = s.prod + (e.daten.produktion or 0)
      s.max = s.max + (e.daten.maxProd or 0)
      s.dampf = math.max(s.dampf, e.daten.dampf or 0)
    end
  end
  return s
end
local function fluxListe()
  local l, summe = {}, 0
  for _, s in pairs(flux) do
    local ok = frisch(s.zeit)
    for _, p in ipairs(s.plugs) do
      local r = ok and p.rate or nil
      l[#l + 1] = { name = tostring(p.name), rate = r, frisch = ok }
      summe = summe + (r or 0)
    end
  end
  table.sort(l, function(a, b) return (a.rate or -1) > (b.rate or -1) end)
  return l, summe
end

local function lagerListe()
  local l, voll = {}, 0
  for _, ls in pairs(lager) do
    local ok = (os.clock() - ls.zeit) < CFG.LAGER_ZEIT
    for _, f in ipairs(ls.faecher) do
      local q = (f.limit or 0) > 0 and f.menge / f.limit or 0
      l[#l + 1] = { name = tostring(f.name), menge = f.menge, q = q, frisch = ok }
      if q >= CFG.LAGER_WARN then voll = voll + 1 end
    end
  end
  if lagerSort == "fuell" then table.sort(l, function(a, b) if a.q ~= b.q then return a.q > b.q end return a.name < b.name end)
  else table.sort(l, function(a, b) return a.name:lower() < b.name:lower() end) end
  return l, voll
end

local function xtremeListe()
  local l = {}
  for key, x in pairs(xtreme) do
    x.key = key
    x.frisch = frisch(x.zeit)
    l[#l + 1] = x
  end
  table.sort(l, function(a, b) return a.name < b.name end)
  return l
end

local function fusionListe()
  local l = {}
  for key, x in pairs(fusion) do
    x.key = key
    x.frisch = frisch(x.zeit)
    l[#l + 1] = x
  end
  table.sort(l, function(a, b) return a.name < b.name end)
  return l
end

-- ---------- Alarme ----------
local function alarmeBerechnen()
  local l = {}
  local function add(t, s) l[#l + 1] = { text = t, stufe = s } end
  local r = quellen.reaktor
  if frisch(r.zeit) then
    if r.daten.scram then add("SCRAM: " .. tostring(r.daten.grund), 2) end
    for _, w in ipairs(r.daten.warnungen or {}) do add("Fission: " .. tostring(w), 1) end
  elseif r.zeit then add("Fission: keine Verbindung", 2) end
  local m = matrixGesamt()
  if m and m.anteil < CFG.STROM_WARN then add("Strom niedrig " .. pz(m.anteil), 2) end
  for _, e in ipairs(matrixListe()) do
    if not e.frisch then add(e.name .. ": keine Daten", 1) end
  end
  for _, e in ipairs(turbinenListe()) do
    if not e.frisch then add(e.name .. ": keine Daten", 1)
    elseif (e.daten.dampf or 0) >= CFG.DAMPF_WARN then add(e.name .. ": Dampfstau", 1) end
  end
  local me = daten("me")
  if me then
    local qi = quote(me.itemsBenutzt, me.itemsGesamt)
    if qi and qi >= CFG.ME_WARN then add("ME-Items fast voll", 1) end
  end
  for _, ls in pairs(lager) do
    if (os.clock() - ls.zeit) >= CFG.LAGER_ZEIT then add(tostring(ls.ort) .. ": keine Daten", 1) end
  end
  for _, x in ipairs(xtremeListe()) do
    local d = x.daten
    if not x.frisch then add(x.name .. ": keine Daten", 1)
    elseif d.fehler then add(x.name .. ": Fehler", 1)
    elseif type(d.brenn) == "number" and (d.brennMax or 0) > 0 and d.brenn / d.brennMax < (x.brennWarn or 0.1) then
      add(x.name .. ": Brennstoff niedrig", 1)
    end
  end
  for _, x in ipairs(fusionListe()) do
    local d = x.daten
    if not x.frisch then add(x.name .. ": keine Daten", 1)
    elseif d.fehler then add(x.name .. ": Fehler", 1)
    else
      if d.gezuendet then x.warGezuendet = true end
      if x.warGezuendet and d.gezuendet == false then add(x.name .. ": ERLOSCHEN", 2) end
      if type(d.dt) == "number" and (d.dtMax or 0) > 0 and d.dt / d.dtMax < (x.brennWarn or 0.1) then
        add(x.name .. ": D-T niedrig", 1)
      end
    end
  end
  local _, lvoll = lagerListe()
  if lvoll > 0 then add(lvoll .. " Drawer fast voll", 1) end
  table.sort(l, function(a, b) return a.stufe > b.stufe end)
  alarme = l
end

-- ---------- Befehle ----------
local function befehlSenden(ziel, befehl, wert)
  local q = quellen[ziel]
  if not frisch(q.zeit) then melden("Keine Verbindung", colors.red) return end
  local status = ziel == "reaktor" and q.daten or q.daten
  local nonce = status.nonce
  if nonce == false then
    ausstehend[ziel] = function() befehlSenden(ziel, befehl, wert) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then melden("Geraet braucht Update", colors.red) return end
  if ziel == "reaktor" then
    rednet.send(q.id, { befehl = befehl, nonce = nonce,
      sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. nonce) }, CFG.PROT_REAKTOR)
  else
    rednet.send(q.id, { befehl = befehl, wert = wert, nonce = nonce,
      sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. wert .. "|" .. nonce) }, CFG.PROT_WETTER)
  end
  status.nonce = false
  melden("Gesendet ...", colors.lightGray)
end

local function xtremeSenden(key, befehl, wert)
  local x = xtreme[key]
  if not x or not frisch(x.zeit) then melden("Keine Verbindung", colors.red) return end
  local nonce = x.daten.nonce
  if nonce == false then
    ausstehend["x:" .. key] = function() xtremeSenden(key, befehl, wert) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then melden("Geraet braucht Update", colors.red) return end
  rednet.send(x.id, { befehl = befehl, wert = wert, nonce = nonce,
    sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. wert .. "|" .. nonce) }, CFG.PROT_XTREME)
  x.daten.nonce = false
  melden("Gesendet ...", colors.lightGray)
end

local function fusionSenden(key, befehl, wert)
  local x = fusion[key]
  if not x or not frisch(x.zeit) then melden("Keine Verbindung", colors.red) return end
  local nonce = x.daten.nonce
  if nonce == false then
    ausstehend["f:" .. key] = function() fusionSenden(key, befehl, wert) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then melden("Geraet braucht Update", colors.red) return end
  rednet.send(x.id, { befehl = befehl, wert = wert, nonce = nonce,
    sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "|" .. wert .. "|" .. nonce) }, CFG.PROT_FUSION)
  x.daten.nonce = false
  melden("Gesendet ...", colors.lightGray)
end

-- Steuerbefehle an Tuer / Mobfarm (NETZ/steuer)
local function steuerSenden(liste, key, befehl)
  local x = liste[key]
  if not x or (os.clock() - x.zeit) >= 15 then melden("Keine Verbindung", colors.red) return end
  local nonce = x.daten.nonce
  if nonce == false then
    ausstehend["s:" .. key] = function() steuerSenden(liste, key, befehl) end
    melden("Wird gesendet ...", colors.lightGray)
    return
  end
  if type(nonce) ~= "string" then melden("Geraet braucht Update", colors.red) return end
  rednet.send(x.id, { befehl = befehl, wert = "", nonce = nonce,
    sig = sha256(CFG.PASSWORT .. "|" .. befehl .. "||" .. nonce) }, CFG.PROT_STEUER)
  x.daten.nonce = false
  melden("Gesendet ...", colors.lightGray)
end

-- ---------- Was ist da? / Abgebautes vergessen ----------
local function vorhanden(i)
  if i == 1 then return true end
  if i == 2 then return quellen.reaktor.zeit ~= nil end
  if i == 3 then return next(matrizen) ~= nil end
  if i == 4 then return next(turbinen) ~= nil end
  if i == 5 then return quellen.me.zeit ~= nil end
  if i == 6 then return quellen.wetter.zeit ~= nil end
  if i == 7 then return next(flux) ~= nil end
  if i == 8 then
    for _, e in pairs(lager) do
      if type(e.faecher) == "table" and #e.faecher > 0 then return true end
    end
    return false
  end
  if i == 9 then return next(xtreme) ~= nil end
  if i == 10 then return next(fusion) ~= nil end
  if i == 11 then return next(mobfarmen) ~= nil end
  if i == 12 then return next(tueren) ~= nil end
  if i == 13 then return quellen.update.zeit ~= nil end
  return true
end

local function blaettern(richtung)
  for _ = 1, #SEITEN do
    seite = (seite - 1 + richtung) % #SEITEN + 1
    if vorhanden(seite) then return end
  end
  seite = 1
end

local function aufraeumen()
  local jetzt = os.clock()
  for q, e in pairs(quellen) do
    if e.zeit and jetzt - e.zeit > CFG.VERGESSEN then quellen[q] = {} end
  end
  for _, t in ipairs({ turbinen, flux, lager, xtreme, fusion, matrizen, tueren, mobfarmen }) do
    for key, e in pairs(t) do
      if e.zeit and jetzt - e.zeit > CFG.VERGESSEN then t[key] = nil end
    end
  end
end

-- ---------- Seiten ----------
local SEITE = {}
local Y0 = 4   -- erste Inhaltszeile

SEITE[1] = function()   -- Uebersicht
  local y = Y0
  -- Wie viele Zeilen gibt es? Bei vielen Anlagen ohne Leerzeile dazwischen
  local anzahl = 0
  for i = 2, #SEITEN do if vorhanden(i) then anzahl = anzahl + 1 end end
  local abstand = (anzahl * 2 <= H - 1 - Y0) and 2 or 1
  local function eintrag(titel, text, f, ziel)
    if y > H - 1 or not vorhanden(ziel) then return end
    schreib(2, y, titel, colors.lightGray)
    rechts(W - 1, y, text, f)
    bereich(1, y, W, y, function() seite = ziel end)
    y = y + abstand
  end
  if anzahl == 0 then
    schreib(2, y, "Noch keine Anlagen", colors.lightGray)
    schreib(2, y + 1, "gemeldet.", colors.lightGray)
    y = y + 3
  end
  local r = quellen.reaktor
  local rd = frisch(r.zeit) and r.daten or nil
  if not rd then eintrag("Fission", "KEINE DATEN", colors.lightGray, 2)
  elseif rd.scram then eintrag("Fission", "SCRAM", colors.red, 2)
  elseif rd.daten and rd.daten.aktiv then eintrag("Fission", string.format("AN %.0fK", rd.daten.temp or 0), colors.lime, 2)
  else eintrag("Fission", "AUS", colors.lightGray, 2) end
  local m, ms = matrixGesamt()
  eintrag(ms.alle > 1 and ("Matrix x" .. ms.alle) or "Matrix", m and pz(m.anteil) or "--", m and farbe(m.anteil, 0.25, CFG.STROM_WARN, true) or colors.lightGray, 3)
  local ts = turbinenSumme()
  eintrag("Turbinen " .. ts.an .. "/" .. ts.alle, ts.an > 0 and kurz(ts.prod, " FE/t") or "--",
    ts.an > 0 and colors.lime or colors.lightGray, 4)
  local me = daten("me")
  local qi = me and quote(me.itemsBenutzt, me.itemsGesamt)
  eintrag("ME Items", me and pz(qi) or "--", me and farbe(qi, 0.75, CFG.ME_WARN) or colors.lightGray, 5)
  local w = daten("wetter")
  eintrag("Wetter", w and ((w.nacht and "Nacht " or "Tag ") .. (w.gewitter and "Gewitter" or (w.regen and "Regen" or "Klar"))) or "--",
    w and (w.gewitter and colors.red or (w.regen and colors.cyan or colors.lime)) or colors.lightGray, 6)
  local fl, fsum = fluxListe()
  eintrag("Flux (" .. #fl .. ")", #fl > 0 and kurz(fsum, " FE/t") or "--", #fl > 0 and colors.lime or colors.lightGray, 7)
  local xl = xtremeListe()
  if #xl > 0 then
    local an = 0
    for _, x in ipairs(xl) do if x.frisch and x.daten.aktiv then an = an + 1 end end
    eintrag("Xtreme (" .. #xl .. ")", an .. " an", an > 0 and colors.lime or colors.lightGray, 9)
  end
  local fl2 = fusionListe()
  if #fl2 > 0 then
    local an = 0
    for _, x in ipairs(fl2) do if x.frisch and x.daten.gezuendet then an = an + 1 end end
    eintrag("Fusion (" .. #fl2 .. ")", an .. " gezuendet", an > 0 and colors.lime or colors.orange, 10)
  end
  local ll, lvoll = lagerListe()
  eintrag("Lager (" .. #ll .. ")", #ll == 0 and "--" or (lvoll > 0 and (lvoll .. " fast voll") or "OK"),
    #ll == 0 and colors.lightGray or (lvoll > 0 and colors.orange or colors.lime), 8)
  -- Alarme
  if y < H - 1 then
    if #alarme == 0 then schreib(2, y, "Keine Alarme", colors.lime)
    else
      for i = 1, math.min(#alarme, H - 1 - y) do
        schreib(2, y + i - 1, alarme[i].text, alarme[i].stufe == 2 and colors.red or colors.orange, nil, W - 2)
      end
    end
  end
end

SEITE[2] = function()   -- Reaktor
  local r = quellen.reaktor
  local st = frisch(r.zeit) and r.daten or nil
  if not st then schreib(2, Y0, "Keine Verbindung", colors.lightGray) return end
  local d = st.daten or {}
  local y = Y0
  if st.scram then
    schreib(2, y, "SCRAM AKTIV", colors.red)
    schreib(2, y + 1, tostring(st.grund), colors.red, nil, W - 2)
    y = y + 2
  else
    schreib(2, y, d.aktiv and "LAEUFT" or "AUS", d.aktiv and colors.lime or colors.lightGray)
    y = y + 1
  end
  zeile(y, "Temperatur", string.format("%.0f K", d.temp or 0), farbe(d.temp or 0, 850, 1000)) y = y + 1
  zeile(y, "Kuehlmittel", pz(d.kuehl), farbe(d.kuehl, 0.8, 0.6, true)) y = y + 1
  zeile(y, "Dampf", pz(d.heiss), farbe(d.heiss, 0.5, 0.8)) y = y + 1
  zeile(y, "Atommuell", pz(d.muell), farbe(d.muell, 0.5, 0.8)) y = y + 1
  zeile(y, "Brennstoff", pz(d.brenn), farbe(d.brenn, 0.1, 0.001, true)) y = y + 1
  zeile(y, "Burn", string.format("%.0f/%.0f", d.burnIst or 0, d.burn or 0)) y = y + 2

  if bestaetigung and os.clock() > bestaetigung then bestaetigung = nil end
  local hb = math.floor((W - 3) / 2)
  if bestaetigung then
    schreib(2, y, "Wirklich STARTEN?", colors.orange)
    knopf(2, y + 1, hb, 3, "JA", colors.green, colors.white, function() bestaetigung = nil befehlSenden("reaktor", "start") end)
    knopf(3 + hb, y + 1, W - 3 - hb, 3, "NEIN", colors.gray, colors.white, function() bestaetigung = nil end)
  else
    knopf(2, y, hb, 3, "START", colors.green, colors.white, function() bestaetigung = os.clock() + 8 end)
    knopf(3 + hb, y, W - 3 - hb, 3, "STOP", colors.gray, colors.white, function() befehlSenden("reaktor", "stop") end)
    if y + 6 <= H - 1 then
      knopf(2, y + 4, W - 2, 2, "NOT-AUS", colors.red, colors.white, function() befehlSenden("reaktor", "notaus") end)
    end
  end
end

SEITE[3] = function()   -- Energie
  local l = matrixListe()
  local g, gs = matrixGesamt()
  if #l == 0 then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  if matrixSeite > #l then matrixSeite = 0 end
  if #l == 1 then matrixSeite = 1 end
  local y = Y0
  local m, titel
  if matrixSeite == 0 then
    m, titel = g, "Gesamt (" .. gs.anzahl .. "/" .. gs.alle .. ")"
  else
    local e = l[matrixSeite]
    m, titel = e.ok and e.daten or nil, e.name
    if m then m.anteil = e.anteil end
  end
  -- Umschalter: < Name >
  if #l > 1 then
    knopf(1, y, 3, 1, "<", colors.gray, colors.white, function() matrixSeite = (matrixSeite - 1) % (#l + 1) end)
    knopf(W - 2, y, 3, 1, ">", colors.gray, colors.white, function() matrixSeite = (matrixSeite + 1) % (#l + 1) end)
    local t = titel:sub(1, W - 8)
    schreib(math.floor((W - #t) / 2) + 1, y, t, colors.cyan)
    y = y + 2
  else
    schreib(2, y, titel, colors.cyan, nil, W - 2)
    y = y + 1
  end
  if not m then schreib(2, y, "Keine aktuellen Daten", colors.red) return end
  local f = farbe(m.anteil, 0.25, CFG.STROM_WARN, true)
  zeile(y, "Fuellstand", pz(m.anteil), f)
  balken(y + 1, m.anteil, f)
  zeile(y + 2, "Speicher", kurz(m.energie, "") .. "/" .. kurz(m.max, " FE"))
  zeile(y + 3, "Eingang", kurz(m.rein, " FE/t"), colors.lime)
  zeile(y + 4, "Ausgang", kurz(m.raus, " FE/t"), colors.orange)
  local netto = (m.rein or 0) - (m.raus or 0)
  zeile(y + 5, "Netto", (netto >= 0 and "+" or "") .. kurz(netto, " FE/t"), netto >= 0 and colors.lime or colors.red)
  if netto > 0 and m.max and m.energie then zeile(y + 6, "Voll in", dauer((m.max - m.energie) / netto / 20))
  elseif netto < 0 and m.energie then zeile(y + 6, "Leer in", dauer(m.energie / -netto / 20), colors.orange) end
  -- Gesamtansicht: kurze Liste aller Matrizen
  if matrixSeite == 0 then
    local ly = y + 8
    for i, e in ipairs(l) do
      if ly > H - 1 then break end
      schreib(2, ly, e.name, e.ok and colors.white or colors.red, nil, W - 9)
      rechts(W - 1, ly, e.ok and pz(e.anteil) or "--", e.ok and farbe(e.anteil, 0.25, CFG.STROM_WARN, true) or colors.red)
      knoepfe[#knoepfe + 1] = { x1 = 1, y1 = ly, x2 = W, y2 = ly, aktion = function() matrixSeite = i end }
      ly = ly + 1
    end
  end
end

SEITE[4] = function()   -- Turbinen
  local l = turbinenListe()
  if #l == 0 then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  local s = turbinenSumme()
  zeile(Y0, "Gesamt", kurz(s.prod, " FE/t"), colors.lime)
  balken(Y0 + 1, quote(s.prod, s.max), colors.lime)
  local y = Y0 + 3
  for _, e in ipairs(l) do
    if y + 2 > H - 1 then break end
    local d = e.daten
    schreib(2, y, e.name, e.frisch and colors.cyan or colors.red, nil, W - 2)
    if not e.frisch then rechts(W - 1, y, "keine Daten", colors.red)
    else
      rechts(W - 1, y, kurz(d.produktion, " FE/t"), colors.lime)
      zeile(y + 1, " Dampf", pz(d.dampf), farbe(d.dampf, 0.5, CFG.DAMPF_WARN))
    end
    y = y + 3
  end
end

SEITE[5] = function()   -- ME
  local me = daten("me")
  if not me then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  local y = Y0
  for _, z in ipairs({ { "Items", me.itemsBenutzt, me.itemsGesamt }, { "Fluids", me.fluidBenutzt, me.fluidGesamt },
                       { "Chemicals", me.chemBenutzt, me.chemGesamt } }) do
    local q = quote(z[2], z[3])
    local f = farbe(q, 0.75, CFG.ME_WARN)
    zeile(y, z[1], pz(q), f)
    schreib(2, y + 1, kurz(z[2]) .. " / " .. kurz(z[3]) .. " Bytes", colors.lightGray)
    balken(y + 2, q, f)
    y = y + 4
  end
end

SEITE[6] = function()   -- Wetter
  local w = daten("wetter")
  if not w then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  local wt = w.gewitter and "Gewitter" or (w.regen and "Regen" or "Klar")
  zeile(Y0, textutils.formatTime(w.uhr or 0, true) .. " Uhr", w.nacht and "NACHT" or "TAG", w.nacht and colors.cyan or colors.orange)
  zeile(Y0 + 1, "Wetter", wt, w.gewitter and colors.red or (w.regen and colors.cyan or colors.lime))
  zeile(Y0 + 2, "Mond", tostring(w.mondName), w.mond == 0 and colors.orange or colors.white)
  if not w.steuerbar then return end
  local da = {}
  for _, f in ipairs(w.funktionen or {}) do da[f] = true end
  local function fehlt() melden("Nicht verbaut", colors.orange) end
  local y = Y0 + 4
  local kb = math.floor((W - 4) / 3)
  local wk = { { "KLAR", "clear", colors.green }, { "REGEN", "rain", colors.cyan }, { "STURM", "thunder", colors.brown } }
  for i, k in ipairs(wk) do
    local x = 2 + (i - 1) * (kb + 1)
    local bw = (i == 3) and (W - 1 - x) or kb
    if da[k[2]] then knopf(x, y, bw, 2, k[1], k[3], k[2] == "rain" and colors.black or colors.white, function() befehlSenden("wetter", "wetter", k[2]) end)
    else knopf(x, y, bw, 2, k[1], colors.gray, colors.lightGray, fehlt) end
  end
  y = y + 3
  local zk = { { "MORGEN", "morgen" }, { "MITTAG", "mittag" }, { "ABEND", "abend" }, { "NACHT", "nacht" } }
  local zb = math.floor((W - 3) / 2)
  for i, k in ipairs(zk) do
    local x = (i % 2 == 1) and 2 or (3 + zb)
    local yy = y + math.floor((i - 1) / 2) * 2
    local bw = (i % 2 == 1) and zb or (W - 2 - zb)
    if da[k[2]] then knopf(x, yy, bw, 1, k[1], colors.cyan, colors.black, function() befehlSenden("wetter", "zeit", k[2]) end)
    else knopf(x, yy, bw, 1, k[1], colors.gray, colors.lightGray, fehlt) end
  end
  y = y + 4
  local auto = w.auto or {}
  for _, k in ipairs({ { "Regen->klar", "regen", "clear" }, { "Gewitter->klar", "gewitter", "clear" }, { "Nacht skip", "nacht", "morgen" } }) do
    if y > H - 1 then break end
    local an, moeglich = auto[k[2]] == true, da[k[3]] == true
    schreib(2, y, k[1], moeglich and colors.white or colors.gray)
    local pill = not moeglich and " -- " or (an and " AN " or " AUS")
    schreib(W - #pill, y, pill, colors.black, an and colors.lime or colors.lightGray)
    bereich(1, y, W, y, moeglich and function() befehlSenden("wetter", "auto", k[2] .. "=" .. (an and "0" or "1")) end or fehlt)
    y = y + 1
  end
end

SEITE[7] = function()   -- Flux
  local l, summe = fluxListe()
  if #l == 0 then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  zeile(Y0, "Gesamt", kurz(summe, " FE/t"), colors.lime)
  local proSeite = H - Y0 - 4
  local seiten = math.max(1, math.ceil(#l / proSeite))
  if fluxSeite > seiten then fluxSeite = seiten end
  for i = 1, proSeite do
    local p = l[(fluxSeite - 1) * proSeite + i]
    if not p then break end
    local y = Y0 + 1 + i
    schreib(2, y, p.name, p.frisch and colors.white or colors.red, nil, W - 11)
    rechts(W - 1, y, p.frisch and kurz(p.rate) or "--", (p.rate or 0) > 0 and colors.lime or colors.lightGray)
  end
  local fy = H - 2
  knopf(2, fy, 5, 1, "<", fluxSeite > 1 and colors.cyan or colors.gray, colors.black,
    function() if fluxSeite > 1 then fluxSeite = fluxSeite - 1 end end)
  local t = fluxSeite .. "/" .. seiten
  schreib(math.floor((W - #t) / 2) + 1, fy, t, colors.lightGray)
  knopf(W - 5, fy, 5, 1, ">", fluxSeite < seiten and colors.cyan or colors.gray, colors.black,
    function() if fluxSeite < seiten then fluxSeite = fluxSeite + 1 end end)
end

SEITE[8] = function()   -- Lager
  local l, voll = lagerListe()
  if #l == 0 then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  zeile(Y0, #l .. " Faecher", voll > 0 and (voll .. " fast voll") or "alles OK", voll > 0 and colors.orange or colors.lime)
  local proSeite = H - Y0 - 4
  local seiten = math.max(1, math.ceil(#l / proSeite))
  if lagerSeite > seiten then lagerSeite = seiten end
  for i = 1, proSeite do
    local f = l[(lagerSeite - 1) * proSeite + i]
    if not f then break end
    local y = Y0 + 1 + i
    local fb = not f.frisch and colors.red or farbe(f.q, 0.80, CFG.LAGER_WARN)
    schreib(2, y, f.name, f.frisch and colors.white or colors.red, nil, W - 9)
    rechts(W - 1, y, string.format("%.0f%%", f.q * 100), fb)
  end
  local fy = H - 2
  knopf(2, fy, 3, 1, "<", lagerSeite > 1 and colors.cyan or colors.gray, colors.black,
    function() if lagerSeite > 1 then lagerSeite = lagerSeite - 1 end end)
  local st = lagerSort == "fuell" and "Fuellst." or "Name"
  knopf(6, fy, W - 11, 1, lagerSeite .. "/" .. seiten .. " " .. st, colors.gray, colors.white,
    function() lagerSort = lagerSort == "fuell" and "name" or "fuell" lagerSeite = 1 end)
  knopf(W - 3, fy, 3, 1, ">", lagerSeite < seiten and colors.cyan or colors.gray, colors.black,
    function() if lagerSeite < seiten then lagerSeite = lagerSeite + 1 end end)
end

SEITE[9] = function()   -- Extreme Reactors
  local l = xtremeListe()
  if #l == 0 then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  if xtremeAuswahl > #l then xtremeAuswahl = 1 end
  local e = l[xtremeAuswahl]
  local d = e.daten or {}
  -- Name antippen = naechster Reaktor
  local titel = (#l > 1 and "< " or "") .. e.name .. (#l > 1 and (" " .. xtremeAuswahl .. "/" .. #l .. " >") or "")
  knopf(1, Y0, W, 1, titel, colors.gray, colors.cyan, function() xtremeAuswahl = xtremeAuswahl % #l + 1 end)
  local y = Y0 + 1
  if not e.frisch then schreib(2, y, "Keine aktuellen Daten", colors.red) return end
  if d.fehler then schreib(2, y, tostring(d.fehler), colors.red, nil, W - 2) return end
  zeile(y, d.aktiv and "LAEUFT" or "AUS", d.aktivKuehl and "aktiv" or "passiv", d.aktiv and colors.lime or colors.lightGray)
  y = y + 1
  if d.aktivKuehl then
    zeile(y, "Dampf", kurz(d.dampfProd, " mB/t"), colors.lime)
  else
    local q = quote(d.energie, d.kapazitaet)
    zeile(y, "Speicher", pz(q), colors.lime)
    balken(y + 1, q, colors.lime)
    y = y + 1
    zeile(y + 1, "Produktion", kurz(d.prod, " FE/t"), colors.lime)
  end
  y = y + 2
  local qb = quote(d.brenn, d.brennMax)
  zeile(y, "Brennstoff", pz(qb), farbe(qb, 0.25, e.brennWarn or 0.1, true)) y = y + 1
  zeile(y, "Abfall", kurz(d.abfall, " mB"), colors.orange) y = y + 1
  zeile(y, "Temperatur", string.format("%.0f C", d.tempBrenn or 0)) y = y + 1
  zeile(y, "Staebe", tostring(d.staebe or "--") .. " %", colors.cyan) y = y + 2

  local hb = math.floor((W - 3) / 2)
  knopf(2, y, hb, 1, "AN", colors.green, colors.white, function() xtremeSenden(e.key, "an", "") end)
  knopf(3 + hb, y, W - 3 - hb, 1, "AUS", colors.gray, colors.white, function() xtremeSenden(e.key, "aus", "") end)
  y = y + 2
  local kb = math.floor((W - 5) / 4)
  for i, sch in ipairs({ -10, -1, 1, 10 }) do
    local x = 2 + (i - 1) * (kb + 1)
    local w = (i == 4) and (W - x) or kb
    knopf(x, y, w, 1, (sch > 0 and "+" or "") .. sch, colors.cyan, colors.black, function()
      xtremeSenden(e.key, "stab", tostring(math.max(0, math.min(100, (d.staebe or 0) + sch))))
    end)
  end
  y = y + 2
  if y <= H - 2 then
    local an = d.auto == true
    schreib(2, y, "Automatik", colors.white)
    local pill = an and " AN " or " AUS"
    schreib(W - #pill, y, pill, colors.black, an and colors.lime or colors.lightGray)
    bereich(1, y, W, y, function() xtremeSenden(e.key, "auto", an and "0" or "1") end)
  end
end

SEITE[10] = function()   -- Mekanism-Fusion
  local l = fusionListe()
  if #l == 0 then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  if fusionAuswahl > #l then fusionAuswahl = 1 end
  local e = l[fusionAuswahl]
  local d = e.daten or {}
  local titel = (#l > 1 and "< " or "") .. e.name .. (#l > 1 and (" " .. fusionAuswahl .. "/" .. #l .. " >") or "")
  knopf(1, Y0, W, 1, titel, colors.gray, colors.cyan, function()
    fusionAuswahl = fusionAuswahl % #l + 1
    fusionStopp = nil
  end)
  local y = Y0 + 1
  if not e.frisch then schreib(2, y, "Keine aktuellen Daten", colors.red) return end
  if d.fehler then schreib(2, y, tostring(d.fehler), colors.red, nil, W - 2) return end
  zeile(y, d.gezuendet and "GEZUENDET" or "AUS (Laser)", "", d.gezuendet and colors.lime or colors.orange) y = y + 1
  zeile(y, "Plasma", kurz(d.plasma, " K"), farbe(quote(d.plasma, d.plasmaMax), 0.85, 0.95)) y = y + 1
  zeile(y, "Gehaeuse", kurz(d.gehaeuse, " K"), farbe(quote(d.gehaeuse, d.gehaeuseMax), 0.85, 0.95)) y = y + 1
  zeile(y, "Produktion", kurz(d.prod, " FE/t"), colors.lime) y = y + 1
  zeile(y, "D-T", pz(quote(d.dt, d.dtMax)), farbe(quote(d.dt, d.dtMax), 0.25, e.brennWarn or 0.1, true)) y = y + 1
  zeile(y, "Injection", tostring(d.rate or "--") .. " (min " .. tostring(d.rateMin or "?") .. ")", colors.cyan) y = y + 2

  local kb = math.floor((W - 5) / 4)
  for i, sch in ipairs({ -10, -2, 2, 10 }) do
    local x = 2 + (i - 1) * (kb + 1)
    local w = (i == 4) and (W - x) or kb
    knopf(x, y, w, 1, (sch > 0 and "+" or "") .. sch, colors.cyan, colors.black, function()
      fusionSenden(e.key, "rate", tostring(math.max(0, math.min(98, (d.rate or 0) + sch))))
    end)
  end
  y = y + 2
  local an = d.auto == true
  schreib(2, y, "Automatik", colors.white)
  local pill = an and " AN " or " AUS"
  schreib(W - #pill, y, pill, colors.black, an and colors.lime or colors.lightGray)
  bereich(1, y, W, y, function() fusionSenden(e.key, "auto", an and "0" or "1") end)
  y = y + 2
  if fusionStopp and (os.clock() > fusionStopp.bis or fusionStopp.key ~= e.key) then fusionStopp = nil end
  if y <= H - 2 then
    if fusionStopp then
      local hb = math.floor((W - 3) / 2)
      knopf(2, y, hb, 1, "JA STOPP", colors.red, colors.white, function() fusionStopp = nil fusionSenden(e.key, "stopp", "") end)
      knopf(3 + hb, y, W - 3 - hb, 1, "NEIN", colors.gray, colors.white, function() fusionStopp = nil end)
    else
      knopf(2, y, W - 2, 1, "STOPP (erlischt!)", colors.brown, colors.white,
        function() fusionStopp = { key = e.key, bis = os.clock() + 8 } end)
    end
  end
end

SEITE[11] = function()   -- Mobfarmen
  local l = {}
  for key, m in pairs(mobfarmen) do m.key = key l[#l + 1] = m end
  table.sort(l, function(a, b) return a.name < b.name end)
  if #l == 0 then schreib(2, Y0, "Keine Daten", colors.lightGray) return end
  if mobAuswahl > #l then mobAuswahl = 1 end
  local m = l[mobAuswahl]
  local d = m.daten
  local titel = (#l > 1 and "< " or "") .. m.name .. (#l > 1 and (" " .. mobAuswahl .. "/" .. #l .. " >") or "")
  knopf(1, Y0, W, 1, titel, colors.gray, colors.cyan, function() mobAuswahl = mobAuswahl % #l + 1 end)
  local y = Y0 + 2
  local ok = (os.clock() - m.zeit) < 15
  if not ok then schreib(2, y, "Keine Verbindung", colors.red) return end
  schreib(2, y, d.an and "AN - Farmen laufen" or "AUS - Farmen gestoppt", d.an and colors.lime or colors.lightGray)
  y = y + 1
  if d.seit then schreib(2, y, "Seit " .. tostring(d.seit), colors.lightGray, nil, W - 2) y = y + 1 end
  if d.wer then schreib(2, y, "(" .. tostring(d.wer) .. ")", colors.lightGray, nil, W - 2) end
  y = y + 2
  local key = m.key
  if d.an then
    knopf(2, y, W - 2, 3, "AUSSCHALTEN", colors.gray, colors.white, function() steuerSenden(mobfarmen, key, "aus") end)
  else
    knopf(2, y, W - 2, 3, "EINSCHALTEN", colors.green, colors.white, function() steuerSenden(mobfarmen, key, "an") end)
  end
end

SEITE[12] = function()   -- Betretungslog
  local alle, heute = {}, 0
  for _, tu in pairs(tueren) do
    heute = heute + (tu.daten.heute or 0)
    for _, e in ipairs(type(tu.daten.eintraege) == "table" and tu.daten.eintraege or {}) do alle[#alle + 1] = e end
  end
  table.sort(alle, function(a, b) return (a.zeit or 0) > (b.zeit or 0) end)
  schreib(2, Y0, "Heute: " .. heute, colors.lightGray)
  if tuerLeeren and os.clock() > tuerLeeren then tuerLeeren = nil end
  if tuerLeeren then
    knopf(W - 11, Y0, 5, 1, "JA", colors.red, colors.white, function()
      tuerLeeren = nil
      for key in pairs(tueren) do steuerSenden(tueren, key, "leeren") end
    end)
    knopf(W - 5, Y0, 5, 1, "NEIN", colors.gray, colors.white, function() tuerLeeren = nil end)
    schreib(2, Y0 + 1, "Log wirklich l\246schen?", colors.orange)
  else
    knopf(W - 8, Y0, 8, 1, "LEEREN", colors.gray, colors.white, function() tuerLeeren = os.clock() + 8 end)
  end
  if #alle == 0 then schreib(2, Y0 + 3, "Noch niemand Fremdes", colors.lime) schreib(2, Y0 + 4, "durch die T\252r.", colors.lime) return end
  for i, e in ipairs(alle) do
    local y = Y0 + 1 + i
    if y > H - 2 then break end
    local zeit = tostring(e.datum or ""):sub(1, 6) .. " " .. tostring(e.uhr or ""):sub(1, 5)
    schreib(1, y, zeit, colors.lightGray)
    schreib(14, y, tostring(e.spieler), i == 1 and colors.orange or colors.white, nil, W - 13)
  end
end

SEITE[13] = function()   -- Updates
  local up = quellen.update
  local d = up.daten or {}
  local ok = up.zeit and (os.clock() - up.zeit) < 30
  local y = Y0
  if not ok then schreib(2, y, "Update-Computer:", colors.red) schreib(2, y + 1, "keine Verbindung", colors.red)
  elseif d.fehler then schreib(2, y, "Fehler:", colors.red) schreib(2, y + 1, tostring(d.fehler), colors.red, nil, W - 2)
  else
    zeile(y, "Programme", tostring(d.anzahl or "?"), colors.lime)
    if d.letzte then zeile(y + 1, "Gepr\252ft vor", math.max(0, math.floor((os.epoch("utc") - d.letzte) / 60000)) .. " min") end
  end
  y = y + 3
  if type(d.zuletzt) == "table" and #d.zuletzt > 0 then
    schreib(2, y, "Zuletzt verteilt:", colors.lightGray) y = y + 1
    for _, n in ipairs(d.zuletzt) do
      if y > H - 6 then break end
      schreib(3, y, n, colors.white, nil, W - 3) y = y + 1
    end
  end
  knopf(2, H - 5, W - 2, 3, "UPDATE", colors.cyan, colors.black, function()
    rednet.broadcast(signieren({ typ = "pruefen" }), CFG.PROT_UPDATE)
    melden("Update-Pr\252fung angefordert", colors.cyan)
  end)
end

-- ---------- Rahmen ----------
local function zeichnen()
  knoepfe = {}
  win.setVisible(false)
  fuell(1, 1, W, H, colors.black)
  -- Kopf
  fuell(1, 1, W, 1, colors.gray)
  schreib(2, 1, "CORVELYX", colors.cyan, colors.gray)
  local w = daten("wetter")
  rechts(W - 1, 1, textutils.formatTime(w and w.uhr or os.time(), true), colors.white, colors.gray)
  -- Seitenwahl
  if not vorhanden(seite) then seite = 1 end
  knopf(1, 2, 3, 1, "<", colors.black, colors.cyan, function() blaettern(-1) end)
  knopf(W - 2, 2, 3, 1, ">", colors.black, colors.cyan, function() blaettern(1) end)
  local titel = SEITEN[seite]
  schreib(math.floor((W - #titel) / 2) + 1, 2, titel, colors.white)
  -- Inhalt
  local ok, err = pcall(SEITE[seite])
  if not ok then schreib(2, Y0, "Fehler: " .. tostring(err), colors.red, nil, W - 2) end
  -- Meldung
  if meldung and os.clock() > meldung.bis then meldung = nil end
  if meldung then fuell(1, H - 1, W, 1, colors.black) schreib(2, H - 1, meldung.text, meldung.farbe, nil, W - 2) end
  -- Alarmleiste
  local rot = #alarme > 0 and alarme[1].stufe == 2
  local bg = #alarme == 0 and colors.green or (rot and (blink and colors.red or colors.brown) or colors.orange)
  knopf(1, H, W, 1, #alarme == 0 and "SYSTEM OK" or ("! " .. #alarme .. " ALARM" .. (#alarme > 1 and "E" or "")),
    bg, colors.white, function() seite = 1 end)
  win.setVisible(true)
end

-- ---------- Empfang ----------
local function empfangen(id, roh, prot)
  if prot ~= CFG.PROT_REAKTOR and prot ~= CFG.PROT_DATEN and prot ~= CFG.PROT_WETTER
     and prot ~= CFG.PROT_XTREME and prot ~= CFG.PROT_FUSION and prot ~= CFG.PROT_STEUER then return end
  local msg = auspacken(id, roh)
  if not msg then return end
  if msg.typ == "antwort" then
    melden(tostring(msg.text), msg.ok and colors.lime or colors.red)
    return
  end
  if msg.typ ~= "status" then return end
  if prot == CFG.PROT_REAKTOR then
    quellen.reaktor = { daten = msg, zeit = os.clock(), id = id }
    if ausstehend.reaktor then local f = ausstehend.reaktor ausstehend.reaktor = nil f() end
  elseif msg.quelle == "matrix" and type(msg.daten) == "table" then
    local k = tostring(msg.schluessel or id)
    local n = msg.name
    if not n or n == "matrix" then n = "Matrix PC" .. id end
    matrizen[k] = { daten = msg.daten, zeit = os.clock(), name = tostring(n) }
  elseif msg.quelle == "turbine" and type(msg.daten) == "table" then
    local k = tostring(msg.schluessel or id)
    turbinen[k] = { daten = msg.daten, zeit = os.clock(), name = tostring(msg.name or ("Turbine PC" .. id)) }
  elseif msg.quelle == "fusion" and type(msg.daten) == "table" then
    local key = tostring(msg.schluessel or id)
    local alt = fusion[key]
    fusion[key] = { name = tostring(msg.name or ("Fusion PC" .. id)), daten = msg.daten, zeit = os.clock(),
      id = id, brennWarn = msg.brennWarn, warGezuendet = alt and alt.warGezuendet }
    if ausstehend["f:" .. key] then local f = ausstehend["f:" .. key] ausstehend["f:" .. key] = nil f() end
  elseif msg.quelle == "xtreme" and type(msg.daten) == "table" then
    local key = tostring(msg.schluessel or id)
    xtreme[key] = { name = tostring(msg.name or ("Xtreme PC" .. id)), daten = msg.daten, zeit = os.clock(),
      id = id, brennWarn = msg.brennWarn }
    if ausstehend["x:" .. key] then local f = ausstehend["x:" .. key] ausstehend["x:" .. key] = nil f() end
  elseif (msg.quelle == "tuer" or msg.quelle == "mobfarm") and type(msg.daten) == "table" then
    local key = tostring(msg.schluessel or id)
    local liste = msg.quelle == "tuer" and tueren or mobfarmen
    liste[key] = { name = tostring(msg.name or ("PC" .. id)), daten = msg.daten, zeit = os.clock(), id = id }
    if ausstehend["s:" .. key] then local f = ausstehend["s:" .. key] ausstehend["s:" .. key] = nil f() end
  elseif msg.quelle == "lager" and type(msg.faecher) == "table" then
    lager[tostring(msg.schluessel or id)] = { ort = msg.ort or ("PC" .. id), faecher = msg.faecher, zeit = os.clock() }
  elseif msg.quelle == "flux" and type(msg.plugs) == "table" then
    flux[tostring(msg.schluessel or id)] = { plugs = msg.plugs, zeit = os.clock() }
  elseif quellen[msg.quelle] and msg.quelle ~= "reaktor" and type(msg.daten) == "table" then
    quellen[msg.quelle] = { daten = msg.daten, zeit = os.clock(), id = id }
    if msg.quelle == "wetter" and ausstehend.wetter then local f = ausstehend.wetter ausstehend.wetter = nil f() end
  end
end

-- ---------- Hauptschleife ----------
local timer = os.startTimer(0)
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "rednet_message" then
    empfangen(ev[2], ev[3], ev[4])
  elseif ev[1] == "timer" and ev[2] == timer then
    blink = not blink
    aufraeumen()
    alarmeBerechnen()
    zeichnen()
    timer = os.startTimer(1)
  elseif ev[1] == "mouse_click" then
    local x, y = ev[3], ev[4]
    for i = #knoepfe, 1, -1 do
      local k = knoepfe[i]
      if x >= k.x1 and x <= k.x2 and y >= k.y1 and y <= k.y2 then k.aktion() break end
    end
    zeichnen()
  elseif ev[1] == "mouse_scroll" and (seite == 7 or seite == 8) then
    if seite == 7 then fluxSeite = math.max(1, fluxSeite + ev[2]) else lagerSeite = math.max(1, lagerSeite + ev[2]) end
    zeichnen()
  elseif ev[1] == "key" then
    if ev[2] == keys.left then blaettern(-1) zeichnen()
    elseif ev[2] == keys.right then blaettern(1) zeichnen() end
  end
end
