# KSUI (검성UI) — handoff notes for Claude Code

An open-source UI addon for **WoW: Forever** (Blizzard's official 2026 classic-style game; game type `camelot`,
interface 16001, client 1.60.1). Public name 검성UI (Kumsung UI); folder, slash command (`/ksui`), saved variables
(`KSUIDB`) and Edit Mode layout are all named `KSUI`. GPL-3.0-or-later. GitHub: SpaceDLFactory/ksui.
CurseForge project 1809000, slug `ksui-kumsungui`. Current release: **0.13.7** (2026-11-21).

Development moved from a Mac session to this Windows machine on 2026-11-20. The game runs here:
`F:\World of Warcraft\_forever_\Interface\AddOns\KSUI` (the Mac copied files there over SSH; that copy matches
`main` at 0.13.5).

## Working with the user

- Reply in Korean, short. Technical terms, code, commands and commit messages stay in English.
- At a fork, give 2–4 options with one recommended. The user often answers with a number or "ㄱㄱ" (go).
- Claims need evidence: test output, a screenshot from the user, a command result. Report unverified parts separately.
  The user plays and sends in-game screenshots; most features are confirmed that way.
- One commit per feature, Conventional Commits in English, body says why and how it was verified, ending with
  the attribution lines your session gives you.
- Pushing commits to `main` is fine after verification. **Tags/releases (and anything else outward) need the user's
  explicit OK each time.** "마이너버전 하나 올려서" means the last digit (0.13.5 → 0.13.6). Say the new number first.
- Other players' names and chat in screenshots get pixelated before anything is published.

## Layout of the repo

- `addons/KSUI/` — the addon. `KSUI.toc` lists load order and the version.
  - `Core.lua` init order (PLAYER_LOGIN), slash commands, ADDON_ACTION_BLOCKED log (`KSUIDB.blockedLog`).
  - `Options.lua` settings panel (each option: key, label, default, optional `refresh` callback, `layout = true`
    for options that change the Edit Mode layout, `choices` for dropdowns).
  - `Layout.lua` builds the `KSUI` Edit Mode layout (positions as screen shares, reference screen 2133x1200).
    Applied while the UI loads (first install, after an update, after layout settings changed) and on logout;
    `/ksui layout` applies and reloads at once.
  - `UnitFrames.lua` square player/target/focus/party frames drawn over Blizzard's (Blizzard's stay underneath,
    faded, for clicks/menus/auras). Heal prediction + absorb bars, threat glow (Blizzard's FrameFlash reparented),
    party row for you (`KSUIPartyPlayer`), role icons, party debuffs moved out from under the rows.
  - `ShortBuffs.lua` shield/HoT icons on KSUI party rows, Blizzard party frames and Compact raid frames.
  - `Nameplates.lua` flat nameplates, level/skull, white target border.
  - `Meter.lua` damage meter (C_DamageMeter), `Threat.lua` party threat meter, `CooldownCast.lua` clickable
    cooldown manager, `Quest.lua` quest arrow, `AutoQuest.lua`, `Chat.lua`, `Convenience.lua` (loot, tooltip,
    invites, XP text, movie skip), `Gear.lua` gear suggestions, `ReadyCheck.lua` missing buffs, `Combat.lua`,
    `Skin.lua`, `Cooldown.lua`, `Merchant.lua`, `Tracking.lua`.
- `tests/run.lua` — one big LuaJIT harness that mocks the WoW API and boots the addon (564 checks).
  Run `luajit tests/run.lua`; it must end with `0 failures` before any commit. On this Windows machine LuaJIT is
  `F:\dev\env\luajit\luajit.exe` (built from source with the MSVC tools in `F:\BuildTools`); every dev tool lives
  under `F:\dev\env`, none on C:. `F:\dev\env\deploy-ksui.ps1` runs the tests and mirrors `addons\KSUI` into the
  game folder. Blizzard's Forever UI source is checked out at `F:\dev\env\ref\wow-ui-forever`.
- Text shown in game goes through `ns.T("한국어", "English")` (Locale.lua); a test fails on a Korean literal outside it.
- `docs/curseforge.md` — CurseForge page text (English first, moderation requires it). The user pastes the part
  after `# Description` into the CurseForge Description tab by hand; keep it in step with released features.
- `.github/workflows/release.yml` + `.pkgmeta` — pushing a `v*` tag runs the tests, then BigWigs packager v2.6.1
  makes `KSUI-vX.Y.Z-forever.zip`, a GitHub Release and the CurseForge upload (secret `CF_API_KEY` is set).
  `workflow_dispatch` is a dry run. CurseForge files go through approval before they're public.

## Release steps

1. Tests pass, feature commits pushed.
2. Bump `## Version:` in `addons/KSUI/KSUI.toc`; update README.md and docs/curseforge.md if features changed.
3. `chore: release X.Y.Z` commit, push, then (with the user's OK) `git tag -a vX.Y.Z -m X.Y.Z && git push origin vX.Y.Z`.
4. `gh run watch` the release run; check the log for `Uploading KSUI-vX.Y.Z-forever.zip ... Success!`.
5. Copy the changed files into the game folder and tell the user to `/reload`.

## Forever / Midnight-era API facts (measured in game — trust these over retail habits)

- **Secret values**: health, power, absorbs, auras, threat, names, levels can be secret in instances. Tainted addon
  code may only pass them to secret-safe setters (SetValue, SetMinMaxValues, SetText, SetFormattedText, SetAlpha,
  SetAlphaFromBoolean, SetVertexColorFromBoolean, SetTexture, SetCooldownFromDurationObject). Never compare or
  index them: check `issecretvalue(x)` first, and `canaccesstable(t)` before indexing a table.
- **ReloadUI** only works right after a click/key press (from a timer or OnHide it is ADDON_ACTION_BLOCKED).
- **Specializations**: one per class, always reported as DAMAGER with intellect. The real role comes from the three
  Classic talent trees: `C_ClassTalents.GetActiveConfigID` → `C_Traits.GetConfigInfo().treeIDs[1]` →
  `GetGroupDisplayInfoByTreeID` (sort by orderIndex) → `GetGroupCurrencyInfo(...).currencyInfos[1].spent`.
- **Party members' auras** come with `duration = 0`, and `C_UnitAuras.GetUnitAuras` ignores filters such as
  PLAYER and RAID_IN_COMBAT. Short buffs are therefore picked by spell name and timed by KSUI from UNIT_AURA's
  addedAuras with a duration table (ShortBuffs.lua); ones already up at reload stay untimed.
- `GetItemStats` keys: `ITEM_MOD_STRENGTH_SHORT`, `ITEM_MOD_HEALTH_REGEN_SHORT`, `RESISTANCE0_NAME` (armor) etc.
- Nameplates get restyled (`UpdateAnchors`) before they have a unit — guard `unitFrame.unit`.
- Blizzard's party frames already draw debuffs (`member.AuraFrameContainer`) and threat (`member.Flash`); KSUI
  moves them rather than reimplementing them. Same idea for the target aura container and player FrameFlash.
- Don't make Edit Mode systems depend on addon frames, and don't add KSUI frames to Blizzard layout frames
  (layoutIndex) — both spread taint into secure code.
- At saved-variables load UIParent is still 1365x768; measure the screen later (EDIT_MODE_LAYOUTS_UPDATED or after).
- The API docs say how each guarded call fails: a precondition with `FailureMode = "Error"` (e.g.
  `RequiresUnitAuraAccess` on every aura query) raises for addon code instead of returning a secret; check first
  (`C_Secrets.ShouldAurasBeSecret()`) and pcall. `tools/api-throws.lua <docs dir> addons/KSUI` lists every call
  site of such an API; `tools/api-flags.lua` lists the secret flags of every API the addon calls. Re-run both after
  a client patch. Event payloads can be secret too (`UNIT_AURA`'s unit is, where auras are restricted).
- Classic Blessing of Kings uses a purple helmet icon (not a crown) — not a bug.
- Chat `/run` lines are capped at 255 characters; split long diagnostics.

Blizzard's Forever UI source: `Gethe/wow-ui-source`, branch `forever`. Fetch single files with
`gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/<path>?ref=forever" -H "Accept: application/vnd.github.raw"`
and the file list with `gh api "repos/Gethe/wow-ui-source/git/trees/forever?recursive=1"`. API docs are under
`Interface/AddOns/Blizzard_APIDocumentationGenerated/`.

## Open items at handoff (2026-11-20)

Not yet confirmed in game:
- Layout saved at load: does it show in the same session or only from the next load?
- Ready check list of members missing buffs; party aggro edge; feral druid bear form = tank (form IDs 5/8).
- Shield/HoT icons on Blizzard raid frames, raid-style party and Blizzard party frames (0.13.3).
- Nameplate UnitLevel(nil) error gone (0.13.4); XP text hides under Blizzard's hover text (0.13.5).
- CurseForge description needs re-pasting after each release.
- Released in 0.13.6 (2026-11-20), not yet confirmed in game: swing timers (Blizzard_SwingTimer via `showSwingTimer`, stacked
  on the cooldown manager), ammo count on the player frame, square pet and target-of-target frames, settings
  export/import (`/ksui export`, `/ksui import`), English text via `ns.T("한국어", "English")`, and no aura queries
  while `C_Secrets.ShouldAurasBeSecret()` (they raised "Auras cannot be accessed when secret while tainted" in
  instances). None of these is confirmed in game yet; the layout needs `/ksui layout` once for the swing timers.
- 0.13.7 (2026-11-21): fixes from a Codex (gpt-6.2-astra) cross-check, not yet confirmed in game. Known and left:
  CooldownCast buttons can point at the wrong spell after an in-combat full UNIT_AURA relayout (secure attributes
  can't change in combat); the enemy channel bar fills instead of draining (SetTimerDuration refuses secrets from
  tainted code); quest arrow skips collapsed quest log headers; nameplate level not refreshed on UNIT_LEVEL.

Ideas the user raised, not built:
- A split action bar "centred on the screen" (an earlier attempt was the wrong shape and was removed — ask for a
  sketch first).
- Questie-style objective markers (decided: recommend Questie instead).
