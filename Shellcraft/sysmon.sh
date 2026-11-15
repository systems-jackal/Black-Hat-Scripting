#!/bin/bash
# =====================================================================
# sysmon_learn.sh
#
# A LEARNING-FRIENDLY system monitoring script.
#
# Every section below:
#   1) prints a short NOTE explaining what it's about to check and why
#   2) runs the real command(s) that do the checking
#   3) prints a short result line so you don't have to interpret raw
#      numbers yourself
#
# HOW TO RUN:
#   bash sysmon_learn.sh
#
# HOW TO READ THIS FILE:
#   Every line starting with "#" is a comment. Bash ignores comments
#   completely - they exist only so a human reading the file understands
#   what's going on. Comments never run or change anything.
# =====================================================================


# ---------------------------------------------------------------------
# SECTION 0: Small helper tools used throughout the script
# ---------------------------------------------------------------------
# We define these once at the top so we don't repeat ourselves later.
# This is normal practice: write a small function, reuse it everywhere.

# note() just prints an explanatory message in a different style,
# so it's visually obvious which lines are "teaching notes" vs
# which lines are real output.
note() {
    echo "   >> NOTE: $1"
}

# section() prints a big heading so the output is easy to scan.
section() {
    echo ""
    echo "===================================================="
    echo " $1"
    echo "===================================================="
}

# have() checks whether a command exists on this system before we
# try to use it. Not every Linux system has every tool installed.
# "command -v X" prints the path to X if it exists, and nothing if not.
# ">/dev/null 2>&1" just means "don't show that output, I only care
# whether it succeeded or failed."
have() {
    command -v "$1" >/dev/null 2>&1
}


# =====================================================================
# SECTION 1: SYSTEM INFORMATION
# =====================================================================
section "1. SYSTEM INFORMATION"
note "This tells us WHAT machine we're on: its name, OS, and hardware."
note "Useful because 'is this normal?' depends on knowing the baseline."

echo "Hostname : $(hostname)"
# hostname = the name of this machine on the network

echo "Kernel   : $(uname -r)"
# uname -r = the version of the Linux kernel (the core of the OS)

echo "Arch     : $(uname -m)"
# uname -m = CPU architecture, e.g. x86_64 (normal PC/server) or aarch64 (ARM)

if [ -r /etc/os-release ]; then
    # [ -r file ] tests "is this file readable?"
    # /etc/os-release holds OS name info as VARIABLE=value lines
    echo "OS       : $(. /etc/os-release && echo "$PRETTY_NAME")"
    # ". /etc/os-release" loads those variables (like PRETTY_NAME)
    # into a temporary shell so we can read PRETTY_NAME out of it
fi

echo "Date     : $(date)"
# date = current system date and time


# =====================================================================
# SECTION 2: UPTIME AND LOAD
# =====================================================================
section "2. UPTIME AND LOAD AVERAGE"
note "Uptime = how long since the machine last rebooted."
note "An UNEXPECTED reboot can be a sign of a crash, a power issue,"
note "or in rare cases, someone rebooting the machine without you."
note "Load average = how many processes were waiting for CPU time,"
note "averaged over the last 1, 5, and 15 minutes."

uptime -p 2>/dev/null
# "uptime -p" prints a friendly sentence like "up 3 days, 2 hours"

uptime
# plain "uptime" also shows the load average at the end of the line

cores=$(nproc)
# nproc = number of CPU cores this machine has
echo "CPU cores available: $cores"

load1=$(cut -d' ' -f1 /proc/loadavg)
# /proc/loadavg is a special file the kernel keeps updated live.
# "cut -d' ' -f1" grabs just the first number (the 1-minute average).
echo "1-minute load: $load1"

# Compare load to core count using awk (a tool for working with numbers/text)
if awk "BEGIN{exit !($load1 > $cores)}"; then
    note "Load ($load1) is HIGHER than your core count ($cores)."
    note "This usually means the CPU is a bottleneck right now."
else
    note "Load is within your core count - CPU is coping fine."
fi


# =====================================================================
# SECTION 3: CPU USAGE
# =====================================================================
section "3. CPU USAGE"
note "This shows how busy the processor is RIGHT NOW, and which"
note "processes (programs) are using the most of it."
note "A process pegging the CPU with no clear reason is worth"
note "investigating - it could be a bug, or in rare cases, something"
note "malicious like cryptomining software."

echo "Sampling CPU usage over 1 second..."
read -r _ u1 n1 s1 i1 w1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 w2 _ < /proc/stat
# /proc/stat holds raw CPU time counters since boot. We read it twice,
# 1 second apart, and compare the difference - that tells us how busy
# the CPU was during that 1 second window.

idle1=$((i1 + w1)); idle2=$((i2 + w2))
total1=$((u1 + n1 + s1 + i1 + w1))
total2=$((u2 + n2 + s2 + i2 + w2))
dt=$((total2 - total1)); di=$((idle2 - idle1))
used=0
[ "$dt" -gt 0 ] && used=$(( (100 * (dt - di)) / dt ))

echo "CPU used: ${used}%"

echo ""
echo "Top 5 processes by CPU usage:"
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 6
# ps = "process status", lists running programs
# -eo pid,user,%cpu,%mem,comm = show these specific columns
# --sort=-%cpu = sort by CPU usage, highest first
# head -n 6 = only show the top 6 lines (1 header + top 5 processes)


# =====================================================================
# SECTION 4: MEMORY (RAM) USAGE
# =====================================================================
section "4. MEMORY USAGE"
note "RAM is short-term working memory. If it fills up, the system"
note "slows down or starts using 'swap' (disk pretending to be RAM,"
note "which is much slower)."
note "A process that keeps using more and more memory over time"
note "('a memory leak') is worth watching."

free -h
# free -h = show memory usage in human-readable units (MB/GB)

total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
used_pct=$(( 100 * (total - avail) / total ))
echo ""
echo "Memory used: ${used_pct}%"

echo ""
echo "Top 5 processes by memory usage:"
ps -eo pid,user,%cpu,%mem,comm --sort=-%mem | head -n 6


# =====================================================================
# SECTION 5: DISK USAGE
# =====================================================================
section "5. DISK USAGE"
note "This shows how full each disk/partition is."
note "A full disk can crash services, and a SUDDEN unexplained jump"
note "in usage can mean a log is flooding, or someone has placed"
note "files on your server that shouldn't be there."

df -h
# df -h = "disk free", human-readable sizes, shows all mounted filesystems

echo ""
echo "Largest folders inside /var (common place for logs to grow):"
du -xh /var --max-depth=1 2>/dev/null | sort -rh | head -n 6
# du = "disk usage", measures size of folders
# --max-depth=1 = only look one folder level deep (don't dig forever)
# sort -rh = sort by size, largest first, understanding "human" sizes like 1.2G


# =====================================================================
# SECTION 6: NETWORK
# =====================================================================
section "6. NETWORK"
note "This shows your network interfaces (connections to the network)"
note "and how much data has gone in (RX = received) and out (TX = transmitted)."

if have ip; then
    ip -brief address
    # ip -brief address = short summary of each network interface and its IP
else
    ifconfig
fi

echo ""
echo "Default route (where traffic goes if no specific rule matches):"
ip route show default 2>/dev/null


# =====================================================================
# SECTION 7: LISTENING PORTS
# =====================================================================
section "7. LISTENING PORTS"
note "A 'listening port' means a program on this machine is waiting"
note "for incoming connections on that port - like a web server"
note "waiting on port 80 or 443."
note "SECURITY TIP: if you see a port open that you didn't"
note "intentionally open, that's worth investigating immediately."

if have ss; then
    ss -tulnp 2>/dev/null
    # ss = "socket statistics", modern replacement for netstat
    # -t = TCP, -u = UDP, -l = listening only, -n = show numbers not
    # names, -p = show which process owns it (may need sudo to see this)
    note "If the process column is blank, try running this with sudo."
else
    note "'ss' isn't installed. Trying netstat instead."
    netstat -tulnp 2>/dev/null
fi


# =====================================================================
# SECTION 8: RUNNING PROCESSES OVERVIEW
# =====================================================================
section "8. PROCESS OVERVIEW"
note "This is a broader look at everything running on the system."
note "SECURITY TIP: a process running as 'root' that you don't"
note "recognize, or one with a strange/random-looking name, is"
note "worth looking up."

total_procs=$(ps -e --no-headers | wc -l)
zombies=$(ps -eo stat --no-headers | grep -c '^Z')
echo "Total running processes: $total_procs"
echo "Zombie processes: $zombies"
note "Zombies are finished processes not yet cleaned up by their"
note "parent. A few is normal; a large growing number can mean a"
note "buggy (or malicious) program is spawning things badly."


# =====================================================================
# SECTION 9: LOGGED-IN USERS
# =====================================================================
section "9. LOGGED-IN USERS"
note "This shows who is currently logged into this machine, and from where."
note "SECURITY TIP: a login from a location/time you don't recognize"
note "is one of the clearest signs something is wrong."

who
echo ""
w
# who = simple list of logged-in users
# w   = same, but also shows what they're currently doing


# =====================================================================
# SECTION 10: LOGIN HISTORY
# =====================================================================
section "10. RECENT LOGIN HISTORY"
note "This is a history of past logins - useful to confirm that"
note "ONLY expected people/IPs have been logging in."

last -n 5 2>/dev/null
# last = shows recent login history from system logs


# =====================================================================
# SECTION 11: FAILED LOGIN ATTEMPTS
# =====================================================================
section "11. FAILED LOGIN ATTEMPTS"
note "This is your early-warning system for brute-force attacks -"
note "someone repeatedly guessing usernames/passwords."
note "A LOT of failed attempts from one IP, especially followed by"
note "a successful login, is a serious red flag."

if have lastb; then
    lastb -n 10 2>/dev/null
    note "If this shows 'Permission denied', run the script with sudo."
else
    note "'lastb' not available on this system."
fi


# =====================================================================
# SECTION 12: FAILED SERVICES
# =====================================================================
section "12. FAILED SERVICES"
note "systemd (the service manager on most modern Linux systems)"
note "keeps track of any service that crashed or failed to start."

if have systemctl; then
    failed_count=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
    if [ "$failed_count" -eq 0 ]; then
        echo "No failed services. Good."
    else
        echo "$failed_count failed service(s):"
        systemctl --failed --no-pager
    fi
else
    note "systemctl not available on this system."
fi


# =====================================================================
# SECTION 13: RECENT SYSTEM ERRORS
# =====================================================================
section "13. RECENT SYSTEM LOG ERRORS"
note "This pulls recent 'error' level messages from the system log."
note "Worth skimming for anything related to authentication, disk,"
note "or services unexpectedly stopping."

if have journalctl; then
    journalctl -p err -n 15 --no-pager 2>/dev/null
    note "If this is empty, it may need sudo to read system logs."
else
    note "journalctl not available. Try checking /var/log/syslog manually."
fi


# =====================================================================
# WRAP UP
# =====================================================================
section "DONE"
note "That's a full pass over CPU, memory, disk, network, processes,"
note "users, logins, and logs - the core things to watch on any"
note "Linux server."
note "Next step for learning: pick ONE section above, and try running"
note "just that command by itself in your terminal to see it raw,"
note "without this script's formatting around it."
