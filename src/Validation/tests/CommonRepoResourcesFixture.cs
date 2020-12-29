using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Validation.Tests
{
    public class CommonRepoResourcesFixture : IDisposable
    {
        public RepoResources CommonResources { get; private set; }

        public CommonRepoResourcesFixture()
        {
            CommonResources = RepoResources.Create(useIsolatedRoots: false).GetAwaiter().GetResult();
        }

        public void Dispose()
        {
            CommonResources.Dispose();
        }
    }
}
