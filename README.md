# wow-forever-ui

Personal UI addons for WoW Forever (game 1.60.1, interface 16001).

`KSUI` (shown in game as 검성UI) recolors the default unit frames and action bars, colors player and target health bars by class,
and shows the client's cooldown numbers on the action bars. Party, raid, focus and boss frames stay
Blizzard's own, so they keep working under instance combat restrictions; KSUI only tints and positions them.

It also has small combat and convenience helpers, each with its own toggle:
- Action buttons turn red when the target is out of range. Blizzard's blue for low mana stays as it is.
- Health and mana bars show the percent next to the number, using Blizzard's own bar text.
- The target frame shows Blizzard's threat number. When you are tanking, it shows your lead over the next player.
- Raid frames show only the debuffs you can dispel.
- Blizzard's cooldown manager is turned on. It shows your class and spec cooldowns and buffs by itself, and the layout stacks it up the middle on top of the cast bar.
- Action bars fade out of combat when you have no target. You can set how faded they get.
- At a vendor, gray items are sold and gear is repaired with your own gold.
- On a ready check, chat lists the raid buffs you are missing from the priests, druids and mages in your group.
- When a bag item beats what you wear, chat names it. The `추천 장비 착용` button under the character window puts it on.
  Items are scored by rough stat weights for your spec's role (tank, healer, melee or caster). Armor, necks, cloaks and
  rings are compared; weapons, shields, trinkets and unbound items are left to you, and the same ring is never suggested twice.
- The minimap tracks herbs, ore or fish for the gathering professions you know.

Type `/ksui`, or open Options > AddOns > KSUI, to change the colors, toggles, number size and frame
position. Appearance and cooldown changes apply immediately and are saved in `KSUIDB`.

The frame position applies when you press `적용` or run `/ksui layout` out of combat. That copies the active
Edit Mode layout to a layout named `KSUI` and reloads the UI. That layout puts everything at the bottom except party and raid:
the minimap sits at the bottom center on top of the experience bars, with the action bars split around it. On its left are the main bar,
bar 2, right bar 1 (made horizontal) and the stance bar. On its right are the micro menu with the bags, bar 3, right bar 2 (made horizontal)
and the pet bar. Empty slots on the two right bars are hidden. The cast bar sits on top of the minimap with the cooldown manager stacked above it, buffs and debuffs above the player
frame, and chat is raised to the height of the unit frames. The quest tracker goes to the bottom-right corner with the tooltip above it and
the boss frames above its left edge. Party and raid frames go to the top-left corner,
and the raid frames are set up for 40 players (eight groups side by side, minimum cell size). Doing
it again rebuilds `KSUI` from the active layout. Fine-tune with the game's Edit Mode afterwards.

## Install on Windows

Delete any old `KSUI` and `KSCooldownText` folders from `World of Warcraft\_forever_\Interface\AddOns`,
then extract `wow-forever-ui-0.9.1.zip` there so that `AddOns\KSUI\KSUI.toc` exists. Restart the game client.

## Develop

```sh
luajit tests/run.lua
```
