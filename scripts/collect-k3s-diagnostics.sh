#!/usr/bin/env bash
# collect-k3s-diagnostics.sh
#
# Collects host and k3s service diagnostics for Manifest support into a
# single text file. Read-only: it changes nothing on the system.
#
# Usage (as root):  bash collect-k3s-diagnostics.sh
# Output:           ./manifest-k3s-diagnostics-<hostname>-<timestamp>.txt

set -u

OUT="./manifest-k3s-diagnostics-$(hostname -s 2>/dev/null || echo host)-$(date +%Y%m%d-%H%M%S).txt"

if [ "$(id -u)" -ne 0 ]; then
  echo "WARNING: not running as root; some sections will be incomplete." >&2
  echo "         Re-run with: sudo bash $0" >&2
fi

# banner <title> <command...>
# Writes a section header into the output file.
banner() {
  local title="$1"
  shift
  {
    echo
    echo "================================================================"
    echo "## ${title}"
    echo "## \$ $*"
    echo "================================================================"
  } >>"$OUT"
}

# section <title> <command...>
# Prints a banner and runs the command, capturing stdout+stderr.
# A failing or missing command is recorded rather than aborting the script.
section() {
  local title="$1"
  banner "$@"
  shift
  if "$@" >>"$OUT" 2>&1; then
    :
  else
    echo "[command exited non-zero or is unavailable]" >>"$OUT"
  fi
  echo "  collected: ${title}"
}

# mount_rollup [path-prefix]
# A container host carries one overlay mount per container plus tmpfs and shm
# mounts per pod, which bury the real filesystems in df output. The df sections
# exclude those types; this summarizes them instead. Only the additive columns
# are summed: overlay reports its backing filesystem, and tmpfs sizes are limits
# against shared RAM, so totalling either would be double-counting. Mounts that
# are nearly full are listed individually so filtering cannot hide them.
mount_rollup() {
  local prefix="${1:-/}"
  { df -PkT; echo '#inodes'; df -PTi; } 2>/dev/null | awk -v prefix="$prefix" '
    function human(kb,   units, i) {
      split("KiB MiB GiB TiB PiB", units, " ")
      for (i = 1; kb >= 1024 && i < 5; i++) kb /= 1024
      return sprintf("%.1f %s", kb, units[i])
    }
    $1 == "#inodes"    { pass = "inodes"; next }
    $1 == "Filesystem" { next }
    {
      mount = $NF
      if (substr(mount, 1, length(prefix)) != prefix) next
      if ($2 == "overlay")    class = "overlay"
      else if ($2 == "tmpfs") class = (mount ~ /\/shm$/) ? "shm" : "tmpfs"
      else next
      if (pass == "inodes") { iused[class] += $4; next }
      total++
      mounts[class]++
      used[class] += $4
      if ($6 + 0 >= 90) full[++nfull] = sprintf("  %-7s %4d%%  %s", class, $6 + 0, mount)
    }
    END {
      if (!total) { print "no overlay/tmpfs/shm mounts found under " prefix; exit }
      printf "%-8s %7s %12s %12s\n", "TYPE", "MOUNTS", "USED", "IUSED"
      n = split("overlay tmpfs shm", order, " ")
      for (i = 1; i <= n; i++) {
        class = order[i]
        if (!(class in mounts)) continue
        if (class == "overlay")
          printf "%-8s %7d %12s %12s\n", class, mounts[class], "-", "-"
        else
          printf "%-8s %7d %12s %12d\n", class, mounts[class], human(used[class]), iused[class]
      }
      if ("overlay" in mounts) {
        print ""
        print "Each overlay mount reports the usage of its backing filesystem, so its"
        print "space is already counted in the disk usage section and is omitted here."
      }
      if (nfull) {
        print ""
        print "Excluded mounts at 90% capacity or above:"
        for (i = 1; i <= nfull; i++) print full[i]
      }
    }
  '
}

{
  echo "Manifest k3s diagnostics"
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC') ($(date '+%Y-%m-%d %H:%M:%S %Z') local)"
  echo "Host: $(hostname -f 2>/dev/null || hostname)"
} >"$OUT"

echo "Writing diagnostics to $OUT"

# ────────────────────────────────────────────────────────────────
# Part 1: quick-look system state
# ────────────────────────────────────────────────────────────────
section "OS release"                 cat /etc/os-release
section "Kernel"                     uname -a
section "Hostname details"           hostnamectl
section "IPv4 addresses"             ip -4 addr
section "Uptime"                     uptime
section "Recent reboots"             bash -c 'last reboot | head -5'
section "Memory"                     free -h
section "Block devices"              lsblk
section "Disk usage"                 df -h -x overlay -x tmpfs
section "Inode usage"                df -i -x overlay -x tmpfs
section "overlay/tmpfs/shm roll-up"  mount_rollup
# is-active exits non-zero for "inactive", which is a valid answer, not a
# failure — mask the exit code so the section note doesn't imply an error.
section "SELinux mode"               getenforce
section "fapolicyd active?"          bash -c 'systemctl is-active fapolicyd; true'
section "nm-cloud-setup active?"     bash -c 'systemctl is-active nm-cloud-setup.service; true'
section "nm-cloud-setup timer?"      bash -c 'systemctl is-active nm-cloud-setup.timer; true'
section "firewalld active?"          bash -c 'systemctl is-active firewalld; true'

# ────────────────────────────────────────────────────────────────
# Part 2: k3s service state
# ────────────────────────────────────────────────────────────────
section "k3s service status"         systemctl status k3s.service --no-pager -l
section "/etc/rancher/k3s contents"  ls -la /etc/rancher/k3s/
section "k3s server dir contents"    ls -la /var/lib/rancher/k3s/server/
# -x keeps du on the data dir's own filesystem so it does not walk the per-pod
# shm and overlay mounts nested under it; the roll-up below accounts for those.
section "k3s data dir sizes"         bash -c 'du -shx /var/lib/rancher/k3s/* 2>/dev/null'
section "k3s nested mount roll-up"   mount_rollup /var/lib/rancher/k3s

# ────────────────────────────────────────────────────────────────
# Part 3: long logs (kept last so the quick-look info is up top)
# ────────────────────────────────────────────────────────────────
section "k3s journal (last 500 lines)" bash -c 'journalctl -u k3s.service --no-pager | tail -500'

# ────────────────────────────────────────────────────────────────
# Part 4: redacted deploy config (interactive, so it runs last)
# ────────────────────────────────────────────────────────────────
echo
echo "----------------------------------------------------------------"
echo "Next: collecting the redacted deploy config."
echo "You may be prompted to decrypt the config."
echo "The output is shown below and appended to the diagnostics file."
echo "----------------------------------------------------------------"
echo

banner "Deploy config (redacted)" manifest-installer deploy-config decrypt --redacted
# Tee so the operator sees exactly what was added to the file. PIPESTATUS[0]
# is the installer's status, not tee's. Older CLI versions lack --redacted;
# that failure is noted and ignored rather than treated as fatal.
manifest-installer deploy-config decrypt --redacted 2>&1 | tee -a "$OUT"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "[command exited non-zero or is unavailable: manifest-installer deploy-config decrypt --redacted]" | tee -a "$OUT"
fi
echo "  collected: Deploy config (redacted)"

echo
echo "Done. Please send this file back to Manifest support:"
echo "  $OUT"
echo
echo "IMPORTANT: always review debug logs for sensitive information before sharing."
