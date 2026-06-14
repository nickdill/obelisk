the idea is you create a whoel workflow

like every project gets `_work/` with epics/work items as directories containing a config explaining how to do the work. Scripts that kick off the different categories of work based on the config.

Brainstorming:
- `_work/placeholder/` contains files, configs, instructions
- like a `worker.md` or agent.md with initial action/directive
- or something like `backlog/` with queue of work to process
- worker.md runs daily, takes something from the backlog performs a function on it
    - powerful, apply claude code opus/fable to reason and take action against the current information provided in this `_work/` topic
    - HOW it does work is also evolutionary, can give it a protocol:
        - draft PRD, technical plan, review
        - handoff to separate agents
           - dev worker writes code, code reviewer, tester, etc

Like mega agents, give claude code a skill to reference a special agent/skill/worker template *$ where example$ would be interpretted be claude as the special agent special-agents/example/ with specific next prompt/action embedded in the agent
