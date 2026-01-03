# AutoBounty - Visual Bug Bounty Reconnaissance Pipeline

Automated reconnaissance pipeline for bug bounty hunting, focused on **visual analysis** and **manual verification** with **intelligent caching** to avoid re-running expensive scans.

## 🎯 Philosophy

This pipeline is designed for **manual bug bounty hunters** who want:
- **Screenshots** of all live targets (via EyeWitness)
- **Technology fingerprinting** (WordPress, admin panels, frameworks)
- **Smart caching** - run once, resume anytime without re-scanning
- **No automated scanning** - focuses on recon, you do the testing

## 🚀 Features

- ✅ **Subdomain Enumeration** (subfinder)
- ✅ **HTTP Probing** (httpx with tech detection)
- ✅ **Port Scanning** (naabu)
- ✅ **Visual Reconnaissance** (EyeWitness screenshots)
- ✅ **Technology Stack Analysis** (Wappalyzer-like detection)
- ✅ **Intelligent Caching** (skip completed steps on resume)
- ✅ **Interactive HTML Report** (screenshot gallery)
- ✅ **Fail-Fast Validation** (preflight checks)

## 📋 Prerequisites

- **Docker Desktop** (Windows/Mac/Linux)
- **Git** (for cloning and line-ending normalization)
- **PowerShell** (Windows) or **Bash/Make** (Git Bash, Linux, Mac)

## 🏃 Quick Start

### 1. Clone & Setup

```bash
git clone <your-repo>
cd autobounty

# Copy environment template
cp .env.example .env
```

### 2. Add Target Scope

Create or edit `input/scope.txt` with target domains (one per line):

```
example.com
target.com
bugcrowd-target.io
```

### 3. Run Complete Pipeline

#### Option A: PowerShell (Windows)

```powershell
# First run - build + execute full pipeline
.\run.ps1

# Resume previous run (skip cached steps)
.\run.ps1 -Resume

# Just generate report from existing data
.\run.ps1 -ReportOnly
```

#### Option B: Git Bash / Make (Windows/Linux/Mac)

```bash
# First run - complete pipeline
make all

# Resume previous run (using cache)
make resume

# Just generate report
make report
```

### 4. Review Results

Open the interactive screenshot gallery:

```powershell
# Windows
start output\<RUN_ID>\eyewitness\report.html

# Mac/Linux
open output/<RUN_ID>/eyewitness/report.html
```

## 📁 Output Structure

```
output/<RUN_ID>/
├── REPORT.md                    # Summary report with tech stack
├── scope.normalized.txt         # Cleaned target domains
├── subdomains.txt              # All discovered subdomains
├── httpx.json                  # Detailed HTTP probe results
├── alive.urls.txt              # Live web services
├── technologies.json           # Technology fingerprints
├── naabu.json                  # Port scan results
├── open.ports.txt              # Open ports list
└── eyewitness/
    ├── report.html             # 📸 Interactive screenshot gallery
    ├── *.png                   # Individual screenshots
    └── source/                 # Page source code
```

## 🔄 Resume Mode (Smart Caching)

The pipeline caches each step. On resume, it **skips** steps that already completed:

```powershell
# PowerShell
.\run.ps1             # Full run (5-30 min)
.\run.ps1 -Resume     # Resume (only runs missing steps)
```

```bash
# Bash/Make
make run              # Full run
make resume           # Resume with cache
```

**Cached steps:**
- ✅ Scope normalization
- ✅ Subfinder (subdomain enumeration)
- ✅ Httpx (HTTP probing)
- ✅ Naabu (port scanning)
- ✅ EyeWitness (screenshots)

**Use case:** If EyeWitness crashes or times out, fix the issue and run `make resume` to continue where it stopped.

## 🎨 Visual Analysis Workflow

1. **Run pipeline** → generates screenshots
2. **Open HTML report** → browse all targets visually
3. **Identify interesting targets:**
   - Admin panels / login pages
   - Development/staging environments
   - Unusual technologies
   - Exposed services
4. **Manual testing** on selected targets

## 🔧 Advanced Usage

### Manual Steps

```bash
# Build runner image only
make build

# Start containers (daemon)
make up

# Run pipeline only (skip build)
make run

# Generate report only
make report

# Clean all outputs
make clean

# Check for CRLF issues
make check-crlf
```

### PowerShell Options

```powershell
# Skip rebuild (use existing image)
.\run.ps1 -SkipBuild

# Generate report only
.\run.ps1 -ReportOnly

# Resume previous run
.\run.ps1 -Resume

# Clean outputs
.\run.ps1 -Clean

# Check CRLF
.\run.ps1 -CheckCRLF
```

### Environment Variables

Edit `.env` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_PORT_SCAN_RATE` | `1000` | Naabu port scan rate limit |
| `RESUME` | `false` | Resume previous run (skip cached steps) |
| `DISCORD_WEBHOOK_URL` | (empty) | Discord notification webhook |

## 📊 Technology Detection

The pipeline automatically detects technologies using httpx:

```bash
# View all detected technologies
jq '.' output/<RUN_ID>/technologies.json

# Find all WordPress sites
jq -r '.[] | select(.technologies[]? == "WordPress") | .url' \
  output/<RUN_ID>/technologies.json

# Find admin panels
jq -r '.[] | select(.title | test("admin|dashboard|panel"; "i")) | .url' \
  output/<RUN_ID>/httpx.json
```

## 🐛 Troubleshooting

### CRLF Line Ending Issues

**Symptom:** Scripts fail with `\r': command not found`

**Fix:**

```bash
# Check for CRLF
make check-crlf
# or
.\run.ps1 -CheckCRLF

# Normalize line endings
git add --renormalize .
git commit -m "Normalize line endings to LF"
```

**Prevention:** The `.gitattributes` file enforces LF for scripts.

### Command Not Found (subfinder, httpx, etc.)

**Symptom:** `subfinder: command not found`

**Fix:** Rebuild the runner image with proper PATH:

```bash
docker compose down
docker compose build runner
```

### EyeWitness Errors

**Symptom:** No screenshots or EyeWitness crashes

**Possible causes:**
1. **Xvfb not running** (virtual display for headless Chrome)
2. **Chrome driver issues**

**Debug:**

```bash
# Check logs
cat output/<RUN_ID>/eyewitness.log

# Rebuild image
docker compose build --no-cache runner
```

### Empty Results

**Symptom:** No subdomains/findings despite valid scope

**Possible causes:**

1. **Network restrictions**: Docker needs internet access
2. **Rate limiting**: Target blocking automated scans
3. **Scope format**: Check `input/scope.txt` has one domain per line

**Debug:**

```bash
# Check normalized scope
cat output/<RUN_ID>/scope.normalized.txt

# Check container logs
docker compose logs runner
```

### Permission Errors on Windows

**Symptom:** Cannot write to `output/` directory

**Fix:** Ensure Docker Desktop has access to the project directory:
1. Docker Desktop → Settings → Resources → File Sharing
2. Add project path
3. Apply & Restart

## 🏗️ Architecture

```
autobounty/
├── Dockerfile.runner           # Pre-built image with all tools
├── docker-compose.yml          # Service orchestration
├── Makefile                    # Build automation (Bash/Make)
├── run.ps1                     # Build automation (PowerShell)
├── .env.example                # Configuration template
├── .gitattributes              # Force LF line endings
├── input/
│   └── scope.txt               # Target domains (user-provided)
├── scripts/
│   ├── lib.sh                  # Shared utilities
│   ├── 05_preflight.sh         # Validation (fail-fast)
│   ├── 10_run_pipeline.sh      # Main orchestration (with cache)
│   ├── 15_run_eyewitness.sh    # EyeWitness screenshots
│   └── 20_build_reports.sh     # Report generation
└── output/
    └── <RUN_ID>/               # Timestamped results
        ├── REPORT.md
        ├── eyewitness/
        └── *.txt, *.json
```

## 🔄 Pipeline Stages

1. **Preflight** (`05_preflight.sh`)
   - Check CRLF in scripts
   - Verify dependencies (subfinder, httpx, naabu, eyewitness, jq)
   - Validate input scope
   - Check output directory writability

2. **Subdomain Enumeration** (subfinder) - **Cached**
   - Passive subdomain discovery

3. **HTTP Probing** (httpx) - **Cached**
   - Identify live web services
   - Extract titles, technologies, status codes, servers

4. **Port Scanning** (naabu) - **Cached**
   - Discover open ports on live hosts
   - Rate-limited for stealth

5. **Visual Reconnaissance** (EyeWitness) - **Cached**
   - Screenshot all live URLs
   - Generate interactive HTML gallery
   - Fingerprint technologies

6. **Report Generation** (`20_build_reports.sh`)
   - Markdown summary with tech stack
   - Interesting targets (admin panels, dev environments)
   - Next steps for manual testing

## 🔍 Finding Interesting Targets

The report automatically highlights:

### Admin Panels & Dashboards
Pages with titles containing "admin", "dashboard", "panel", "login", "portal"

### Dev/Staging Environments
URLs containing "dev", "staging", "test", "uat", "qa"

### Technology-Specific
- WordPress sites
- PHP applications
- ASP.NET applications
- Node.js applications
- Specific frameworks (Laravel, Django, Rails, etc.)

## 🎯 Manual Testing Workflow

1. Run pipeline: `make all` or `.\run.ps1`
2. Open screenshot gallery: `output/<RUN_ID>/eyewitness/report.html`
3. Review technologies: `output/<RUN_ID>/technologies.json`
4. Identify high-value targets:
   - Admin panels
   - Unusual technologies
   - Exposed services
5. Manual testing on selected targets
6. Document findings

## 🛡️ Security Considerations

- **Rate limiting**: Configured via `MAX_PORT_SCAN_RATE`
- **Scope validation**: Only scans domains in `input/scope.txt`
- **No credential storage**: All secrets via `.env` (excluded from git)
- **Isolated execution**: Runs in Docker container
- **Passive first**: Subfinder uses passive sources only

## 📝 Example: Filtering Results

```bash
# Find all sites with specific technology
jq -r '.[] | select(.technologies[]? == "WordPress") | .url' \
  output/<RUN_ID>/technologies.json

# Find all admin panels
jq -r '.[] | select(.title | ascii_downcase | contains("admin")) | .url' \
  output/<RUN_ID>/httpx.json

# Find all 200 OK responses
jq -r '.[] | select(.status_code == 200) | .url' \
  output/<RUN_ID>/httpx.json

# Find sites with specific server
jq -r '.[] | select(.server | contains("Apache")) | .url' \
  output/<RUN_ID>/httpx.json
```

## 🔄 Workflow Tips

### Incremental Recon

```bash
# Day 1: Initial scan
make all

# Day 2: Update scope, resume (keeps old results + scans new domains)
# Edit input/scope.txt, then:
make resume
```

### Parallel Workflows

```bash
# Terminal 1: Run recon
make run

# Terminal 2: While running, start analyzing previous results
make report  # (for previous RUN_ID)
open output/<PREVIOUS_RUN_ID>/eyewitness/report.html
```

## 🤝 Contributing

1. Ensure `.gitattributes` is respected (LF line endings)
2. Test on both Windows (PowerShell) and Linux (Bash)
3. Update `.env.example` for new variables
4. Document changes in README

## 📜 License

MIT

## 🙏 Credits

Built with:
- [ProjectDiscovery](https://projectdiscovery.io/) tools (subfinder, httpx, naabu)
- [EyeWitness](https://github.com/RedSiege/EyeWitness) visual recon
- [n8n](https://n8n.io/) workflow automation (optional)
- Docker & Docker Compose

---

**Happy Hunting!** 🎯
