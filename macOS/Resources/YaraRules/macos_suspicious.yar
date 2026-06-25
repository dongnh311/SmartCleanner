/*
 * Generic macOS heuristics. These are intentionally broad — a match is a
 * REVIEW signal (shown for inspection), not an automatic quarantine, so the
 * occasional benign script that trips one of them does no harm. Drop your own
 * .yar / .yara files into  ~/Library/Application Support/MacCleaner/YaraRules
 * to extend coverage.
 */

rule Shell_Download_And_Execute
{
    meta:
        description = "Pipes a remote download straight into a shell"
    strings:
        $dl1 = "curl "
        $dl2 = "wget "
        $sh1 = "| sh"
        $sh2 = "| bash"
        $sh3 = "|sh"
        $sh4 = "|bash"
        $sh5 = "| /bin/sh"
    condition:
        (any of ($dl*)) and (any of ($sh*))
}

rule Osascript_Abuse
{
    meta:
        description = "AppleScript shelling out or fetching remote content"
    strings:
        $o = "osascript"
        $do = "do shell script"
        $dl1 = "curl "
        $dl2 = "wget "
    condition:
        $o and ($do or any of ($dl*))
}

rule Base64_Decoded_To_Interpreter
{
    meta:
        description = "base64-decoded payload piped into an interpreter"
    strings:
        $b1 = "base64 -d"
        $b2 = "base64 --decode"
        $b3 = "openssl enc -d"
        $i1 = "| python"
        $i2 = "| /bin/sh"
        $i3 = "| sh"
        $i4 = "| bash"
        $i5 = "eval("
    condition:
        (any of ($b*)) and (any of ($i*))
}

rule LaunchItem_AutoRun_From_Temp
{
    meta:
        description = "plist auto-runs a program from a temp/hidden path"
    strings:
        $run = "RunAtLoad"
        $args = "ProgramArguments"
        $t1 = "/tmp/"
        $t2 = "/private/tmp/"
        $t3 = "/var/tmp/"
        $t4 = "/Users/Shared/."
    condition:
        $run and $args and (any of ($t*))
}

rule Persistence_Curl_In_Plist
{
    meta:
        description = "LaunchAgent/Daemon plist that fetches & runs code"
    strings:
        $args = "ProgramArguments"
        $c1 = "curl "
        $c2 = "wget "
        $c3 = "nscurl"
    condition:
        $args and (any of ($c*))
}
