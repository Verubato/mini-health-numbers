# MiniHealthNumbers - bot reference

## What it does

MiniHealthNumbers shows real health values (e.g. "1.2k / 4.3k") instead of only
percentages on the target and focus frames, for Classic Era and TBC Classic clients where
Blizzard does not expose real health numbers for everything. Mob health and grouped
players' health are shown with full accuracy; enemy players, non-grouped players and pets
are estimated from combat log events.

## Facts

| Item | Value |
|---|---|
| Version | 1.7.5 |
| Interface versions (.toc) | 20506 (TBC Classic 2.5.6), 11509 (Classic Era 1.15.x). Not for retail. |
| Saved variables | MiniHealthNumbersDB, account wide (settings only) |
| Slash commands | /minihealthnumbers, /minihn, /mhn (all open the settings panel) |
| Settings location | Game Menu -> Options -> AddOns -> MiniHealthNumbers |
| Frames affected | Target frame and focus frame only |
| Public API | Global MiniHealthNumbersApi (see API section) |
| Support | Discord: https://discord.gg/UruPTPHHxK |

## How health is determined

Stated in the addon's own options panel:

- Mob (NPC) health: full accuracy (read directly from the client).
- Your own health and players in your party/raid: full accuracy.
- Everyone else (enemy players, non-grouped players) and pets: estimated from combat log
  events.

Estimation mechanics (for the estimated group):

- The addon watches damage and healing combat log events on player characters (swing,
  spell, ranged and periodic damage; direct and periodic heals; overkill, resists, blocks,
  absorbs and overheal are subtracted).
- It pairs the net damage/healing over a window (max 30 seconds) with the observed change
  in the unit's health percentage to infer the unit's max health
  (max = net amount / percent change).
- New estimates are blended into the old one with adaptive smoothing: small corrections
  move slowly, large discrepancies move fast. This means an estimate can start wrong and
  converge as more combat is observed.
- Estimates are held in memory for the session only, so they start empty on every login
  and are not written to saved variables. An entry not seen for 1 hour is discarded, and
  the sweep runs once a minute.
- Death (UNIT_DIED) sets the unit's known health to 0.
- No estimate can be shown until the addon has both a max-health estimate and a current
  health percentage for the unit, so a freshly seen enemy player may show nothing at
  first.

## Display behaviour

The addon writes into the status text of the target/focus health bar and follows
Blizzard's "Status Text" display setting (the statusTextDisplay CVar):

- Percent or Numeric: shows "current / max" centered (abbreviated, e.g. "1.2k"). Percent
  mode intentionally shows real values too, since percent-only makes no sense with this
  addon.
- Both: shows the percentage on the left and the current value on the right.
- If the CVar is unavailable or set to a value other than the above (e.g. status text
  disabled), the addon displays nothing.
- Large numbers are abbreviated with Blizzard's AbbreviateNumbers.
- At 0 health the addon steps aside and Blizzard's "Dead" text shows.

Client differences:

- TBC Classic: hooks the frame's own text update function and reuses Blizzard's text
  regions.
- Classic Era: the target frame has no health text regions, so the addon creates its own
  font strings on the health bar and refreshes them from UNIT_HEALTH events.

## Settings reference

| UI label | Default | Effect |
|---|---|---|
| Exclude max | OFF | Only show current hp; hides the " / max" part. Tooltip: "Only show the current hp (exclude max hp)." |

That is the only setting. The options panel also shows a red warning line when another
addon has put MiniHealthNumbers into passive mode:
"'<AddonName>' is controlling UI updates and we are running in passive mode."

## API for other addons

Global table MiniHealthNumbersApi, versioned namespace v1:

- MiniHealthNumbersApi.v1:GetHealth(unit) -> current, max (or nil, nil)
- MiniHealthNumbersApi.v1:GetHealthByGuid(guid) -> current, max (or nil, nil)
- MiniHealthNumbersApi.v1:PassiveMode(addonName) -> stops MiniHealthNumbers updating any
  text; the calling addon handles display itself using the API. addonName (string) is
  shown in the options panel warning.
- MiniHealthNumbersApi.v1:ActiveMode() -> resumes normal text updates.

## Troubleshooting by symptom

- "No numbers on my target frame": check Blizzard's Status Text setting; if status text
  is off (statusTextDisplay not Percent/Numeric/Both) the addon shows nothing. Also
  confirm you are looking at the target or focus frame; no other frames are touched.
- "No numbers on an enemy player": expected until the addon has seen enough combat log
  activity on them to build an estimate. Numbers appear once damage/healing has been
  observed alongside a health percent change.
- "The number on an enemy player looks wrong": enemy player health is an estimate from
  combat log data; it self-corrects as more damage/healing is observed. Large jumps are
  smoothed.
- "It shows 'Dead' not 0": intentional; at 0 hp Blizzard's dead text is left alone.
- "Numbers on party/raid members or mobs are wrong": those come straight from the client
  and are not estimated; if they look wrong the client is reporting them that way.
- "Red text in the options about passive mode": another addon (named in the message)
  called the passive mode API and is handling display itself. That addon can release
  control via ActiveMode.
- "Does it work on retail / Wrath / Cata?": no; the .toc lists TBC Classic (2.5.6) and
  Classic Era (1.15.x) only. Retail already shows real health values.
- "Can it show only current hp without the max?": yes, enable "Exclude max". Note this
  applies to the centered "current / max" text (Percent/Numeric status text modes); in
  "Both" mode the right-hand value is already current-only.
- "Does it show numbers on nameplates or raid frames?": no, target and focus frames only.
