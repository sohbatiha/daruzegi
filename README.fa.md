<p align="center">
  <img src="assets/daruzegi.jpg" alt="دَریوزِگی (Daruzegi)" width="320" />
</p>

<div dir="rtl">

<h1 align="center">دَریوزِگی (Daruzegi)</h1>

<p align="center">
  <strong>محیط کار ایزوله T3 Code (<code>sing-box</code> Proxy Chain)</strong><br />
  تلفظ: <strong>دَر-یو-زِ-گی</strong> · فونتیک: <span dir="ltr"><strong>/dæɾ.juː.zeˈɡiː/</strong> · <code>dar-yoo-ze-GEE</code></span>
</p>

<p align="center">
  🌐 <strong>زبان:</strong> <a href="README.md">English</a> | <strong>فارسی</strong>
</p>

یک محیط Docker ایزوله برای اجرای **T3 Code** (همراه با **Claude Code** و **OpenAI Codex**) و مرورگر امن‌شده‌ی **Firefox** که در آن تمام ترافیک شبکه خروجی و درخواست‌های DNS به‌صورت اجباری از طریق یک تونل زنجیره‌ای عبور می‌کنند:

</div>

```text
T3 Code (container :3773)    ──► TUN (tun0, strict_route) ──┐
                                                             ├──► auto (VLESS / VMess / Trojan / SS) ──► SSH Exit Node ──► Internet
Hardened Firefox (host)      ──► SOCKS5 (127.0.0.1:1080)  ──┘
```

<div dir="rtl">

## ویژگی‌ها

- **رابط وب T3 Code + ایجنت‌های کدنویسی:** سرویس `t3 serve` را به‌صورت لوکال روی `127.0.0.1:3773` اجرا می‌کند و هر دو ابزار `@anthropic-ai/claude-code` و `@openai/codex` به‌صورت پیش‌فرض داخل آن نصب هستند؛ همچنین دستور `make pair` (یا `./pair.sh`) لینک ورود (pairing) تولید می‌کند.
- **حالت‌های انعطاف‌پذیر پروکسی (`sub`، `uri` و `direct`):**
  - `sub` *(پیش‌فرض)*: لینک سابسکریپشن Xray/V2Ray (خروجی JSON پنل سنایی، JSON استاندارد، sing-box JSON یا لیست URI به‌صورت متن ساده/Base64) را دریافت کرده، به فرمت `sing-box` نسخه 1.14 به بالا تبدیل می‌کند، سریع‌ترین سرور را با `urltest` (`auto`) انتخاب کرده و ترافیک خروجی را از طریق تونل SSH به سرور نهایی هدایت می‌کند.
  - `uri`: اتصال تکی از طریق یک لینک کانفیگ (`vless://`، `vmess://`، `trojan://` یا `ss://`) در متغیر `PROXY_URI` و عبور آن از تونل SSH.
  - `direct`: حذف کامل لایه پروکسی/سابسکریپشن و عبور مستقیم ترافیک فقط از طریق سرور SSH خروجی.
- **کنترل پروکسی SSH (`SSH_ENABLED`):** به‌صورت پیش‌فرض همیشه فعال است (`SSH_ENABLED=true`). غیرفعال کردن آن (`SSH_ENABLED=false`) به معنی خروج مستقیم بدون تونل SSH است و **به‌ویژه در حالت `PROXY_MODE=direct` باعث لو رفتن IP واقعی شما می‌شود**.
- **مسیریابی شفاف TUN و Kill Switch:** کانتینر `t3code` فضای شبکه `singbox` را به اشتراک می‌گذارد (`network_mode: "service:singbox"`) و تا آماده شدن کامل `singbox` (بالا آمدن `tun0` و باز شدن پورت `1080`) صبر می‌کند. تمام ترافیک خروجی کانتینر با `strict_route: true` از `tun0` عبور می‌کند.
- **بدون نشت DNS (No DNS Leaks):** تنظیم DNS کانتینر روی `1.1.1.1` قرار می‌گیرد تا تمام درخواست‌ها وارد `tun0` شده، توسط `hijack-dns` رهگیری شوند و از طریق DoH (`https://1.1.1.1/dns-query`) روی `ssh-exit` حل شوند.
- **پروکسی SOCKS5/HTTP روی سیستم میزبان + فایرفاکس امن‌شده:** یک ورودی `mixed` روی `127.0.0.1:1080` برای برنامه‌های سیستم میزبان (macOS) باز می‌کند و دستور `make firefox` یک پروفایل ایزوله از Firefox با DNS از راه دور روی SOCKS5 و تایم‌زون هماهنگ با `.env` اجرا می‌کند.
- **ذخیره‌سازی یکپارچه تمام دیتاها در یک پوشه واحد (`DATA_DIR`):** کل دایرکتوری خانه کانتینر (`/home/node`) به یک پوشه واحد روی سیستم میزبان (`DATA_DIR` با پیش‌فرض `./data`) مانت می‌شود؛ بنابراین تمام فایل‌ها، اسکیل‌ها (`.claude/skills`، `.codex/skills`، `.agents/skills`)، پلاگین‌ها، تنظیمات MCP، نشست‌های لاگین، `.config`، `.local/bin`، `.npm-global`، `.ssh` و وضعیت `t3` با تغییر `docker-compose.yaml`، ریستارت، بیلد مجدد یا حتی `docker compose down -v` از بین نمی‌روند.
- **اتصال داینامیک پروژه‌ها از طریق `.env`:** مسیر پروژه‌های خود را در متغیر `PROJECTS` داخل `.env` مشخص کنید تا خودکار در `/workspace/<نام-پوشه>` مانت شوند.

## ساختار پروژه

</div>

```text
.
├── Dockerfile              # Node 22 + t3 + @anthropic-ai/claude-code + @openai/codex
├── entrypoint.sh           # تنظیم Git، safe.directory و لاگین اختیاری Codex با API key
├── t3-pair                 # اسکریپت داخل کانتینر برای ساخت لینک pairing
├── pair.sh                 # میان‌بر روی میزبان برای ساخت لینک pairing
├── docker-compose.yaml     # استک یکپارچه: دروازه singbox + کانتینر t3code
├── Makefile                # دستورات کمکی (برای راهنما make را اجرا کنید)
├── README.md               # مستندات انگلیسی
├── README.fa.md            # مستندات فارسی
├── .env.example            # الگوی متغیرهای محیطی
├── .gitignore              # نادیده گرفتن .env، پوشه data و docker-compose.override.yaml
├── assets/
│   └── daruzegi.jpg        # تصویر پروژه
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
- *(اختیاری بسته به `PROXY_MODE`)* لینک سابسکریپشن Xray/V2Ray/sing-box (`sub`) یا لینک تکی `vless://` / `vmess://` / `trojan://` / `ss://` (`uri`)
- یک سرور SSH خروجی با احراز هویت کلید خصوصی (`~/.ssh/id_rsa` یا مسیر دلخواه) — به‌صورت پیش‌فرض فعال
- *(اختیاری)* مرورگر Firefox نصب‌شده در مسیر `/Applications/Firefox.app` (در macOS) برای دستور `make firefox`

## راه‌اندازی

۱. فایل `.env` را از روی فایل نمونه بسازید:

</div>

```bash
make setup
```

<div dir="rtl">

۲. فایل `.env` را با حالت پروکسی، سرور SSH، تنظیمات T3 Code، هویت Git و مسیر پروژه‌ها ویرایش کنید:

</div>

```env
# Upstream Proxy Mode: sub | uri | direct
PROXY_MODE=sub

# Subscription URL (در حالت PROXY_MODE=sub)
SUB_URL=https://sub.example.com/json/YOUR_TOKEN
# بازه زمانی تست سرعت سرورهای سابسکریپشن (مثلاً 30s، 5m، 1h)
SUB_TEST_INTERVAL=5m

# Single proxy URI (در حالت PROXY_MODE=uri) — پشتیبانی از vless://, vmess://, trojan://, ss://
# PROXY_URI=vless://uuid@example.com:443?security=reality&sni=example.com&pbk=...&sid=...&fp=chrome#node

# SSH Tunnel (final exit node)
# SSH_ENABLED=true
SSH_HOST=1.2.3.4
SSH_PORT=22
SSH_USER=root
SSH_KEY_FILE=~/.ssh/id_rsa

# Proxy & T3 Code
SOCKS_PORT=1080
DATA_DIR=./data
T3_PORT=3773
T3_CPUS=0
# T3_PUBLIC_URL=http://localhost:3773
T3_PAIRING_TTL=1h

# Coding Agents (اختیاری — برای لاگین تعاملی خالی بگذارید)
CLAUDE_CODE_OAUTH_TOKEN=
OPENAI_API_KEY=

# Workspace Environment
TZ=Europe/Helsinki
WORKSPACE_LANG=en_US.UTF-8
WORKSPACE_TERM=xterm-256color

# Git Identity
GIT_USER_NAME=your-name
GIT_USER_EMAIL=you@example.com

# Projects (مسیرها با کاما جدا می‌شوند و در /workspace/<نام-پوشه> مانت می‌شوند)
PROJECTS=/path/to/project-a,/other/path/project-b:custom-b
```

<div dir="rtl">

۳. ایمیج‌ها را بسازید و استک را اجرا کنید:

</div>

```bash
make build
```

<div dir="rtl">

۴. اتصال تونل، IP خروجی، تنظیمات DNS و در دسترس بودن T3 Code را بررسی کنید:

</div>

```bash
make check
```

<div dir="rtl">

۵. لینک ورود T3 Code را بگیرید و در صورت نیاز وارد Claude Code یا Codex شوید:

</div>

```bash
make pair          # ساخت لینک ورود روی http://localhost:3773 (مثلاً make pair TTL=30d)
make claude-login  # داخل محیط دستور /login را اجرا کنید
make codex-login   # لاگین Codex با حساب ChatGPT
```

<div dir="rtl">

## دستورات

برای مشاهده تمام دستورات موجود `make` (یا `make help`) را اجرا کنید:

| دستور | توضیح |
| :--- | :--- |
| `make` / `make help` | نمایش فهرست دستورات موجود |
| `make setup` | ساخت `.env` از روی `.env.example` |
| `make sync-projects` | تولید مجدد `docker-compose.override.yaml` از روی `PROJECTS` در `.env` |
| `make up` | همگام‌سازی مسیر پروژه‌ها و اجرای کانتینرها در پس‌زمینه |
| `make build` | همگام‌سازی مسیر پروژه‌ها، ساخت مجدد ایمیج‌ها و اجرای کانتینرها |
| `make down` | توقف و حذف کانتینرها |
| `make restart` | راه‌اندازی مجدد کانتینرها (دریافت مجدد سابسکریپشن هنگام شروع `singbox`) |
| `make ps` | نمایش وضعیت کانتینرها |
| `make pair` | ساخت لینک ورود T3 Code (مثلاً `make pair TTL=30d`) |
| `make claude` / `make claude-login` | اجرای CLI کلود کد (`claude`) داخل کانتینر `t3code` |
| `make codex-login` | لاگین به Codex با حساب ChatGPT |
| `make shell` | باز کردن شل تعاملی `bash` داخل کانتینر `t3code` |
| `make firefox` | اجرای Firefox امن‌شده روی پروکسی `127.0.0.1:1080` |
| `make check` | بررسی IP پروکسی میزبان، IP کانتینر، تونل شفاف TUN، DNS و پورت لوکال T3 |
| `make logs` | مشاهده زنده لاگ تمام کانتینرها |
| `make logs-singbox` | مشاهده زنده لاگ کانتینر `singbox` |
| `make logs-t3` | مشاهده زنده لاگ کانتینر `t3code` |
| `make fix-perms` | تنظیم مالکیت پوشه `/workspace` برای کاربر `node` |

## عیب‌یابی

- **بررسی لاگ شروع به کار کانتینرها:**

</div>

```bash
make logs
```

<div dir="rtl">

- **تغییر یا به‌روزرسانی سابسکریپشن در پنل:** دستور `make restart` را اجرا کنید تا `singbox` سابسکریپشن جدید را دانلود و تبدیل کند.
- **تغییر مسیر پروژه‌ها یا متغیرهای `.env`:** پس از ویرایش `.env` دستور `make up` را اجرا کنید تا کانتینر با تنظیمات جدید به‌روز شود.
- **زمان‌بر بودن اولین درخواست:** در شروع کار، `urltest` سرورهای سابسکریپشن را تست سرعت می‌کند و اولین اتصال SSH برقرار می‌شود؛ درخواست‌های بعدی از تونل فعال استفاده می‌کنند.
- **خطای دسترسی یا مانت کلید SSH:** مطمئن شوید `SSH_KEY_FILE` در `.env` به یک کلید خصوصی خواندنی و بدون passphrase روی سیستم میزبان اشاره می‌کند.

</div>
