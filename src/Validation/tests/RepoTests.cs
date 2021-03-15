// Licensed to the .NET Foundation under one or more agreements. 
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using FluentAssertions;
using Microsoft.Build.Utilities.ProjectCreation;
using System;
using System.IO;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;

namespace Validation.Tests
{
    [Trait("Category", "SkipWhenLiveUnitTesting")]
    public class RepoTests : IClassFixture<CommonRepoResourcesFixture>
    {
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
    }
}
