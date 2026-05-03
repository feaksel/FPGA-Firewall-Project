# Run one SignalTap acquisition and export it to CSV.
#
# Usage:
#   quartus_stp.exe -t scripts/signaltap_capture.tcl <stp_file> <out_csv> [timeout] [instance] [signal_set] [trigger]
#
# Example:
#   quartus_stp.exe -t scripts/signaltap_capture.tcl quartus/de1_soc_w5500.stp captures/stp/latest.csv 20 auto_signaltap_0 signal_set_1 trigger_1

if {$argc < 2} {
    puts "usage: signaltap_capture.tcl <stp_file> <out_csv> [timeout] [instance] [signal_set] [trigger]"
    exit 2
}

set stp_file   [lindex $argv 0]
set out_csv    [lindex $argv 1]
set timeout_s  20
set instance   "auto_signaltap_0"
set signal_set ""
set trigger    ""

if {$argc >= 3} { set timeout_s  [lindex $argv 2] }
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

puts "SignalTap CLI capture"
puts "  stp_file   = $stp_file"
puts "  out_csv    = $out_csv"
puts "  timeout_s  = $timeout_s"
puts "  instance   = $instance"
puts "  signal_set = $signal_set"
puts "  trigger    = $trigger"

open_session -name $stp_file

set run_rc [catch {
    run -instance $instance -signal_set $signal_set -trigger $trigger -data_log $data_log -timeout $timeout_s
} run_result]
puts $run_result

if {$run_rc == 0} {
    set export_rc [catch {
        export_data_log -instance $instance -signal_set $signal_set -trigger $trigger -data_log $data_log -filename $out_csv -format csv
    } export_result]
    puts $export_result
    close_session
    exit $export_rc
} else {
    close_session
    exit $run_rc
}
