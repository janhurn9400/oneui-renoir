#!/usr/bin/env bash
# Quick health check of a running build over adb (no SIM needed). Usage: scripts/probe_device.sh > report.txt
A=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}
s() { echo "== $1"; timeout 20 "$A" shell "$2" 2>&1 | cut -c1-200; }
s modem 'getprop gsm.version.baseband; getprop gsm.version.ril-impl; getprop gsm.network.type; getprop gsm.sim.state'
s cell 'dumpsys telephony.registry | grep -E "mSignalStrength" | head -2'
s ims 'getprop init.svc.imsd; dumpsys activity services com.sec.imsservice | grep -c ServiceRecord'
s sensors 'dumpsys sensorservice | grep -E "^0x[0-9a-f]+\)" | head -40'
s bluetooth 'settings get global bluetooth_on; dumpsys bluetooth_manager | grep -E "^  state:|^  enabled:|^  name:" | head -4'
s wifi 'dumpsys wifi | grep -E "^Wi-Fi is|mWifiInfo SSID" | head -2'
s gnss 'dumpsys location | grep -iE "hardware model|gnss hal|GnssManagerService" | head -4'
s vibrator 'service list | grep -i vibrat; dumpsys vibrator_manager | grep -iE "vibratorIds|halAvailable|capabilities" | head -4'
s camera 'dumpsys media.camera | grep -E "Number of camera devices|== Camera device" | head -8'
s fingerprint 'dumpsys fingerprint | grep -E "service|HAL deaths" | head -3'
s brightness 'dumpsys display | grep -E "mScreenBrightnessSetting|mBrightness=|mBacklight|brightnessMinimum|brightnessMaximum|mActualBacklight" | head -8; cat /sys/class/backlight/*/brightness /sys/class/backlight/*/max_brightness 2>&1'
s refresh 'dumpsys display | grep -oE "fps=[0-9.]+" | sort -u'
s audio 'dumpsys media.audio_flinger | grep -E "HAL format|Processing format" | sort | uniq -c'
s nfc 'service list | grep -i nfc; settings get global nfc_on 2>/dev/null'
s crashes 'logcat -b crash -d | grep -E "Process: |Abort message" | sed -E "s/^.{31}//" | sort | uniq -c | sort -rn | head -15'
s anr 'ls /data/anr 2>&1 | head -5'
