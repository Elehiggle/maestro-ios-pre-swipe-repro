# Usage: awk -f measure.awk CLI_LOG NATIVE_LOG
# CLI timestamps must be UTC. Native syslog timestamps carry their own offset;
# compact timestamps without an offset are accepted only as already-UTC input.
function seconds(value, parts) {
    split(value, parts, ":")
    return parts[1] * 3600 + parts[2] * 60 + parts[3]
}
function day_number(value, parts, year, month) {
    split(value, parts, "-")
    year = parts[1]
    month = parts[2]
    if (month <= 2) { year--; month += 12 }
    return int(365.25 * year) - int(year / 100) + int(year / 400) + int(30.6001 * (month + 1)) + parts[3]
}
function clock_text(value, hours, minutes) {
    hours = int(value / 3600)
    minutes = int((value - hours * 3600) / 60)
    return sprintf("%02d:%02d:%06.3f", hours, minutes, value - hours * 3600 - minutes * 60)
}
FNR == NR {
    if ($1 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+$/ && /: Swipe .* RUNNING$/) {
        starts++
        start = seconds($1)
        start_text = $1
        start_line = FNR
    }
    next
}
/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / {
    if ($2 !~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+([+-][0-9][0-9][0-9][0-9])?$/) {
        invalid_timestamp = 1
        next
    }
    time = seconds($2)
    utc_day = day_number($1)
    if ($2 ~ /[+-][0-9][0-9][0-9][0-9]$/) {
        offset = substr($2, length($2) - 4)
        offset_seconds = substr(offset, 2, 2) * 3600 + substr(offset, 4, 2) * 60
        time -= (substr(offset, 1, 1) == "+" ? 1 : -1) * offset_seconds
    }
    if (time < 0) { time += 86400; utc_day-- }
    if (time >= 86400) { time -= 86400; utc_day++ }
    if (date_seen != "" && utc_day != date_seen) crossed_midnight = 1
    date_seen = utc_day
    if (/request: POST \/swipeV2$/) {
        swipes++
        if (swipes == 1) {
            dispatch = time
            dispatch_text = clock_text(time)
            dispatch_line = FNR
        }
    }
    if (time >= start && swipes == 0) {
        if (/request: POST \/viewHierarchy$/) hierarchies++
        if (/request: GET \/isScreenStatic$/) static_checks++
    }
}
END {
    if (starts != 1 || swipes != 1 || crossed_midnight || invalid_timestamp || dispatch < start) {
        printf "No measurement: CLI starts=%d native swipes=%d UTC midnight=%d invalid timestamp=%d; inspect the paired logs and clocks.\n", starts, swipes, crossed_midnight, invalid_timestamp > "/dev/stderr"
        exit 1
    }
    print "cli_start_utc\tcli_line\tnative_receipt_utc\tnative_line\tpre_dispatch_seconds\thierarchy_requests\tscreen_static_requests"
    printf "%s\t%d\t%s\t%d\t%.3f\t%d\t%d\n", start_text, start_line, dispatch_text, dispatch_line, dispatch - start, hierarchies, static_checks
}
