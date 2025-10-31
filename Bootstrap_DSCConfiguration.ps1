<#
.SYNOPSIS
    Bootstrap script for Microsoft DSC 3.0 configuration deployment.

.DESCRIPTION
    This script automates the installation and configuration of a Windows 11 device using
    Microsoft Desired State Configuration 3.0. It can be run directly from a GitHub repository
    without needing to copy files locally first.
    
    The script performs the following tasks:
    1. Validates that DSC 3.0 is installed (installs if missing)
    2. Downloads the DSC configuration document from GitHub
    3. Executes the configuration to set the system to the desired state
    4. Provides detailed logging and progress feedback

.PARAMETER ConfigurationUrl
    The URL to the DSC configuration YAML file in your GitHub repository.
    Default: Points to the example configuration in this repository.

.PARAMETER Operation
    The DSC operation to perform: Test, Set, or Get
    - Test: Check if system is in desired state (read-only)
    - Set: Enforce the desired state (makes changes)
    - Get: Retrieve current state
    Default: Set

.PARAMETER LogPath
    Path where execution logs will be written.
    Default: C:\Windows\Temp\DSC-Bootstrap.log

.EXAMPLE
    # Run directly from GitHub (using Invoke-Expression)
    irm https://raw.githubusercontent.com/yourorg/yourrepo/main/Bootstrap-DSCConfiguration.ps1 | iex

.EXAMPLE
    # Run with custom configuration URL
    .\Bootstrap-DSCConfiguration.ps1 -ConfigurationUrl "https://raw.githubusercontent.com/yourorg/yourrepo/main/custom-config.dsc.yaml"

.EXAMPLE
    # Test configuration without making changes
    .\Bootstrap-DSCConfiguration.ps1 -Operation Test

.NOTES
    Author: IT Administrator
    Version: 1.0.0
    Requires: Windows 11, PowerShell 5.1 or later, Administrator privileges
    
    This script requires administrator privileges to install DSC and modify system settings.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigurationUrl = "https://raw.githubusercontent.com/yourorg/yourrepo/main/TimeZone-Config.dsc.yaml",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Test", "Set", "Get")]
    [string]$Operation = "Set",
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Windows\Temp\DSC-Bootstrap.log"
)

#Requires -RunAsAdministrator

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to both the console and log file with timestamp.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Color coding for console output
    $color = switch ($Level) {
        "Info"    { "Cyan" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
        "Success" { "Green" }
        default   { "White" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
    
    # Ensure log directory exists
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $logMessage
}

function Write-SectionHeader {
    <#
    .SYNOPSIS
        Writes a formatted section header to logs.
    #>
    param([string]$Title)
    
    $separator = "=" * 80
    Write-Log -Message $separator -Level Info
    Write-Log -Message $Title -Level Info
    Write-Log -Message $separator -Level Info
}

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

try {
    Write-SectionHeader -Title "DSC 3.0 Bootstrap Script Started"
    Write-Log -Message "Script Version: 1.0.0" -Level Info
    Write-Log -Message "Configuration URL: $ConfigurationUrl" -Level Info
    Write-Log -Message "Operation: $Operation" -Level Info
    Write-Log -Message "Log Path: $LogPath" -Level Info
    
    # ========================================================================
    # STEP 1: Validate Administrator Privileges
    # ========================================================================
    Write-SectionHeader -Title "STEP 1: Validating Administrator Privileges"
    
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Log -Message "ERROR: This script requires administrator privileges!" -Level Error
        Write-Log -Message "Please run PowerShell as Administrator and try again." -Level Error
        throw "Administrator privileges required"
    }
    
    Write-Log -Message "Administrator privileges confirmed" -Level Success
    
    # ========================================================================
    # STEP 2: Check DSC 3.0 Installation
    # ========================================================================
    Write-SectionHeader -Title "STEP 2: Checking DSC 3.0 Installation"
    
    $dscCommand = Get-Command -Name "dsc" -ErrorAction SilentlyContinue
    
    if ($null -eq $dscCommand) {
        Write-Log -Message "DSC 3.0 not found. Attempting to install via WinGet..." -Level Warning
        
        # Check if WinGet is available
        $wingetCommand = Get-Command -Name "winget" -ErrorAction SilentlyContinue
        
        if ($null -eq $wingetCommand) {
            Write-Log -Message "ERROR: WinGet is not available on this system!" -Level Error
            Write-Log -Message "Please install WinGet or manually install DSC from: https://github.com/PowerShell/DSC/releases/latest" -Level Error
            throw "WinGet not available"
        }
        
        Write-Log -Message "Installing DSC 3.0 from Microsoft Store..." -Level Info
        
        # Install DSC using WinGet
        $installResult = winget install --id 9NVTPZWRC6KQ --source msstore --accept-package-agreements --accept-source-agreements 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "ERROR: Failed to install DSC 3.0!" -Level Error
            Write-Log -Message "Install output: $installResult" -Level Error
            throw "DSC installation failed"
        }
        
        Write-Log -Message "DSC 3.0 installed successfully" -Level Success
        Write-Log -Message "Refreshing environment variables..." -Level Info
        
        # Refresh PATH environment variable
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Verify installation
        $dscCommand = Get-Command -Name "dsc" -ErrorAction SilentlyContinue
        
        if ($null -eq $dscCommand) {
            Write-Log -Message "ERROR: DSC command not found after installation!" -Level Error
            Write-Log -Message "You may need to restart your PowerShell session or computer." -Level Error
            throw "DSC command not available after installation"
        }
    }
    
    # Get and display DSC version
    $dscVersion = & dsc --version 2>&1
    Write-Log -Message "DSC 3.0 is installed. Version: $dscVersion" -Level Success
    
    # ========================================================================
    # STEP 3: Install Required PowerShell Modules
    # ========================================================================
    Write-SectionHeader -Title "STEP 3: Checking Required PowerShell Modules"
    
    Write-Log -Message "Checking for ComputerManagementDsc module..." -Level Info
    
    $module = Get-Module -ListAvailable -Name "ComputerManagementDsc"
    
    if ($null -eq $module) {
        Write-Log -Message "ComputerManagementDsc module not found. Installing..." -Level Warning
        
        # Install NuGet provider if needed
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if ($null -eq $nugetProvider) {
            Write-Log -Message "Installing NuGet package provider..." -Level Info
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        }
        
        # Set PSGallery as trusted
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($psGallery.InstallationPolicy -ne "Trusted") {
            Write-Log -Message "Setting PSGallery as trusted repository..." -Level Info
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        
        # Install the module
        Write-Log -Message "Installing ComputerManagementDsc module from PowerShell Gallery..." -Level Info
        Install-Module -Name ComputerManagementDsc -Scope AllUsers -Force -AllowClobber
        
        Write-Log -Message "ComputerManagementDsc module installed successfully" -Level Success
    } else {
        Write-Log -Message "ComputerManagementDsc module is already installed (Version: $($module.Version))" -Level Success
    }
    
    # ========================================================================
    # STEP 4: Download Configuration Document
    # ========================================================================
    Write-SectionHeader -Title "STEP 4: Downloading DSC Configuration Document"
    
    $tempConfigPath = Join-Path -Path $env:TEMP -ChildPath "dsc-config-$(Get-Date -Format 'yyyyMMdd-HHmmss').yaml"
    
    Write-Log -Message "Downloading configuration from: $ConfigurationUrl" -Level Info
    Write-Log -Message "Temporary file: $tempConfigPath" -Level Info
    
    try {
        $ProgressPreference = 'SilentlyContinue'  # Suppress progress bar for faster download
        Invoke-WebRequest -Uri $ConfigurationUrl -OutFile $tempConfigPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        Write-Log -Message "Configuration document downloaded successfully" -Level Success
        
        # Display configuration content for verification
        Write-Log -Message "Configuration content:" -Level Info
        $configContent = Get-Content -Path $tempConfigPath -Raw
        Write-Log -Message $configContent -Level Info
        
    } catch {
        Write-Log -Message "ERROR: Failed to download configuration document!" -Level Error
        Write-Log -Message "Error: $($_.Exception.Message)" -Level Error
        throw
    }
    
    # ========================================================================
    # STEP 5: Execute DSC Configuration
    # ========================================================================
    Write-SectionHeader -Title "STEP 5: Executing DSC Configuration ($Operation)"
    
    Write-Log -Message "Preparing to execute DSC $Operation operation..." -Level Info
    
    # Build the DSC command
    $dscOperation = $Operation.ToLower()
    $dscCommand = "dsc config $dscOperation --file `"$tempConfigPath`" --output-format pretty-json"
    
    Write-Log -Message "Executing command: $dscCommand" -Level Info
    
    # Execute DSC configuration
    $startTime = Get-Date
    Write-Log -Message "Operation started at: $startTime" -Level Info
    
    try {
        # Execute and capture output
        $dscOutput = & cmd /c "dsc config $dscOperation --file `"$tempConfigPath`" --output-format pretty-json 2>&1"
        $exitCode = $LASTEXITCODE
        
        $endTime = Get-Date
        $duration = $endTime - $startTime
        
        Write-Log -Message "Operation completed in: $($duration.TotalSeconds) seconds" -Level Info
        
        # Parse and display results
        if ($exitCode -eq 0) {
            Write-Log -Message "DSC operation completed successfully!" -Level Success
            Write-Log -Message "Raw Output:" -Level Info
            Write-Log -Message ($dscOutput -join "`n") -Level Info
            
            # Try to parse JSON output for better reporting
            try {
                $result = $dscOutput -join "`n" | ConvertFrom-Json
                
                Write-SectionHeader -Title "OPERATION RESULTS"
                
                # Display metadata
                if ($result.metadata -and $result.metadata.'Microsoft.DSC') {
                    $meta = $result.metadata.'Microsoft.DSC'
                    Write-Log -Message "DSC Version: $($meta.version)" -Level Info
                    Write-Log -Message "Operation: $($meta.operation)" -Level Info
                    Write-Log -Message "Duration: $($meta.duration)" -Level Info
                    Write-Log -Message "Security Context: $($meta.securityContext)" -Level Info
                }
                
                # Display results for each resource
                if ($result.results) {
                    foreach ($resourceResult in $result.results) {
                        Write-Log -Message "`nResource: $($resourceResult.name)" -Level Info
                        Write-Log -Message "Type: $($resourceResult.type)" -Level Info
                        
                        if ($resourceResult.result) {
                            switch ($Operation) {
                                "Test" {
                                    $inDesiredState = $resourceResult.result.inDesiredState
                                    if ($inDesiredState) {
                                        Write-Log -Message "Status: In desired state" -Level Success
                                    } else {
                                        Write-Log -Message "Status: NOT in desired state" -Level Warning
                                        if ($resourceResult.result.differingProperties) {
                                            Write-Log -Message "Differing Properties: $($resourceResult.result.differingProperties -join ', ')" -Level Warning
                                        }
                                    }
                                }
                                "Set" {
                                    Write-Log -Message "Before State: $($resourceResult.result.beforeState | ConvertTo-Json -Compress)" -Level Info
                                    Write-Log -Message "After State: $($resourceResult.result.afterState | ConvertTo-Json -Compress)" -Level Info
                                    if ($resourceResult.result.changedProperties) {
                                        Write-Log -Message "Changed Properties: $($resourceResult.result.changedProperties -join ', ')" -Level Success
                                    }
                                }
                                "Get" {
                                    Write-Log -Message "Actual State: $($resourceResult.result.actualState | ConvertTo-Json -Compress)" -Level Info
                                }
                            }
                        }
                        
                        # Display any messages
                        if ($resourceResult.messages -and $resourceResult.messages.Count -gt 0) {
                            Write-Log -Message "Messages:" -Level Info
                            foreach ($msg in $resourceResult.messages) {
                                Write-Log -Message "  - $msg" -Level Info
                            }
                        }
                    }
                }
                
            } catch {
                Write-Log -Message "Could not parse JSON output (this may be normal for some outputs)" -Level Warning
            }
            
        } else {
            Write-Log -Message "ERROR: DSC operation failed with exit code: $exitCode" -Level Error
            Write-Log -Message "Output: $($dscOutput -join "`n")" -Level Error
            throw "DSC operation failed"
        }
        
    } catch {
        Write-Log -Message "ERROR: Exception during DSC execution!" -Level Error
        Write-Log -Message "Error: $($_.Exception.Message)" -Level Error
        throw
    }
    
    # ========================================================================
    # STEP 6: Cleanup
    # ========================================================================
    Write-SectionHeader -Title "STEP 6: Cleanup"
    
    Write-Log -Message "Removing temporary configuration file..." -Level Info
    Remove-Item -Path $tempConfigPath -Force -ErrorAction SilentlyContinue
    Write-Log -Message "Cleanup completed" -Level Success
    
    # ========================================================================
    # COMPLETION
    # ========================================================================
    Write-SectionHeader -Title "BOOTSTRAP SCRIPT COMPLETED SUCCESSFULLY"
    
    Write-Log -Message "All operations completed successfully!" -Level Success
    Write-Log -Message "Log file location: $LogPath" -Level Info
    
    if ($Operation -eq "Test") {
        Write-Log -Message "`nTIP: Run with -Operation Set to apply the configuration" -Level Info
    }
    
    exit 0
    
} catch {
    Write-Log -Message "`n!!! FATAL ERROR !!!" -Level Error
    Write-Log -Message "Script execution failed: $($_.Exception.Message)" -Level Error
    Write-Log -Message "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Write-Log -Message "`nLog file location: $LogPath" -Level Error
    
    exit 1
}
