<#
.SYNOPSIS
    Bootstrap script for Microsoft DSC 3.0 configuration deployment.

.DESCRIPTION
    This script automates the installation and configuration of a Windows 11 device using
    Microsoft Desired State Configuration 3.0. It can be run directly from a GitHub repository
    without needing to copy files locally first.
    
    The script performs the following tasks:
    1. Validates that DSC 3.0 is installed (installs if missing)
    2. Installs PowerShell Core (pwsh) if not present
    3. Configures WinRM (required for PowerShell DSC resources)
    4. Downloads the DSC configuration document from GitHub
    5. Executes the configuration to set the system to the desired state
    6. Provides detailed logging and progress feedback

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
    irm https://raw.githubusercontent.com/mlamia-usa/win11-dsc3-config/main/bootstrap-dsc3-configuration.ps1 | iex

.EXAMPLE
    # Run with custom configuration URL
    .\Bootstrap-DSCConfiguration.ps1 -ConfigurationUrl "https://raw.githubusercontent.com/mlamia-usa/win11-dsc3-config/main/custom-config.dsc.yaml"

.EXAMPLE
    # Test configuration without making changes
    .\Bootstrap-DSCConfiguration.ps1 -Operation Test

.NOTES
    Author: IT Administrator
    Version: 1.2.0
    Requires: Windows 11, PowerShell 5.1 or later, Administrator privileges
    
    This script requires administrator privileges to install DSC and modify system settings.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigurationUrl = "https://raw.githubusercontent.com/mlamia-usa/win11-dsc3-config/main/timezone-config.dsc.yaml",
    
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
    Write-Log -Message "Script Version: 1.2.0" -Level Info
    Write-Log -Message "Configuration URL: $ConfigurationUrl" -Level Info
    Write-Log -Message "Operation: $Operation" -Level Info
    Write-Log -Message "Log Path: $LogPath" -Level Info
    
    # ========================================================================
    # INITIAL SETUP: Configure TLS and Security Protocols
    # ========================================================================
    Write-Log -Message "Configuring security protocols for PowerShell Gallery access..." -Level Info
    try {
        # Enable TLS 1.2 (required for PowerShell Gallery)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Log -Message "TLS 1.2 enabled for secure connections" -Level Success
    } catch {
        Write-Log -Message "WARNING: Could not configure TLS settings: $($_.Exception.Message)" -Level Warning
    }
    
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
    # STEP 2: Check and Install PowerShell Core (pwsh)
    # ========================================================================
    Write-SectionHeader -Title "STEP 2: Checking PowerShell Core Installation"
    
    Write-Log -Message "PowerShell Core (pwsh) is required for DSC 3.0 compatibility" -Level Info
    
    $pwshCommand = Get-Command -Name "pwsh" -ErrorAction SilentlyContinue
    
    if ($null -eq $pwshCommand) {
        Write-Log -Message "PowerShell Core not found. Attempting to install via WinGet..." -Level Warning
        
        # Check if WinGet is available
        $wingetCommand = Get-Command -Name "winget" -ErrorAction SilentlyContinue
        
        if ($null -eq $wingetCommand) {
            Write-Log -Message "ERROR: WinGet is not available on this system!" -Level Error
            Write-Log -Message "Please install WinGet from: https://aka.ms/getwinget" -Level Error
            Write-Log -Message "Or manually install PowerShell from: https://aka.ms/powershell-release" -Level Error
            throw "WinGet not available"
        }
        
        Write-Log -Message "Installing PowerShell Core from Microsoft Store..." -Level Info
        
        # Install PowerShell using WinGet
        # Using the Microsoft.PowerShell package ID
        $installResult = winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "WARNING: WinGet install may have encountered issues (exit code: $LASTEXITCODE)" -Level Warning
            Write-Log -Message "Install output: $($installResult -join "`n")" -Level Warning
            Write-Log -Message "Checking if PowerShell Core was installed anyway..." -Level Info
        } else {
            Write-Log -Message "PowerShell Core installation completed" -Level Success
        }
        
        Write-Log -Message "Refreshing environment variables..." -Level Info
        
        # Refresh PATH environment variable
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Verify installation
        $pwshCommand = Get-Command -Name "pwsh" -ErrorAction SilentlyContinue
        
        if ($null -eq $pwshCommand) {
            Write-Log -Message "ERROR: PowerShell Core (pwsh) command not found after installation!" -Level Error
            Write-Log -Message "You may need to:" -Level Error
            Write-Log -Message "  1. Restart your PowerShell session" -Level Error
            Write-Log -Message "  2. Manually install from: https://aka.ms/powershell-release" -Level Error
            Write-Log -Message "  3. Ensure 'pwsh' is in your PATH" -Level Error
            throw "PowerShell Core command not available after installation"
        }
        
        Write-Log -Message "PowerShell Core is now available" -Level Success
    } else {
        Write-Log -Message "PowerShell Core is already installed: $($pwshCommand.Source)" -Level Success
    }
    
    # Get and display PowerShell Core version
    try {
        $pwshVersion = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1
        Write-Log -Message "PowerShell Core Version: $pwshVersion" -Level Success
    } catch {
        Write-Log -Message "Could not determine PowerShell Core version" -Level Warning
    }
    
    # ========================================================================
    # STEP 3: Check DSC 3.0 Installation
    # ========================================================================
    Write-SectionHeader -Title "STEP 3: Checking DSC 3.0 Installation"
    
    $dscCommand = Get-Command -Name "dsc" -ErrorAction SilentlyContinue
    
    if ($null -eq $dscCommand) {
        Write-Log -Message "DSC 3.0 not found. Attempting to install via WinGet..." -Level Warning
        
        # Check if WinGet is available (should be, we verified it in Step 2)
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
            Write-Log -Message "Install output: $($installResult -join "`n")" -Level Error
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
    # STEP 4: Configure WinRM Service
    # ========================================================================
    Write-SectionHeader -Title "STEP 4: Configuring WinRM Service"
    
    Write-Log -Message "WinRM is required for PowerShell DSC resources and remote management" -Level Info
    
    # Check if WinRM service exists and its status
    $winrmService = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    
    if ($null -eq $winrmService) {
        Write-Log -Message "ERROR: WinRM service not found on this system!" -Level Error
        throw "WinRM service not available"
    }
    
    Write-Log -Message "WinRM service found. Current status: $($winrmService.Status)" -Level Info
    Write-Log -Message "WinRM service startup type: $($winrmService.StartType)" -Level Info
    
    # Configure WinRM
    try {
        Write-Log -Message "Running 'winrm quickconfig' to configure WinRM..." -Level Info
        
        # Run winrm quickconfig with automatic yes to prompts
        $quickConfigOutput = & cmd /c "winrm quickconfig -force 2>&1"
        
        Write-Log -Message "WinRM configuration output:" -Level Info
        foreach ($line in $quickConfigOutput) {
            Write-Log -Message "  $line" -Level Info
        }
        
        # Ensure WinRM service is running
        $winrmService = Get-Service -Name WinRM
        if ($winrmService.Status -ne "Running") {
            Write-Log -Message "Starting WinRM service..." -Level Info
            Start-Service -Name WinRM -ErrorAction Stop
            Start-Sleep -Seconds 2
            $winrmService = Get-Service -Name WinRM
            Write-Log -Message "WinRM service started successfully. Status: $($winrmService.Status)" -Level Success
        } else {
            Write-Log -Message "WinRM service is already running" -Level Success
        }
        
        # Set WinRM service to automatic startup
        $startupType = (Get-Service -Name WinRM).StartType
        if ($startupType -ne "Automatic") {
            Write-Log -Message "Setting WinRM service to automatic startup..." -Level Info
            Set-Service -Name WinRM -StartupType Automatic
            Write-Log -Message "WinRM startup type set to Automatic" -Level Success
        } else {
            Write-Log -Message "WinRM service is already set to automatic startup" -Level Success
        }
        
        # Configure WinRM for localhost
        Write-Log -Message "Configuring WinRM trusted hosts..." -Level Info
        
        try {
            # Get current trusted hosts
            $currentTrustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
            
            Write-Log -Message "Current trusted hosts: $currentTrustedHosts" -Level Info
            
            # Always ensure localhost is in trusted hosts
            if ([string]::IsNullOrWhiteSpace($currentTrustedHosts)) {
                Write-Log -Message "Setting trusted hosts to 'localhost'..." -Level Info
                Set-Item WSMan:\localhost\Client\TrustedHosts -Value "localhost" -Force
                Write-Log -Message "Trusted hosts set to 'localhost'" -Level Success
            } elseif ($currentTrustedHosts -notmatch "localhost") {
                Write-Log -Message "Adding 'localhost' to trusted hosts..." -Level Info
                $newTrustedHosts = "$currentTrustedHosts,localhost"
                Set-Item WSMan:\localhost\Client\TrustedHosts -Value $newTrustedHosts -Force
                Write-Log -Message "Added 'localhost' to trusted hosts" -Level Success
            } else {
                Write-Log -Message "'localhost' is already in trusted hosts" -Level Success
            }
            
            # Display final trusted hosts configuration
            $finalTrustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
            Write-Log -Message "Final trusted hosts configuration: $finalTrustedHosts" -Level Info
            
        } catch {
            Write-Log -Message "WARNING: Could not configure trusted hosts: $($_.Exception.Message)" -Level Warning
            Write-Log -Message "WinRM may still work for local operations" -Level Warning
        }
        
        # Enable PSRemoting (this also configures WinRM properly)
        Write-Log -Message "Enabling PSRemoting..." -Level Info
        try {
            Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop | Out-Null
            Write-Log -Message "PSRemoting enabled successfully" -Level Success
        } catch {
            Write-Log -Message "WARNING: Error enabling PSRemoting: $($_.Exception.Message)" -Level Warning
            Write-Log -Message "Continuing anyway as WinRM service is running..." -Level Warning
        }
        
        # Test WinRM connectivity
        Write-Log -Message "Testing WinRM connectivity to localhost..." -Level Info
        try {
            $testResult = Test-WSMan -ComputerName localhost -ErrorAction Stop
            Write-Log -Message "WinRM connectivity test SUCCESSFUL" -Level Success
            Write-Log -Message "  Protocol Version: $($testResult.ProductVersion)" -Level Info
            Write-Log -Message "  Product Vendor: $($testResult.ProductVendor)" -Level Info
        } catch {
            Write-Log -Message "WARNING: WinRM connectivity test failed: $($_.Exception.Message)" -Level Warning
            Write-Log -Message "DSC may still work, but some features might be limited" -Level Warning
        }
        
        Write-Log -Message "WinRM configuration completed" -Level Success
        
    } catch {
        Write-Log -Message "WARNING: Error during WinRM configuration: $($_.Exception.Message)" -Level Warning
        Write-Log -Message "Some DSC features may not work properly without WinRM" -Level Warning
        Write-Log -Message "Attempting to continue anyway..." -Level Warning
    }
    
    # ========================================================================
    # STEP 5: Install Required PowerShell Modules
    # ========================================================================
    Write-SectionHeader -Title "STEP 5: Checking Required PowerShell Modules"
    
    Write-Log -Message "Checking for ComputerManagementDsc module..." -Level Info
    
    $module = Get-Module -ListAvailable -Name "ComputerManagementDsc"
    
    if ($null -eq $module) {
        Write-Log -Message "ComputerManagementDsc module not found. Installing..." -Level Warning
        
        # Try to install using PowerShell Gallery
        try {
            Write-Log -Message "Attempting to configure PackageManagement..." -Level Info
            
            # Force import of PackageManagement module
            try {
                Import-Module PackageManagement -Force -ErrorAction Stop
                Write-Log -Message "PackageManagement module loaded" -Level Success
            } catch {
                Write-Log -Message "WARNING: Could not load PackageManagement module: $($_.Exception.Message)" -Level Warning
                Write-Log -Message "Attempting alternative installation method..." -Level Warning
            }
            
            # Install NuGet provider if needed (with error handling)
            try {
                $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
                if ($null -eq $nugetProvider) {
                    Write-Log -Message "Installing NuGet package provider..." -Level Info
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop | Out-Null
                    Write-Log -Message "NuGet package provider installed" -Level Success
                } else {
                    Write-Log -Message "NuGet package provider is already installed" -Level Success
                }
            } catch {
                Write-Log -Message "WARNING: Could not install NuGet provider: $($_.Exception.Message)" -Level Warning
                Write-Log -Message "Trying to continue without NuGet provider..." -Level Warning
            }
            
            # Set PSGallery as trusted
            try {
                $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
                if ($null -ne $psGallery -and $psGallery.InstallationPolicy -ne "Trusted") {
                    Write-Log -Message "Setting PSGallery as trusted repository..." -Level Info
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
                    Write-Log -Message "PSGallery set as trusted" -Level Success
                } else {
                    Write-Log -Message "PSGallery is already trusted" -Level Success
                }
            } catch {
                Write-Log -Message "WARNING: Could not configure PSGallery: $($_.Exception.Message)" -Level Warning
            }
            
            # Try Install-Module first
            Write-Log -Message "Installing ComputerManagementDsc module from PowerShell Gallery..." -Level Info
            try {
                Install-Module -Name ComputerManagementDsc -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
                Write-Log -Message "ComputerManagementDsc module installed successfully via Install-Module" -Level Success
            } catch {
                Write-Log -Message "WARNING: Install-Module failed: $($_.Exception.Message)" -Level Warning
                Write-Log -Message "Attempting installation using PowerShell Core (pwsh)..." -Level Warning
                
                # Try using PowerShell Core as fallback
                try {
                    Write-Log -Message "Running Install-Module in PowerShell Core..." -Level Info
                    $pwshInstall = & pwsh -NoProfile -Command "Install-Module -Name ComputerManagementDsc -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop; Get-Module -ListAvailable -Name ComputerManagementDsc | Select-Object -First 1 | ConvertTo-Json" 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log -Message "ComputerManagementDsc module installed successfully via PowerShell Core" -Level Success
                        Write-Log -Message "Module info: $pwshInstall" -Level Info
                    } else {
                        Write-Log -Message "WARNING: PowerShell Core installation failed: $pwshInstall" -Level Warning
                        throw "Both Windows PowerShell and PowerShell Core installation methods failed"
                    }
                } catch {
                    Write-Log -Message "ERROR: Failed to install ComputerManagementDsc module using all methods" -Level Error
                    Write-Log -Message "Error: $($_.Exception.Message)" -Level Error
                    Write-Log -Message "You may need to manually install: Install-Module ComputerManagementDsc -Scope AllUsers" -Level Error
                    throw
                }
            }
        } catch {
            Write-Log -Message "ERROR: Failed to install ComputerManagementDsc module" -Level Error
            Write-Log -Message "Error: $($_.Exception.Message)" -Level Error
            
            # Provide detailed troubleshooting information
            Write-Log -Message "`nTroubleshooting steps:" -Level Error
            Write-Log -Message "1. Try manually: Install-Module ComputerManagementDsc -Scope CurrentUser" -Level Error
            Write-Log -Message "2. Check PowerShell Gallery access: Find-Module ComputerManagementDsc" -Level Error
            Write-Log -Message "3. Verify TLS 1.2: [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12" -Level Error
            Write-Log -Message "4. Check internet connectivity to PowerShell Gallery" -Level Error
            
            throw
        }
    } else {
        Write-Log -Message "ComputerManagementDsc module is already installed (Version: $($module.Version))" -Level Success
    }
    
    # Verify module is available (check in both Windows PowerShell and PowerShell Core locations)
    Write-Log -Message "Verifying ComputerManagementDsc module availability..." -Level Info
    $module = Get-Module -ListAvailable -Name "ComputerManagementDsc" | Select-Object -First 1
    
    if ($null -eq $module) {
        Write-Log -Message "ERROR: Module not found after installation!" -Level Error
        throw "ComputerManagementDsc module not available"
    }
    
    Write-Log -Message "Module verified. Location: $($module.ModuleBase)" -Level Success
    Write-Log -Message "Module version: $($module.Version)" -Level Info
    
    # Import the module to ensure it's available
    Write-Log -Message "Importing ComputerManagementDsc module..." -Level Info
    try {
        Import-Module ComputerManagementDsc -Force -ErrorAction Stop
        Write-Log -Message "Module imported successfully" -Level Success
    } catch {
        Write-Log -Message "WARNING: Could not import module in Windows PowerShell: $($_.Exception.Message)" -Level Warning
        Write-Log -Message "Module may still work when called by DSC" -Level Warning
    }
    
    # ========================================================================
    # STEP 6: Download Configuration Document
    # ========================================================================
    Write-SectionHeader -Title "STEP 6: Downloading DSC Configuration Document"
    
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
    # STEP 7: Execute DSC Configuration
    # ========================================================================
    Write-SectionHeader -Title "STEP 7: Executing DSC Configuration ($Operation)"
    
    Write-Log -Message "Preparing to execute DSC $Operation operation..." -Level Info
    
    # Build the DSC command
    $dscOperation = $Operation.ToLower()
    $dscCommand = "dsc config $dscOperation --file `"$tempConfigPath`""
    
    Write-Log -Message "Executing command: $dscCommand" -Level Info
    
    # Execute DSC configuration
    $startTime = Get-Date
    Write-Log -Message "Operation started at: $startTime" -Level Info
    
    try {
        # Execute and capture output
        $dscOutput = & cmd /c "dsc config $dscOperation --file `"$tempConfigPath`" 2>&1"
        $exitCode = $LASTEXITCODE
        
        $endTime = Get-Date
        $duration = $endTime - $startTime
        
        Write-Log -Message "Operation completed in: $($duration.TotalSeconds) seconds" -Level Info
        Write-Log -Message "Exit Code: $exitCode" -Level Info
        
        # Display raw output
        Write-Log -Message "Raw Output:" -Level Info
        Write-Log -Message ($dscOutput -join "`n") -Level Info
        
        # Parse results based on exit code
        if ($exitCode -eq 0) {
            Write-Log -Message "DSC operation completed successfully!" -Level Success
            
            # Try to parse JSON output for better reporting
            try {
                $jsonOutput = $dscOutput -join "`n"
                $result = $jsonOutput | ConvertFrom-Json
                
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
                                    if ($resourceResult.result.beforeState) {
                                        Write-Log -Message "Before State: $($resourceResult.result.beforeState | ConvertTo-Json -Compress)" -Level Info
                                    }
                                    if ($resourceResult.result.afterState) {
                                        Write-Log -Message "After State: $($resourceResult.result.afterState | ConvertTo-Json -Compress)" -Level Info
                                    }
                                    if ($resourceResult.result.changedProperties) {
                                        Write-Log -Message "Changed Properties: $($resourceResult.result.changedProperties -join ', ')" -Level Success
                                    }
                                }
                                "Get" {
                                    if ($resourceResult.result.actualState) {
                                        Write-Log -Message "Actual State: $($resourceResult.result.actualState | ConvertTo-Json -Compress)" -Level Info
                                    }
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
                Write-Log -Message "Could not parse JSON output (output may not be in JSON format)" -Level Warning
            }
            
        } else {
            Write-Log -Message "ERROR: DSC operation failed with exit code: $exitCode" -Level Error
            Write-Log -Message "This may indicate a configuration error or missing prerequisites" -Level Error
            throw "DSC operation failed with exit code $exitCode"
        }
        
    } catch {
        Write-Log -Message "ERROR: Exception during DSC execution!" -Level Error
        Write-Log -Message "Error: $($_.Exception.Message)" -Level Error
        throw
    }
    
    # ========================================================================
    # STEP 8: Cleanup
    # ========================================================================
    Write-SectionHeader -Title "STEP 8: Cleanup"
    
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
    
    # Display current system information
    Write-Log -Message "`nCurrent System Information:" -Level Info
    
    # Timezone
    $currentTZ = Get-TimeZone
    Write-Log -Message "  Timezone:" -Level Info
    Write-Log -Message "    ID: $($currentTZ.Id)" -Level Info
    Write-Log -Message "    Display Name: $($currentTZ.DisplayName)" -Level Info
    Write-Log -Message "    Standard Name: $($currentTZ.StandardName)" -Level Info
    
    # PowerShell versions
    Write-Log -Message "  PowerShell:" -Level Info
    Write-Log -Message "    Windows PowerShell: $($PSVersionTable.PSVersion)" -Level Info
    if ($pwshCommand) {
        try {
            $pwshVer = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1
            Write-Log -Message "    PowerShell Core: $pwshVer" -Level Info
        } catch {
            Write-Log -Message "    PowerShell Core: Installed but version check failed" -Level Info
        }
    }
    
    # WinRM status
    $winrmSvc = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    if ($winrmSvc) {
        Write-Log -Message "  WinRM Service:" -Level Info
        Write-Log -Message "    Status: $($winrmSvc.Status)" -Level Info
        Write-Log -Message "    Startup Type: $($winrmSvc.StartType)" -Level Info
    }
    
    exit 0
    
} catch {
    Write-Log -Message "`n!!! FATAL ERROR !!!" -Level Error
    Write-Log -Message "Script execution failed: $($_.Exception.Message)" -Level Error
    Write-Log -Message "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Write-Log -Message "`nLog file location: $LogPath" -Level Error
    
    exit 1
}