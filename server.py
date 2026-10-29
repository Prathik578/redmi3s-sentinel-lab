#!/usr/bin/env python3
"""
Redmi 3S (Land) Device Intelligence Monitor & Engineering Lab Server
Snapdragon 430 Octa-Core Telemetry, Debian Userspace Interface & Web Dashboard
"""

import http.server
import json
import os
import re
import socketserver
import subprocess
import sys
import time
from urllib.parse import parse_qs, urlparse

PORT = 8080
HOST = "0.0.0.0"

# CPU state tracker for calculating delta utilization
prev_cpu_times = {}
prev_net_times = {"rx": 0, "tx": 0, "timestamp": time.time()}

def read_file(path, default=""):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except Exception:
        return default

def get_cpu_info():
    global prev_cpu_times
    curr_times = {}
    cores_info = []

    # Read /proc/stat for core usage
    try:
        with open("/proc/stat", "r") as f:
            for line in f:
                if line.startswith("cpu"):
                    parts = line.split()
                    name = parts[0]
                    # user, nice, system, idle, iowait, irq, softirq, steal
                    vals = [float(x) for x in parts[1:]]
                    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
                    total = sum(vals)
                    curr_times[name] = (idle, total)
    except Exception:
        pass

    # Total CPU load
    total_load = 0
    if "cpu" in curr_times and "cpu" in prev_cpu_times:
        prev_idle, prev_total = prev_cpu_times["cpu"]
        curr_idle, curr_total = curr_times["cpu"]
        delta_idle = curr_idle - prev_idle
        delta_total = curr_total - prev_total
        if delta_total > 0:
            total_load = max(0, min(100, round((1.0 - (delta_idle / delta_total)) * 100, 1)))

    # Per-core frequencies and status (Snapdragon 430: 8 cores cpu0..cpu7)
    for i in range(8):
        c_name = f"cpu{i}"
        online_str = read_file(f"/sys/devices/system/cpu/{c_name}/online", "1" if i >= 4 else "0")
        is_online = (online_str == "1")
        freq_str = read_file(f"/sys/devices/system/cpu/{c_name}/cpufreq/scaling_cur_freq", "0")
        freq_mhz = round(int(freq_str) / 1000) if freq_str.isdigit() else 0

        # Calculate per-core utilization
        core_load = 0
        if is_online and c_name in curr_times and c_name in prev_cpu_times:
            p_idle, p_total = prev_cpu_times[c_name]
            c_idle, c_total = curr_times[c_name]
            d_idle = c_idle - p_idle
            d_total = c_total - p_total
            if d_total > 0:
                core_load = max(0, min(100, round((1.0 - (d_idle / d_total)) * 100, 1)))

        cores_info.append({
            "id": i,
            "cluster": "A53 Little (Power-save)" if i < 4 else "A53 Big (Performance)",
            "online": is_online,
            "freq_mhz": freq_mhz,
            "load_pct": core_load
        })

    prev_cpu_times = curr_times

    # Load averages
    load1, load5, load15 = 0.0, 0.0, 0.0
    try:
        load_avg_str = read_file("/proc/loadavg")
        if load_avg_str:
            parts = load_avg_str.split()
            load1, load5, load15 = float(parts[0]), float(parts[1]), float(parts[2])
    except Exception:
        pass

    return {
        "model": "Qualcomm Snapdragon 430 (MSM8937)",
        "arch": "ARM64 (aarch64 8-Core)",
        "total_load_pct": total_load,
        "load_avg": [load1, load5, load15],
        "cores": cores_info
    }

def get_memory_info():
    mem = {}
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    key = parts[0].strip()
                    val = parts[1].strip().split()[0]
                    if val.isdigit():
                        mem[key] = int(val) * 1024  # convert kB to Bytes
    except Exception:
        pass

    total = mem.get("MemTotal", 1)
    free = mem.get("MemFree", 0)
    avail = mem.get("MemAvailable", free)
    buffers = mem.get("Buffers", 0)
    cached = mem.get("Cached", 0)
    used = total - avail
    used_pct = round((used / total) * 100, 1)

    swap_total = mem.get("SwapTotal", 0)
    swap_free = mem.get("SwapFree", 0)
    swap_used = swap_total - swap_free
    swap_pct = round((swap_used / swap_total) * 100, 1) if swap_total > 0 else 0

    return {
        "total_bytes": total,
        "used_bytes": used,
        "free_bytes": free,
        "avail_bytes": avail,
        "buffers_bytes": buffers,
        "cached_bytes": cached,
        "used_pct": used_pct,
        "swap_total_bytes": swap_total,
        "swap_used_bytes": swap_used,
        "swap_pct": swap_pct
    }

def get_thermal_info():
    zones = []
    base_dir = "/sys/class/thermal"
    try:
        if os.path.exists(base_dir):
            for entry in sorted(os.listdir(base_dir)):
                if entry.startswith("thermal_zone"):
                    z_path = os.path.join(base_dir, entry)
                    z_type = read_file(os.path.join(z_path, "type"), "unknown")
                    z_temp_str = read_file(os.path.join(z_path, "temp"), "0")
                    if z_temp_str.lstrip("-").isdigit():
                        raw_temp = float(z_temp_str)
                        # sysfs temps are usually millidegrees (e.g. 35000 = 35.0 C) or tenths (350 = 35.0 C) or direct C
                        if abs(raw_temp) > 10000:
                            temp_c = round(raw_temp / 1000.0, 1)
                        elif abs(raw_temp) > 150:
                            temp_c = round(raw_temp / 10.0, 1)
                        else:
                            temp_c = round(raw_temp, 1)
                        
                        # Friendly naming
                        label = z_type
                        if z_type.startswith("tsens_tz_sensor"):
                            sensor_idx = z_type.replace("tsens_tz_sensor", "")
                            label = f"SoC CPU Cluster #{sensor_idx}"
                        elif z_type == "pm8937_tz":
                            label = "Qualcomm PM8937 PMIC"
                        elif z_type == "battery" or z_type == "bms":
                            label = "Battery Sensor"
                        elif z_type == "case_therm":
                            label = "Device Chassis / Case"
                        elif z_type == "chg_temp":
                            label = "Charger Controller"
                        elif z_type.startswith("xo_therm"):
                            label = "Crystal Oscillator"
                        elif z_type.startswith("pa_therm"):
                            label = "RF Power Amplifier"

                        zones.append({
                            "zone": entry,
                            "type": z_type,
                            "label": label,
                            "temp_c": temp_c
                        })
    except Exception:
        pass
    return zones

def get_battery_info():
    base = "/sys/class/power_supply/battery"
    cap_str = read_file(f"{base}/capacity", "0")
    status = read_file(f"{base}/status", "Unknown")
    health = read_file(f"{base}/health", "Good")
    volt_str = read_file(f"{base}/voltage_now", "0")
    temp_str = read_file(f"{base}/temp", "0")

    voltage_mv = round(int(volt_str) / 1000) if volt_str.isdigit() else 0
    temp_c = round(int(temp_str) / 10.0, 1) if temp_str.isdigit() else 0

    return {
        "capacity_pct": int(cap_str) if cap_str.isdigit() else 0,
        "status": status,
        "health": health,
        "voltage_mv": voltage_mv,
        "temp_c": temp_c,
        "charging": status.lower() == "charging"
    }

def get_storage_info():
    partitions = []
    for mount in ["/data", "/system", "/sdcard"]:
        if os.path.exists(mount):
            try:
                st = os.statvfs(mount)
                total = st.f_blocks * st.f_frsize
                free = st.f_bavail * st.f_frsize
                used = total - free
                used_pct = round((used / total) * 100, 1) if total > 0 else 0
                partitions.append({
                    "mount": mount,
                    "total_bytes": total,
                    "used_bytes": used,
                    "free_bytes": free,
                    "used_pct": used_pct
                })
            except Exception:
                pass
    return partitions

def get_network_info():
    global prev_net_times
    rx_bytes = 0
    tx_bytes = 0
    try:
        with open("/proc/net/dev", "r") as f:
            for line in f:
                if "wlan0:" in line:
                    parts = line.split("wlan0:")[1].split()
                    rx_bytes = int(parts[0])
                    tx_bytes = int(parts[8])
                    break
    except Exception:
        pass

    now = time.time()
    dt = max(0.1, now - prev_net_times["timestamp"])
    rx_speed = round((rx_bytes - prev_net_times["rx"]) / dt / 1024, 1) if prev_net_times["rx"] > 0 else 0.0
    tx_speed = round((tx_bytes - prev_net_times["tx"]) / dt / 1024, 1) if prev_net_times["tx"] > 0 else 0.0

    prev_net_times = {"rx": rx_bytes, "tx": tx_bytes, "timestamp": now}

    ip_addr = "192.168.0.9"
    try:
        out = subprocess.check_output("ip -4 addr show wlan0 2>/dev/null", shell=True).decode()
        m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        if m:
            ip_addr = m.group(1)
    except Exception:
        pass

    return {
        "interface": "wlan0",
        "ip": ip_addr,
        "rx_bytes": rx_bytes,
        "tx_bytes": tx_bytes,
        "rx_speed_kbps": max(0.0, rx_speed),
        "tx_speed_kbps": max(0.0, tx_speed)
    }

def get_system_info():
    uptime_sec = 0
    try:
        up_str = read_file("/proc/uptime").split()[0]
        uptime_sec = int(float(up_str))
    except Exception:
        pass

    h = uptime_sec // 3600
    m = (uptime_sec % 3600) // 60
    s = uptime_sec % 60
    uptime_formatted = f"{h}h {m}m {s}s"

    kernel = read_file("/proc/version", "Linux localhost")
    proc_count = 0
    try:
        proc_count = len([p for p in os.listdir("/proc") if p.isdigit()])
    except Exception:
        pass

    # Debian rootfs status
    debian_ready = os.path.exists("/data/data/com.termux/files/home/debian/etc/debian_version")
    debian_version = read_file("/data/data/com.termux/files/home/debian/etc/debian_version", "12.x") if debian_ready else "Not installed"

    return {
        "hostname": "redmi3s-land",
        "device": "Xiaomi Redmi 3S (land)",
        "android_version": "6.0.1 (MIUI 10 Debloated)",
        "kernel": kernel.split(" (")[0] if " (" in kernel else kernel,
        "uptime_sec": uptime_sec,
        "uptime_formatted": uptime_formatted,
        "process_count": proc_count,
        "debian": {
            "installed": debian_ready,
            "version": debian_version,
            "environment": "proot Bookworm userspace"
        }
    }

class MonitorHTTPHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Quiet logger to keep terminal clean
        pass

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/telemetry":
            data = {
                "timestamp": time.time(),
                "system": get_system_info(),
                "cpu": get_cpu_info(),
                "memory": get_memory_info(),
                "battery": get_battery_info(),
                "thermals": get_thermal_info(),
                "storage": get_storage_info(),
                "network": get_network_info()
            }
            res = json.dumps(data).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(res)))
            self.end_headers()
            self.wfile.write(res)
            return

        elif url.path == "/" or url.path == "/index.html":
            index_path = os.path.join(os.path.dirname(__file__), "index.html")
            if os.path.exists(index_path):
                with open(index_path, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return

        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"Not Found")

    def do_POST(self):
        url = urlparse(self.path)
        if url.path == "/api/exec":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8")
            try:
                payload = json.loads(body)
                cmd = payload.get("cmd", "").strip()
                in_debian = payload.get("debian", False)

                if not cmd:
                    raise ValueError("Empty command")

                # Wrap in debian launcher if requested
                if in_debian:
                    full_cmd = f'/data/data/com.termux/files/usr/bin/debian "{cmd}"'
                else:
                    full_cmd = f'export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; export PATH=/data/data/com.termux/files/usr/bin:$PATH; {cmd}'

                start_t = time.time()
                proc = subprocess.Popen(
                    full_cmd,
                    shell=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    executable="/data/data/com.termux/files/usr/bin/sh"
                )
                stdout, stderr = proc.communicate(timeout=15)
                duration = round(time.time() - start_t, 3)

                resp = {
                    "cmd": cmd,
                    "in_debian": in_debian,
                    "exit_code": proc.returncode,
                    "stdout": stdout.decode("utf-8", errors="replace"),
                    "stderr": stderr.decode("utf-8", errors="replace"),
                    "duration_sec": duration
                }
            except subprocess.TimeoutExpired:
                proc.kill()
                resp = {"error": "Execution timed out (15s limit)", "exit_code": 124}
            except Exception as e:
                resp = {"error": str(e), "exit_code": 1}

            out = json.dumps(resp).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)
            return

        self.send_response(404)
        self.end_headers()

def daemonize():
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError:
        pass
    os.setsid()
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError:
        pass
    sys.stdout.flush()
    sys.stderr.flush()
    log_file = os.path.join(os.path.dirname(__file__), "server.log")
    log_fd = os.open(log_file, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    devnull_fd = os.open("/dev/null", os.O_RDONLY)
    os.dup2(devnull_fd, sys.stdin.fileno())
    os.dup2(log_fd, sys.stdout.fileno())
    os.dup2(log_fd, sys.stderr.fileno())

if __name__ == "__main__":
    if "--daemon" in sys.argv or "-d" in sys.argv:
        daemonize()

    # Initial read to populate deltas
    get_cpu_info()
    get_network_info()
    print(f"[*] Redmi 3S Device Intelligence Server starting on http://{HOST}:{PORT}")
    server = socketserver.ThreadingTCPServer((HOST, PORT), MonitorHTTPHandler)
    server.allow_reuse_address = True
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Server stopped.")

