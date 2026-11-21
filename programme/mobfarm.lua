-- =====================================================
--  CORVELYX // MOBFARM  v1.1
--  Ersetzt den Hebel am Create Redstone Link: Der Computer
--  gibt ein DAUERHAFTES Redstone-Signal, solange die
--  Mobfarmen an sein sollen. Schalten vom Control Center
--  aus oder direkt hier (Leertaste oder Bildschirm anklicken).
--  Der Zustand bleibt auch nach Neustart/Update erhalten.
--
--  Aufbau: Computer + Ender Modem, der Redstone Link
--  (Sender) direkt an einer Seite des Computers.
-- =====================================================

local CFG = {
  NETZ     = "Hier-Netzname-Eintragen",
  PASSWORT = "Hier-Netzpasswort-Eintragen",
  NAME     = "Mobfarmen",  -- Name, wie er im Control Center steht
  SEITE    = "back",       -- Seite zum Redstone Link: top, bottom, left, right, front, back
  SENDEN   = 3,            -- Sekunden zwischen Statusmeldungen
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
-- Sprache (de/en) - wird vom Update-Computer fuers ganze Netz vorgegeben
local EN = {
  ["  (Signal: "] = "  (signal: ",
  ["AN  - Farmen laufen"] = "ON  - farms running",
  ["AUS - Farmen gestoppt"] = "OFF - farms stopped",
  ["Kein Ender Modem gefunden!"] = "No Ender Modem found!",
  ["Leertaste oder Feld anklicken = umschalten"] = "Space or click the field = toggle",
  ["Mobfarmen"] = "Mob farms",
  ["SEITE muss top, bottom, left, right, front oder back sein"] = "SEITE must be top, bottom, left, right, front or back",
  ["Seit "] = "Since ",
  ["Unbekannter Befehl"] = "Unknown command",
  ["Zugriff verweigert"] = "Access denied",
  ["ausgeschaltet"] = "switched off",
  ["eingeschaltet"] = "switched on",
  ["vor Ort"] = "on site",
}
local function L(s) if CFG.SPRACHE == "en" then return EN[s] or s end return s end
CFG.PROTOKOLL   = CFG.NETZ .. "/daten"
CFG.PROT_STEUER = CFG.NETZ .. "/steuer"
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

local DATEI = "mobfarm_zustand.txt"

local function signieren(inhalt)
  local s = textutils.serialize(inhalt, { compact = true })
  local t = os.epoch("utc")
  return { v = 2, t = t, s = s, sig = sha256(CFG.PASSWORT .. "|" .. CFG.NETZ .. "|" .. tostring(t) .. "|" .. s) }
end

-- ---------- Deutsche Zeit (MEZ/MESZ) ----------
local function zivil(tage)
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
local function tageVon(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = m > 2 and m - 3 or m + 9
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
local function letzterSonntag(y, m) local t = tageVon(y, m, 31) return t - (t + 4) % 7 end
local function deutsch(sek)
  local y = zivil(math.floor(sek / 86400))
  local start = letzterSonntag(y, 3) * 86400 + 3600
  local ende  = letzterSonntag(y, 10) * 86400 + 3600
  local lokal = sek + ((sek >= start and sek < ende) and 7200 or 3600)
  local tag = math.floor(lokal / 86400)
  local yy, mm, dd = zivil(tag)
  local rest = lokal - tag * 86400
  return string.format("%02d.%02d.%04d %02d:%02d", dd, mm, yy, math.floor(rest / 3600), math.floor(rest % 3600 / 60))
end

-- ---------- Zustand ----------
local SEITEN = { top = true, bottom = true, left = true, right = true, front = true, back = true }
if not SEITEN[CFG.SEITE] then error(L("SEITE muss top, bottom, left, right, front oder back sein"), 0) end

local zustand = { an = false, seit = nil, wer = nil }
if fs.exists(DATEI) then
  local f = fs.open(DATEI, "r")
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) == "table" then zustand = t end
end
local function speichern()
  local f = fs.open(DATEI, "w")
  f.write(textutils.serialize(zustand))
  f.close()
end
local function schalten(an, wer)
  zustand.an = an and true or false
  zustand.seit = deutsch(math.floor(os.epoch("utc") / 1000))
  zustand.wer = wer
  rs.setOutput(CFG.SEITE, zustand.an)
  speichern()
end
-- Beim Start den gespeicherten Zustand wiederherstellen
rs.setOutput(CFG.SEITE, zustand.an)

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error(L("Kein Ender Modem gefunden!"), 0) end
rednet.open(peripheral.getName(modem))

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
  rednet.broadcast(signieren({ typ = "status", quelle = "mobfarm", name = CFG.NAME,
    schluessel = os.getComputerID() .. ":" .. CFG.NAME,
    daten = { an = zustand.an, seit = zustand.seit, wer = zustand.wer, nonce = neueNonce() } }), CFG.PROTOKOLL)
end

-- ---------- Anzeige ----------
local knopf = nil
local function zeigen()
  local w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  local function z(y, text, f, bg)
    term.setCursorPos(1, y) term.setTextColor(f or colors.white) term.setBackgroundColor(bg or colors.black)
    term.write(text:sub(1, w))
  end
  z(1, "CORVELYX // MOBFARM", colors.cyan)
  z(2, CFG.NAME .. L("  (Signal: ") .. CFG.SEITE .. ")", colors.lightGray)
  local bg = zustand.an and colors.green or colors.gray
  local txt = zustand.an and L("AN  - Farmen laufen") or L("AUS - Farmen gestoppt")
  for y = 4, 6 do z(y, string.rep(" ", w), colors.white, bg) end
  term.setCursorPos(math.floor((w - #txt) / 2) + 1, 5) term.setBackgroundColor(bg) term.setTextColor(colors.white)
  term.write(txt)
  knopf = { y1 = 4, y2 = 6 }
  term.setBackgroundColor(colors.black)
  if zustand.seit then z(8, L("Seit ") .. zustand.seit .. (zustand.wer and (" (" .. zustand.wer .. ")") or ""), colors.lightGray) end
  z(h, L("Leertaste oder Feld anklicken = umschalten"), colors.gray)
end

-- ---------- Hauptschleife ----------
zeigen()
senden()
local takt = os.startTimer(CFG.SENDEN)
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == takt then
    takt = os.startTimer(CFG.SENDEN)
    rs.setOutput(CFG.SEITE, zustand.an)   -- sicherheitshalber immer wieder setzen
    senden()
  elseif (ev[1] == "key" and (ev[2] == keys.space or ev[2] == keys.enter))
      or (ev[1] == "mouse_click" and knopf and ev[4] >= knopf.y1 and ev[4] <= knopf.y2) then
    schalten(not zustand.an, L("vor Ort"))
    zeigen()
    senden()
  elseif ev[1] == "rednet_message" and ev[4] == CFG.PROT_STEUER then
    local id, msg = ev[2], ev[3]
    if type(msg) == "table" and type(msg.befehl) == "string" and type(msg.wert) == "string"
       and type(msg.nonce) == "string" and type(msg.sig) == "string" then
      local ok = nonceEinloesen(msg.nonce)
        and msg.sig == sha256(CFG.PASSWORT .. "|" .. msg.befehl .. "|" .. msg.wert .. "|" .. msg.nonce)
      local text
      if not ok then text = L("Zugriff verweigert")
      elseif msg.befehl == "an" then schalten(true, L("Control Center")) text = L("eingeschaltet")
      elseif msg.befehl == "aus" then schalten(false, L("Control Center")) text = L("ausgeschaltet")
      else ok, text = false, L("Unbekannter Befehl") end
      rednet.send(id, signieren({ typ = "antwort", ok = ok, text = CFG.NAME .. ": " .. text }), CFG.PROT_STEUER)
      zeigen()
      senden()
    end
  elseif ev[1] == "term_resize" then
    zeigen()
  end
end
