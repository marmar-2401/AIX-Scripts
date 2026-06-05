# clamav.ksh — AIX ClamAV Management Script

**Author:** Mark Pierce-Zellfrow | **Platform:** AIX 7.1/7.2/7.3 (Korn Shell) | **Version:** 2.3.1

---

## Quick Start

```sh
# 1. Stage the install files (see Staging)
ksh clamav.ksh --stageclamav

# 2. Install everything
ksh clamav.ksh --setupclamav

# 3. Verify it's healthy
ksh clamav.ksh --clamavcheck

# 4. Confirm detection works
ksh clamav.ksh --testclamav
```

> Always run as `root`.

---

## All Options

| Option | What it does |
|---|---|
| `--help` | Show this option list |
| `--ver` | Version history |
| `--stageclamav` | Check staging files are in place; print placement steps if not |
| `--setupclamav` | Full install: libunwind → RPM → config → freshclam → cron |
| `--freshclam` | Update virus databases |
| `--clamavcheck` | Full health status report |
| `--testclamav` | EICAR detection test + `/tmp` scan |
| `--scan <dir>` | Scan any directory |
| `--manualscan` | Trigger an immediate scan (same logic as daily cron) |
| `--whitelsclamav` | Manage false-positive whitelist |
| `--runtests` | Run automated self-tests (`--pre` before install, `--post` after) |
| `--removeclamav` | Full uninstall |

---

## Staging

The script **never copies files automatically**. You place them manually once, then
`--stageclamav` checks they're all there and prints what's missing.

### Required files

These three files must exist at these exact paths before running `--setupclamav`:

```
/SCC-TMP/clamaix/clamav-1.4.3-1.aix7.2.ppc.rpm
/SCC-TMP/clamaix/freshclam.conf
/SCC-TMP/clamaix/libunwind.17.1.3.0.bff
```

They come bundled as `clamaix.tar` on the source server (e.g. `fse6-1`).

### How to get them there

```sh
mkdir -p /SCC-TMP && cd /SCC-TMP

# Pull from source server (you'll be prompted for password):
scp fse6-1:/SCC-TMP/clamaix.tar .

# Extract:
tar -xvf clamaix.tar

# Verify all three show [PRESENT]:
ksh clamav.ksh --stageclamav
```

---

## What Gets Installed

```
/usr/lpp/xlC/lib/libunwind.a            ← restored from BFF
/usr/lib/libunwind.a                    ← symlink to above
/opt/freeware/bin/clamscan
/opt/freeware/bin/freshclam
/opt/freeware/etc/clamav/freshclam.conf
/var/lib/clamav/                        ← virus databases + state
/var/log/clamav/                        ← all log output
/usr/local/bin/aix_clamav_scan.sh       ← daily scan (cron)
/usr/local/bin/aix_freshclam.sh         ← daily DB update (cron)
/usr/local/bin/aix_clamav_weekly_report.sh  ← weekly email (cron)
/etc/profile                            ← LIBPATH block appended
```

---

## Cron Jobs

Installed automatically by `--setupclamav` into root's crontab:

| Schedule | Script | Purpose |
|---|---|---|
| Daily 01:00 | `aix_clamav_scan.sh` | Incremental scan |
| Daily 02:00 | `aix_freshclam.sh` | Update virus databases |
| Sunday 09:00 | `aix_clamav_weekly_report.sh` | Email weekly summary |

**How scanning works:**
- **First run** — scans all of `/` (called `Full-Initial`). Creates a checkpoint.
- **Every day after** — only scans files newer than the last checkpoint. If nothing changed, clamscan is skipped entirely (zero CPU).
- **On scan error** — checkpoint is not advanced so the same files are retried next run.

To change the schedule: `crontab -e`

To change the alert email after install, edit `EMAIL_ADDR=` near the top of each
script in `/usr/local/bin/`.

**Scan exclusions** (never scanned): `/proc`, `/dev`, `/var/lib/clamav`, `/var/log/clamav`.
To change: edit the `find` commands inside `/usr/local/bin/aix_clamav_scan.sh`.

---

## Whitelist

Use the whitelist to suppress known false positives.

```sh
ksh clamav.ksh --whitelsclamav
```

- Entries are **exact absolute paths** — no wildcards
- Matching detections are logged as `[WHITELIST]` in the audit log — no email sent
- Changes take effect on the next scan automatically

The whitelist file lives at `/var/lib/clamav/whitelist.txt`.

---

## Logs

| File | What's in it | Cleared? |
|---|---|---|
| `/var/log/clamav/clamav-YYYY-MM-DD.log` | Full clamscan output per day | Never |
| `/var/log/clamav/freshclam-YYYY-MM-DD.log` | freshclam output per day | Never |
| `/var/log/clamav/infected_audit.log` | All detections + whitelist events | Never |
| `/var/log/clamav/weekly_report.log` | One line per scan run | After weekly email |

```sh
# Follow today's scan in real time:
tail -f /var/log/clamav/clamav-$(date '+%Y-%m-%d').log
```

AIX has no `logrotate`. To compress logs older than 30 days, add to cron:
```sh
0 3 * * 0  find /var/log/clamav -name "*.log" -mtime +30 -exec compress {} \;
```

---

## Testing

The test suite is built into the script — no separate file needed.

```sh
ksh clamav.ksh --runtests          # Run all tests (pre + post)
ksh clamav.ksh --runtests --pre    # Before install: syntax, staging, options
ksh clamav.ksh --runtests --post   # After install: detection, scans, cron, whitelist
```

Must run as root. Exits 0 if all tests pass, 1 if any fail.

**`--pre` covers:** syntax check, `--help`/`--ver`/unknown-option exit codes,
staging with missing and present files.

**`--post` covers:** health check, EICAR detection and cleanup, directory scans
(clean and with EICAR), automation scripts (daily / MANUAL-TEST / PID lock /
checkpoint delete), whitelist add/remove/duplicate/audit, manual scan PID lock,
log file creation, cron format, LIBPATH idempotency.

Skipped tests are normal when staging files are not present on the test host.
---

## Troubleshooting

**`clamscan: error while loading shared libraries`**
```sh
. /etc/profile && echo $LIBPATH   # reload LIBPATH for this session
```

**freshclam fails or times out**
```sh
nslookup database.clamav.net     # check DNS
# No internet? SCP the .cvd files from a server that has them:
# scp <source>:/var/lib/clamav/*.cvd /var/lib/clamav/
```

**Cron jobs not running**
```sh
crontab -l | grep clamav         # confirm entries exist
lssrc -s cron                    # confirm cron daemon is running
```

**First scan is very slow**
Expected — `Full-Initial` scans everything under `/`. Daily scans after that only
process files newer than the last checkpoint. Confirm the checkpoint was created:
```sh
ls -l /var/lib/clamav/scan_checkpoint
```
If missing, check `infected_audit.log` for `[ERROR] clamscan error (RC=2)`.


**Alert emails never arrive**
`sendmail` **must be installed and running** on the AIX host before `--setupclamav` is run.
Without it, alert emails and the weekly report will fail silently.
```sh
lssrc -s sendmail                    # confirm sendmail is active
echo "test" | mail -s "test" root   # confirm mail delivery works
```
If sendmail is not set up, install and configure it first, then re-run `--setupclamav`.

**`restore` fails on the BFF**
The BFF must match your AIX level. Check: `lslpp -h`

**RPM install fails with dependency errors**
`--nodeps` is intentional — libunwind is installed separately via BFF.
If a different library is missing:
```sh
dump -H /opt/freeware/bin/clamscan | grep -i needed
```
