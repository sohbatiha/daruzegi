<div dir="rtl">

🌐 **زبان:** [English](README.md) | **فارسی**

# محیط کار ایزوله Claude (`sing-box` Proxy Chain)

یک محیط Docker ایزوله برای اجرای **Claude Code** و مرورگر امن‌شده‌ی **Firefox** که در آن تمام ترافیک شبکه و درخواست‌های DNS به‌صورت اجباری از طریق یک تونل زنجیره‌ای عبور می‌کنند:

</div>

```text
Claude Workspace (container) ──► TUN (tun0, strict_route) ──┐
                                                             ├──► auto (VLESS / VMess / Trojan / SS) ──► SSH Exit Node ──► Internet
Hardened Firefox (host)      ──► SOCKS5 (127.0.0.1:1080)  ──┘
```

<div dir="rtl">

## ویژگی‌ها

- **معماری پروکسی زنجیره‌ای (Chained Proxy):** لینک سابسکریپشن Xray/V2Ray (از جمله خروجی JSON پنل سنایی) را دریافت کرده، به فرمت `sing-box` نسخه 1.14 به بالا تبدیل می‌کند، سریع‌ترین سرور را با `urltest` (`auto`) انتخاب کرده و ترافیک خروجی را از طریق تونل SSH به سرور نهایی هدایت می‌کند.
- **مسیریابی شفاف TUN و Kill Switch:** کانتینر `claude-workspace` فضای شبکه `singbox` را به اشتراک می‌گذارد (`network_mode: "service:singbox"`) و تا آماده شدن کامل `singbox` (بالا آمدن `tun0` و باز شدن پورت `1080`) صبر می‌کند. تمام ترافیک کانتینر با `strict_route: true` از `tun0` عبور می‌کند؛ بنابراین حتی ابزارهایی که متغیرهای پروکسی را نادیده می‌گیرند نیز نمی‌توانند تونل را دور بزنند.
- **بدون نشت DNS (No DNS Leaks):** تنظیم DNS کانتینر روی `1.1.1.1` قرار می‌گیرد تا تمام درخواست‌ها وارد `tun0` شده، توسط `hijack-dns` رهگیری شوند و از طریق DoH (`https://1.1.1.1/dns-query`) روی `ssh-exit` حل شوند. نام دامنه‌ی خود سرورهای پروکسی به‌صورت جداگانه با resolver داخلی Docker (`default_domain_resolver`) حل می‌شود تا حلقه (bootstrap loop) ایجاد نشود.
- **پروکسی SOCKS5/HTTP روی سیستم میزبان + فایرفاکس امن‌شده:** یک ورودی `mixed` روی `127.0.0.1:1080` برای برنامه‌های سیستم میزبان (macOS) باز می‌کند و دستور `make firefox` یک پروفایل ایزوله از Firefox با DNS از راه دور روی SOCKS5، غیرفعال بودن WebRTC و مکان‌یابی، فعال بودن `resistFingerprinting` و تایم‌زون هماهنگ با `.env` اجرا می‌کند.
- **ذخیره‌سازی پایدار تنظیمات Claude:** پوشه `/root/.claude` داخل والیوم `claude-config` ذخیره می‌شود تا نشست لاگین و تنظیمات پس از ساخت مجدد کانتینر حفظ شوند.
- **اتصال داینامیک پروژه‌ها از طریق `.env`:** می‌توانید یک یا چند مسیر پروژه در پوشه‌های مختلف سیستم را در متغیر `PROJECTS` داخل `.env` مشخص کنید تا خودکار به `/workspace` داخل کانتینر متصل شوند.

## ساختار پروژه

</div>

```text
.
├── Dockerfile              # Node 20 + git + curl + @anthropic-ai/claude-code
├── docker-compose.yaml     # استک یکپارچه: دروازه singbox + کانتینر claude-workspace
├── Makefile                # دستورات کمکی (برای راهنما make را اجرا کنید)
├── README.md               # مستندات انگلیسی
├── README.fa.md            # مستندات فارسی
├── .env.example            # الگوی متغیرهای محیطی
├── .gitignore              # نادیده گرفتن .env و docker-compose.override.yaml
├── scripts/
│   └── sync-projects.py    # تولید docker-compose.override.yaml از PROJECTS در .env
└── singbox-chain/
    ├── Dockerfile          # sing-box + Python 3.12 (Alpine)
    ├── convert.py          # تبدیل JSON سابسکریپشن Xray/V2Ray به outboundهای sing-box
    ├── entrypoint.sh       # دریافت سابسکریپشن، ساخت و اعتبارسنجی کانفیگ، تنظیم DNS
    └── template.json       # کانفیگ پایه sing-box 1.14+ (TUN، mixed، DNS و روتینگ)
```

<div dir="rtl">

## پیش‌نیازها

- Docker و Docker Compose
- لینک سابسکریپشن JSON از Xray/V2Ray (یا کانفیگ JSON از sing-box)
- یک سرور SSH خروجی با احراز هویت کلید خصوصی (`~/.ssh/id_rsa` یا مسیر دلخواه)
- *(اختیاری)* مرورگر Firefox نصب‌شده در مسیر `/Applications/Firefox.app` (در macOS) برای دستور `make firefox`

## راه‌اندازی

۱. فایل `.env` را از روی فایل نمونه بسازید:

</div>

```bash
cp .env.example .env
```

<div dir="rtl">

۲. فایل `.env` را با اطلاعات سابسکریپشن، سرور SSH، تنظیمات محیط کار، هویت Git و مسیر پروژه‌ها ویرایش کنید:

</div>

```env
# Subscription (Xray/V2Ray JSON, e.g. from Sanaei panel)
SUB_URL=https://sub.example.com/json/YOUR_TOKEN

# SSH Tunnel (final exit node)
SSH_HOST=1.2.3.4
SSH_PORT=22
SSH_USER=root
SSH_KEY_FILE=~/.ssh/id_rsa

# Proxy
SOCKS_PORT=1080

# Workspace Environment
TZ=Europe/Helsinki
WORKSPACE_LANG=en_US.UTF-8
WORKSPACE_TERM=xterm-256color

# Git Identity
GIT_USER_NAME=your-name
GIT_USER_EMAIL=you@example.com

# Projects (مسیرها با کاما جدا می‌شوند و در /workspace/<نام-پوشه> مانت می‌شوند)
# برای تعیین نام دلخواه در کانتینر از فرمت /path/to/dir:custom-name استفاده کنید
PROJECTS=/path/to/project-a,/other/path/project-b:custom-b
```

<div dir="rtl">

۳. ایمیج‌ها را بسازید و استک را اجرا کنید:

</div>

```bash
make build
```

<div dir="rtl">

۴. اتصال تونل، IP خروجی و تنظیمات DNS را بررسی کنید:

</div>

```bash
make check
```

<div dir="rtl">

هر سه بررسی IP (پروکسی SOCKS5 روی میزبان، `curl` داخل کانتینر و `curl --noproxy "*"` داخل کانتینر) باید IP سرور `SSH_HOST` شما را برگردانند.

## دستورات

برای مشاهده تمام دستورات موجود `make` (یا `make help`) را اجرا کنید:

| دستور | توضیح |
| :--- | :--- |
| `make` / `make help` | نمایش فهرست دستورات موجود |
| `make sync-projects` | تولید مجدد `docker-compose.override.yaml` از روی `PROJECTS` در `.env` |
| `make up` | همگام‌سازی مسیر پروژه‌ها و اجرای کانتینرها در پس‌زمینه |
| `make build` | همگام‌سازی مسیر پروژه‌ها، ساخت مجدد ایمیج‌ها و اجرای کانتینرها |
| `make down` | توقف و حذف کانتینرها |
| `make restart` | راه‌اندازی مجدد کانتینرها (دریافت مجدد سابسکریپشن هنگام شروع `singbox`) |
| `make claude` | اجرای CLI کلود کد (`claude`) داخل کانتینر `claude-workspace` |
| `make shell` | باز کردن شل تعاملی `bash` داخل کانتینر `claude-workspace` |
| `make firefox` | اجرای Firefox امن‌شده روی پروکسی `127.0.0.1:1080` |
| `make check` | بررسی IP پروکسی میزبان، IP کانتینر، تونل شفاف TUN و تنظیم DNS |
| `make logs` | مشاهده زنده لاگ‌های کانتینر `singbox` |

## عیب‌یابی

- **بررسی شروع به کار sing-box و انتخاب پروکسی:**

</div>

```bash
make logs
```

<div dir="rtl">

- **تغییر یا به‌روزرسانی سابسکریپشن در پنل:** دستور `make restart` را اجرا کنید تا `singbox` سابسکریپشن جدید را دانلود و تبدیل کند.
- **تغییر مسیر پروژه‌ها یا متغیرهای `.env`:** پس از ویرایش `.env` دستور `make up` را اجرا کنید تا کانتینر با تنظیمات جدید به‌روز شود.
- **زمان‌بر بودن اولین درخواست:** در شروع کار، `urltest` سرورهای سابسکریپشن را تست سرعت می‌کند و اولین اتصال SSH برقرار می‌شود؛ درخواست‌های بعدی از تونل فعال استفاده می‌کنند.
- **خطای دسترسی یا مانت کلید SSH:** مطمئن شوید `SSH_KEY_FILE` در `.env` به یک کلید خصوصی خواندنی و بدون passphrase روی سیستم میزبان اشاره می‌کند (در صورت داشتن passphrase باید `singbox-chain/entrypoint.sh` را متناسب با آن تغییر دهید).

</div>
