param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Command
)

if ($Command[0] -eq 'devices') {
    'List of devices attached'
    "emulator-5554`tdevice"
    exit 0
}

if ($Command.Count -ge 5 -and $Command[0] -eq '-s' -and $Command[2] -eq 'emu' -and $Command[3] -eq 'avd' -and $Command[4] -eq 'name') {
    "Root_GMS_API_36`r"
    "OK`r"
    exit 0
}

exit 1
