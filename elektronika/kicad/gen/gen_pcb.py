# -*- coding: utf-8 -*-
"""Generator PCB (pcbnew) - CARRIER: wszystkie moduly w gniazdach zenskich.
   Uruchom Pythonem KiCada:  C:\\TMP\\kicad_portable\\bin\\python.exe gen_pcb.py
ESP32 = DOIT DevKit V1 30-pin -> 2x PinSocket_1x15; moduly GNSS/OLED/IMU/TP4056/buck + ogniwo
jako PinSocket; pasywy (dzielnik, pull-upy, bulk, LED, przycisk) SMD/THT na carrierze.
Nety modulow/pasywow z netlisty schematu; ESP32 mapowany wg pinoutu DevKit V1 (EN/VIN/5V wolne)."""
import re, pcbnew

FPDIR = r"C:\TMP\kicad_portable\share\kicad\footprints"
NET   = r"C:\TMP\kicad_portable\full.net"
OUT   = r"C:\TMP\My_GIT\GPS_RTK\elektronika\kicad\gps_rtk_v1.kicad_pcb"
def fl(lib): return FPDIR + "\\" + lib + ".pretty"
def mm(v): return pcbnew.FromMM(v)
PINSOCK = "Connector_PinSocket_2.54mm"

# --- moduly (gniazda zenskie) + pasywy carriera ---
MOD = {
 "J1": (PINSOCK, "PinSocket_1x06_P2.54mm_Vertical", 14, 16, 0, "GNSS LC29HEA (modul)"),
 "J2": (PINSOCK, "PinSocket_1x04_P2.54mm_Vertical", 14, 34, 0, "OLED SSD1306 (modul)"),
 "J3": (PINSOCK, "PinSocket_1x04_P2.54mm_Vertical", 14, 47, 0, "IMU BNO085 v2 (modul)"),
 "J4": (PINSOCK, "PinSocket_1x04_P2.54mm_Vertical", 88, 16, 0, "Buck-boost 3V3 (modul)"),
 "J5": (PINSOCK, "PinSocket_1x06_P2.54mm_Vertical", 88, 30, 0, "TP4056 USB-C (modul)"),
 "BT1":(PINSOCK, "PinSocket_1x02_P2.54mm_Vertical", 88, 50, 0, "18650 (przewody)"),
 "C1": ("Capacitor_SMD","C_0805_2012Metric", 16, 68, 0, "100uF"),
 "C2": ("Capacitor_SMD","C_0805_2012Metric", 22, 68, 0, "100nF"),
 "R3": ("Resistor_SMD","R_0805_2012Metric", 28, 68, 0, "4k7"),
 "R4": ("Resistor_SMD","R_0805_2012Metric", 34, 68, 0, "4k7"),
 "R1": ("Resistor_SMD","R_0805_2012Metric", 40, 68, 0, "100k"),
 "R2": ("Resistor_SMD","R_0805_2012Metric", 46, 68, 0, "100k"),
 "R5": ("Resistor_SMD","R_0805_2012Metric", 56, 68, 0, "330"),
 "D1": ("LED_SMD","LED_0805_2012Metric", 62, 68, 0, "status"),
 "SW1":("Button_Switch_THT","SW_PUSH_6mm_H5mm", 73, 68, 0, "user"),
}

# --- ESP32 DOIT DevKit V1 (30-pin), kolejnosc fizyczna gora->dol; ZWERYFIKUJ z nadrukiem ---
ESP_L = ["EN","IO36","IO39","IO34","IO35","IO32","IO33","IO25","IO26","IO27","IO14","IO12","IO13","GND","VIN"]
ESP_R = ["3V3","GND","IO15","IO2","IO4","IO16","IO17","IO5","IO18","IO19","IO21","IO3","IO1","IO22","IO23"]
# Etykieta GPIO -> net (tylko uzywane; EN/VIN/5V/GND-nadmiarowe wolne na carrierze)
ESP_LABEL_NET = {
 "3V3":"+3V3", "GND":"GND",
 "IO34":"VBAT_SENSE", "IO35":"GNSS_PPS", "IO27":"BTN",
 "IO16":"GNSS_TX", "IO17":"GNSS_RX", "IO21":"SDA", "IO22":"SCL",
 "IO4":"GNSS_RST", "IO2":"LED_STAT",
}
ESP_ROW_MM = 22.86   # rozstaw rzedow gniazd (0.9") - ZMIERZ na swoim devkicie i popraw
ESP_X, ESP_Y = 42.0, 16
ESP_SOCK = [("U1L", ESP_X, ESP_Y, "ESP32 DevKit V1 (L)", ESP_L),
            ("U1R", ESP_X+ESP_ROW_MM, ESP_Y, "ESP32 DevKit V1 (R)", ESP_R)]

# netlista -> pady modulow/pasywow (U1 chipowe pomijamy)
txt = open(NET, encoding="utf-8").read()
padnet = {}
for m in re.finditer(r'\(net \(code "\d+"\) \(name "([^"]+)"\)(.*?)(?=\(net \(code|\Z)', txt, re.S):
    name = m.group(1).lstrip("/")
    if name.startswith("unconnected-"): continue
    for n in re.finditer(r'\(node \(ref "([^"]+)"\) \(pin "([^"]+)"\)', m.group(2)):
        padnet[(n.group(1), n.group(2))] = name
netnames = sorted(set(list(padnet.values()) + list(ESP_LABEL_NET.values())))
print("nety:", len(netnames))

board = pcbnew.CreateEmptyBoard()
try: board.GetDesignSettings().m_MinThroughDrill = pcbnew.FromMM(0.2)
except Exception as e: print("min drill:", e)
nets = {}
for nm in netnames:
    ni = pcbnew.NETINFO_ITEM(board, nm); board.Add(ni); nets[nm] = ni

assigned = 0; placed = 0; missing = []
for ref,(lib,fpn,x,y,rot,val) in MOD.items():
    fp = pcbnew.FootprintLoad(fl(lib), fpn)
    if fp is None: missing.append(f"{ref}:{fpn}"); continue
    fp.SetReference(ref); fp.SetValue(val); fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
    if rot: fp.SetOrientationDegrees(rot)
    board.Add(fp); placed += 1
    for pad in fp.Pads():
        net = padnet.get((ref, pad.GetNumber()))
        if net: pad.SetNet(nets[net]); assigned += 1
for ref,x,y,val,labels in ESP_SOCK:
    fp = pcbnew.FootprintLoad(fl(PINSOCK), "PinSocket_1x15_P2.54mm_Vertical")
    if fp is None: missing.append(f"{ref}:1x15"); continue
    fp.SetReference(ref); fp.SetValue(val); fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
    board.Add(fp); placed += 1
    for pad in fp.Pads():
        i = int(pad.GetNumber())
        label = labels[i-1] if 1 <= i <= len(labels) else None
        net = ESP_LABEL_NET.get(label)
        if net: pad.SetNet(nets[net]); assigned += 1
print("footprinty:", placed, "| pady przypisane:", assigned, "| braki:", missing)

# obrys 100 x 78 mm
rect = pcbnew.PCB_SHAPE(board); rect.SetShape(pcbnew.SHAPE_T_RECT)
rect.SetStart(pcbnew.VECTOR2I(mm(0), mm(0))); rect.SetEnd(pcbnew.VECTOR2I(mm(100), mm(78)))
rect.SetLayer(pcbnew.Edge_Cuts); rect.SetWidth(mm(0.15)); board.Add(rect)

board.BuildListOfNets()
pcbnew.SaveBoard(OUT, board)
print("OK ->", OUT)
