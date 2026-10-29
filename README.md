# ⚡ Redmi 3S Sentinel & Linux Engineering Lab

[![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-a80030?style=for-the-badge&logo=debian&logoColor=white)](https://www.debian.org/)
[![Python](https://img.shields.io/badge/Python-3.8+-3776ab?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![SoC](https://img.shields.io/badge/SoC-Qualcomm%20Snapdragon%20430-e01e5a?style=for-the-badge&logo=qualcomm&logoColor=white)](https://www.qualcomm.com/)
[![Android](https://img.shields.io/badge/Android-MIUI%2010%20(Debloated)-3ddc84?style=for-the-badge&logo=android&logoColor=white)](https://android.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

Transform an old **Xiaomi Redmi 3S** (*codename: `land`*) into an autonomous, 24/7 battery-backed **Linux Engineering Micro-Server** and **Hardware Telemetry Sentinel Node** without wiping Android or needing root access.

---

## 🌟 Overview & Key Features

* **🐧 Native Debian 12 (Bookworm) Userspace**: Runs a full 64-bit ARM (`aarch64`) Debian 12 environment alongside Android via PRoot, equipped with `apt`, `git`, `htop`, `nano`, `curl`, and standard compilers.
* **🛡️ Safe Non-Root MIUI Debloater**: Strips 18 MIUI telemetry trackers, background adware daemons (MSA, analytics, daemon), and bloatware using safe Android user package management.
* **📊 Cyber Intelligence Dashboard**: A responsive, dark-mode real-time web interface running directly on the phone (`http://<phone-ip>:8080`) featuring:
  * **Qualcomm Snapdragon 430 Octa-Core Grid**: Real-time core hotplugging state, dynamic clock frequencies (MHz), and per-core utilization bars.
  * **Canvas Live Plots**: Rolling high-frequency graphs for CPU load and thermal sensor curves.
  * **19 Hardware Thermal Zones**: Monitored directly via kernel sysfs (SoC CPU clusters 0–10, PMIC PM8937, battery, oscillator, chassis, charger IC).
  * **Battery & Power Node**: Real-time capacity %, charging/discharging detection, voltage (mV), cell temperature, and health.
  * **Memory & Storage**: 3.0 GB RAM breakdown, buffers/cached, ZRAM swap, and eMMC partition metrics.
  * **Network I/O**: Real-time wireless throughput (RX/TX KB/s) and packet counters.
* **🧪 Interactive Engineering Lab Console**: Web terminal built into the dashboard with support for executing both Debian 12 and Termux host commands with instant feedback.
* **🔑 Zero-Password SSH Access**: OpenSSH daemon pre-configured on port `8022` with key-based authentication.
* **🔄 Persistent Auto-Start**: Automatically boots SSH and the telemetry daemon on phone startup.

---

## 🏗️ System Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Xiaomi Redmi 3S (land) — Qualcomm MSM8937            │
├────────────────────────────────────────────────────────────────────────┤
│ Android Kernel 3.18 (aarch64)                                          │
│  ├── /sys/class/thermal/thermal_zone*   (19 Hardware Thermal Zones)    │
│  ├── /sys/devices/system/cpu/cpu0..7    (Dynamic Hotplug & Freqs)      │
│  ├── /sys/class/power_supply/battery    (Voltage, Capacity, Current)   │
│  └── /proc/stat, /proc/meminfo          (CPU & Memory Telemetry)       │
├───────────────────────────────────┬────────────────────────────────────┤
│ Termux Environment (u0_a48)       │ Debian 12 Bookworm Userspace       │
│  ├── OpenSSH Server (:8022)       │  (via PRoot & /dev /proc /sys)     │
│  ├── Sentinel HTTP Server (:8080) │  ├── APT Package Manager (Debian)  │
│  │    ├── /api/telemetry (JSON)   │  ├── Development Tools (git, htop) │
│  │    ├── /api/exec (Runner API)  │  └── CLI Tools & Utilities         │
│  │    └── Web Dashboard (HTML5)   │                                    │
│  └── Auto-start Hooks (~/.bashrc) │                                    │
└───────────────────────────────────┴────────────────────────────────────┘
                               ▲
                               │ Wi-Fi (192.168.0.x)
                               ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       Host Computer / Browser                          │
│  ├── Web Dashboard: http://192.168.0.9:8080                            │
│  ├── SSH Session:   ssh -p 8022 192.168.0.9                            │
│  └── Wireless ADB:  adb connect 192.168.0.9:5555                       │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Repository Structure

```
├── server.py              # Python telemetry HTTP daemon & command execution backend
├── index.html             # Cyber intelligence dashboard UI (Single-Page App)
├── deploy.sh              # One-click deployment script (syncs & restarts server)
├── scripts/
│   ├── debloat.sh         # Non-destructive MIUI telemetry and ad removal script
│   ├── setup_debian.sh    # Installs PRoot, bootstraps Debian 12, sets up dev tools
│   ├── setup_ssh.sh       # Generates & installs SSH keys, starts sshd on port 8022
│   └── setup_termux.sh    # Whitelists Doze & configures ~/.bashrc persistence
├── .gitignore             # Standard gitignore
├── LICENSE                # MIT License
└── README.md              # Project documentation
```

---

## 🚀 Quick Start Guide

### Prerequisites
1. **Xiaomi Redmi 3S** (or compatible Android device) connected via USB or Wi-Fi.
2. **Developer Options** enabled with **USB Debugging** turned on.
3. **Termux** installed on the device.

### 1. Safe Debloat
Remove background MIUI ads, trackers, and telemetry:
```bash
chmod +x scripts/*.sh deploy.sh
./scripts/debloat.sh
```

### 2. Bootstrap Debian 12 Bookworm Lab
Install the Debian 12 userspace and essential dev tools:
```bash
./scripts/setup_debian.sh
```

### 3. Setup SSH Access
Configure key-based passwordless SSH access:
```bash
./scripts/setup_ssh.sh
```

### 4. Deploy Dashboard & Enable Persistence
Deploy the telemetry server and auto-start hooks:
```bash
./scripts/setup_termux.sh
./deploy.sh
```

### 5. Access Your Device!
* **Web Dashboard**: Open `http://<phone-ip>:8080` in your browser.
* **SSH Terminal**:
  ```bash
  ssh -p 8022 <phone-ip>
  ```
* **Enter Debian Userspace**:
  ```bash
  # Inside Termux or SSH:
  debian
  ```

---

## 📡 REST API Reference

### 1. `GET /api/telemetry`
Returns full hardware and system snapshot:
```json
{
  "timestamp": 1793272867.3,
  "system": {
    "device": "Xiaomi Redmi 3S (land)",
    "android_version": "6.0.1 (MIUI 10 Debloated)",
    "kernel": "Linux version 3.18.20-g89abe5f",
    "uptime_formatted": "1h 1m 30s",
    "debian": { "installed": true, "version": "12.15" }
  },
  "cpu": {
    "model": "Qualcomm Snapdragon 430 (MSM8937)",
    "total_load_pct": 1.9,
    "cores": [
      { "id": 0, "online": false, "freq_mhz": 0, "load_pct": 0 },
      { "id": 4, "online": true, "freq_mhz": 768, "load_pct": 5.6 }
    ]
  },
  "battery": {
    "capacity_pct": 11,
    "status": "Discharging",
    "voltage_mv": 3795,
    "temp_c": 28.2
  },
  "thermals": [
    { "zone": "thermal_zone10", "label": "SoC CPU Cluster #4", "temp_c": 35.0 },
    { "zone": "thermal_zone17", "label": "Qualcomm PM8937 PMIC", "temp_c": 37.0 }
  ]
}
```

### 2. `POST /api/exec`
Executes a shell command on the device (either in Debian userspace or Termux host):
```bash
curl -X POST http://<phone-ip>:8080/api/exec \
  -H "Content-Type: application/json" \
  -d '{"cmd": "git --version && htop --version", "debian": true}'
```

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
