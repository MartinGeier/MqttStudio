# Creates the MSIX package like "dart run msix:create", plus the command line alias "mqttstudio" (doc/cli-design.md).
# msix_config in pubspec.yaml can only alias the main executable, the GUI. The alias of the console launcher
# mqttstudio-cli.exe needs a second, hidden application in the manifest, which is added between msix:build and
# msix:pack. The launcher is a console program itself, so the alias needs no desktop4:Subsystem (that attribute is for
# UWP console apps and makes makeappx reject the manifest).
# Run from src/mqttstudio_client: powershell -ExecutionPolicy Bypass -File windows\packaging\create_msix.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

dart run msix:build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$manifestPath = 'build\windows\x64\runner\Release\AppxManifest.xml'
$manifest = Get-Content $manifestPath -Raw

if ($manifest -notmatch 'Id="mqttstudiocli"') {
  $application = @'
      <Application Id="mqttstudiocli" Executable="mqttstudio-cli.exe" EntryPoint="Windows.FullTrustApplication">
        <uap:VisualElements AppListEntry="none" BackgroundColor="transparent" DisplayName="MQTT Studio CLI"
          Square150x150Logo="Images\Square150x150Logo.png" Square44x44Logo="Images\Square44x44Logo.png"
          Description="Runs MQTT Studio from the command line" />
        <Extensions>
          <uap5:Extension Category="windows.appExecutionAlias" Executable="mqttstudio-cli.exe" EntryPoint="Windows.FullTrustApplication">
            <uap5:AppExecutionAlias>
              <uap5:ExecutionAlias Alias="mqttstudio.exe" />
            </uap5:AppExecutionAlias>
          </uap5:Extension>
        </Extensions>
      </Application>
'@
  $manifest = $manifest.Replace('</Applications>', $application + '    </Applications>')
  $manifest = $manifest.Replace('xmlns:uap6=', 'xmlns:uap5="http://schemas.microsoft.com/appx/manifest/uap/windows10/5" xmlns:uap6=')
  $manifest = $manifest.Replace('IgnorableNamespaces="uap3 desktop"', 'IgnorableNamespaces="uap3 uap5 desktop"')
  [System.IO.File]::WriteAllText((Resolve-Path $manifestPath), $manifest, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host 'added the command line alias mqttstudio to the manifest'
}

dart run msix:pack
exit $LASTEXITCODE
