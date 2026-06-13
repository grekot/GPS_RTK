# -*- coding: utf-8 -*-
"""Generator pelnego schematu KiCad odbiornika GPS RTK v1.
Symbole z bibliotek KiCad 9; polaczenia przez etykiety netow (po nazwie).
Weryfikacja: kicad-cli sch export netlist."""
import uuid as U, copy
from kiutils.schematic import Schematic
from kiutils.symbol import SymbolLib
from kiutils.items.schitems import (SchematicSymbol, LocalLabel, Connection,
                                    SymbolProjectInstance, SymbolProjectPath, Text)
from kiutils.items.common import Position, Property

SD = r"C:\TMP\kicad_portable\share\kicad\symbols"
OUT = r"C:\TMP\My_GIT\GPS_RTK\elektronika\kicad\gps_rtk_v1.kicad_sch"
PROJ = "gps_rtk_v1"
L = 2.54

def u(): return str(U.uuid4())

libs = {n: SymbolLib.from_file(SD + f"\\{n}.kicad_sym")
        for n in ("Device", "Connector_Generic", "Switch", "RF_Module")}

def getsym(libid):
    lib, name = libid.split(":")
    for s in libs[lib].symbols:
        if s.libId == name:
            return s
    raise KeyError(libid)

def pinmap(sym):
    m = {}
    for un in sym.units:
        for p in (getattr(un, "pins", []) or []):
            m[p.number] = (p.position.X, p.position.Y, p.position.angle)
    return m

# --- komponenty: (lib_id, ref, value, x, y, dnp, {pin_number: net}) ---
COMPONENTS = [
    dict(lib="RF_Module:ESP32-WROOM-32", ref="U1", val="ESP32-WROOM-32", x=150, y=140, nets={
        "2": "+3V3", "1": "GND", "3": "+3V3",          # VDD, GND, EN(pull-up)
        "27": "GNSS_TX", "28": "GNSS_RX",              # IO16(RX2), IO17(TX2)
        "33": "SDA", "36": "SCL",                       # IO21, IO22
        "24": "LED_STAT", "12": "BTN",                  # IO2, IO27
        "6": "VBAT_SENSE", "7": "GNSS_PPS", "26": "GNSS_RST"}),  # IO34, IO35, IO4
    dict(lib="Connector_Generic:Conn_01x06", ref="J1", val="GNSS LC29HEA", x=70, y=72, nets={
        "1": "+3V3", "2": "GND", "3": "GNSS_TX", "4": "GNSS_RX", "5": "GNSS_PPS", "6": "GNSS_RST"}),
    dict(lib="Connector_Generic:Conn_01x04", ref="J2", val="OLED SSD1306", x=70, y=115, nets={
        "1": "+3V3", "2": "GND", "3": "SCL", "4": "SDA"}),
    dict(lib="Connector_Generic:Conn_01x04", ref="J3", val="IMU BNO085 (v2)", x=70, y=150, dnp=True, nets={
        "1": "+3V3", "2": "GND", "3": "SCL", "4": "SDA"}),
    dict(lib="Connector_Generic:Conn_01x04", ref="J4", val="Buck-boost 3V3", x=70, y=195, nets={
        "1": "VBAT", "2": "GND", "3": "+3V3", "4": "+3V3"}),  # VIN, GND, VOUT, SHDN->ON
    dict(lib="Connector_Generic:Conn_01x06", ref="J5", val="TP4056 USB-C", x=95, y=240, nets={
        "1": "VBUS", "2": "GND", "3": "BATT_CELL", "4": "GND", "5": "VBAT", "6": "GND"}),
    dict(lib="Device:Battery_Cell", ref="BT1", val="18650 3500mAh", x=40, y=242, nets={
        "1": "BATT_CELL", "2": "GND"}),
    dict(lib="Device:R", ref="R1", val="100k", x=250, y=110, nets={"1": "VBAT", "2": "VBAT_SENSE"}),
    dict(lib="Device:R", ref="R2", val="100k", x=250, y=132, nets={"1": "VBAT_SENSE", "2": "GND"}),
    dict(lib="Device:R", ref="R3", val="4k7", x=285, y=110, nets={"1": "+3V3", "2": "SDA"}),
    dict(lib="Device:R", ref="R4", val="4k7", x=305, y=110, nets={"1": "+3V3", "2": "SCL"}),
    dict(lib="Device:R", ref="R5", val="330", x=250, y=170, nets={"1": "LED_STAT", "2": "LED_A"}),
    dict(lib="Device:LED", ref="D1", val="status", x=250, y=190, nets={"2": "LED_A", "1": "GND"}),
    dict(lib="Switch:SW_Push", ref="SW1", val="user", x=300, y=170, nets={"1": "BTN", "2": "GND"}),
    dict(lib="Device:C", ref="C1", val="100uF", x=330, y=110, nets={"1": "+3V3", "2": "GND"}),
    dict(lib="Device:C", ref="C2", val="100nF", x=350, y=110, nets={"1": "+3V3", "2": "GND"}),
]

sch = Schematic.create_new()
sch.version = "20231120"
sch.generator = "kiutils"
ROOT = "a1b2c3d4-0000-4000-8000-000000000001"  # zgodny z 'sheets' w gps_rtk_v1.kicad_pro
sch.uuid = ROOT
try:
    sch.paper.paperSize = "A3"
except Exception as e:
    print("paper:", e)
try:
    from kiutils.items.common import TitleBlock
    sch.titleBlock = TitleBlock(title="Odbiornik GPS RTK - v1 (prototyp devkit)",
                                date="2026-06-13", revision="v1", company="Projekt GPS_RTK")
except Exception as e:
    print("titleblock skip:", e)

embedded = set()
def ensure_lib(libid):
    if libid in embedded:
        return
    s = copy.deepcopy(getsym(libid))
    s.libId = libid
    sch.libSymbols.append(s)
    embedded.add(libid)

def add_comp(c):
    ensure_lib(c["lib"])
    X, Y = c["x"], c["y"]
    sym = SchematicSymbol()
    sym.libId = c["lib"]
    sym.position = Position(X, Y, 0)
    sym.unit = 1
    sym.inBom = not c.get("dnp", False)
    sym.onBoard = True
    sym.uuid = u()
    if c.get("dnp"):
        sym.dnp = True
    sym.properties = [
        Property(key="Reference", value=c["ref"], position=Position(X + 1.27, Y - 1.27, 0)),
        Property(key="Value", value=c["val"], position=Position(X + 1.27, Y + 1.27, 0)),
    ]
    pm = pinmap(getsym(c["lib"]))
    sym.pins = {n: u() for n in pm}
    inst = SymbolProjectInstance(name=PROJ)
    inst.paths.append(SymbolProjectPath(sheetInstancePath="/" + ROOT, reference=c["ref"], unit=1))
    sym.instances.append(inst)
    sch.schematicSymbols.append(sym)
    for num, net in c["nets"].items():
        px, py, ang = pm[num]
        ax, ay = X + px, Y - py
        # kierunek stubu wg KATA pinu: 0/180 = poziomy, 90/270 = pionowy
        if int(ang or 0) % 180 == 0:
            ox, oy = (L if px > 0 else -L), 0
        else:
            ox, oy = 0, (-L if py > 0 else L)
        sch.graphicalItems.append(Connection(type="wire",
            points=[Position(ax, ay), Position(ax + ox, ay + oy)], uuid=u()))
        sch.labels.append(LocalLabel(text=net, position=Position(ax + ox, ay + oy, 0), uuid=u()))

for c in COMPONENTS:
    add_comp(c)

def note(txt, x, y):
    sch.texts.append(Text(text=txt, position=Position(x, y, 0), uuid=u()))

note("ODBIORNIK GPS RTK - schemat v1 (pelny). Polaczenia po nazwie netu.", 20, 18)
note("Moduly GNSS/OLED/IMU/TP4056/buck-boost jako zlacza. Szczegoly: docs/02, docs/05.", 20, 25)

sch.to_file(OUT)
print("OK ->", OUT, "| symbole:", len(sch.schematicSymbols), "| etykiety:", len(sch.labels))
