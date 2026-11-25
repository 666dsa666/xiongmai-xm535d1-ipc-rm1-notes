"""Upload a firmware package to a Xiongmai camera over DVRIP (OPSystemUpgrade).

Usage: python3 dvrip_upgrade.py PACKAGE [PASSWORD] [CAMERA_IP]

  PACKAGE    upgrade .bin to upload
  PASSWORD   admin password; use '' for a factory camera (empty password)
  CAMERA_IP  defaults to 192.168.1.10 (vendor factory fallback address)

The user name is fixed to "admin". Needs the dvrip module (python-dvr).
Exit status: 2 if login fails; otherwise 0, also when the upload raises an
exception, so read the printed "Ret" frames and "UPGRADE EXCEPTION" line.
"""
import os
import sys

IP = sys.argv[3] if len(sys.argv) > 3 else "192.168.1.10"
PKG = sys.argv[1]
PW = sys.argv[2] if len(sys.argv) > 2 else ""

from dvrip import DVRIPCam

cam = DVRIPCam(IP, user="admin", password=PW)
if not cam.login():
    print("login failed")
    sys.exit(2)
print("login OK session=0x%08X" % cam.session)
try:
    cam.alive.cancel()
except Exception:
    pass
cam.socket.settimeout(30)
print("uploading", PKG, os.path.getsize(PKG), flush=True)
try:
    cam.upgrade(PKG, vprint=lambda m: print("  " + str(m), flush=True))
except Exception as e:
    print("UPGRADE EXCEPTION:", repr(e), flush=True)
try:
    cam.close()
except Exception:
    pass
print("client done", flush=True)
