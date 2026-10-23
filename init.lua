-- Welcome scene for Hammerspoon: plays a walk-in song first, then lays out your windows.
-- Docs: README.md. Everything is local; no network calls.

require("hs.ipc")              -- lets the bundled `hs` CLI talk to this config (local mach port only)
hs.uploadCrashData(false)      -- keep crash reports local
hs.window.animationDuration = 0

local HOME_DIR = os.getenv("HOME") .. "/.hammerspoon"
local LOG_FILE = HOME_DIR .. "/welcome.log"
local STATE_FILE = HOME_DIR .. "/welcome-state.txt"

------------------------------------------------------------------ settings
local cfg = {
  song = {
    name = "Papi",            -- matched with "contains" (title is "Papi’s Home", curly apostrophe)
    artist = "Drake",
    startAt = 133,            -- 2:13
    stopBeforeEnd = 10,       -- pause with 0:10 left
    volume = 100,              -- Music volume after the silent start
    catalogURL = "music://music.apple.com/us/album/papis-home/1584449196?i=1584449202",
  },
  morningHour = 4,            -- first unlock after 4:00 AM local, once per day
  launchDelay = 0.5,            -- seconds to wait after Hammerspoon launches before running
  -- Second screen (portrait 1080x1920 in the original setup). Offsets are relative to that screen's top-left.
  -- Measure yours with: hs.window.focusedWindow():frame()
  asus = {
    match = "ASUS",
    safari = { x = 10, y = 40,   w = 1050, h = 989 },
    grok   = { x = 16, y = 1055, w = 1054, h = 812 },
  },
  -- Main screen (1920x1080 points). Frames are relative to the screen's top-left.
  -- The item with focus = true is brought to the front last (handy for a password manager sign-in).
  lg = {
    match = "LG",
    apps = {
      { bundle = "com.apple.weather",       frame = { x = 8,   y = 38,  w = 1048, h = 640 } },
      { bundle = "com.apple.iCal",          frame = { x = 964, y = 38,  w = 948,  h = 503 } },
      { bundle = "com.apple.stocks",        frame = { x = 8,   y = 520, w = 948,  h = 670 }, url = "stocks://?symbol=AAPL" },
      { bundle = "com.apple.Music",         frame = { x = 964, y = 520, w = 980,  h = 600 } },
      { bundle = "com.1password.1password", frame = { x = 560, y = 240, w = 800,  h = 560 }, focus = true },
    },
  },
  bundles = { safari = "com.apple.Safari", grok = "com.anysphere.sand" },  -- second app on the side screen
}

------------------------------------------------------------------ helpers
-- Keep one-shot timers referenced so Lua's garbage collector can't cancel them early.
timersKeep = {}
local function after(sec, fn)
  local t
  t = hs.timer.doAfter(sec, function() timersKeep[t] = nil; fn() end)
  timersKeep[t] = true
  return t
end
local function log(msg)
  local f = io.open(LOG_FILE, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg .. "\n"); f:close() end
  print(msg)
end

local function readState()
  local s = {}
  local f = io.open(STATE_FILE, "r")
  if f then
    for line in f:lines() do local k, v = line:match("^(%w+)=(.*)$"); if k then s[k] = v end end
    f:close()
  end
  return s
end

local function writeState(s)
  local f = io.open(STATE_FILE, "w")
  if f then for k, v in pairs(s) do f:write(k .. "=" .. tostring(v) .. "\n") end; f:close() end
end

local function findScreen(match)
  for _, sc in ipairs(hs.screen.allScreens()) do
    if (sc:name() or ""):find(match, 1, true) then return sc end
  end
  return nil
end

-- Wait (up to `tries` x 0.5 s) for an app's main window, then call fn(win).
local function withWindow(bundle, fn, tries)
  tries = tries or 30
  local app = hs.application.get(bundle)
  local win = app and (app:mainWindow() or app:allWindows()[1])
  if win then return fn(win) end
  if tries <= 0 then log("no window for " .. bundle); return end
  after(0.5, function() withWindow(bundle, fn, tries - 1) end)
end

local function placeOn(screen, bundle, rel)
  withWindow(bundle, function(win)
    local sf = screen:fullFrame()
    win:setFrame(hs.geometry.rect(sf.x + rel.x, sf.y + rel.y, rel.w, rel.h), 0)
  end)
end

------------------------------------------------------------------ music
local musicTimer = nil

local function stopMusic()
  if musicTimer then musicTimer:stop(); musicTimer = nil end
  hs.osascript.applescript('tell application "Music" to pause')
  log("music paused")
end

local function scheduleStop(stopAt)
  if musicTimer then musicTimer:stop() end
  local ok, pos = hs.osascript.applescript('tell application "Music" to get player position')
  local wait = (ok and type(pos) == "number") and (stopAt - pos) or (stopAt - cfg.song.startAt)
  if wait < 0.2 then wait = 0.2 end
  musicTimer = after(wait, function()
    musicTimer = nil
    local ok2, res = hs.osascript.applescript(
      'tell application "Music" to return {name of current track, player position, (player state as text)}')
    if not ok2 or type(res) ~= "table" then return end
    local name, p, state = res[1], res[2], res[3]
    if not tostring(name):find(cfg.song.name, 1, true) then log("song changed; not stopping"); return end
    if state ~= "playing" then log("song not playing; nothing to stop"); return end
    if p < stopAt - 0.5 then scheduleStop(stopAt); return end  -- scrubbed or paused earlier; re-arm
    stopMusic()
  end)
end

local function playSong()
  local s = cfg.song
  -- Route to the Mac mini's built-in speakers and make sure they're audible
  local spk = hs.audiodevice.findOutputByName("Mac mini Speakers")
  if spk then
    spk:setDefaultOutputDevice()
    if spk:muted() then spk:setMuted(false) end
    if (spk:volume() or 0) < 50 then spk:setVolume(70) end
  end
  local script = string.format([[
    tell application "Music"
      set ts to (every track of library playlist 1 whose name contains "%s" and artist contains "%s")
      if (count of ts) = 0 then return "NOTFOUND"
      set t to item 1 of ts
      set sound volume to 0
      play t
      return (duration of t)
    end tell]], s.name, s.artist)
  local ok, res = hs.osascript.applescript(script)
  if not ok then log("music error: " .. hs.inspect(res)); return end
  if res == "NOTFOUND" then
    log("song not in library; opening catalog page")
    hs.urlevent.openURL(s.catalogURL)
    hs.alert.show("Papi's Home isn't in your library. Add it once (+), then press Ctrl+Opt+Cmd+W.", 6)
    return
  end
  local stopAt = tonumber(res) - s.stopBeforeEnd
  -- Cloud (not downloaded) tracks can take up to ~60 s to start streaming; wait until Music reports "playing" (up to 90 s).
  local tries = 0
  local function seekWhenPlaying()
    tries = tries + 1
    local okS, st = hs.osascript.applescript('tell application "Music" to return (player state as text)')
    -- "playing" alone isn't enough right after boot (cloud track still buffering): require the position to advance
    local okP, p1 = hs.osascript.applescript('tell application "Music" to get player position')
    if okS and st == "playing" and okP and type(p1) == "number" then
      hs.timer.usleep(700000)
      local _, p2 = hs.osascript.applescript('tell application "Music" to get player position')
      if not (type(p2) == "number" and p2 > p1 + 0.2) then
        if tries < 180 then after(0.5, seekWhenPlaying) end
        return
      end
    else
      if tries < 180 then after(0.5, seekWhenPlaying); return end
    end
    if okS and st == "playing" then
      hs.osascript.applescript(string.format('tell application "Music" to set player position to %d', s.startAt))
      local v = 0
      local function fadeUp()
        v = math.min(v + 10, s.volume or 70)
        hs.osascript.applescript(string.format('tell application "Music" to set sound volume to %d', v))
        if v < (s.volume or 70) then after(0.15, fadeUp) end
      end
      after(0.4, fadeUp)
      log(string.format("playing from %ds, will pause at %.1fs", s.startAt, stopAt))
      scheduleStop(stopAt)
    elseif tries < 180 then
      after(0.5, seekWhenPlaying)
    else
      hs.osascript.applescript(string.format('tell application "Music" to set sound volume to %d', s.volume or 70))
      log("song did not start playing within 90 s (Music state: " .. tostring(st) .. ")")
      hs.alert.show("Music didn't start Papi's Home. Try playing it once by hand in Music.", 6)
    end
  end
  seekWhenPlaying()
end

------------------------------------------------------------------ scene
function welcome(reason)
  log("Welcome start (" .. tostring(reason) .. ")")
  if not hs.accessibilityState() then
    log("Accessibility not granted; windows will not move")
  end
  -- Song first: start it before any windows so it comes on as fast as possible.
  local function startWhenOnline(n)
    n = n or 0
    local r = hs.network.reachability.internet()
    if (r and (r:status() & hs.network.reachability.flags.reachable) > 0) or n >= 120 then
      playSong()
    else
      after(0.5, function() startWhenOnline(n + 1) end)
    end
  end
  startWhenOnline()

  local asus, lg = findScreen(cfg.asus.match), findScreen(cfg.lg.match)

  -- Asus: Safari top, Grok Bot bottom (your measured positions)
  hs.application.launchOrFocusByBundleID(cfg.bundles.safari)
  hs.application.launchOrFocusByBundleID(cfg.bundles.grok)
  if asus then
    placeOn(asus, cfg.bundles.safari, cfg.asus.safari)
    placeOn(asus, cfg.bundles.grok, cfg.asus.grok)
  else log("ASUS screen not found") end

  -- LG: your saved layout (1Password last, on top)
  for _, item in ipairs(cfg.lg.apps) do
    if item.url then hs.urlevent.openURLWithBundle(item.url, item.bundle)
    else hs.application.launchOrFocusByBundleID(item.bundle) end
  end
  if lg then
    for _, item in ipairs(cfg.lg.apps) do placeOn(lg, item.bundle, item.frame) end
    for _, item in ipairs(cfg.lg.apps) do
      if item.focus then
        after(2.5, function()
          local a = hs.application.get(item.bundle)
          local w = a and a:mainWindow()
          if w then placeOn(lg, item.bundle, item.frame); w:focus() end
        end)
      end
    end
  else log("LG screen not found") end

end

-- Placeholder: daytime return (screensaver / display sleep / later unlocks).
-- Design your own routine here. Nothing runs here yet.
function daytimeReturn(reason)
  log("daytime return (" .. tostring(reason) .. "): no routine yet")
end

------------------------------------------------------------------ triggers
local function today() return os.date("%Y-%m-%d") end
local function pastMorningHour() return tonumber(os.date("%H")) >= cfg.morningHour end

local function markMorningDone()
  local s = readState(); s.morningDone = today(); writeState(s)
end

-- 1) Hammerspoon launch (login or restart). A config reload in the same process does not re-run.
do
  local s = readState()
  local pid = tostring(hs.processInfo.processID)
  if s.pid ~= pid then
    s.pid = pid
    if pastMorningHour() then s.morningDone = today() end  -- the launch counts as this morning's welcome
    writeState(s)
    after(cfg.launchDelay, function() welcome("launch") end)
  else
    log("config reloaded (no Welcome)")
  end
end

-- 2) First unlock after 4:00 AM each day; everything else goes to the daytime stub.
cafWatcher = hs.caffeinate.watcher.new(function(ev)
  local W = hs.caffeinate.watcher
  if ev == W.screensDidUnlock then
    local s = readState()
    if pastMorningHour() and s.morningDone ~= today() then
      markMorningDone()
      after(2, function() welcome("morning unlock") end)
    else
      daytimeReturn("unlock")
    end
  elseif ev == W.screensaverDidStop then
    daytimeReturn("screensaver stopped")
  elseif ev == W.screensDidWake then
    daytimeReturn("display woke")
  end
end)
cafWatcher:start()

-- 3) Hotkeys
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "W", function() welcome("hotkey") end)
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "M", stopMusic)

log("config loaded (Hammerspoon " .. hs.processInfo.version .. ")")
