-- =====================================================
--  CORVELYX // WETTER- & TAGESZENTRALE  v3
--  Liest Tageszeit, Regen, Gewitter und Mondphase
--  und funkt den Stand an das Control Center.
--
--  Steuerung OHNE Admin-Rechte ueber Celestial
--  Manipulators (Draconic Evolution):
--   - jeder Manipulator ist im Redstone-Tab auf EINE
--     Funktion eingestellt (z.B. "Stop Rain")
--   - dieser Computer gibt ihm einen Redstone-Impuls
--   - Automatik (an/aus im Control Center):
--       Regen -> klar, Gewitter -> klar, Nacht ueberspringen
--
--  Aufbau: Environment Detector + Ender Modem an zwei
--  Seiten, die Manipulatoren an die uebrigen Seiten
--  (oder ueber Redstone Integrator, siehe FUNKTIONEN).
-- =====================================================

local CFG = {
  -- Funknetz: alle eigenen Computer brauchen GLEICHEN Namen + Passwort
  NETZ      = "Hier-Netzname-Eintragen",
  PASSWORT  = "Hier-Netzpasswort-Eintragen",
  INTERVALL = 1,           -- Sekunden zwischen Sendungen

  -- Nacht = Zeit, in der Monster spawnen koennen (Ingame-Uhr)
  NACHT_AB  = 18.5,        -- 18:30
  NACHT_BIS = 5.5,         -- 05:30

  -- Welche Funktion haengt an welcher Seite?
  -- Nicht verbaute Funktionen einfach loeschen oder mit -- auskommentieren.
  -- geraet = nil  -> Seite direkt am Computer
  -- geraet = "redstoneIntegrator_0" -> Seite an einem Redstone Integrator
  -- Moegliche Funktionen:
  --   clear   = Stop Rain           rain   = Start Rain
  --   thunder = Start Thunderstorm  morgen = Skip to Sunrise
  --   mittag  = Skip to Mid-day     abend  = Skip to Sunset
  --   nacht   = Skip to Midnight
  FUNKTIONEN = {
    clear   = { seite = "left" },
    morgen  = { seite = "right" },
    rain    = { seite = "bottom" },
    thunder = { seite = "front" },
    -- mittag = { geraet = "redstoneIntegrator_0", seite = "north" },
    -- abend  = { geraet = "redstoneIntegrator_0", seite = "south" },
    -- nacht  = { geraet = "redstoneIntegrator_0", seite = "east" },
  },

  IMPULS     = 1,          -- Sekunden Redstone-Signal pro Ausloesung
  AUTO_PAUSE = 5,          -- Sekunden Pause zwischen Automatik-Aktionen
  DATEI      = "himmel.cfg",
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end

CFG.PROT_DATEN  = CFG.NETZ .. "/daten"
CFG.PROT_WETTER = CFG.NETZ .. "/wetter"

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

local MONDE = {
  [0] = "Vollmond", "Abnehmend (gross)", "Letztes Viertel", "Abnehmend (klein)",
  "Neumond", "Zunehmend (klein)", "Erstes Viertel", "Zunehmend (gross)",
}

local NAMEN = {
  clear = "Klar", rain = "Regen", thunder = "Gewitter",
  morgen = "Morgen", mittag = "Mittag", abend = "Abend", nacht = "Nacht",
  regen = "Regen -> klar", gewitter = "Gewitter -> klar",
}

-- ---------- Peripherie ----------
local det = peripheral.find("environment_detector") or peripheral.find("environmentDetector")
if not det then error("Kein Environment Detector gefunden!") end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if modem then rednet.open(peripheral.getName(modem)) end

local function p(fn, ...)
  if type(det[fn]) == "function" then
    local ok, a, b = pcall(det[fn], ...)
    if ok then return a, b end
  end
  return nil
end

-- Liste der verbauten Funktionen (fuer das Control Center)
local function verfuegbar()
  local liste = {}
  for name in pairs(CFG.FUNKTIONEN) do liste[#liste + 1] = name end
  table.sort(liste)
  return liste
end

-- ---------- Einstellungen (ueberstehen Neustart) ----------
local auto = { regen = false, gewitter = false, nacht = false }

local function laden()
  if not fs.exists(CFG.DATEI) then return end
  local f = fs.open(CFG.DATEI, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  if type(t) == "table" then
    for k in pairs(auto) do if type(t[k]) == "boolean" then auto[k] = t[k] end end
  end
end

local function speichern()
  local f = fs.open(CFG.DATEI, "w")
  f.write(textutils.serialize(auto))
  f.close()
end

local logZeilen = {}
local function log(text)
  table.insert(logZeilen, 1, textutils.formatTime(os.time(), true) .. " " .. text)
  if #logZeilen > 5 then table.remove(logZeilen) end
end

-- ---------- Redstone-Impulse ----------
local impulse = {}   -- [timerId] = funktion (zum Abschalten)

local function setzen(f, an)
  if f.geraet then
    local g = peripheral.wrap(f.geraet)
    if not g then return false, "Geraet " .. f.geraet .. " fehlt" end
    local ok, err = pcall(g.setOutput, f.seite, an)
    return ok, err
  end
  redstone.setOutput(f.seite, an)
  return true
end

local function ausloesen(name)
  local f = CFG.FUNKTIONEN[name]
  if not f then return false, NAMEN[name] .. " nicht verbaut" end
  local ok, err = setzen(f, true)
  if not ok then return false, tostring(err) end
  impulse[os.startTimer(CFG.IMPULS)] = f
  return true
end

-- ---------- Auslesen ----------
local function lesen()
  local z = {}
  z.uhr      = os.time()          -- 0.0 - 24.0
  z.tag      = os.day()
  z.nacht    = z.uhr >= CFG.NACHT_AB or z.uhr < CFG.NACHT_BIS
  z.regen    = p("isRaining") == true
  z.gewitter = p("isThunder") == true
  local id = p("getMoon")
  if type(id) ~= "number" then id = p("getMoonId") end
  z.mond     = type(id) == "number" and id or nil
  z.mondName = z.mond and MONDE[z.mond] or "?"
  z.licht    = p("getSkyLightLevel")
  z.biom     = p("getBiome")
  z.nachtAb, z.nachtBis = CFG.NACHT_AB, CFG.NACHT_BIS
  return z
end

-- ---------- Automatik ----------
local letzteAktion = -1000

local function automatik(z)
  if os.clock() - letzteAktion < CFG.AUTO_PAUSE then return end
  if (auto.gewitter and z.gewitter) or (auto.regen and z.regen) then
    if ausloesen("clear") then
      log("Auto: " .. (z.gewitter and "Gewitter" or "Regen") .. " -> klar")
      letzteAktion = os.clock()
    end
  elseif auto.nacht and z.nacht then
    if ausloesen("morgen") then
      log("Auto: Nacht uebersprungen")
      letzteAktion = os.clock()
    end
  end
end

-- ---------- Fernbefehle (wie beim Reaktor) ----------
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

local BRAUCHT = { regen = "clear", gewitter = "clear", nacht = "morgen" }

local function befehl(id, msg)
  local function antwort(ok, text)
    rednet.send(id, signieren({ typ = "antwort", ok = ok, text = text }), CFG.PROT_WETTER)
  end
  if type(msg.befehl) ~= "string" or type(msg.wert) ~= "string"
     or type(msg.nonce) ~= "string" or type(msg.sig) ~= "string" then return end
  local erwartet = sha256(CFG.PASSWORT .. "|" .. msg.befehl .. "|" .. msg.wert .. "|" .. msg.nonce)
  if not nonceEinloesen(msg.nonce) or msg.sig ~= erwartet then
    log("Abgelehnt: PC #" .. id)
    antwort(false, "Zugriff verweigert")
    return
  end

  if msg.befehl == "wetter" or msg.befehl == "zeit" then
    if not NAMEN[msg.wert] then antwort(false, "Unbekannte Funktion") return end
    local ok, err = ausloesen(msg.wert)
    if ok then log(NAMEN[msg.wert] .. " (PC #" .. id .. ")") end
    antwort(ok, ok and (NAMEN[msg.wert] .. " ausgeloest") or err)

  elseif msg.befehl == "auto" then
    local name, an = msg.wert:match("^(%w+)=([01])$")
    if not name or auto[name] == nil then antwort(false, "Unbekannte Automatik") return end
    if an == "1" and not CFG.FUNKTIONEN[BRAUCHT[name]] then
      antwort(false, "Dafuer fehlt: " .. NAMEN[BRAUCHT[name]])
      return
    end
    auto[name] = (an == "1")
    speichern()
    letzteAktion = -1000
    log(NAMEN[name] .. ": " .. (auto[name] and "AN" or "AUS"))
    antwort(true, NAMEN[name] .. ": " .. (auto[name] and "AN" or "AUS"))
  else
    antwort(false, "Unbekannter Befehl")
  end
end

-- ---------- Anzeige ----------
local function zeile(y, text, farbe)
  term.setCursorPos(1, y)
  term.setTextColor(farbe or colors.white)
  term.clearLine()
  term.write(text)
end

local function anzeigen(z)
  term.setBackgroundColor(colors.black)
  term.clear()
  zeile(1, "CORVELYX // WETTER & ZEIT", colors.cyan)
  zeile(3, "Tag " .. z.tag .. "   " .. textutils.formatTime(z.uhr, true) .. " Uhr   "
    .. (z.nacht and "NACHT" or "TAG"), z.nacht and colors.lightBlue or colors.yellow)
  local wetter = z.gewitter and "Gewitter" or (z.regen and "Regen" or "Klar")
  zeile(4, "Wetter: " .. wetter, z.gewitter and colors.red or (z.regen and colors.lightBlue or colors.lime))
  zeile(5, "Mond:   " .. z.mondName, z.mond == 0 and colors.orange or colors.white)

  local fl = {}
  for _, n in ipairs(verfuegbar()) do
    local f = CFG.FUNKTIONEN[n]
    fl[#fl + 1] = NAMEN[n] .. "=" .. (f.geraet and (f.geraet .. ":") or "") .. f.seite
  end
  zeile(7, "Manipulatoren:", colors.cyan)
  zeile(8, #fl > 0 and table.concat(fl, "  ") or "keine (nur Anzeige)", colors.lightGray)

  zeile(10, "Automatik:", colors.cyan)
  zeile(11, "  Regen -> klar     " .. (auto.regen and "AN" or "aus"), auto.regen and colors.lime or colors.gray)
  zeile(12, "  Gewitter -> klar  " .. (auto.gewitter and "AN" or "aus"), auto.gewitter and colors.lime or colors.gray)
  zeile(13, "  Nacht ueberspr.   " .. (auto.nacht and "AN" or "aus"), auto.nacht and colors.lime or colors.gray)
  for i, l in ipairs(logZeilen) do zeile(13 + i, l, colors.lightGray) end
  zeile(19, "Funk: " .. (modem and "an" or "kein Ender Modem") .. "   Strg+T = Ende", colors.gray)
end

-- ---------- Hauptschleife ----------
laden()
math.randomseed(os.epoch("utc"))
for _, f in pairs(CFG.FUNKTIONEN) do pcall(setzen, f, false) end

local timer = os.startTimer(0)
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == timer then
    local z = lesen()
    automatik(z)
    anzeigen(z)
    if modem then
      z.funktionen = verfuegbar()
      z.steuerbar = #z.funktionen > 0
      z.auto = auto
      z.nonce = neueNonce()
      rednet.broadcast(signieren({ typ = "status", quelle = "wetter", daten = z }), CFG.PROT_DATEN)
    end
    timer = os.startTimer(CFG.INTERVALL)
  elseif ev[1] == "timer" and impulse[ev[2]] then
    pcall(setzen, impulse[ev[2]], false)
    impulse[ev[2]] = nil
  elseif ev[1] == "rednet_message" and ev[4] == CFG.PROT_WETTER then
    if type(ev[3]) == "table" and ev[3].befehl then befehl(ev[2], ev[3]) end
  end
end
