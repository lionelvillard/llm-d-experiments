# Upstream Issue Draft

Ready to paste as a new issue on `lionelvillard/llm-d-experiments`.

---

**Title:** Spike: minimum-cost oracle scaling for a given trace/model/environment

**Body:**

## Problem

We don't have a way to say how far a real autoscaler (HPA, KEDA, or a custom
controller) is from optimal for a given workload. Without a floor to compare
against, "the autoscaler overshoots" is qualitative, not measurable.

This issue tracks a spike to explore whether we can build a tool that
computes the **lowest possible cost** of serving a given inference trace —
for a fixed model, on a fixed deployment environment — subject to latency/SLO
constraints, using full advance knowledge of the trace ("perfect
clairvoyance" oracle scaling). That number becomes the baseline every real
autoscaler is measured against.

## Scope

- Input: a workload trace, e.g. [inference-perf's `code-generation`
  workload](https://github.com/kubernetes-sigs/inference-perf/tree/main/workload-catalog/code-generation).
- Given a fixed model and target environment (instance types, pricing,
  capacity/throughput characteristics), compute the minimum-cost resource
  allocation over time that serves the trace within its latency/SLO
  constraints.
- Work out what's actually needed to make this tractable: cost model
  inputs, a throughput/latency model for the target environment, a solver
  approach (offline optimization vs. simulation), and how it reuses/relates
  to [vllm-simulated-model](https://github.com/lionelvillard/vllm-simulated-model).

## Deliverable

A spike/writeup on whether this is buildable, and if so, a rough design for
the tool. See [`oracle-scaling/`](oracle-scaling/) in this repo for the
design doc produced by this spike.

## Summary of findings (see `oracle-scaling/spec.md` for full detail)

The naive approach — searching over candidate scaling schedules and
evaluating each with a full simulation — is intractable. The problem
decomposes into two independent stages:

1. **Offline capacity profiling**: for a given (model, instance type,
   workload token-length profile), what request rate can one replica sustain
   within the SLO? This is exactly what `vllm-simulated-model` is built to
   answer (real vLLM scheduler/batching/API server, CPU-only, no real
   weights), and only needs to run once per instance type in the catalog —
   independent of the scheduling search.
2. **Cost-minimizing scheduling**: given per-replica capacity and a
   time-varying demand curve derived from the trace, find the
   cheapest replica schedule that covers demand at every point in time,
   respecting startup lag and instance pricing. Structurally similar to
   unit-commitment scheduling in power grids — solvable with a DP for a
   single instance type, or a small MILP for a heterogeneous fleet.

**Verdict: buildable.** A phase-1 version (single instance type, i.i.d.
demand curve, no prefix-cache modeling) is a modestly scoped spike reusing
`vllm-simulated-model` unmodified. Open questions that affect accuracy but
not feasibility: tail-latency shape near saturation, KV-cache state as a
non-fungible resource, and multi-turn causality in conversational traces
like `code-generation`.
