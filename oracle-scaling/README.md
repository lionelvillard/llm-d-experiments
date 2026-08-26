# Minimum-Cost Oracle Scaling

Feasibility spike for a tool that computes the lowest possible cost of serving
a fixed inference workload trace — for a given model, on a given deployment
environment — as a theoretical floor to compare real autoscalers against
("perfect clairvoyance" oracle scaling, as opposed to a reactive controller
like the one explored in [`hpa-overshoot`](../hpa-overshoot/spec.md)).

See [spec.md](spec.md) for the full design: problem framing, why it splits
into an offline capacity-profiling stage and a cost-minimizing scheduling
stage, how it reuses
[`vllm-simulated-model`](https://github.com/lionelvillard/vllm-simulated-model)
for the former, solver approach for the latter (DP for a single instance
type, MILP for heterogeneous fleets), open questions, and a phased build-out
plan grounded in
[inference-perf's `code-generation` workload](https://github.com/kubernetes-sigs/inference-perf/tree/main/workload-catalog/code-generation).

**Status:** design spike only — no code yet. Verdict: buildable; see
[spec.md](spec.md#feasibility-verdict).
