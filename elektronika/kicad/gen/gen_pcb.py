# -*- coding: utf-8 -*-
"""Generator PCB (pcbnew) - CARRIER: wszystkie moduly w gniazdach zenskich.
   Uruchom Pythonem KiCada:  C:\\TMP\\kicad_portable\\bin\\python.exe gen_pcb.py
ESP32-DevKitC (38-pin) jako 2x PinSocket_1x19; moduly GNSS/OLED/IMU/TP4056/buck + ogniwo
jako PinSocket; pasywy (dzielnik, pull-upy, bulk, LED, przycisk) SMD/THT na carrierze.
Nety z netlisty schematu; ESP32 mapowany wg pinoutu DevKitC V4 (EN/5V wolne - obsluga devkitu)."""
import re, pcbnew

FPDIR = r"C:\TMP\kicad_portable\share\kicad\footprints"
NET   = r"C:\TMP\kicad_portable\full.net"
OUT   = r"C:\TMP\My_GIT\GPS_RTK\elektronika\kicad\gps_rtk_v1.kicad_pcb"
def fl(lib): return FPDIR + "\\" + lib + ".pretty"
def mm(v): return pcbnew.FromMM(v)
PINSOCK = "Connector_PinSocket_2.54mm"

# --- moduly (gniazda zenskie) + pasywy carriera: ref -> (lib, fp, x, y, rot, value) ---
MOD = {
 "J1": (PINSOCK, "PinSocket_1x06_P2.54mm_Vertical", 14, 14, 0, "GNSS LC29HEA (modul)"),
 "J2": (PINSOCK, "PinSocket_1x04_P2.54mm_Vertical", 14, 32, 0, "OLED SSD1306 (modul)"),
 "J3": (PINSOCK, "PinSocket_1x04_P2.54mm_Vertical", 14, 45, 0, "IMU BNO085 v2 (modul)"),
 "J4": (PINSOCK, "PinSocket_1x04_P2.54mm_Vertical", 88, 14, 0, "Buck-boost 3V3 (modul)"),
 "J5": (PINSOCK, "PinSocket_1x06_P2.54mm_Vertical", 88, 28, 0, "TP4056 USB-C (modul)"),
 "BT1":(PINSOCK, "PinSocket_1x02_P2.54mm_Vertical", 88, 48, 0, "18650 (przewody)"),
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

# --- ESP32-DevKitC (38-pin) = 2x PinSocket_1x19. Mapa pad->net wg pinoutu DevKitC V4 ---
# Lewa kolumna (pad1 = gora):  1=3V3 2=EN 3=IO36 4=IO39 5=IO34 6=IO35 7=IO32 8=IO33 9=IO25
#   10=IO26 11=IO27 12=IO14 13=IO12 14=GND 15=IO13 16=IO9 17=IO10 18=IO11 19=5V
# Prawa kolumna: 1=GND 2=IO23 3=IO22 4=TX0 5=RX0 6=IO21 7=GND 8=IO19 9=IO18 10=IO5
#   11=IO17 12=IO16 13=IO4 14=IO0 15=IO2 16=IO15 17=IO8 18=IO7 19=IO6
ESP_L = {"1":"+3V3", "5":"VBAT_SENSE", "6":"GNSS_PPS", "11":"BTN", "14":"GND"}   # EN(2),5V(19)=wolne
ESP_R = {"1":"GND", "3":"SCL", "6":"SDA", "7":"GND", "11":"GNSS_RX", "12":"GNSS_TX", "13":"GNSS_RST", "15":"LED_STAT"}
ESP_SOCK = [  # ref, x, y, value, padnet
 ("U1L", 42.0, 14, "ESP32-DevKitC (lewa)", ESP_L),
 ("U1R", 64.86, 14, "ESP32-DevKitC (prawa)", ESP_R),  # rozstaw rzedow 22.86 mm (0.9in) - ZWERYFIKUJ z devkitem
]

# netlista -> pady modulow/pasywow (U1 chipowe pomijamy - ESP32 mapujemy wlasna tabela)
txt = open(NET, encoding="utf-8").read()
padnet = {}
for m in re.finditer(r'\(net \(code "\d+"\) \(name "([^"]+)"\)(.*?)(?=\(net \(code|\Z)', txt, re.S):
    name = m.group(1).lstrip("/")
    if name.startswith("unconnected-"):
        continue
    for n in re.finditer(r'\(node \(ref "([^"]+)"\) \(pin "([^"]+)"\)', m.group(2)):
        padnet[(n.group(1), n.group(2))] = name
netnames = sorted(set(list(padnet.values()) + list(ESP_L.values()) + list(ESP_R.values())))
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
for ref,x,y,val,pm in ESP_SOCK:
    fp = pcbnew.FootprintLoad(fl(PINSOCK), "PinSocket_1x19_P2.54mm_Vertical")
    if fp is None: missing.append(f"{ref}:1x19"); continue
    fp.SetReference(ref); fp.SetValue(val); fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
    board.Add(fp); placed += 1
    for pad in fp.Pads():
        net = pm.get(pad.GetNumber())
        if net: pad.SetNet(nets[net]); assigned += 1
print("footprinty:", placed, "| pady przypisane:", assigned, "| braki:", missing)

# obrys 100 x 78 mm
rect = pcbnew.PCB_SHAPE(board); rect.SetShape(pcbnew.SHAPE_T_RECT)
rect.SetStart(pcbnew.VECTOR2I(mm(0), mm(0))); rect.SetEnd(pcbnew.VECTOR2I(mm(100), mm(78)))
rect.SetLayer(pcbnew.Edge_Cuts); rect.SetWidth(mm(0.15)); board.Add(rect)

board.BuildListOfNets()
pcbnew.SaveBoard(OUT, board)
print("OK ->", OUT)
