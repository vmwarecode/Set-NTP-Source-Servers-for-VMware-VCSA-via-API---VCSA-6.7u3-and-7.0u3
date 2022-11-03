Function Set-VcsaNtpSource {
    <#
    .SYNOPSIS
        Set NTP Source Servers for VMware VCSA
    .DESCRIPTION
        Example is using NIST NTP source IPs. These are not for production use.
    .EXAMPLE
        Set-VcsaNtpSource -vcenter 'vcenter.fqdn.com'
        Set-VcsaNtpSource -vcenter 'vcenter.fqdn.com' -ntpSource "129.6.15.28","129.6.15.29"
    #>

    param(
          [Parameter(Mandatory = $true)][string]$vcenter,
          [parameter(Mandatory = $false)]$ntpSource,
          [Parameter(Mandatory = $true)][string]$vc_user,
          [Parameter(Mandatory = $true)][secureString]$vc_pass
    )

    # Auth and NTP variables
    $ErrorActionPreference = "Stop"
    if (!$vcenter) { $vcenter = Read-Host  "Please enter vCenter name" }
    if (!$vc_user) { $vc_user = Read-Host  "Please enter an administrator username (administrator@vsphere.local)" }
    if (!$vc_pass) { $vc_pass = Read-Host  | ConvertFrom-SecureString -AsPlainText -Force "Please enter the administrator password" }
    # REI NTP Source Servers
    if (!$ntpSource) { $ntpSource = '"129.6.15.28","129.6.15.29"' }
    
    # Connect to vCenter Server
    $BaseUrl = "https://" + $vcenter + "/"
    $AuthUrl = $BaseUrl + "api/session"
    $NtpUrl = $BaseUrl + "api/appliance/ntp"

    # Create API Auth Session
    $auth = $vc_user + ':' + ($vc_pass | ConvertFrom-SecureString -AsPlainText)
    $Encoded = [System.Text.Encoding]::UTF8.GetBytes($auth)
    $authorizationInfo = [System.Convert]::ToBase64String($Encoded)
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Basic $($authorizationInfo)")

    # Get API Session ID
    $apiSessionId = Invoke-WebRequest $AuthUrl -Method 'POST' -Headers $headers -SkipCertificateCheck
    $sessionId = $apiSessionId.Content | ConvertFrom-Json

    #Test for VCSA 6.7.* or VCSA 7.0.* API and get API Session ID
    if ($null -eq $sessionId) {
        Write-Host "VCSA API Version is 6.7..."
        $AuthUrl = $BaseUrl + "rest/com/vmware/cis/session"
        $headers.Add("vmware-use-header-authn", "Basic $($authorizationInfo)")
        $headers.Add("Content-Type", "application/json")
        $apiSessionId = Invoke-WebRequest $AuthUrl -Method 'POST' -Headers $headers -SkipCertificateCheck
        $sessionId = $apiSessionId.Content | ConvertFrom-Json

        # Return NTP Information
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers = @{
            'vmware-api-session-id' = $sessionId.value
        }

        $NtpUrl = $BaseUrl + "rest/appliance/ntp"
        $NtpInfo = Invoke-WebRequest $NtpUrl -Method 'GET' -Headers $headers -SkipCertificateCheck

        $current_ntpSources = ($NtpInfo.Content | ConvertFrom-Json).value
        $curSources = [string]::Join('|',$current_ntpSources)
        $ntpSources = [string]::Join('|',$ntpSource)

        if ($ntpSources -notin $curSources) {
            Write-host "The NTP Source(s) for $vcenter is different than the standard." -ForegroundColor Yellow

            Write-Host "Updating NTP Source on $vcenter..." -Foreground Cyan -NoNewline

            $ntpSourceBody = "{`n    `"servers`": [ $ntpSources ]`n}"
            
            $headers.Add("Content-Type", "application/json")
            $ntpSourceSet = Invoke-WebRequest $NtpUrl -Method 'PUT' -Headers $headers -Body $ntpSourceBody -SkipCertificateCheck

            if ($null -eq $ntpSourceSet ){
                Write-Host "Please check configurations for this module. No payload was sent to be modified."
            }
            elseif ($ntpSourceSet.StatusDescription -eq 'OK') {
                Write-Host "NTP Source(s) has been correctly updated to $ntpSource." -ForegroundColor DarkGreen
            }
        }
        else { Write-host "VCSA NTP Source is correctly configured!" -ForegroundColor "Green" }

        # Close API Session ID
        $apiSessionClose = Invoke-WebRequest $AuthUrl -Method 'DELETE' -Headers $headers -SkipCertificateCheck

        if ($apiSessionClose.StatusCode -ne 200) {
            Write-Host "Unable to terminate API session and release token. Please terminate your session manually by closing this terminal." -ForegroundColor DarkYellow
        }
        else {
            Write-Host "You are now logged out of the VCSA API for " -ForegroundColor DarkGreen -NoNewline
            Write-Host "$vcenter." -ForegroundColor DarkYellow  -NoNewline
            Write-Host " Your access token has been released and is no longer valid." -ForegroundColor DarkGreen
        }
    }
    else {
        Write-Host "VCSA API Version is 7.0..."
        $NtpUrl = $BaseUrl + "api/appliance/ntp"
        # Return NTP Information
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("vmware-api-session-id", $sessionId)

        $NtpInfo = Invoke-WebRequest $NtpUrl -Method 'GET' -Headers $headers -SkipCertificateCheck
        $current_ntpSources = $NtpInfo.Content | ConvertFrom-Json
        $curSources = [string]::Join('|',$current_ntpSources)
        $ntpSources = [string]::Join('|',$ntpSource)

        if ($ntpSources -notin $curSources) {
            Write-host "The NTP Source(s) for $vcenter is different than the standard." -ForegroundColor Yellow

            Write-Host "Updating NTP Source on $vcenter..." -Foreground Cyan -NoNewline

            $ntpSourceBody = "{`n    `"servers`": [ $ntpSources ]`n}"
            
            $headers.Add("Content-Type", "application/json")
            $ntpSourceSet = Invoke-WebRequest $NtpUrl -Method 'PUT' -Headers $headers -SkipCertificateCheck -Body $ntpSourceBody
            
            if ($ntpSourceSet.StatusCode -eq "204"){
                Write-Host "NTP Source(s) has been correctly updated to $ntpSource." -ForegroundColor DarkGreen
            }else{
                Write-Host "NTP Source(s) have not been updated." -ForegroundColor Red
                Write-Host $ntpSourceSet.Content -ForegroundColor Red
            }
        }
        else { Write-host "VCSA NTP Source is correctly configured!" -ForegroundColor "Green" }

        # Close API Session ID
        $apiSessionClose = Invoke-WebRequest $AuthUrl -Method 'DELETE' -Headers $headers -SkipCertificateCheck

        if ($apiSessionClose.StatusCode -ne '204') {
            Write-Host "Unable to terminate API session and release token. Please terminate your session manually by closing this terminal." -ForegroundColor DarkYellow
        }
        else {
            Write-Host "You are now logged out of the VCSA API for " -ForegroundColor DarkGreen -NoNewline
            Write-Host "$vcenter." -ForegroundColor DarkYellow  -NoNewline
            Write-Host " Your access token has been released and is no longer valid." -ForegroundColor DarkGreen
        }
    }
}