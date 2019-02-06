﻿using Orleans;
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;

namespace GrainInterfaces
{
    public interface IAgentRegistryGrain : IGrainWithStringKey
    {
        Task AgentStart(MockEgg egg);
        Task AgentStop(string agentId);
        Task GetAgentStatus(string agentId);
        Task GetAllAgents();
    }
}