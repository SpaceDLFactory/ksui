"""Write a KSUI-style HUD into one HUD layout slot of an FFXIV ADDON.DAT.

Usage: python3 ksui_layout.py ADDON.DAT OUT.DAT [slot]   (slot 1-4, default 4)

The slot starts as a copy of the slot whose records match the live "Default" set (the layout in use),
then the KSUI elements are moved. Scales are kept. Nothing outside that slot changes.
In game, `/hudlayout <slot>` switches to it; `/hudlayout <old slot>` goes back.
"""
import struct
import sys

import addondat as a

# Screen units: percent positions are converted with the HUD's own unit size. Measured from the user's
# stacked hotbars, one HUD unit is about 1/2100 of the screen height on their 4K screen.
UNITS_H = 2100.0
UNITS_W = UNITS_H * 16 / 9
GAP = 4  # units between stacked elements

# Anchor byte: 3x3 grid, 0 top-left ... 8 bottom-right.
TL, TC, TR, BL, BC, BR = 0, 1, 2, 6, 7, 8

# Hotbar flags: low byte bar index, high byte shape. Shape 0 is 12x1.
HORIZONTAL = 0


def build(data, slot):
    live = {r[0]: r for _, r in a.records(data, a.DEFAULT_START, struct.unpack_from("<I", data, a.DEFAULT_COUNT_AT)[0])}
    starts = [s for name, s, c in a.blocks(data) if name != "default"]
    current = max(range(4), key=lambda i: sum(1 for _, r in a.records(data, starts[i], a.LAYOUT_COUNT) if r[0] and live.get(r[0]) == r))
    out = bytearray(data)
    src, dst = starts[current], starts[slot - 1]
    out[dst:dst + a.LAYOUT_COUNT * a.REC.size] = data[src:src + a.LAYOUT_COUNT * a.REC.size]

    recs = {}
    for off, r in a.records(out, dst, a.LAYOUT_COUNT):
        if r[0]:
            recs[r[0]] = [off, list(r)]

    def get(name):
        return recs.get(a.name_hash(name))

    def size(name):
        r = get(name)[1]
        return r[5] * r[3], r[6] * r[3]

    def put(name, anchor, x_units, y_units, flags=None, wh=None):
        rec = get(name)
        if rec is None:
            return False
        r = rec[1]
        r[1], r[2] = x_units / UNITS_W * 100, y_units / UNITS_H * 100
        if flags is not None:
            r[4] = flags
        if wh is not None:
            r[5], r[6] = wh
        tail = bytearray(r[7])
        tail[0] = anchor
        r[7] = bytes(tail)
        return True

    def bar(name, index):
        put_flags = (HORIZONTAL << 8) | index
        r = get(name)
        if r is not None:
            r[1][4], r[1][5], r[1][6] = put_flags, 624, 72

    cx, bottom = UNITS_W / 2, UNITS_H
    moved = []

    def place(name, anchor, x, y):
        if put(name, anchor, x, y):
            moved.append(name)

    # Middle column, bottom up: experience bar, minimap, cast bar, job gauges.
    _, exp_h = size("_Exp")
    place("_Exp", BC, cx, bottom)
    y = bottom - exp_h - GAP
    map_w, map_h = size("_NaviMap")
    place("_NaviMap", BC, cx, y)
    y -= map_h + GAP
    place("_CastBar", BC, cx, y)
    y -= size("_CastBar")[1] + GAP
    gauge_top = y
    # Only one job's gauges show at a time, so every job stacks in the same spot.
    for job in JOBS:
        y0 = gauge_top
        for part in ("JobHud%s0" % job, "JobHud%s1" % job):
            if get(part):
                place(part, BC, cx, y0)
                y0 -= size(part)[1] + GAP

    # The side stacks clear both the minimap and the experience bar under it.
    half = max(map_w, size("_Exp")[0]) / 2
    left, right = cx - half - GAP, cx + half + GAP

    # Left of the minimap: main bar, bar 2, bar 3 stacked, then HP/MP and buffs.
    for i, name in enumerate(("_ActionBar", "_ActionBar01", "_ActionBar02")):
        bar(name, i)
    y = bottom
    for name in ("_ActionBar", "_ActionBar01", "_ActionBar02"):
        place(name, BR, left, y)
        y -= size(name)[1] + GAP
    place("_ParameterWidget", BR, left, y)
    y -= size("_ParameterWidget")[1] + GAP
    # _Status is the unsplit buff list; only one of it or the three split lists is shown.
    place("_Status", BR, left, y)
    for name in ("_StatusCustom0", "_StatusCustom1", "_StatusCustom2"):
        place(name, BR, left, y)
        y -= size(name)[1] + GAP

    # Right of the minimap: main menu and bags, bar 4, bar 5 (made horizontal), pet bar, then the target.
    menu_h = max(size("_MainCommand")[1], size("_BagWidget")[1])
    place("_MainCommand", BL, right, bottom)
    place("_BagWidget", BL, right + size("_MainCommand")[0] + GAP, bottom)
    y = bottom - menu_h - GAP
    for i, name in ((3, "_ActionBar03"), (4, "_ActionBar04")):
        bar(name, i)
    for name in ("_ActionBar03", "_ActionBar04", "_ActionBarEx"):
        place(name, BL, right, y)
        y -= size(name)[1] + GAP
    for name in ("_TargetInfoMainTarget", "_TargetInfo"):
        place(name, BL, right, y)
    y -= size("_TargetInfoMainTarget")[1] + GAP
    place("_TargetInfoCastBar", BL, right, y)
    y -= size("_TargetInfoCastBar")[1] + GAP
    place("_TargetInfoBuffDebuff", BL, right, y)

    # Party top-left, alliance lists beside it, enemy list under it.
    edge = 10
    place("_PartyList", TL, edge, edge)
    party_w, party_h = size("_PartyList")
    place("_AllianceList1", TL, edge + party_w + GAP, edge)
    place("_AllianceList2", TL, edge + party_w + GAP, edge + size("_AllianceList1")[1] + GAP)
    place("_EnemyList", TL, edge, edge + party_h + GAP)

    # Quest tracker bottom-right with the tooltips above it; server info top-right.
    place("_ToDoList", BR, UNITS_W - edge, bottom - edge)
    todo_h = size("_ToDoList")[1]
    place("ItemDetail", BR, UNITS_W - edge, bottom - edge - todo_h - GAP)
    place("ActionDetail", BR, UNITS_W - edge, bottom - edge - todo_h - GAP)
    place("_DTR", TR, UNITS_W - edge, edge)

    for off, r in recs.values():
        a.REC.pack_into(out, off, *r)
    return bytes(out), current + 1, moved


JOBS = "PLD WAR DRK GNB WHM SCH AST SGE MNK DRG NIN SAM RPR VPR BRD MCH DNC BLM SMN RDM PCT ACN XBM".split()


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    slot = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    data = open(src, "rb").read()
    new, current, moved = build(data, slot)
    open(dst, "wb").write(new)
    print("copied slot %d into slot %d, moved %d: %s" % (current, slot, len(moved), " ".join(moved)))
