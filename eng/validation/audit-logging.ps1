# OTel Audit Logging Helper for arcade-validation pipeline scripts
# Emits structured audit log entries via Azure DevOps pipeline logging commands.
# These entries are picked up by Geneva Agent on 1ES hosted agents.

# Service Tree IDs: GitHub vs AzDO mirror
$GitHubServiceTreeId = "b3bbd815-183a-4142-8056-3a676d687f71"
$AzDOServiceTreeId = "8835b1f3-0d22-4e28-bae0-65da04655ed4"

# Resolve the correct Service Tree ID based on environment
# Priority: env var override > auto-detect (TF_BUILD = AzDO, otherwise GitHub)
if ($env:OTEL_AUDIT_SERVICE_TREE_ID) {
    $AuditServiceTreeId = $env:OTEL_AUDIT_SERVICE_TREE_ID
} elseif ($env:TF_BUILD) {
    $AuditServiceTreeId = $AzDOServiceTreeId
} else {
    $AuditServiceTreeId = $GitHubServiceTreeId
}

function Get-AgentIpAddress {
    try {
        if ($IsWindows -or ($PSVersionTable.PSVersion.Major -le 5)) {
            # Windows: use Get-NetIPAddress
            $ip = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } |
                Select-Object -First 1).IPAddress
            if ($ip) { return $ip }
        } else {
            # Linux/macOS: use hostname or ip command
            $ip = (hostname -I 2>/dev/null) -split '\s+' |
                Where-Object { $_ -ne '127.0.0.1' -and $_ -notlike '169.254.*' -and $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
                Select-Object -First 1
            if ($ip) { return $ip }
        }
    } catch {}
    return "127.0.0.1"
}

function Write-AuditLog {
    <#
    .SYNOPSIS
        Emits a structured audit log entry for a privileged operation.
    .DESCRIPTION
        Logs audit telemetry using Azure DevOps pipeline logging commands.
        The structured data is captured by Geneva Agent for OTel Audit compliance.
    .PARAMETER OperationName
        PascalCase verb+noun name of the operation (e.g., PromoteBuildToChannel).
    .PARAMETER OperationCategory
        Category of the operation: ResourceManagement, KeyManagement, UserManagement,
        RoleManagement, GroupManagement, PolicyManagement, Authorization, Authentication, Other.
    .PARAMETER OperationType
        Type: Create, Read, Update, Delete, Assign, Unassign, Other.
    .PARAMETER OperationResult
        Result: Success, Failure.
    .PARAMETER CallerIdentity
        Identity performing the operation (e.g., pipeline service account, UPN).
    .PARAMETER TargetResourceType
        Type of resource being acted upon (e.g., MaestroChannel, AzdoBuild, GitBranch).
    .PARAMETER TargetResourceId
        Identifier of the target resource.
    .PARAMETER OperationAccessLevel
        Permission required to execute the operation.
    .PARAMETER CallerAccessLevels
        Permissions the caller has.
    .PARAMETER ResultDescription
        Description of failure reason (required when OperationResult is Failure).
    .PARAMETER CustomData
        Hashtable of additional key-value pairs for context.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$OperationName,

        [Parameter(Mandatory=$true)]
        [ValidateSet("ResourceManagement", "KeyManagement", "UserManagement", "RoleManagement",
                     "GroupManagement", "PolicyManagement", "Authorization", "Authentication", "Other")]
        [string]$OperationCategory,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Create", "Read", "Update", "Delete", "Assign", "Unassign", "Other")]
        [string]$OperationType,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Success", "Failure")]
        [string]$OperationResult,

        [Parameter(Mandatory=$false)]
        [string]$CallerIdentity = $env:BUILD_REQUESTEDFOR,

        [Parameter(Mandatory=$true)]
        [string]$TargetResourceType,

        [Parameter(Mandatory=$true)]
        [string]$TargetResourceId,

        [Parameter(Mandatory=$false)]
        [string]$OperationAccessLevel = "PipelineExecution",

        [Parameter(Mandatory=$false)]
        [string[]]$CallerAccessLevels = @("PipelineServiceAccount"),

        [Parameter(Mandatory=$false)]
        [string]$ResultDescription,

        [Parameter(Mandatory=$false)]
        [hashtable]$CustomData = @{}
    )

    # Build the audit record
    $auditRecord = @{
        ServiceTreeId         = $AuditServiceTreeId
        OperationName         = $OperationName
        OperationCategory     = $OperationCategory
        OperationType         = $OperationType
        OperationResult       = $OperationResult
        CallerIdentity        = if ($CallerIdentity) { $CallerIdentity } else { "AzurePipelines" }
        CallerAgent           = "AzurePipelines/$($env:SYSTEM_TEAMPROJECT)/$($env:BUILD_DEFINITIONNAME)"
        CallerIpAddress       = (Get-AgentIpAddress)
        TargetResourceType    = $TargetResourceType
        TargetResourceId      = $TargetResourceId
        OperationAccessLevel  = $OperationAccessLevel
        CallerAccessLevels    = ($CallerAccessLevels -join ",")
        Timestamp             = (Get-Date -Format "o")
        # Golden Schema fields
        UserAgent             = "ArcadeValidation/$($env:BUILD_BUILDNUMBER)"
        AppId                 = if ($env:BUILD_REQUESTEDFORID) { $env:BUILD_REQUESTEDFORID } else { "local" }
        TokenInfo             = if ($env:TF_BUILD) { "AuthSchema=AzurePipelines" } else { "" }
        # Environment context
        MachineName           = $env:COMPUTERNAME
        BuildId               = $env:BUILD_BUILDID
        BuildNumber           = $env:BUILD_BUILDNUMBER
        Repository            = $env:BUILD_REPOSITORY_NAME
        SourceBranch          = $env:BUILD_SOURCEBRANCH
    }

    if ($OperationResult -eq "Failure" -and $ResultDescription) {
        $auditRecord["ResultDescription"] = $ResultDescription
    }

    foreach ($key in $CustomData.Keys) {
        $auditRecord["Custom$key"] = $CustomData[$key]
    }

    # Emit as structured telemetry via pipeline logging
    $jsonPayload = $auditRecord | ConvertTo-Json -Compress
    Write-Host "##[section]OTelAudit: $OperationName ($OperationResult)"
    Write-Host "##vso[task.logdetail id=$(New-Guid);name=OTelAudit;type=AuditRecord;state=Completed]$jsonPayload"

    # Also write to pipeline timeline for visibility
    if ($OperationResult -eq "Failure") {
        Write-Warning "[OTel Audit] $OperationName FAILED: $ResultDescription"
    } else {
        Write-Host "[OTel Audit] $OperationName succeeded on $TargetResourceType/$TargetResourceId"
    }
}

function Write-AuditLog-ChannelPromotion {
    <#
    .SYNOPSIS
        Logs a Maestro channel promotion operation.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$ChannelName,
        [Parameter(Mandatory=$true)][string]$BuildId,
        [Parameter(Mandatory=$true)][ValidateSet("Success", "Failure")][string]$Result,
        [Parameter(Mandatory=$false)][string]$ResultDescription
    )

    Write-AuditLog `
        -OperationName "PromoteBuildToChannel" `
        -OperationCategory "ResourceManagement" `
        -OperationType "Update" `
        -OperationResult $Result `
        -TargetResourceType "MaestroChannel" `
        -TargetResourceId $ChannelName `
        -OperationAccessLevel "MaestroChannelAdmin" `
        -CallerAccessLevels @("MaestroChannelAdmin", "AzdoPipelineToken") `
        -ResultDescription $ResultDescription `
        -CustomData @{ BuildId = $BuildId }
}

function Write-AuditLog-ChannelDeletion {
    <#
    .SYNOPSIS
        Logs a Maestro default channel deletion operation.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$ChannelName,
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$Branch,
        [Parameter(Mandatory=$true)][ValidateSet("Success", "Failure")][string]$Result,
        [Parameter(Mandatory=$false)][string]$ResultDescription
    )

    Write-AuditLog `
        -OperationName "DeleteDefaultChannel" `
        -OperationCategory "ResourceManagement" `
        -OperationType "Delete" `
        -OperationResult $Result `
        -TargetResourceType "MaestroDefaultChannel" `
        -TargetResourceId "$Repository@$Branch->$ChannelName" `
        -OperationAccessLevel "MaestroChannelAdmin" `
        -CallerAccessLevels @("MaestroChannelAdmin", "AzdoPipelineToken") `
        -ResultDescription $ResultDescription
}

function Write-AuditLog-BuildRetention {
    <#
    .SYNOPSIS
        Logs a build retention operation.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$BuildId,
        [Parameter(Mandatory=$true)][string]$Project,
        [Parameter(Mandatory=$true)][ValidateSet("Success", "Failure")][string]$Result,
        [Parameter(Mandatory=$false)][string]$ResultDescription
    )

    Write-AuditLog `
        -OperationName "RetainBuildPermanently" `
        -OperationCategory "ResourceManagement" `
        -OperationType "Update" `
        -OperationResult $Result `
        -TargetResourceType "AzdoBuild" `
        -TargetResourceId "$Project/Build/$BuildId" `
        -OperationAccessLevel "BuildAdmin" `
        -CallerAccessLevels @("BuildAdmin", "SystemAccessToken") `
        -ResultDescription $ResultDescription
}

function Write-AuditLog-BranchOperation {
    <#
    .SYNOPSIS
        Logs a Git branch operation (create/delete).
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$BranchName,
        [Parameter(Mandatory=$true)][ValidateSet("Create", "Delete")][string]$OperationType,
        [Parameter(Mandatory=$true)][ValidateSet("Success", "Failure")][string]$Result,
        [Parameter(Mandatory=$false)][string]$ResultDescription
    )

    Write-AuditLog `
        -OperationName "${OperationType}RemoteBranch" `
        -OperationCategory "ResourceManagement" `
        -OperationType $OperationType `
        -OperationResult $Result `
        -TargetResourceType "GitBranch" `
        -TargetResourceId "$Repository/$BranchName" `
        -OperationAccessLevel "GitPush" `
        -CallerAccessLevels @("GitPush", "AzdoPipelineToken") `
        -ResultDescription $ResultDescription
}

function Write-AuditLog-BuildInvocation {
    <#
    .SYNOPSIS
        Logs a build invocation via Azure DevOps API.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Project,
        [Parameter(Mandatory=$true)][string]$PipelineId,
        [Parameter(Mandatory=$true)][string]$SourceBranch,
        [Parameter(Mandatory=$true)][ValidateSet("Success", "Failure")][string]$Result,
        [Parameter(Mandatory=$false)][string]$ResultDescription
    )

    Write-AuditLog `
        -OperationName "InvokeAzdoBuild" `
        -OperationCategory "ResourceManagement" `
        -OperationType "Create" `
        -OperationResult $Result `
        -TargetResourceType "AzdoPipeline" `
        -TargetResourceId "$Project/Pipeline/$PipelineId" `
        -OperationAccessLevel "QueueBuilds" `
        -CallerAccessLevels @("QueueBuilds", "AzdoPipelineToken") `
        -ResultDescription $ResultDescription `
        -CustomData @{ SourceBranch = $SourceBranch }
}
