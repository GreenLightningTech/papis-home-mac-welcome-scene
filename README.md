# Welcome Scene for Hammerspoon

A walk-in song for your Mac. When you sit down, your song starts first, then your apps open and snap into place on your screens while it plays. When the song ends, your workstation is ready.

## What it does

**When it runs**
- When Hammerspoon launches, at login or after a restart. Reloading the config doesn't re-run it.
- On the first unlock after 4 AM each day, once per day. A launch after 4 AM counts as that day's run.
- Any time you press **Ctrl+Opt+Cmd+W**.

**What happens, in order**
1. **Song first.** Once the network is reachable (it waits up to 60 s), it routes audio to the built-in speakers and unmutes them. If their volume is below 50, it raises it to 70. Then it finds your song in the Music library and starts it silently. Once the song is actually playing, it jumps to your chosen start time and fades the volume up.
2. **Stops near the end.** Music pauses a set number of seconds before the track ends, so the scene finishes on your cue.
3. **Windows.** It opens your apps and moves each one to an exact frame on two screens. One app can be marked `focus = true`, so it ends up on top (handy for a password manager sign-in).

If the song isn't in your library, the scene opens its Apple Music page and shows a reminder to add it.

## Example config

The included `cfg` plays Drake's "Papi's Home" from 2:13 and pauses it with 0:10 left:

```lua
song = {
  name = "Papi",            -- matched with "contains"
  artist = "Drake",
  startAt = 133,            -- 2:13
  stopBeforeEnd = 10,       -- pause with 0:10 left
  volume = 100,             -- Music volume after the fade-up
  catalogURL = "music://music.apple.com/us/album/papis-home/1584449196?i=1584449202",
},
```

## Requirements

- macOS with [Hammerspoon](https://www.hammerspoon.org/) 1.1.x
- **Accessibility** permission for Hammerspoon (System Settings > Privacy & Security > Accessibility), so it can move windows
- **Automation** permission for Hammerspoon to control **Music** (macOS asks the first time it runs)
- The song in your Music library. Download it to your Mac if you can; a downloaded track starts almost instantly, while a streamed one has to buffer first.
- This Mac authorized in Music (Account > Authorizations > Authorize This Computer), or downloads and playback can fail with "not authorized"

## Install

1. Copy `init.lua` to `~/.hammerspoon/init.lua`. If you already have a config, merge it in.
2. Edit the `cfg` table at the top:
   - `song`: track name, artist, start time, seconds before the end, volume, and catalog URL
   - `morningHour`: the hour after which the first unlock counts as "morning" (default `4`)
   - `asus` / `lg`: the two screens, matched by part of each screen's name (`match`), plus each app's frame relative to that screen's top-left. Rename these to fit your monitors.
   - `bundles`: bundle IDs for the two side-screen apps. Replace the second one with an app you use. You can find any app's ID with `osascript -e 'id of app "AppName"'`.
   - Speaker name: `playSong()` looks for `"Mac mini Speakers"`. Change it to your Mac's output name, which is listed in System Settings > Sound.
3. Reload Hammerspoon, then press **Ctrl+Opt+Cmd+W** to test.

To measure a window's frame, place it where you want it, then run this in the Hammerspoon console:

```lua
hs.window.focusedWindow():frame()
```

## Hotkeys

| Keys | Action |
| --- | --- |
| Ctrl+Opt+Cmd+W | Run the Welcome scene |
| Ctrl+Opt+Cmd+M | Stop the music |

## Files it writes

Both go in `~/.hammerspoon/`:
- `welcome.log`: a timestamped log of each run, useful for checking timing
- `welcome-state.txt`: remembers the last launch and whether today's morning run already happened

## Tips

- **Uncheck "Reopen windows when logging back in"** in the restart/shut down dialog. Otherwise macOS restores your old windows first and the song starts later.
- **Layouts may overlap.** Many apps have minimum window sizes (Weather, Stocks and Music, for example), so a lot of apps on one screen may not fit side by side. Pick the overlap you like and put the app you need first on top with `focus = true`.
- **Speed.** On a Mac mini with the song downloaded, the music started about 8 seconds after the desktop appeared. Streaming it from the cloud took noticeably longer.

## Coming later: `daytimeReturn()`

`daytimeReturn(reason)` is a stub. It's called when the screensaver stops, when the display wakes, and on unlocks that aren't the morning run. Right now it only logs the event. Fill it in if you want a lighter "welcome back" during the day.

## License

MIT. See [LICENSE](LICENSE).
