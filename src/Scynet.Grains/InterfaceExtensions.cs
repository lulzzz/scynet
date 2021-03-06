using System;
using System.Collections.Generic;
using System.Linq;
using Google.Protobuf;
using Grpc.Core;
using Scynet.GrainInterfaces;

namespace Scynet.Grains
{
    public static class InterfaceExtensions
    {
        public static Agent ToProtobuf(this AgentInfo info, Guid id)
        {
            return new Agent
            {
                Uuid = id.ToString(),
                ComponentType = info.RunnerType,
                ComponentId = info.ComponentId.ToString(),
                Outputs = { info.OutputShapes.Select(i => new Shape { Dimension = { i } }) },
                Frequency = info.Frequency
            };
        }

        public static Agent ToProtobuf(this AgentInfo info, Guid id, byte[] data, IEnumerable<Guid> inputs)
        {
            var result = info.ToProtobuf(id);
            result.EggData = ByteString.CopyFrom(data);
            result.Inputs.Add(inputs.Select(i => i.ToString()));
            return result;
        }
    }
}
