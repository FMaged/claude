#Requires -Version 5.1
# Generalizes the image. Always the last provisioner: nothing may change the image after it.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Setup kept a copy of the build's answer file in Panther. A clone's Setup reads Panther
# before the seed ISO, so a copy left here makes every clone ignore its seed.
$answerFiles = 'unattend.xml', 'autounattend.xml' | ForEach-Object { Join-Path -Path "$env:SystemRoot\Panther" -ChildPath $_ }
$removeAnswerFiles = {
    foreach ($file in $answerFiles) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
    }
}
& $removeAnswerFiles

# /mode:vm because the image only boots as a Hyper-V generation 2 VM. No /unattend:,
# which would cache another answer file in Panther. /quit, not /shutdown, so a failure
# fails this provisioner instead of leaving a VM that never stops.
$sysprep = Start-Process -FilePath "$env:SystemRoot\System32\Sysprep\sysprep.exe" `
    -ArgumentList '/generalize', '/oobe', '/quiet', '/quit', '/mode:vm' -Wait -PassThru

$stateKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State'
$deadline = (Get-Date).AddMinutes(30)
while ((Get-ItemProperty -Path $stateKey).ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
    if ((Get-Date) -gt $deadline) {
        $log = "$env:SystemRoot\System32\Sysprep\Panther\setuperr.log"
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 30 }
        throw "sysprep did not generalize the image within 30 minutes (exit code $($sysprep.ExitCode))"
    }
    Start-Sleep -Seconds 10
}

& $removeAnswerFiles
