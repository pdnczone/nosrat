# 🛡️ nosrat — GRE-over-IPsec Tunnel Manager

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Go Report Card](https://goreportcard.com/badge/github.com/pdnczone/nosrat)](https://goreportcard.com/report/github.com/pdnczone/nosrat)
[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04-orange.svg)](https://ubuntu.com/)
[![strongSwan](https://img.shields.io/badge/strongSwan-IKEv2-green.svg)](https://www.strongswan.org/)

**[English](#english) | [فارسی](#فارسی)**

📺 **[YouTube: @PDNC30](https://youtube.com/@PDNC30)** | 📢 **[Telegram: @PDNCzone](https://t.me/PDNCzone)** | 💬 **[Support](https://t.me/dncdirect)**

</div>

---

<a name="english"></a>
## 🇬🇧 English

A production-oriented tunnel manager for Ubuntu 24.04 LTS: builds a kernel GRE tunnel between two servers and protects it end-to-end with strongSwan (IKEv2 + ESP, IPsec **Transport Mode**). Ships as a single static Go binary (`nosrat`) plus a systemd service — no Docker, no external Go modules.

```
Internet
   │
   ▼
Server A ── GRE encapsulate ── IPsec (ESP, transport mode) ── Internet ──▶
                                                                 IPsec decrypt
                                                                     │
                                                                  GRE decap
                                                                     │
                                                                     ▼
                                                                  Server B
```

### ⚡ Quick Install

```bash
# One-line installer (interactive)
curl -sL https://bit.ly/nosrat-install | sudo bash

# Or manual install
git clone https://github.com/pdnczone/nosrat.git
cd nosrat
sudo ./install.sh
```

### 🏗️ Architecture

| Component | Technology | Why |
|-----------|-----------|-----|
| **IPsec** | strongSwan + Linux XFRM | Mature, audited IKEv2 implementation |
| **Tunnel** | Kernel GRE via `ip tunnel` | Faster than userspace forwarding |
| **Crypto** | AES-256-GCM, MODP_2048 PFS | No weak cipher downgrade allowed |
| **Firewall** | nftables `inet nosrat` table | Isolated from existing rules |
| **Service** | systemd with auto-recovery | Production-grade process management |

### 📊 MTU Budget

```
Ethernet/link MTU                         1500
  - Outer IPv4 header                      -20
  - ESP header (SPI+SeqNo) + IV (GCM)       -16
  - ESP trailer (pad+len+next) + ICV-16     -18
  - GRE header (no key/seq/csum)             -4
                                          ------
Usable tunnel MTU                         1442   → config default 1400 (safety margin)
TCP MSS to clamp to                       1360   (on MTU 1400)
```

### 🔒 Threat Model

**Defended against:**
- ✅ Passive eavesdropping → AES-256-GCM confidentiality
- ✅ Tampering / injection → GCM integrity + XFRM anti-replay
- ✅ Replay attacks → kernel XFRM replay window
- ✅ Credential exposure → PSK isolated to `0600` root-only file
- ✅ Weak crypto downgrade → rejects DH < 14, non-AEAD/non-AES-256

**Out of scope:**
- ❌ Host OS compromise (root = game over)
- ❌ Volumetric DDoS against UDP 500
- ❌ Traffic analysis (timing/size metadata)

### 🚀 Deploy in 5 Steps

```bash
# 1. Clone & install on BOTH servers
git clone https://github.com/pdnczone/nosrat.git
cd nosrat && sudo ./install.sh

# 2. Copy PSK from Server A to Server B
# On A: cat /etc/nosrat/secrets/psk
# On B: echo '<psk-from-A>' | sudo tee /etc/nosrat/secrets/psk

# 3. Edit config on each server
sudo nano /etc/nosrat/tunnel.yaml

# 4. Start tunnel (both servers)
sudo systemctl start nosrat

# 5. Verify
nosrat status
nosrat diagnose
```

### 📋 CLI Reference

```bash
nosrat init          # create /etc/nosrat, generate PSK, write starter config
nosrat create        # (re)build GRE iface + strongSwan connection
nosrat start         # bring tunnel up: GRE + IPsec SA + routes + firewall
nosrat stop          # tear down IPsec SA, GRE down
nosrat restart       # restart tunnel
nosrat status        # human-readable summary
nosrat health        # one health-check pass
nosrat routes        # routes installed on the GRE interface
nosrat ipsec         # raw `swanctl --list-sas` detail
nosrat logs          # journalctl for nosrat + strongswan
nosrat diagnose      # full checklist with fix commands
nosrat uninstall     # remove GRE/IPsec/firewall (keeps config)
```

### 📁 Project Layout

```
nosrat/
├── cmd/nosrat/            # CLI entrypoint + starter config template
├── internal/config/       # config load/validate + tiny YAML-subset parser
├── internal/gre/          # kernel GRE interface lifecycle (via `ip`)
├── internal/ipsec/        # swanctl config generation + strongSwan control
├── internal/routing/      # sysctl (forward/rp_filter) + static routes
├── internal/firewall/     # nftables `inet nosrat` table (ports + MSS clamp)
├── internal/health/       # ICMP/SA/interface checks + auto-recovery
├── internal/diagnostics/  # `nosrat diagnose` checklist
├── configs/               # example tunnel.yaml
├── systemd/nosrat.service
├── scripts/               # benchmark.sh, mtu-calc.sh
├── tests/test-plan.md
├── install.sh / uninstall.sh
└── go.mod
```

### 🔥 Firewall Requirements

| Protocol/Port | When needed |
|---|---|
| UDP 500 | Always — initial IKE_SA negotiation |
| UDP 4500 | Always — IKE NAT-T detection |
| ESP (IP proto 50) | When **no NAT** between servers |
| GRE (IP proto 47) | Always — carries tunneled payload |

---

<a name="فارسی"></a>
## 🇮🇷 فارسی

مدیر تونل امن برای اوبونتو ۲۴.۰۴: تونل GRE بین دو سرور با محافظت IPsec (strongSwan IKEv2 + ESP Transport Mode). یک باینری استاتیک Go (`nosrat`) + سرویس systemd — بدون داکر، بدون وابستگی خارجی.

```
اینترنت
   │
   ▼
سرور A ── کپسوله GRE ── IPsec (ESP, transport mode) ── اینترنت ──▶
                                                             رمزگشایی IPsec
                                                                   │
                                                               بازکردن GRE
                                                                   │
                                                                   ▼
                                                                سرور B
```

### ⚡ نصب سریع

```bash
# نصب با یک دستور (اینتراکتیو)
curl -sL https://bit.ly/nosrat-install | sudo bash

# یا نصب دستی
git clone https://github.com/pdnczone/nosrat.git
cd nosrat
sudo ./install.sh
```

### 🏗️ معماری

| جزء | فناوری | دلیل |
|-----|--------|------|
| **IPsec** | strongSwan + Linux XFRM | پیاده‌سازی IKEv2 بالغ و حسابرسی‌شده |
| **تونل** | Kernel GRE با `ip tunnel` | سریع‌تر از فورواردینگ کاربررضا |
| **رمزنگاری** | AES-256-GCM, MODP_2048 PFS | بدون اجازه downgrade ضعیف |
| **فایروال** | nftables `inet nosrat` | جدا از قوانین موجود |
| **سرویس** | systemd با auto-recovery | مدیریت پردازش تولیدی |

### 📊 بودجه MTU

```
MTU اترنت/لینک                          1500
  - هدر IPv4 خارجی                       -20
  - هدر ESP (SPI+SeqNo) + IV (GCM)       -16
  - تریلر ESP (pad+len+next) + ICV-16    -18
  - هدر GRE (بدون key/seq/csum)          -4
                                       ------
MTU قابل استفاده تونل                  1442   → پیش‌فرض 1400 (حاشیه امنیتی)
TCP MSS برای clamp                     1360   (روی MTU 1400)
```

### 🔒 مدل تهدید

**پشتیبانی شده:**
- ✅ استراق غیرفعال → محرمانگی AES-256-GCM
- ✅ دستکاری / تزریق → یکپارچگی GCM + پنجره anti-replay XFRM
- ✅ حملات replay → پنجره replay XFRM کرنل
- ✅ افشای اعتبارنامه → PSK مجزا در فایل `0600` root-only
- ✅ downgrade رمزنگاری ضعیف → رد DH < 14, non-AEAD/non-AES-256

**خارج از محدوده:**
- ❌ سیستم عامل میزبان (root = باخت)
- ❌ DDoS حجمی علیه UDP 500
- ❌ تحلیل ترافیک (متادایای زمان/اندازه)

### 🚀 راه‌اندازی در ۵ مرحله

```bash
# ۱. کلون و نصب روی هر دو سرور
git clone https://github.com/pdnczone/nosrat.git
cd nosrat && sudo ./install.sh

# ۲. کپی PSK از سرور A به سرور B
# روی A: cat /etc/nosrat/secrets/psk
# روی B: echo '<psk-from-A>' | sudo tee /etc/nosrat/secrets/psk

# ۳. ویرایش تنظیمات روی هر سرور
sudo nano /etc/nosrat/tunnel.yaml

# ۴. شروع تونل (هر دو سرور)
sudo systemctl start nosrat

# ۵. بررسی
nosrat status
nosrat diagnose
```

### 📋 مرجع CLI

```bash
nosrat init          # ایجاد /etc/nosrat، تولید PSK، نوشتن تنظیمات اولیه
nosrat create        # ساخت (مجدد) GRE + اتصال strongSwan
nosrat start         # بالا آوردن تونل: GRE + IPsec SA + مسیرها + فایروال
nosrat stop          # پایین آوردن IPsec SA، GRE
nosrat restart       # راه‌اندازی مجدد تونل
nosrat status        # خلاصه خوانا برای انسان
nosrat health        # یک پاس بررسی سلامت
nosrat routes        # مسیرهای نصب‌شده روی رابط GRE
nosrat ipsec         # جزئیات `swanctl --list-sas`
nosrat logs          # journalctl برای nosrat + strongswan
nosrat diagnose      # چک‌لیست کامل با دستورهای رفع مشکل
nosrat uninstall     # حذف GRE/IPsec/فایروال (نگه‌داشتن تنظیمات)
```

### 📁 ساختار پروژه

```
nosrat/
├── cmd/nosrat/            # ورودی CLI + قالب تنظیمات اولیه
├── internal/config/       # بارگذاری/اعتبارسنجی تنظیمات + پارسر YAML کوچک
├── internal/gre/          # چرخه حیات رابط GRE کرنل (از طریق `ip`)
├── internal/ipsec/        # تولید تنظیمات swanctl + کنترل strongSwan
├── internal/routing/      # sysctl (forward/rp_filter) + مسیرهای استاتیک
├── internal/firewall/     # جدول nftables `inet nosrat` (پورت‌ها + MSS clamp)
├── internal/health/       # بررسی‌های ICMP/SA/رابط + بازیابی خودکار
├── internal/diagnostics/  # چک‌لیست `nosrat diagnose`
├── configs/               # نمونه tunnel.yaml
├── systemd/nosrat.service
├── scripts/               # benchmark.sh, mtu-calc.sh
├── tests/test-plan.md
├── install.sh / uninstall.sh
└── go.mod
```

### 🔥 نیازمندی‌های فایروال

| پروتکل/پورت | چه زمانی نیاز است |
|---|---|
| UDP 500 | همیشه — مذاکره اولیه IKE_SA |
| UDP 4500 | همیشه — تشخیص IKE NAT-T |
| ESP (IP proto 50) | وقتی **بدون NAT** بین سرورها هستید |
| GRE (IP proto 47) | همیشه — حمل بار تونل‌شده |

---

## 📜 License

MIT License — see [LICENSE](./LICENSE) for details.

---

<div align="center">

**[📺 YouTube](https://youtube.com/@PDNC30)** | **[📢 Telegram](https://t.me/PDNCzone)** | **[💬 Support](https://t.me/dncdirect)** | **[🐙 GitHub](https://github.com/pdnczone/nosrat)**

Made with ❤️ by **PDNC Team**

</div>
