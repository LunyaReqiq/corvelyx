-- =====================================================
--  CORVELYX // LADER  v1
--  Laeuft als startup.lua auf JEDEM Corvelyx-Computer.
--  Holt beim Start die aktuelle Version seines Programms
--  vom Update-Computer und startet es. Kommt spaeter ein
--  Update, startet der Computer automatisch neu.
--
--  Einstellungen stehen in "corvelyx.cfg" (nicht hier!).
--  Ersteinrichtung: Datei auf den Computer ziehen und
--  "lader" eintippen - oder direkt im Spiel:
--  wget run https://raw.githubusercontent.com/LunyaReqiq/corvelyx/main/programme/lader.lua
-- =====================================================
local LADER_VERSION = "6"
local CFG_DATEI  = "corvelyx.cfg"
local LADER_URL  = "https://raw.githubusercontent.com/LunyaReqiq/corvelyx/main/programme/lader.lua"
local ORDNER     = "corvelyx"
local UPDATE_SERVER = "update_server.lua"
local LILA = 0x9D4EDD   -- Corvelyx-Akzentfarbe (ersetzt Blau/Cyan auf dem Bildschirm)

-- Programme: Datei, Erkennung im Kopf der alten Datei, Beschreibung
local PROGRAMME = {
  { "corvelyx_cc.lua",      "CORVELYX // CONTROL CENTER", "Control Center (Monitore)" },
  { "corvelyx_pocket.lua",  "CORVELYX // POCKET",         "Pocket Computer" },
  { "reaktor_waechter.lua", "CORVELYX // REAKTOR-WAECHTER", "Fission-Waechter" },
  { "fusion_reaktor.lua",   "CORVELYX // FUSION-REAKTOR", "Fusion-Reaktor" },
  { "xtreme_reaktor.lua",   "CORVELYX // XTREME-REAKTOR", "Extreme Reactors" },
  { "corvelyx_sender.lua",  "CORVELYX // SENDER",         "Sender (Matrix, Turbine, ME)" },
  { "flux_sender.lua",      "CORVELYX // FLUX-SENDER",    "Flux-Sender" },
  { "lager_sender.lua",     "CORVELYX // LAGER-SENDER",   "Lager-Sender" },
  { "corvelyx_wetter.lua",  "CORVELYX // WETTER",         "Wetter-PC" },
  { UPDATE_SERVER,          "CORVELYX // UPDATE-SERVER",  "Update-Computer (GitHub)" },
  { "tuer_sender.lua",      "CORVELYX // TUER-SENDER",    "Betretungslog (Player Detector)" },
  { "mobfarm.lua",          "CORVELYX // MOBFARM",        "Mobfarm-Schalter (Redstone)" },
  { "laser_zuender.lua",    "CORVELYX // LASER-ZUENDER",  "Laser-Z\252nder (Fusion)" },
}
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

-- ---------- Hilfen ----------
local function lesen(pfad)
  if not fs.exists(pfad) then return nil end
  local f = fs.open(pfad, "rb")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local function schreiben(pfad, inhalt)
  local tmp = pfad .. ".neu"
  local f = fs.open(tmp, "wb")
  f.write(inhalt)
  f.close()
  if fs.exists(pfad) then fs.delete(pfad) end
  fs.move(tmp, pfad)
end

local function farbe(f) if term.isColor() then term.setTextColor(f) end end
local function meldung(text, f) farbe(f or colors.white) print(text) farbe(colors.white) end

local function gleich(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not gleich(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Liest die Tabelle "local CFG = { ... }" aus einem Programmtext
local function cfgAus(text)
  if type(text) ~= "string" then return nil end
  local a = text:find("local CFG = {", 1, true)
  if not a then return nil end
  local i = text:find("{", a, true)
  local tiefe, n = 0, #text
  local p = i
  while p <= n do
    local c = text:sub(p, p)
    if c == "-" and text:sub(p, p + 1) == "--" then
      local e = text:find("\n", p, true) or n
      p = e
    elseif c == '"' or c == "'" then
      local q = p + 1
      while q <= n do
        local d = text:sub(q, q)
        if d == "\\" then q = q + 1 elseif d == c then break end
        q = q + 1
      end
      p = q
    elseif c == "{" then tiefe = tiefe + 1
    elseif c == "}" then
      tiefe = tiefe - 1
      if tiefe == 0 then
        local env = { colors = colors, colours = colours, keys = keys, math = math }
        local fn = load("return " .. text:sub(i, p), "cfg", "t", env)
        if not fn then return nil end
        local ok, t = pcall(fn)
        return ok and type(t) == "table" and t or nil
      end
    end
    p = p + 1
  end
  return nil
end

local function cfgSpeichern(cfg)
  local f = fs.open(CFG_DATEI, "w")
  f.write("-- CORVELYX Einstellungen (bleiben bei Updates erhalten)\n")
  f.write(textutils.serialize(cfg))
  f.close()
end

-- (Kommentarzeile vorne wird ignoriert)
local function cfgLaden()
  local s = lesen(CFG_DATEI)
  if not s then return nil end
  s = s:gsub("^%-%-[^\n]*\n", "")
  local t = textutils.unserialize(s)
  return type(t) == "table" and t or nil
end

-- ---------- Signatur (gleiches Verfahren wie alle Corvelyx-Programme) ----------
local CFG = {}
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
  local key = id .. "/" .. tostring(inhalt.typ)
  if letzteZeit[key] and msg.t < letzteZeit[key] then return nil end
  letzteZeit[key] = msg.t
  return inhalt
end

local function modemOeffnen()
  local m = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not m then return false end
  rednet.open(peripheral.getName(m))
  return true
end

-- Fragt den Update-Computer nach einer Datei. Rueckgabe:
--   "aktuell" | "neu", inhalt, hash | "unbekannt" | nil (keine Antwort)
local function nachfragen(datei, hash)
  local prot = CFG.NETZ .. "/update"
  for versuch = 1, 3 do
    local nonce = tostring(os.epoch("utc")) .. "-" .. math.random(100000, 999999)
    rednet.broadcast(signieren({ typ = "frage", datei = datei, hash = hash, nonce = nonce }), prot)
    local ende = os.clock() + 2
    while os.clock() < ende do
      local id, msg = rednet.receive(prot, ende - os.clock())
      if id then
        local a = auspacken(id, msg)
        if a and a.typ == "antwort" and a.nonce == nonce and a.datei == datei then
          if a.status == "neu" then
            if type(msg.inhalt) == "string" and sha256(msg.inhalt) == a.hash then
              return "neu", msg.inhalt, a.hash
            end
          else
            return a.status
          end
        end
      end
    end
  end
  return nil
end

-- ---------- GitHub (nur Einrichtung des Update-Computers) ----------
local function github(cfg, datei)
  local pfad = (cfg.ORDNER and cfg.ORDNER ~= "") and (cfg.ORDNER .. "/" .. datei) or datei
  local url = "https://api.github.com/repos/" .. cfg.GITHUB_BENUTZER .. "/" .. cfg.REPO
    .. "/contents/" .. pfad .. "?ref=" .. (cfg.BRANCH or "main")
  local kopf = { Accept = "application/vnd.github.raw", ["User-Agent"] = "Corvelyx" }
  if cfg.TOKEN and cfg.TOKEN ~= "" then kopf.Authorization = "Bearer " .. cfg.TOKEN end
  local r, err, fr = http.get(url, kopf, true)
  if not r then
    local code = fr and fr.getResponseCode() or nil
    if fr then fr.close() end
    return nil, code and ("GitHub antwortet " .. code) or tostring(err)
  end
  local s = r.readAll()
  r.close()
  return s
end

-- ---------- Ersteinrichtung ----------
local function fragen(text, vorgabe, verdeckt)
  farbe(colors.yellow) write(text) farbe(colors.white)
  if vorgabe then farbe(colors.lightGray) write(" [" .. vorgabe .. "]") farbe(colors.white) end
  write(": ")
  local a = read(verdeckt and "*" or nil)
  if a == "" then a = vorgabe end
  return a
end

local function einrichten()
  term.clear() term.setCursorPos(1, 1)
  meldung("CORVELYX // EINRICHTUNG", colors.cyan)
  print("")
  local alt = lesen("startup.lua")
  local selbst = shell and shell.getRunningProgram() or "lader.lua"
  local programm, altCfg
  if alt and not alt:find("CORVELYX // LADER", 1, true) then
    for _, p in ipairs(PROGRAMME) do
      if alt:find(p[2], 1, true) then programm = p[1] break end
    end
    altCfg = cfgAus(alt)
  end
  if programm then
    meldung("Gefunden: " .. programm, colors.lime)
    if altCfg then meldung("Deine Einstellungen werden uebernommen.", colors.lime) end
  else
    print("Welches Programm soll dieser Computer haben?")
    for i, p in ipairs(PROGRAMME) do print(string.format(" %2d  %s", i, p[3])) end
    while not programm do
      local n = tonumber(fragen("Nummer"))
      if n and PROGRAMME[n] then programm = PROGRAMME[n][1] end
    end
  end

  local cfg = {}
  if altCfg then for k, v in pairs(altCfg) do cfg[k] = v end end
  cfg.PROGRAMM = programm
  if not altCfg or not altCfg.NETZ or altCfg.NETZ:find("Hier%-") then
    cfg.NETZ = fragen("Netzname")
    cfg.PASSWORT = fragen("Passwort", nil, true)
  end
  if not altCfg then
    if programm == "corvelyx_sender.lua" or programm == "fusion_reaktor.lua" or programm == "xtreme_reaktor.lua" then
      local n = fragen("Name (z.B. Matrix 1, leer = automatisch)")
      cfg.NAME = (n and n ~= "") and n or nil
    end
  end
  if programm == "laser_zuender.lua" and not altCfg then
    cfg.NAME = fragen("Name (Laser 1 geh\246rt zu Fusion 1)", "Laser 1")
  end
  if programm == "mobfarm.lua" and not altCfg then
    cfg.NAME = fragen("Name (wie im Control Center)", "Mobfarmen")
    local s
    repeat
      s = fragen("Seite zum Redstone Link (top/bottom/left/right/front/back)", "back")
    until s == "top" or s == "bottom" or s == "left" or s == "right" or s == "front" or s == "back"
    cfg.SEITE = s
  end
  if programm == "tuer_sender.lua" and not altCfg then
    cfg.NAME = fragen("Name der T\252r", "Haust\252r")
    local t = fragen("Team-Spieler (werden NICHT geloggt), mit Komma getrennt")
    cfg.TEAM = {}
    for roh in tostring(t or ""):gmatch("[^,]+") do
      local n = roh:gsub("^%s+", ""):gsub("%s+$", "")
      if n ~= "" then cfg.TEAM[#cfg.TEAM + 1] = n end
    end
  end
  if programm == UPDATE_SERVER then
    print("")
    meldung("GitHub-Zugang (nur auf diesem Computer!)", colors.cyan)
    cfg.GITHUB_BENUTZER = fragen("GitHub-Benutzername", "LunyaReqiq")
    cfg.REPO   = fragen("Repo-Name", "corvelyx")
    cfg.BRANCH = fragen("Branch", "main")
    cfg.ORDNER = fragen("Ordner im Repo", "programme")
    cfg.TOKEN  = fragen("Token (leer lassen, wenn das Repo \246ffentlich ist)", nil, true) or ""
  end
  cfg._ABGLEICH = altCfg and true or nil   -- nur geaenderte Werte behalten, sobald neue Version da ist

  fs.makeDir(ORDNER)
  if alt and programm ~= UPDATE_SERVER and not alt:find("CORVELYX // LADER", 1, true) then
    schreiben(ORDNER .. "/" .. programm, alt)      -- alte Version als Notfall-Kopie
    schreiben("startup_alt.lua", alt)
  end
  CFG = cfg
  if programm == UPDATE_SERVER then
    meldung("Lade Update-Server von GitHub ...", colors.lightGray)
    local s, err = github(cfg, UPDATE_SERVER)
    if not s then
      meldung("Fehler: " .. tostring(err), colors.red)
      meldung("Benutzername, Repo, Ordner und Token pruefen.", colors.red)
      meldung("Nochmal: lader", colors.red)
      return
    end
    schreiben(ORDNER .. "/" .. UPDATE_SERVER, s)
  end
  cfgSpeichern(cfg)
  local ich = lesen(selbst)
  if not (ich and ich:find("CORVELYX // LADER", 1, true)) then
    -- Gestartet per "wget run ..." -> Lader direkt von GitHub holen
    local r = http.get(LADER_URL, nil, true)
    if r then ich = r.readAll() r.close() end
  end
  if ich and ich:find("CORVELYX // LADER", 1, true) and selbst ~= "startup.lua" then
    schreiben("startup.lua", ich)
  end
  if not fs.exists("startup.lua") then
    meldung("Konnte den Lader nicht speichern.", colors.red)
    return
  end
  print("")
  meldung("Fertig! Neustart ...", colors.lime)
  sleep(2)
  os.reboot()
end

-- ---------- Start ----------
if term.isColor() then
  term.setPaletteColour(colors.cyan, LILA)
  term.setPaletteColour(colors.lightBlue, LILA)
end
local cfg = cfgLaden()
if not cfg or not cfg.PROGRAMM then einrichten() return end
CFG = cfg
math.randomseed(os.epoch("utc") + os.getComputerID())
local PROG = cfg.PROGRAMM
local pfad = ORDNER .. "/" .. PROG
fs.makeDir(ORDNER)

term.clear() term.setCursorPos(1, 1)
meldung("CORVELYX // LADER v" .. LADER_VERSION, colors.cyan)
print("Programm: " .. PROG)
local hatModem = modemOeffnen()
if not hatModem then meldung("Kein Ender Modem gefunden! Bitte ein Ender Modem an den Computer.", colors.red) end

local function hashVon(p) local s = lesen(p) return s and sha256(s) or nil end
local meinHash = hashVon(pfad)
local laderHash = hashVon("startup.lua")

if PROG ~= UPDATE_SERVER and hatModem then
  -- 1. Lader selbst aktuell?
  local st, inhalt = nachfragen("lader.lua", laderHash)
  if st == "neu" then
    meldung("Neuer Lader - Neustart", colors.lime)
    schreiben("startup.lua", inhalt)
    sleep(1)
    os.reboot()
  end
  -- 2. Programm aktuell?
  if st then
    write("Suche Update ... ")
    local st2, inhalt2, h2 = nachfragen(PROG, meinHash)
    if st2 == "neu" then
      schreiben(pfad, inhalt2)
      meinHash = h2
      meldung("neue Version geladen", colors.lime)
    elseif st2 == "aktuell" then
      meldung("aktuell", colors.lime)
    elseif st2 == "unbekannt" then
      meldung("nicht im Repo", colors.orange)
    else
      meldung("keine Antwort", colors.orange)
    end
    -- Einstellungen entruempeln: nur behalten, was von der Vorgabe abweicht
    if cfg._ABGLEICH and (st2 == "neu" or st2 == "aktuell") then
      local vorgabe = cfgAus(lesen(pfad))
      if vorgabe then
        for k, v in pairs(cfg) do
          if k ~= "NETZ" and k ~= "PASSWORT" and k ~= "PROGRAMM" and vorgabe[k] ~= nil and gleich(v, vorgabe[k]) then
            cfg[k] = nil
          end
        end
        cfg._ABGLEICH = nil
        cfgSpeichern(cfg)
      end
    end
  else
    meldung("Update-Computer nicht erreichbar - starte gespeicherte Version", colors.orange)
  end
end

if not fs.exists(pfad) then
  meldung("Programm fehlt und kein Update-Computer erreichbar.", colors.red)
  meldung("Neuer Versuch in 30 Sekunden ...", colors.red)
  sleep(30)
  os.reboot()
end

-- Waechter: startet neu, wenn der Update-Computer eine neue Version meldet
local function updateWaechter()
  if not hatModem then while true do os.pullEvent("corvelyx_nie") end end
  local prot = CFG.NETZ .. "/update"
  while true do
    local _, id, msg, p = os.pullEvent("rednet_message")
    if p == prot then
      local a = auspacken(id, msg)
      if a and a.typ == "neustart" and type(a.dateien) == "table" then
        local neu = a.dateien[PROG]
        local neuLader = a.dateien["lader.lua"]
        local ziel = (neu and neu ~= meinHash) and neu or ((neuLader and neuLader ~= laderHash) and neuLader)
        -- Pro Zielversion nur EIN Neustart-Versuch (keine Neustart-Schleifen)
        if ziel and lesen(ORDNER .. "/.ziel") ~= ziel then
          schreiben(ORDNER .. "/.ziel", ziel)
          os.reboot()
        end
      end
    end
  end
end

local beendet, fehler = false, nil
local function programm()
  local env = setmetatable({ CORVELYX_CFG = cfg, shell = shell, multishell = multishell }, { __index = _G })
  local fn, err = loadfile(pfad, nil, env)
  if not fn then fehler = err return end
  local ok, e = pcall(fn)
  if not ok then
    if tostring(e):find("Terminated") then beendet = true else fehler = e end
  end
end

parallel.waitForAny(programm, updateWaechter)
if beendet then
  term.redirect(term.native())
  farbe(colors.yellow) print("Beendet. Neustart mit: reboot") farbe(colors.white)
  return
end
term.redirect(term.native())
term.setBackgroundColor(colors.black)
term.clear() term.setCursorPos(1, 1)
meldung("CORVELYX // " .. PROG, colors.cyan)
meldung("Programm abgestuerzt:", colors.red)
meldung(tostring(fehler or "beendet"), colors.red)
print("")
print("Neustart in 30 Sekunden (Strg+T = abbrechen)")
parallel.waitForAny(function() sleep(30) end, updateWaechter)
os.reboot()
