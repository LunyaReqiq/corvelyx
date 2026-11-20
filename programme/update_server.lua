-- =====================================================
--  CORVELYX // UPDATE-SERVER  v1.1
--  Holt die Programme aus deinem privaten GitHub-Repo und
--  verteilt sie ueber das Funknetz an alle Corvelyx-
--  Computer. Nur DIESER Computer kennt den GitHub-Token.
--
--  Einrichtung: lader.lua auf den Computer ziehen,
--  "lader" eintippen, "Update-Computer" waehlen.
--  Alle Werte stehen danach in corvelyx.cfg.
-- =====================================================
local CFG = {
  NETZ             = "Hier-Netzname-Eintragen",
  PASSWORT         = "Hier-Netzpasswort-Eintragen",
  GITHUB_BENUTZER  = "",
  REPO             = "corvelyx",
  BRANCH           = "main",
  ORDNER           = "programme",
  TOKEN            = "",
  PRUEF_INTERVALL  = 600,   -- Sekunden zwischen GitHub-Pruefungen
  STATUS_INTERVALL = 3,     -- Sekunden zwischen Statusmeldungen ans CC
  STAND_INTERVALL  = 300,   -- Sekunden: kompletter Stand fuer verpasste Updates
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
CFG.PROT_UPDATE = CFG.NETZ .. "/update"
CFG.PROT_DATEN  = CFG.NETZ .. "/daten"
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

local SPEICHER = "corvelyx_repo"
local INDEX    = SPEICHER .. "/index.txt"

local function lesen(pfad)
  if not fs.exists(pfad) then return nil end
  local f = fs.open(pfad, "rb")
  local s = f.readAll()
  f.close()
  return s
end
local function schreiben(pfad, inhalt)
  local f = fs.open(pfad .. ".neu", "wb")
  f.write(inhalt)
  f.close()
  if fs.exists(pfad) then fs.delete(pfad) end
  fs.move(pfad .. ".neu", pfad)
end

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

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Kein Ender Modem gefunden!", 0) end
rednet.open(peripheral.getName(modem))
fs.makeDir(SPEICHER)

-- index[datei] = { sha = Git-Kennung, hash = SHA-256 des Inhalts }
local index = {}
do
  local s = lesen(INDEX)
  local t = s and textutils.unserialize(s)
  if type(t) == "table" then index = t end
end
local function indexSpeichern() local f = fs.open(INDEX, "w") f.write(textutils.serialize(index)) f.close() end

local status = { fehler = nil, letzte = nil, zuletzt = {}, zuletztZeit = nil, anfragen = 0 }
local protokoll = {}
local function log(text, f)
  table.insert(protokoll, 1, { textutils.formatTime(os.time(), true) .. " " .. text, f or colors.white })
  if #protokoll > 40 then table.remove(protokoll) end
end

-- ---------- GitHub ----------
local function api(pfad, roh)
  local url = "https://api.github.com/repos/" .. CFG.GITHUB_BENUTZER .. "/" .. CFG.REPO .. "/contents/" .. pfad
    .. "?ref=" .. CFG.BRANCH
  local r, err, fr = http.get(url, {
    Authorization = "Bearer " .. CFG.TOKEN,
    Accept = roh and "application/vnd.github.raw" or "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = "2022-11-28",
    ["User-Agent"] = "Corvelyx",
  }, true)
  if not r then
    local code = fr and fr.getResponseCode()
    if fr then fr.close() end
    if code == 401 then return nil, "Token ungueltig oder abgelaufen"
    elseif code == 404 then return nil, "Repo/Ordner nicht gefunden (Name, Token-Rechte?)"
    elseif code == 403 then return nil, "GitHub verweigert (Limit oder Rechte)"
    elseif code then return nil, "GitHub antwortet " .. code end
    return nil, "Keine Verbindung: " .. tostring(err)
  end
  local s = r.readAll()
  r.close()
  return s
end

local pruefLaeuft = false
local function pruefen()
  if pruefLaeuft then return end
  pruefLaeuft = true
  if CFG.GITHUB_BENUTZER == "" or CFG.TOKEN == "" then
    status.fehler = "GitHub-Zugang fehlt (corvelyx.cfg)"
    pruefLaeuft = false
    return
  end
  local s, err = api(CFG.ORDNER, false)
  local liste = s and textutils.unserializeJSON(s)
  if type(liste) ~= "table" then
    status.fehler = err or "Antwort von GitHub unlesbar"
    log("Fehler: " .. status.fehler, colors.red)
    pruefLaeuft = false
    return
  end
  local geaendert, anzahl = {}, 0
  for _, e in ipairs(liste) do
    if e.type == "file" and type(e.name) == "string" and e.name:match("%.lua$") then
      anzahl = anzahl + 1
      local alt = index[e.name]
      if not alt or alt.sha ~= e.sha or not fs.exists(SPEICHER .. "/" .. e.name) then
        local inhalt, err2 = api(e.path, true)
        if inhalt then
          schreiben(SPEICHER .. "/" .. e.name, inhalt)
          local h = sha256(inhalt)
          local warNeu = (not alt) or alt.hash ~= h
          index[e.name] = { sha = e.sha, hash = h }
          if warNeu and alt then geaendert[e.name] = h end
          if warNeu then log((alt and "Update: " or "Neu: ") .. e.name, colors.lime) end
        else
          status.fehler = err2
          log("Fehler bei " .. e.name .. ": " .. tostring(err2), colors.red)
        end
      end
    end
  end
  indexSpeichern()
  status.letzte = os.epoch("utc")
  status.anzahl = anzahl
  if not err then status.fehler = nil end

  if next(geaendert) then
    local namen = {}
    for n in pairs(geaendert) do namen[#namen + 1] = n end
    table.sort(namen)
    status.zuletzt, status.zuletztZeit = namen, os.epoch("utc")
    rednet.broadcast(signieren({ typ = "neustart", dateien = geaendert }), CFG.PROT_UPDATE)
    log("Neustart-Signal: " .. table.concat(namen, ", "), colors.yellow)
    -- Eigenes Update: Update-Server bzw. Lader auf diesem Computer ersetzen
    local selbst = geaendert["update_server.lua"] or geaendert["lader.lua"]
    if selbst then
      if geaendert["update_server.lua"] then
        schreiben("corvelyx/update_server.lua", lesen(SPEICHER .. "/update_server.lua"))
      end
      if geaendert["lader.lua"] then schreiben("startup.lua", lesen(SPEICHER .. "/lader.lua")) end
      sleep(2)
      os.reboot()
    end
  end
  pruefLaeuft = false
end

-- ---------- Anzeige ----------
local function zeigen()
  local w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  local function z(y, text, f) term.setCursorPos(1, y) term.setTextColor(f or colors.white) term.write(text:sub(1, w)) end
  z(1, "CORVELYX // UPDATE-SERVER", colors.cyan)
  z(2, "Repo: " .. CFG.GITHUB_BENUTZER .. "/" .. CFG.REPO .. " (" .. CFG.BRANCH .. ")", colors.lightGray)
  local zeile3, f3
  if status.fehler then zeile3, f3 = "FEHLER: " .. status.fehler, colors.red
  elseif status.letzte then zeile3, f3 = "OK - " .. (status.anzahl or 0) .. " Programme, geprueft vor "
    .. math.floor((os.epoch("utc") - status.letzte) / 60000) .. " min", colors.lime
  else zeile3, f3 = "Pruefe GitHub ...", colors.yellow end
  z(3, zeile3, f3)
  z(4, "Anfragen beantwortet: " .. status.anfragen .. "   U = jetzt pruefen", colors.lightGray)
  for i, e in ipairs(protokoll) do
    if 5 + i > h then break end
    z(5 + i, e[1], e[2])
  end
end

local function statusSenden()
  rednet.broadcast(signieren({ typ = "status", quelle = "update", schluessel = "update-" .. os.getComputerID(),
    daten = { fehler = status.fehler, letzte = status.letzte, anzahl = status.anzahl,
      zuletzt = status.zuletzt, zuletztZeit = status.zuletztZeit, intervall = CFG.PRUEF_INTERVALL } }), CFG.PROT_DATEN)
end

-- ---------- Anfragen ----------
local function anfrage(id, a)
  if a.typ == "frage" and type(a.datei) == "string" then
    local eintrag = index[a.datei]
    local antwort = { typ = "antwort", datei = a.datei, nonce = a.nonce }
    local msg
    if not eintrag or not fs.exists(SPEICHER .. "/" .. a.datei) then
      antwort.status = "unbekannt"
      msg = signieren(antwort)
    elseif eintrag.hash == a.hash then
      antwort.status = "aktuell"
      msg = signieren(antwort)
    else
      antwort.status, antwort.hash = "neu", eintrag.hash
      msg = signieren(antwort)
      msg.inhalt = lesen(SPEICHER .. "/" .. a.datei)
      log("PC #" .. id .. " bekommt " .. a.datei, colors.lightBlue)
    end
    rednet.send(id, msg, CFG.PROT_UPDATE)
    status.anfragen = status.anfragen + 1
  elseif a.typ == "pruefen" then
    log("Pruefung angefordert von PC #" .. id, colors.yellow)
    return true
  end
end

-- Kompletten Stand senden (regelmaessig, beim Start und bei UPDATE):
-- Regelmaessig den kompletten Stand senden: wer ein Update verpasst hat
-- (war aus, Chunk nicht geladen ...), holt es so automatisch nach.
local function standSenden()
  local alle = {}
  for n, e in pairs(index) do alle[n] = e.hash end
  rednet.broadcast(signieren({ typ = "neustart", dateien = alle, stand = true }), CFG.PROT_UPDATE)
end

-- ---------- Hauptschleife ----------
log("Gestartet", colors.lightGray)
zeigen()
pruefen()
zeigen()
statusSenden()
standSenden()
local pruefTimer = os.startTimer(CFG.PRUEF_INTERVALL)
local statusTimer = os.startTimer(CFG.STATUS_INTERVALL)
local standTimer = os.startTimer(CFG.STAND_INTERVALL)
local letztePruefung = os.clock()
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == pruefTimer then
    pruefen() letztePruefung = os.clock()
    pruefTimer = os.startTimer(CFG.PRUEF_INTERVALL)
  elseif ev[1] == "timer" and ev[2] == standTimer then
    standSenden()
    standTimer = os.startTimer(CFG.STAND_INTERVALL)
  elseif ev[1] == "timer" and ev[2] == statusTimer then
    statusSenden()
    statusTimer = os.startTimer(CFG.STATUS_INTERVALL)
  elseif ev[1] == "rednet_message" and ev[4] == CFG.PROT_UPDATE then
    local a = auspacken(ev[2], ev[3])
    if a and anfrage(ev[2], a) and os.clock() - letztePruefung > 20 then
      pruefen() letztePruefung = os.clock()
      statusSenden()
      standSenden()
    end
  elseif ev[1] == "key" and ev[2] == keys.u then
    pruefen() letztePruefung = os.clock()
    standSenden()
  end
  zeigen()
end
