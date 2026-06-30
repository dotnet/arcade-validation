// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

﻿using System;
using ArcadeValidation.Audit;

namespace HelloWorld
{
    class Program
    {
        static void Main(string[] args)
        {
            // Initialize OTel Audit SDK with arcade-validation Service Tree ID
            AuditHelper.Initialize();

            Console.WriteLine("Hello World!");
        }
    }
}


