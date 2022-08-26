﻿// Licensed to the .NET Foundation under one or more agreements. 
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using FluentAssertions;
using Microsoft.Build.Utilities.ProjectCreation;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;

namespace Validation.Tests
{
    [Trait("Category", "SkipWhenLiveUnitTesting")]
    public class RepoTests : IClassFixture<CommonRepoResourcesFixture>
    {
        private const string DotNetCertificate = "MicrosoftDotNet500";
        private const string MicrosoftCertificate = "Microsoft400";
        private CommonRepoResourcesFixture _commonRepoResourcesFixture;

        public RepoTests(CommonRepoResourcesFixture commonResourcesFixture)
        {
            _commonRepoResourcesFixture = commonResourcesFixture;
        }

        [Fact]
        public async Task BasicRepoBuild()
        {
            var envVars = Environment.GetEnvironmentVariables();
            using (var builder = new TestRepoBuilder(nameof(BasicRepoBuild), _commonRepoResourcesFixture.CommonResources))
            {
                await builder.AddDefaultRepoSetupAsync();

                builder.AddProject(ProjectCreator
                    .Create()
                    .PropertyGroup()
                    .Property("AllowEmptySignList", "true"), "eng/Signing.props");

                // Create a simple project
                builder.AddProject(ProjectCreator
                        .Templates
                        .SdkCsproj(
                            targetFramework: "net6.0",
                            outputType: "Exe")
                        .PropertyGroup()
                        .Property("IsPackable", "true"),
                    "./src/FooPackage/FooPackage.csproj");
                await builder.AddSimpleCSFile("src/FooPackage/Program.cs");

                builder.Build(
                    TestRepoUtils.BuildArg("configuration"),
                    "Release",
                    TestRepoUtils.BuildArg("restore"),
                    TestRepoUtils.BuildArg("sign"),
                    TestRepoUtils.BuildArg("projects"),
                    Path.Combine(builder.TestRepoRoot, "src/FooPackage/FooPackage.csproj"))
                    .Should().NotThrow();
            }
        }

        /// <summary>
        /// We should get an error if AllowEmptySignList is set to false, or
        /// if it is not set at all (default behavior), and there are no items to sign.
        /// </summary>
        /// <param name="propertyIsSet">Is the property set or are we using the expecte ddefault?</param>
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task BuildShouldErrorIfNoItemsToSignAndNonEmptySignList(bool propertyIsSet)
        {
            var envVars = Environment.GetEnvironmentVariables();
            using (var builder = new TestRepoBuilder(nameof(BuildShouldErrorIfNoItemsToSignAndNonEmptySignList), _commonRepoResourcesFixture.CommonResources))
            {
                await builder.AddDefaultRepoSetupAsync();

                if (propertyIsSet)
                {
                    builder.AddProject(ProjectCreator
                        .Create()
                        .PropertyGroup()
                        .Property("AllowEmptySignList", "false"), "eng/Signing.props");
                }

                // Create a simple project
                builder.AddProject(ProjectCreator
                        .Templates
                        .SdkCsproj(
                            targetFramework: "net6.0",
                            outputType: "Exe")
                        .PropertyGroup()
                        .Property("IsPackable", "true"),
                    "./src/FooPackage/FooPackage.csproj");
                await builder.AddSimpleCSFile("src/FooPackage/Program.cs");

                builder.Build(
                    TestRepoUtils.BuildArg("configuration"),
                    "Release",
                    TestRepoUtils.BuildArg("restore"),
                    TestRepoUtils.BuildArg("sign"),
                    TestRepoUtils.BuildArg("projects"),
                    Path.Combine(builder.TestRepoRoot, "src/FooPackage/FooPackage.csproj"))
                    .Should().Throw<Exception>().WithMessage("*error : List of files to sign is empty. Make sure that ItemsToSign is configured correctly*");
            }
        }

        /// <summary>
        /// We should get an error if AllowEmptySignPostBuildList is set to false, or
        /// if it is not set at all (default behavior), and there are no items to sign in post build signing
        /// </summary>
        /// <param name="propertyIsSet">Is the property set or are we using the expecte default?</param>
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task BuildShouldErrorIfNoItemsToSignAndNonEmptySignPostBuildList(bool propertyIsSet)
        {
            var envVars = Environment.GetEnvironmentVariables();
            using (var builder = new TestRepoBuilder(nameof(BuildShouldErrorIfNoItemsToSignAndNonEmptySignPostBuildList), _commonRepoResourcesFixture.CommonResources))
            {
                await builder.AddDefaultRepoSetupAsync();

                // Always put in the AllowEmptySignList
                var signingProps = ProjectCreator.Create().PropertyGroup();
                signingProps.Property("AllowEmptySignList", "true");

                if (propertyIsSet)
                {
                    signingProps.Property("AllowEmptySignPostBuildList", "false");
                }

                // Clear out ItemsToSignPostBuild
                signingProps.ItemGroup()
                    .ItemRemove("ItemsToSignPostBuild", "@(ItemsToSignPostBuild)");

                builder.AddProject(signingProps, "eng/Signing.props");

                // Create a simple project
                builder.AddProject(ProjectCreator
                        .Templates
                        .SdkCsproj(
                            targetFramework: "net6.0",
                            outputType: "Exe")
                        .PropertyGroup()
                        .Property("IsPackable", "true")
                        .Property("EnableSourceLink", "false"),
                    "./src/FooPackage/FooPackage.csproj");
                await builder.AddSimpleCSFile("src/FooPackage/Program.cs");

                builder.Build(
                    TestRepoUtils.BuildArg("configuration"),
                    "Release",
                    TestRepoUtils.BuildArg("restore"),
                    TestRepoUtils.BuildArg("pack"),
                    TestRepoUtils.BuildArg("publish"),
                    TestRepoUtils.BuildArg("sign"),
                    TestRepoUtils.BuildArg("projects"),
                    Path.Combine(builder.TestRepoRoot, "src/FooPackage/FooPackage.csproj"),
                    "/p:AutoGenerateSymbolPackages=false",
                    "/p:PostBuildSign=true")
                    .Should().Throw<Exception>($"build of repo {builder.TestRepoRoot} is post build signed")
                    .WithMessage("*error : List of files to sign post-build is empty. Make sure that ItemsToSignPostBuild is configured correctly.*");
            }
        }

        /// <summary>
        /// UseDotNetCertificate should replace Microsoft400 with MicrosoftDotNet500 in the call to signing
        /// </summary>
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        [InlineData(null)]
        public async Task BuildShouldUseDotNetCertifcateIfSet(bool? useDotNetCert)
        {
            var envVars = Environment.GetEnvironmentVariables();
            using (var builder = new TestRepoBuilder(nameof(BuildShouldUseDotNetCertifcateIfSet), _commonRepoResourcesFixture.CommonResources))
            {
                await builder.AddDefaultRepoSetupAsync();

                // Always put in the AllowEmptySignList
                var signingProps = ProjectCreator.Create().PropertyGroup();
                signingProps.Property("AllowEmptySignList", "true");

                if (useDotNetCert.HasValue)
                {
                    signingProps.Property("UseDotNetCertificate", useDotNetCert.Value.ToString());
                }

                // Clear out ItemsToSignPostBuild
                signingProps.ItemGroup()
                    .ItemRemove("ItemsToSignPostBuild", "@(ItemsToSignPostBuild)");

                builder.AddProject(signingProps, "eng/Signing.props");

                // Create a simple project
                builder.AddProject(ProjectCreator
                        .Templates
                        .SdkCsproj(
                            targetFramework: "net6.0",
                            outputType: "Exe")
                        .PropertyGroup()
                        .Property("IsPackable", "true")
                        .Property("EnableSourceLink", "false"),
                    "./src/FooPackage/FooPackage.csproj");
                await builder.AddSimpleCSFile("src/FooPackage/Program.cs");

                builder.Build(
                    TestRepoUtils.BuildArg("configuration"),
                    "Release",
                    TestRepoUtils.BuildArg("restore"),
                    TestRepoUtils.BuildArg("pack"),
                    TestRepoUtils.BuildArg("publish"),
                    TestRepoUtils.BuildArg("sign"),
                    TestRepoUtils.BuildArg("projects"),
                    Path.Combine(builder.TestRepoRoot, "src/FooPackage/FooPackage.csproj"),
                    "/p:AutoGenerateSymbolPackages=false")
                    .Should().NotThrow();

                // Now, go find the Round0 signing project and ensure that the certificate names were set properly.
                // The arcade default for an exe is Microsoft400
                string round0FilePath = Path.Combine(builder.TestRepoRoot, "artifacts", "tmp", "Release", "Signing", "Round0.proj");
                string round0ProjectText = File.ReadAllText(round0FilePath);
                string expectedCert = useDotNetCert.GetValueOrDefault() ? DotNetCertificate : MicrosoftCertificate;

                Regex authenticodeRegex = new Regex("<Authenticode>(.*)</Authenticode>");
                var matches = authenticodeRegex.Matches(round0ProjectText);
                matches.Count.Should().Be(1);
                matches[0].Groups[1].Value.Should().Be(expectedCert);
            }
        }

        /// <summary>
        /// UseDotNetCertificate should replace not replace non-Microsoft400 with MicrosoftDotNet500 when using Sign.proj.
        /// </summary>
        [Fact]
        public async Task BuildShouldNotChangeNonMicrosoft400CertsWhenSigning()
        {
            var envVars = Environment.GetEnvironmentVariables();
            using (var builder = new TestRepoBuilder(nameof(BuildShouldNotChangeNonMicrosoft400CertsWhenSigning), _commonRepoResourcesFixture.CommonResources))
            {
                await builder.AddDefaultRepoSetupAsync();

                // Always put in the AllowEmptySignList
                var signingProps = ProjectCreator.Create().PropertyGroup();
                signingProps.Property("AllowEmptySignList", "true");

                // Clear out ItemsToSignPostBuild
                signingProps.ItemGroup()
                    .ItemRemove("ItemsToSignPostBuild", "@(ItemsToSignPostBuild)");

                // Update the .exe extension with a new cert.
                // <StrongNameSignInfo Include="MsSharedLib72" PublicKeyToken="31bf3856ad364e35" CertificateName="Microsoft400" />
                const string certOverride = "Microsoft401";

                signingProps.ItemGroup()
                    .ItemUpdate("StrongNameSignInfo", update: "MsSharedLib72",
                    metadata: new Dictionary<string, string> { { "PublicKeyToken", "31bf3856ad364e35" }, { "CertificateName", certOverride } } );

                builder.AddProject(signingProps, "eng/Signing.props");

                // Create a simple project
                builder.AddProject(ProjectCreator
                        .Templates
                        .SdkCsproj(
                            targetFramework: "net6.0",
                            outputType: "Exe")
                        .PropertyGroup()
                        .Property("IsPackable", "true")
                        .Property("EnableSourceLink", "false"),
                    "./src/FooPackage/FooPackage.csproj");
                await builder.AddSimpleCSFile("src/FooPackage/Program.cs");

                builder.Build(
                    TestRepoUtils.BuildArg("configuration"),
                    "Release",
                    TestRepoUtils.BuildArg("restore"),
                    TestRepoUtils.BuildArg("pack"),
                    TestRepoUtils.BuildArg("publish"),
                    TestRepoUtils.BuildArg("sign"),
                    TestRepoUtils.BuildArg("projects"),
                    Path.Combine(builder.TestRepoRoot, "src/FooPackage/FooPackage.csproj"),
                    "/p:AutoGenerateSymbolPackages=false")
                    .Should().NotThrow();

                // Now, go find the Round0 signing project and ensure that the certificate names were set properly.
                // The arcade default for an exe is Microsoft400
                string round0FilePath = Path.Combine(builder.TestRepoRoot, "artifacts", "tmp", "Release", "Signing", "Round0.proj");
                string round0ProjectText = File.ReadAllText(round0FilePath);

                Regex authenticodeRegex = new Regex("<Authenticode>(.*)</Authenticode>");
                var matches = authenticodeRegex.Matches(round0ProjectText);
                matches.Count.Should().Be(1);
                matches[0].Groups[1].Value.Should().Be(certOverride);
            }
        }

        /// <summary>
        /// UseDotNetCertificate should replace Microsoft400 with MicrosoftDotNet500 for post build signing.
        /// </summary>
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        [InlineData(null)]
        public async Task BuildShouldUseDotNetCertifcateIfSetWithPostBuildSigning(bool? useDotNetCert)
        {
            var envVars = Environment.GetEnvironmentVariables();
            using (var builder = new TestRepoBuilder(nameof(BuildShouldUseDotNetCertifcateIfSet), _commonRepoResourcesFixture.CommonResources))
            {
                await builder.AddDefaultRepoSetupAsync();

                // Always put in the AllowEmptySignList
                var signingProps = ProjectCreator.Create().PropertyGroup();
                signingProps.Property("AllowEmptySignList", "true");

                if (useDotNetCert.HasValue)
                {
                    signingProps.Property("UseDotNetCertificate", useDotNetCert.Value.ToString());
                }

                builder.AddProject(signingProps, "eng/Signing.props");

                // Create a simple project
                builder.AddProject(ProjectCreator
                        .Templates
                        .SdkCsproj(
                            targetFramework: "net6.0",
                            outputType: "Exe")
                        .PropertyGroup()
                        .Property("IsPackable", "true")
                        .Property("EnableSourceLink", "false"),
                    "./src/FooPackage/FooPackage.csproj");
                await builder.AddSimpleCSFile("src/FooPackage/Program.cs");

                builder.Build(
                    TestRepoUtils.BuildArg("configuration"),
                    "Release",
                    TestRepoUtils.BuildArg("restore"),
                    TestRepoUtils.BuildArg("pack"),
                    TestRepoUtils.BuildArg("publish"),
                    TestRepoUtils.BuildArg("sign"),
                    TestRepoUtils.BuildArg("projects"),
                    Path.Combine(builder.TestRepoRoot, "src/FooPackage/FooPackage.csproj"),
                    "/p:AutoGenerateSymbolPackages=false",
                    "/p:PostBuildSign=true",
                    "/p:DotNetPublishUsingPipelines=true")
                    .Should().NotThrow();
                string assetManifestText = GetAssetManifest(builder);
                string expectedCert = useDotNetCert.GetValueOrDefault() ? DotNetCertificate : MicrosoftCertificate;
                string unexpectedCert = useDotNetCert.GetValueOrDefault() ? MicrosoftCertificate : DotNetCertificate;

                // Ensure that we see the expected cert.
                assetManifestText.IndexOf(unexpectedCert).Should().Be(-1);
                assetManifestText.IndexOf(expectedCert).Should().NotBe(-1);
            }
        }

        /// <summary>
        /// UseDotNetCertificate should replace not replace non-Microsoft400 with MicrosoftDotNet500 when using Sign.proj.
        /// </summary>
        [Fact]
        public async Task BuildShouldNotChangeNonMicrosoft400CertsWhenPostBuildSigning()
        {
            var envVars = Environment.GetEnvironmentVariables();
            using (var builder = new TestRepoBuilder(nameof(BuildShouldNotChangeNonMicrosoft400CertsWhenSigning), _commonRepoResourcesFixture.CommonResources))
            {
                await builder.AddDefaultRepoSetupAsync();

                // Always put in the AllowEmptySignList
                var signingProps = ProjectCreator.Create().PropertyGroup();
                signingProps.Property("AllowEmptySignList", "true");
                signingProps.Property("UseDotNetCertificate", "true");

                // Update the .exe extension with a new cert.
                const string certOverride = "Microsoft401";

                signingProps.ItemGroup()
                    .ItemUpdate("StrongNameSignInfo", update: "MsSharedLib72",
                    metadata: new Dictionary<string, string> { { "PublicKeyToken", "31bf3856ad364e35" }, { "CertificateName", certOverride } });

                builder.AddProject(signingProps, "eng/Signing.props");

                // Create a simple project
                builder.AddProject(ProjectCreator
                        .Templates
                        .SdkCsproj(
                            targetFramework: "net6.0",
                            outputType: "Exe")
                        .PropertyGroup()
                        .Property("IsPackable", "true")
                        .Property("EnableSourceLink", "false"),
                    "./src/FooPackage/FooPackage.csproj");
                await builder.AddSimpleCSFile("src/FooPackage/Program.cs");

                builder.Build(
                    TestRepoUtils.BuildArg("configuration"),
                    "Release",
                    TestRepoUtils.BuildArg("restore"),
                    TestRepoUtils.BuildArg("pack"),
                    TestRepoUtils.BuildArg("publish"),
                    TestRepoUtils.BuildArg("sign"),
                    TestRepoUtils.BuildArg("projects"),
                    Path.Combine(builder.TestRepoRoot, "src/FooPackage/FooPackage.csproj"),
                    "/p:AutoGenerateSymbolPackages=false",
                    "/p:PostBuildSign=true",
                    "/p:DotNetPublishUsingPipelines=true")
                    .Should().NotThrow();

                string assetManifestText = GetAssetManifest(builder);
                // Should find Microsoft401, MicrosoftDotNet500, but not Microsoft400
                assetManifestText.IndexOf(DotNetCertificate).Should().NotBe(-1);
                assetManifestText.IndexOf(certOverride).Should().NotBe(-1);
                assetManifestText.IndexOf(MicrosoftCertificate).Should().Be(-1);
            }
        }

        /// <summary>
        /// Retrieve the text from the asset manifest file. Checks that there is only a single asset manifest.
        /// </summary>
        /// <param name="builder"></param>
        /// <returns></returns>
        private static string GetAssetManifest(TestRepoBuilder builder)
        {
            // Now, go find the asset manifest. Since we don't know exactly where it will be and what it will
            // be named (configuration and OS names end up influencing the path), just find an asset manifest under
            // artifacts/log/**/AssetManifests/*. There should only be one.
            string logsDirectory = Path.Combine(builder.TestRepoRoot, "artifacts", "log");
            string[] logFiles = Directory.GetFiles(logsDirectory, "*.xml", SearchOption.AllDirectories);
            string escapedDirSeparator = Regex.Escape($"{Path.DirectorySeparatorChar}");
            Regex assetManifestRegex = new Regex(@$".*{escapedDirSeparator}AssetManifest{escapedDirSeparator}.*\.xml");
            var assetManifests = logFiles.Where(am => assetManifestRegex.IsMatch(am)).ToArray();
            assetManifests.Length.Should().Be(1);
            string assetManifestText = File.ReadAllText(assetManifests[0]);
            return assetManifestText;
        }
    }
}
