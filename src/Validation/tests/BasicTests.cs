// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using Xunit;

namespace Validation_Tests
{
    public class UnitTest1
    {
        [Fact]
        public void Test1()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test2()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test3()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test4()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test5()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test6()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test7()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test8()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test9()
        {
            Assert.True(true);
        }

        [Fact]
        public void Test10()
        {
            Assert.True(true);
        }

        [Fact]
        public void UploadFileTest()
        {
            using (var fs = new FileStream(Path.Combine(Environment.GetEnvironmentVariable("HELIX_DUMP_FOLDER"), "fakedump.dmp"), FileMode.Create, FileAccess.ReadWrite))
            {
                TextWriter tw = new StreamWriter(fs);
                tw.Write("blabla");
                tw.Flush();
            }

            throw new Exception("blerg");
        }
    }
}
