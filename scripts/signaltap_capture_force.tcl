# Variant of signaltap_capture.tcl that:
#   - sets the trigger position to "post" so it captures into a circular
#     buffer until force-stopped,
#   - issues a force_trigger after a short delay so we always get a CSV
#     even when the configured trigger condition does not fire on hardware.
#
# Usage:
#   quartus_stp -t scripts/signaltap_capture_force.tcl <stp_file> <out_csv> [delay_s] [instance] [signal_set] [trigger]

if {$argc < 2} {
    puts "usage: signaltap_capture_force.tcl <stp_file> <out_csv> [delay_s] [instance] [signal_set] [trigger]"
    exit 2
}

set stp_file   [lindex $argv 0]
set out_csv    [lindex $argv 1]
set delay_s    5
set instance   "auto_signaltap_0"
set signal_set ""
set trigger    ""

if {$argc >= 3} { set delay_s    [lindex $argv 2] }
if {$argc >= 4} { set instance   [lindex $argv 3] }
if {$argc >= 5} { set signal_set [lindex $argv 4] }
if {$argc >= 6} { set trigger    [lindex $argv 5] }

if {$signal_set eq "" || $trigger eq ""} {
    set fh [open $stp_file r]
    set stp_text [read $fh]
    close $fh
    if {$signal_set eq ""} {
        if {[regexp {<signal_set[^>]*name="([^"]+)"} $stp_text -> parsed_signal_set]} {
            set signal_set $parsed_signal_set
        } else {
            puts "ERROR: could not auto-detect signal_set name from $stp_file"
            exit 2
        }
    }
    if {$trigger eq ""} {
        if {[regexp {<trigger[[:space:]][^>]*name="(trigger:[^"]+)"} $stp_text -> parsed_trigger]} {
            set trigger $parsed_trigger
        } else {
            puts "ERROR: could not auto-detect trigger name from $stp_file"
            exit 2
        }
    }
}

set out_dir [file dirname $out_csv]
if {$out_dir ne "." && ![file exists $out_dir]} {
    file mkdir $out_dir
}

set data_log "cli_log"

puts "SignalTap CLI capture (force-trigger variant)"
puts "  stp_file   = $stp_file"
puts "  out_csv    = $out_csv"
puts "  delay_s    = $delay_s"
puts "  instance   = $instance"
puts "  signal_set = $signal_set"
puts "  trigger    = $trigger"

open_session -name $stp_file

# Run in background while we sleep then force-trigger.
# quartus_stp does not have a true async run; instead we use run -timeout
# with a short delay and then export whatever buffered samples exist.
set rc [catch {
    run -instance $instance -signal_set $signal_set -trigger $trigger \
        -data_log $data_log -timeout $delay_s -force_trigger
} result]
puts "run result: rc=$rc msg=$result"

set export_rc [catch {
    export_data_log -instance $instance -signal_set $signal_set -trigger $trigger \
        -data_log $data_log -filename $out_csv -format csv
} export_result]
puts "export result: rc=$export_rc msg=$export_result"

close_session
exit 0
