-- =====================================================
--  CORVELYX // FLUX-SENDER  v1.1
--  Liest alle Energy Detectors (Advanced Peripherals), die
--  vor Flux Plugs sitzen, und funkt den Durchfluss (FE/t)
--  an das Flux-Panel.
--
--  Aufbau:  [Generator] -> [Energy Detector] -> [Flux Plug]
--  Jeder Detector bekommt ein Wired Modem (rechtsklicken,
--  muss rot leuchten) und wird per Networking Cable mit
--  diesem Computer verbunden. Ein Detector darf auch direkt
--  am Computer stehen. Dazu ein Ender Modem.
-- =====================================================

local CFG = {
  -- Funknetz: alle eigenen Computer brauchen GLEICHEN Namen + Passwort
  NETZ      = "Hier-Netzname-Eintragen",
  PASSWORT  = "Hier-Netzpasswort-Eintragen",
  INTERVALL = 1,             -- Sekunden zwischen Sendungen

  -- Standort dieser Gruppe, erscheint im Panel
  ORT       = "Basis",

  -- Anzeigenamen pro Detector. Den Namen eines Detectors siehst du
  -- auf dem Bildschirm dieses Computers (z.B. energy_detector_0).
  -- Nicht eingetragene Detectors heissen "ORT #Nummer".
  NAMEN = {
    -- ["energy_detector_0"] = "Solar Dach",
    -- ["energy_detector_1"] = "Reaktor-Turbinen",
  },

  -- Durchfluss-Grenze der Detectors beim Start (nil = nicht aendern)
  LIMIT     = 2147483647,
}
-- Einstellungen aus corvelyx.cfg (Update-System) uebernehmen
if type(CORVELYX_CFG) == "table" then for k, v in pairs(CORVELYX_CFG) do CFG[k] = v end end
-- Sprache (de/en) - wird vom Update-Computer fuers ganze Netz vorgegeben
local EN = {
  [" Detector(s)   Summe: "] = " detector(s)   total: ",
  [" weitere"] = " more",
  ["... und "] = "... and ",
  ["FEHLER"] = "ERROR",
  ["Kein Ender Modem gefunden!"] = "No Ender Modem found!",
  ["Strg+T = Beenden"] = "Ctrl+T = quit",
}
local function L(s) if CFG.SPRACHE == "en" then return EN[s] or s end return s end

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

-- ---------- Detectors finden ----------
local function finden()
  local liste = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "energy_detector") or peripheral.hasType(n, "energyDetector") then
      liste[#liste + 1] = n
    end
  end
  table.sort(liste)
  return liste
end

local function anzeigeName(n, i)
  if CFG.NAMEN[n] then return CFG.NAMEN[n] end
  local nr = n:match("_(%d+)$")
  if nr then return CFG.ORT .. " #" .. nr end
  return CFG.ORT .. " (" .. n .. ")"   -- direkt am Computer, z.B. "back"
end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error(L("Kein Ender Modem gefunden!")) end
rednet.open(peripheral.getName(modem))

local gesetzt = {}
local function limitSetzen(n)
  if CFG.LIMIT and not gesetzt[n] then
    pcall(peripheral.call, n, "setTransferRateLimit", CFG.LIMIT)
    gesetzt[n] = true
  end
end

local function kurz(n)
  if type(n) ~= "number" then return "--" end
  local a = math.abs(n)
  if a >= 1e12 then return string.format("%.2fT", n / 1e12) end
  if a >= 1e9 then return string.format("%.2fG", n / 1e9) end
  if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if a >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return string.format("%.0f", n)
end

-- ---------- Hauptschleife ----------
while true do
  local plugs, summe = {}, 0
  for i, n in ipairs(finden()) do
    limitSetzen(n)
    local ok, rate = pcall(peripheral.call, n, "getTransferRate")
    rate = (ok and type(rate) == "number") and rate or nil
    plugs[#plugs + 1] = { id = n, name = anzeigeName(n, i), rate = rate }
    summe = summe + (rate or 0)
  end

  rednet.broadcast(signieren({ typ = "status", quelle = "flux",
    schluessel = "flux-" .. os.getComputerID(), ort = CFG.ORT, plugs = plugs }), CFG.PROTOKOLL)

  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  print("CORVELYX // FLUX-SENDER   Ort: " .. CFG.ORT)
  term.setTextColor(colors.white)
  print(#plugs .. L(" Detector(s)   Summe: ") .. kurz(summe) .. " FE/t")
  print("")
  local _, h = term.getSize()
  for i, pl in ipairs(plugs) do
    if i > h - 5 then term.setTextColor(colors.gray) print(L("... und ") .. (#plugs - i + 1) .. L(" weitere")) break end
    term.setTextColor(pl.rate and (pl.rate > 0 and colors.lime or colors.lightGray) or colors.red)
    print(string.format("%-18s %-18s %s", pl.id:sub(1, 18), pl.name:sub(1, 18), pl.rate and kurz(pl.rate) or L("FEHLER")))
  end
  term.setTextColor(colors.gray)
  term.setCursorPos(1, h)
  term.write(L("Strg+T = Beenden"))
  sleep(CFG.INTERVALL)
end
