#!/usr/bin/env python3
"""Talks to the Broadcom powerline chip of the TP-Link Deco P9 (ethertype 0x8912).

Protocol deduced from the disassembly of libplcapi.so (see docs/powerline.md).
Run as root on the Deco, for example with Python installed in RAM.

    mme.py get-nmk
    mme.py set-nmk <32 hexadecimal characters>
    mme.py pushbutton
    mme.py raw <type in hex, bytes as on the wire> [payload in hex]

Options: -i INTERFACE (default eth0.1, the tagged VLAN 1) and -d CHIP_MAC
(default: interface MAC + 5, rule from the stock firmware's plc_mac_fix script).
"""
import argparse
import select
import socket
import sys
import time

ETHERTYPE = b"\x89\x12"
OUI = b"\x00\x1f\x84"
VERSION = b"\x02"
# Message type, as sent on the wire (little-endian).
GET_PARAM = "5ca0"   # 0xA05C
SET_NMK = "18a0"     # 0xA018
PUSHBUTTON = "8ca0"  # 0xA08C
NMK_PARAM = b"\x24\x00"  # parameter 36 = NMK
SET_NMK_DELAY = 8   # the chip takes more than 3 s to reply after a write


def if_mac(ifname):
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    s.bind((ifname, 0))
    mac = s.getsockname()[4]
    s.close()
    return mac


class Plc:
    def __init__(self, ifname, dst=None):
        self.src = if_mac(ifname)
        if dst is None:
            plc = int.from_bytes(if_mac("eth0"), "big") + 5
            dst = plc.to_bytes(6, "big")
        self.dst = dst
        self.own = {self.src, if_mac("eth0")}
        self.rx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(3))
        self.rx.bind(("eth0", 0))
        self.tx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
        self.tx.bind((ifname, 0))
        self.seq = int(time.time()) & 0xFF

    def send(self, mmtype_hex, payload=b"", wait=4.0):
        """Send a message and return the payload of the reply, or None."""
        self.seq = (self.seq + 1) & 0xFF
        frame = (self.dst + self.src + ETHERTYPE + VERSION + bytes.fromhex(mmtype_hex)
                 + b"\x00\x00" + OUI + bytes([self.seq]) + payload)
        self.tx.send(frame.ljust(60, b"\0"))
        end = time.time() + wait
        while time.time() < end:
            ready, _, _ = select.select([self.rx], [], [], 0.3)
            if not ready:
                continue
            d = self.rx.recv(2048)
            off = 4 if d[12:14] == b"\x81\x00" else 0  # VLAN-tagged frame
            if d[12 + off:14 + off] == ETHERTYPE and d[6:12] not in self.own:
                return d[14 + off:]
        return None

    def get_nmk(self):
        r = self.send(GET_PARAM, NMK_PARAM)
        # r: version(1) type(2) 00 00 OUI(3) seq(1) status(1) length(2, LE) NMK(16)
        if r is None or r[9] != 1 or int.from_bytes(r[10:12], "little") != 16:
            return None
        return r[12:28]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-i", dest="ifname", default="eth0.1")
    ap.add_argument("-d", dest="dst", help="chip MAC, e.g. aa:bb:cc:dd:ee:05")
    ap.add_argument("cmd", choices=["get-nmk", "set-nmk", "pushbutton", "raw"])
    ap.add_argument("args", nargs="*")
    a = ap.parse_args()
    dst = bytes.fromhex(a.dst.replace(":", "")) if a.dst else None
    plc = Plc(a.ifname, dst)
    print("chip:", plc.dst.hex(":"))

    if a.cmd == "get-nmk":
        nmk = plc.get_nmk()
        if nmk is None:
            sys.exit("no reply (if a write just happened, wait 5 s)")
        print(nmk.hex())
    elif a.cmd == "set-nmk":
        if len(a.args) != 1 or len(a.args[0]) != 32:
            sys.exit("set-nmk expects 32 hexadecimal characters")
        nmk = bytes.fromhex(a.args[0])
        if plc.send(SET_NMK, nmk + b"\x00\x00") is None:
            sys.exit("no reply to the write")
        time.sleep(SET_NMK_DELAY)
        back = plc.get_nmk()
        if back != nmk:
            sys.exit("read-back differs: %s" % (back.hex() if back else "no reply"))
        print("NMK written and verified:", back.hex())
    elif a.cmd == "pushbutton":
        r = plc.send(PUSHBUTTON, b"\x00")
        print("reply:", r[:16].hex(" ") if r else "none")
    else:
        pl = bytes.fromhex(a.args[1]) if len(a.args) > 1 else b""
        r = plc.send(a.args[0], pl)
        print("reply:", r[:48].hex(" ") if r else "none")


if __name__ == "__main__":
    main()
