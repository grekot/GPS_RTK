# -*- coding: utf-8 -*-
"""Generator PCB (pcbnew). Uruchom Pythonem KiCada:
   C:\\TMP\\kicad_portable\\bin\\python.exe gen_pcb.py
Footprinty + nety z netlisty schematu + obrys. Bez trasowania (ratsnest)."""
import re, pcbnew

FPDIR = r"C:\TMP\kicad_portable\share\kicad\footprints"
NET   = r"C:\TMP\kicad_portable\full.net"
OUT   = r"C:\TMP\My_GIT\GPS_RTK\elektronika\kicad\gps_rtk_v1.kicad_pcb"
def fl(lib): return FPDIR + "\\" + lib + ".pretty"
def mm(v): return pcbnew.FromMM(v)

# ref -> (libdir, footprint, x_mm, y_mm, rot_deg, value)
COMP = {
 "U1":  ("RF_Module","ESP32-WROOM-32", 40, 30, 0, "ESP32-WROOM-32"),
 "J1":  ("Connector_PinHeader_2.54mm","PinHeader_1x06_P2.54mm_Vertical", 11, 14, 0, "GNSS LC29HEA"),
 "J2":  ("Connector_PinHeader_2.54mm","PinHeader_1x04_P2.54mm_Vertical", 11, 32, 0, "OLED SSD1306"),
 "J3":  ("Connector_PinHeader_2.54mm","PinHeader_1x04_P2.54mm_Vertical", 11, 48, 0, "IMU BNO085 v2"),
 "J4":  ("Connector_PinHeader_2.54mm","PinHeader_1x04_P2.54mm_Vertical", 69, 14, 0, "Buck-boost 3V3"),
 "J5":  ("Connector_PinHeader_2.54mm","PinHeader_1x06_P2.54mm_Vertical", 69, 34, 0, "TP4056 USB-C"),
 "BT1": ("Connector_PinHeader_2.54mm","PinHeader_1x02_P2.54mm_Vertical", 69, 55, 0, "18650 (off-board)"),
 "C1":  ("Capacitor_SMD","C_0805_2012Metric", 26, 55, 0, "100uF"),
 "C2":  ("Capacitor_SMD","C_0805_2012Metric", 32, 55, 0, "100nF"),
 "R3":  ("Resistor_SMD","R_0805_2012Metric", 38, 55, 0, "4k7"),
 "R4":  ("Resistor_SMD","R_0805_2012Metric", 44, 55, 0, "4k7"),
 "R1":  ("Resistor_SMD","R_0805_2012Metric", 50, 55, 0, "100k"),
 "R2":  ("Resistor_SMD","R_0805_2012Metric", 56, 55, 0, "100k"),
 "R5":  ("Resistor_SMD","R_0805_2012Metric", 38, 62, 0, "330"),
 "D1":  ("LED_SMD","LED_0805_2012Metric", 44, 62, 0, "status"),
 "SW1": ("Button_Switch_THT","SW_PUSH_6mm_H5mm", 55, 63, 0, "user"),
}

txt = open(NET, encoding="utf-8").read()
padnet = {}
for m in re.finditer(r'\(net \(code "\d+"\) \(name "([^"]+)"\)(.*?)(?=\(net \(code|\Z)', txt, re.S):
    name = m.group(1).lstrip("/")
    if name.startswith("unconnected-"):
        continue
    for n in re.finditer(r'\(node \(ref "([^"]+)"\) \(pin "([^"]+)"\)', m.group(2)):
        padnet[(n.group(1), n.group(2))] = name
netnames = sorted(set(padnet.values()))
print("nety:", len(netnames), "| przypisania pad->net:", len(padnet))

board = pcbnew.CreateEmptyBoard()
# pad termiczny ESP32-WROOM ma przelotki 0.2 mm -> poluzuj min. wiercenie
bds = board.GetDesignSettings()
try:
    bds.m_MinThroughDrill = pcbnew.FromMM(0.2)
except Exception as e:
    print("min drill set fail:", e)
nets = {}
for nm in netnames:
    ni = pcbnew.NETINFO_ITEM(board, nm)
    board.Add(ni)
    nets[nm] = ni

placed = 0; assigned = 0; missing = []
for ref, (lib, fpn, x, y, rot, val) in COMP.items():
    fp = pcbnew.FootprintLoad(fl(lib), fpn)
    if fp is None:
        missing.append(f"{ref}:{lib}/{fpn}"); continue
    fp.SetReference(ref); fp.SetValue(val)
    fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
    if rot:
        fp.SetOrientationDegrees(rot)
    board.Add(fp)
    for pad in fp.Pads():
        key = (ref, pad.GetNumber())
        if key in padnet:
            pad.SetNet(nets[padnet[key]]); assigned += 1
    placed += 1
print("footprinty:", placed, "| pady przypisane:", assigned, "| braki:", missing)

# obrys Edge.Cuts 80 x 72 mm
rect = pcbnew.PCB_SHAPE(board)
rect.SetShape(pcbnew.SHAPE_T_RECT)
rect.SetStart(pcbnew.VECTOR2I(mm(0), mm(0)))
rect.SetEnd(pcbnew.VECTOR2I(mm(80), mm(72)))
rect.SetLayer(pcbnew.Edge_Cuts)
rect.SetWidth(mm(0.15))
board.Add(rect)

board.BuildListOfNets()
pcbnew.SaveBoard(OUT, board)
print("OK ->", OUT)
