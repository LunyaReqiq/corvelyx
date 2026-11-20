-- =====================================================
--  CORVELYX // LAGER-SENDER  v1
--  Liest den Storage Controller von Functional Storage
--  (alle verbundenen Drawer) und funkt Inhalt, Menge und
--  Kapazitaet jedes Fachs an Control Center und Pocket.
--
--  Aufbau: Computer direkt an den (Framed) Storage
--  Controller, dazu ein Ender Modem.
-- =====================================================

local CFG = {
  -- Funknetz: alle eigenen Computer brauchen GLEICHEN Namen + Passwort
  NETZ      = "Hier-Netzname-Eintragen",
  PASSWORT  = "Hier-Netzpasswort-Eintragen",
  NAME      = "Lager",      -- Name dieses Lagers (bei mehreren Lagern)
  INTERVALL = 5,            -- Sekunden zwischen Sendungen
  LIMIT_NEU = 60,           -- Kapazitaeten alle X Sekunden neu lesen
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

-- ---------- Controller finden ----------
local function istController(name)
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t:find("storage_controller") then return true end
  end
  return false
end

local lager
for _, n in ipairs(peripheral.getNames()) do
  if istController(n) then lager = n break end
end
if not lager then
  -- Ersatz: irgendein Inventar (z.B. einzelner Drawer)
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "inventory") then lager = n break end
  end
end
if not lager then error("Kein Storage Controller / Inventar gefunden!") end
local inv = peripheral.wrap(lager)

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Kein Ender Modem gefunden!") end
rednet.open(peripheral.getName(modem))

-- ---------- Zwischenspeicher (spart Zeit) ----------
local anzeige = {}     -- [itemId] = Anzeigename
local limits = {}      -- [slot .. "|" .. itemId] = Kapazitaet
local limitZeit = -1000

local function kurz(n)
  if type(n) ~= "number" then return "--" end
  local a = math.abs(n)
  if a >= 1e9 then return string.format("%.2fG", n / 1e9) end
  if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if a >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return string.format("%.0f", n)
end

local function lesen()
  local ok, liste = pcall(inv.list)
  if not ok or type(liste) ~= "table" then error("Lesen fehlgeschlagen: " .. tostring(liste)) end
  local okS, groesse = pcall(inv.size)
  local neuLimits = (os.clock() - limitZeit) >= CFG.LIMIT_NEU
  if neuLimits then limits = {} limitZeit = os.clock() end
  local faecher = {}
  for slot, item in pairs(liste) do
    if not anzeige[item.name] then
      local okD, det = pcall(inv.getItemDetail, slot)
      anzeige[item.name] = (okD and det and det.displayName) or item.name:gsub("^.-:", "")
    end
    local key = slot .. "|" .. item.name
    if not limits[key] then
      local okL, lim = pcall(inv.getItemLimit, slot)
      limits[key] = (okL and type(lim) == "number") and lim or 0
    end
    faecher[#faecher + 1] = { slot = slot, id = item.name, name = anzeige[item.name],
      menge = item.count, limit = limits[key] }
  end
  table.sort(faecher, function(a, b) return a.slot < b.slot end)
  return faecher, okS and groesse or nil
end

-- ---------- Hauptschleife ----------
while true do
  local ok, faecher, groesse = pcall(lesen)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  print("CORVELYX // LAGER-SENDER   " .. CFG.NAME)
  term.setTextColor(colors.white)
  print("Geraet: " .. lager)
  if ok then
    rednet.broadcast(signieren({ typ = "status", quelle = "lager", schluessel = "lager-" .. os.getComputerID(),
      ort = CFG.NAME, slots = groesse, faecher = faecher }), CFG.PROTOKOLL)
    local summe, voll = 0, 0
    for _, f in ipairs(faecher) do
      summe = summe + f.menge
      if f.limit > 0 and f.menge / f.limit >= 0.95 then voll = voll + 1 end
    end
    print("Faecher: " .. #faecher .. " belegt / " .. tostring(groesse))
    print("Items gesamt: " .. kurz(summe))
    term.setTextColor(voll > 0 and colors.orange or colors.lime)
    print("Fast voll (>=95%): " .. voll)
  else
    term.setTextColor(colors.red)
    print("Fehler: " .. tostring(faecher))
  end
  term.setTextColor(colors.gray)
  print("")
  print("Sendet alle " .. CFG.INTERVALL .. " s. Strg+T = Ende")
  sleep(CFG.INTERVALL)
end
