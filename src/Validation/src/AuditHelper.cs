// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using OpenTelemetry.Audit.Geneva;

namespace ArcadeValidation.Audit
{
    /// <summary>
    /// Centralized OTel Audit logging helper for arcade-validation.
    /// Wraps the OpenTelemetry.Audit.Geneva SDK for consistent audit instrumentation.
    /// </summary>
    public static class AuditHelper
    {
        // Default Service Tree ID (GitHub: dotnet/arcade-validation)
        private static readonly Guid GitHubServiceTreeId = new("b3bbd815-183a-4142-8056-3a676d687f71");
        // AzDO mirror Service Tree ID
        private static readonly Guid AzDOServiceTreeId = new("8835b1f3-0d22-4e28-bae0-65da04655ed4");

        private static bool _initialized;

        /// <summary>
        /// Initializes the OTel Audit SDK. Must be called once at application startup.
        /// Reads OTEL_AUDIT_SERVICE_TREE_ID env var if set, otherwise detects environment
        /// (AzDO vs GitHub) and uses the appropriate Service Tree ID.
        /// </summary>
        public static void Initialize()
        {
            if (_initialized)
                return;

            var serviceTreeId = ResolveServiceTreeId();
            AuditLogger.Initialize(serviceId: serviceTreeId);
            _initialized = true;
        }

        private static Guid ResolveServiceTreeId()
        {
            // Explicit override via environment variable takes priority
            var envOverride = Environment.GetEnvironmentVariable("OTEL_AUDIT_SERVICE_TREE_ID");
            if (!string.IsNullOrEmpty(envOverride) && Guid.TryParse(envOverride, out var overrideId))
            {
                return overrideId;
            }

            // Auto-detect: AzDO pipelines set TF_BUILD=True
            var isAzDO = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("TF_BUILD"));
            return isAzDO ? AzDOServiceTreeId : GitHubServiceTreeId;
        }

        /// <summary>
        /// Returns the machine's first non-loopback IPv4 address, or 127.0.0.1 as fallback.
        /// </summary>
        public static string GetLocalIpAddress()
        {
            try
            {
                var host = Dns.GetHostEntry(Dns.GetHostName());
                var ip = host.AddressList
                    .FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork
                                      && !IPAddress.IsLoopback(a)
                                      && !a.ToString().StartsWith("169.254."));
                if (ip != null) return ip.ToString();
            }
            catch { }
            return "127.0.0.1";
        }

        /// <summary>
        /// Logs a control plane audit event (e.g., channel promotion, build retention, branch operations).
        /// </summary>
        public static void LogControlPlane(
            string operationName,
            OperationCategory category,
            OperationType operationType,
            OperationResult result,
            string callerIdentity,
            string callerIpAddress,
            string callerAgent,
            string operationAccessLevel,
            string[] callerAccessLevels,
            string targetResourceType,
            string targetResourceId,
            string resultDescription = null,
            Action<AuditRecord> customize = null)
        {
            var record = BuildRecord(
                operationName, category, operationType, result,
                callerIdentity, callerIpAddress, callerAgent,
                operationAccessLevel, callerAccessLevels,
                targetResourceType, targetResourceId,
                resultDescription, customize);

            try
            {
                AuditLogger.LogAuditControlPlane(record);
            }
            catch (AuditLoggingException ex)
            {
                Console.Error.WriteLine($"[OTel Audit] Control plane logging failed: {ex.Message}");
            }
        }

        /// <summary>
        /// Logs a data plane audit event (e.g., process execution, file operations).
        /// </summary>
        public static void LogDataPlane(
            string operationName,
            OperationCategory category,
            OperationType operationType,
            OperationResult result,
            string callerIdentity,
            string callerIpAddress,
            string callerAgent,
            string operationAccessLevel,
            string[] callerAccessLevels,
            string targetResourceType,
            string targetResourceId,
            string resultDescription = null,
            Action<AuditRecord> customize = null)
        {
            var record = BuildRecord(
                operationName, category, operationType, result,
                callerIdentity, callerIpAddress, callerAgent,
                operationAccessLevel, callerAccessLevels,
                targetResourceType, targetResourceId,
                resultDescription, customize);

            try
            {
                AuditLogger.LogAuditDataPlane(record);
            }
            catch (AuditLoggingException ex)
            {
                Console.Error.WriteLine($"[OTel Audit] Data plane logging failed: {ex.Message}");
            }
        }

        private static AuditRecord BuildRecord(
            string operationName,
            OperationCategory category,
            OperationType operationType,
            OperationResult result,
            string callerIdentity,
            string callerIpAddress,
            string callerAgent,
            string operationAccessLevel,
            string[] callerAccessLevels,
            string targetResourceType,
            string targetResourceId,
            string resultDescription,
            Action<AuditRecord> customize)
        {
            var record = new AuditRecord();
            record.OperationName = operationName;
            record.AddOperationCategory(category);
            record.OperationType = operationType;
            record.OperationResult = result;
            record.OperationAccessLevel = operationAccessLevel;

            if (result == OperationResult.Failure && !string.IsNullOrEmpty(resultDescription))
            {
                record.OperationResultDescription = resultDescription;
            }

            // CallerIdentities — UPN + AppId/ObjectId when available
            record.AddCallerIdentity(CallerIdentityType.UPN, callerIdentity);
            var appId = Environment.GetEnvironmentVariable("BUILD_REQUESTEDFORID")
                     ?? Environment.GetEnvironmentVariable("AZURE_CLIENT_ID");
            if (!string.IsNullOrEmpty(appId))
            {
                record.AddCallerIdentity(CallerIdentityType.ApplicationID, appId);
            }

            record.AddCallerAccessLevels(callerAccessLevels);
            record.CallerIpAddress = callerIpAddress;
            record.CallerAgent = callerAgent;
            record.AddTargetResource(targetResourceType, targetResourceId);

            // Golden Schema: TokenInfo — auth details when running in pipeline
            var isAzDO = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("TF_BUILD"));
            if (isAzDO)
            {
                record.AddTokenInfo("AuthSchema", "AzurePipelines");
                record.AddTokenInfo("TokenType", "SystemAccessToken");
            }

            // Golden Schema: UserAgent
            record.AddCustomData("UserAgent", $"ArcadeValidation/{Environment.GetEnvironmentVariable("BUILD_BUILDNUMBER") ?? "local"}");

            // Environment context
            record.AddCustomData("MachineName", Environment.MachineName);
            record.AddCustomData("OsPlatform", RuntimeInformation.OSDescription);

            customize?.Invoke(record);

            return record;
        }
    }
}
