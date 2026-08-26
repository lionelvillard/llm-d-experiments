# Minimum-Cost Oracle Scaling for a Given Trace/Model/Environment

A feasibility spike and rough design for a tool that computes the **theoretical
minimum cost** of serving a fixed inference workload trace — for a fixed model,
on a fixed deployment environment — as a "perfect clairvoyance" floor to compare
real autoscalers (HPA, KEDA, custom controllers) against.

## Problem Statement

Given:

- a **trace** — a timestamped sequence of requests, each with prompt/output
  token lengths (and possibly multi-turn structure with think-time between
  turns), e.g. [inference-perf's `code-generation`
  workload](https://github.com/kubernetes-sigs/inference-perf/tree/main/workload-catalog/code-generation);
- a **model** (fixed weights, fixed serving engine — vLLM);
- an **environment**: a catalog of instance types, each with a price and a
  capacity/throughput characteristic when serving that model;
- an **SLO**: latency constraints the served trace must satisfy (e.g. TTFT
  P95, ITL P99);

compute the time-varying resource allocation — how many replicas of which
instance type(s) are running at each moment — that serves the *entire trace*
within the SLO at **minimum total cost**, with full advance knowledge of the
trace (no reaction delay, no forecasting error).

This is deliberately an oracle, not a controller: it is allowed to scale a
replica up *before* the demand that needs it arrives, because it already knows
the whole trace. That's what makes its cost a legitimate floor — any online
autoscaler, however good, can only do worse (it reacts to metrics after the
fact, exactly the failure mode explored in
[`hpa-overshoot`](../hpa-overshoot/spec.md)).

## Why This Splits Into Two Decoupled Problems

The naive approach — search over allocation schedules and evaluate each one by
running the trace through a real (or simulated) vLLM deployment — is
intractable. A solver exploring different scale-up/scale-down timings needs to
evaluate thousands of candidate schedules; running a discrete-event simulation
per candidate is far too slow, and running it on real GPUs is a non-starter.

The key realization is that the problem decomposes cleanly into two stages
that can be solved independently:

1. **Offline capacity profiling** — for a given (model, instance type, ISL/OSL
   distribution), what is the maximum sustainable request rate a *single
   replica* can serve while keeping TTFT/ITL within the SLO? This is a
   property of the hardware and the model and the workload's token-length
   distribution — it does **not** depend on the specific schedule the solver
   is trying to evaluate, so it can be computed **once, up front**, independent
   of the optimization.

2. **Cost-minimizing scheduling** — given a per-replica capacity number (from
   step 1) and a time-varying demand curve derived from the trace, find the
   cheapest time-varying replica count (per instance type) that keeps
   supplied capacity ≥ demand at every point in time, accounting for
   replica startup delay and instance pricing. This is a scheduling /
   covering problem over a handful of numeric curves — fast to solve, and
   can be re-solved for many candidate environments or SLOs without
   re-running any simulation.

This decoupling is what makes the tool tractable at all: the expensive part
(characterizing engine behavior) is amortized over one profiling pass per
(model, instance type) pair, and the search over schedules never touches a
simulator directly.

## Inputs

### Trace

Per-request: arrival timestamp, input token count, output token count (or a
distribution to sample from), and — for multi-turn traces like
`code-generation` — a conversation ID, turn index, and inter-turn think-time.
From the `code-generation` workload specifically: input lengths are
lognormal and skew very large (system prompts and repo context in the
10K–990K token range, ~1,500 tokens/turn on top), output lengths are
lognormal and modest (mean ~425 tokens), turns per conversation are
long-tailed (up to ~3,000), and the workload's own stated SLO targets are
TTFT P95 ≤ 30s and ITL P99 ≤ 100ms — driven by large prefill cost per turn.
That prefill/decode imbalance (the workload notes a ratio around 376:1) is
exactly the kind of thing that makes throughput non-trivial to model with a
flat req/s number — see below.

### Model + Environment

- Model identity (weights, quantization) — needed to interpret which
  instance types can even host it (memory footprint) and what per-token
  latency it produces.
- Instance type catalog: for each type, `$/hour` (or `$/second` — most cloud
  GPU SKUs bill sub-hour), GPU count/type, and any known capacity numbers
  (throughput at a given latency point), or a hardware spec sufficient to
  *derive* those numbers (HBM bandwidth, FLOPs, memory capacity).
- Replica startup latency per instance type (image pull + weight load +
  warmup) — the same quantity that makes `hpa-overshoot`'s pending-pod
  problem real, and a hard constraint here too: the oracle cannot supply
  capacity it hasn't finished starting, even though it can *start early*.
- Minimum billing granularity / minimum run duration, if the environment
  bills that way (relevant to whether rapid scale up/down is actually free).

### SLO

Latency targets (TTFT / ITL / end-to-end, at some percentile). The SLO is
what turns "serve the trace" into a hard constraint the solver must satisfy
rather than a soft objective — cost is minimized *subject to* the SLO holding
at every point in the trace, not traded off against it.

## Cost Model

```
total_cost = Σ_t Σ_i  price(i) × replicas(i, t) × Δt
```

subject to, for every time bucket `t`:

```
Σ_i  capacity(i, model, workload_profile) × replicas(i, t)  ≥  demand(t)
```

where `demand(t)` is derived from the trace (see below) and `capacity(i, …)`
is the per-replica sustainable throughput from the offline profiling stage.
Replica transitions are further constrained by:

- **startup delay**: a replica of type `i` requested at time `t` only counts
  toward capacity at `t + startup(i)`;
- **no negative replicas**, integer replica counts;
- optionally, a **minimum run time** per replica if billing is coarse-grained.

This is structurally the same shape as *unit commitment* in power-grid
scheduling (decide which generators run when, at minimum fuel cost, subject
to meeting forecasted demand with startup lead times) — a well-studied
problem class with mature solvers, which is reassuring for tractability.

## Throughput/Latency Model, and Reuse of `vllm-simulated-model`

The hard part of stage 1 is: for a given instance type and workload profile,
what request rate can one replica sustain before TTFT/ITL SLOs are violated?
This is precisely what
[`vllm-simulated-model`](https://github.com/lionelvillard/vllm-simulated-model)
is built to answer, without needing the real GPU or real weights:

- It runs the **actual vLLM scheduler, batching, and API server**, replacing
  only the model forward pass with a latency stand-in — so scheduling
  effects that matter for tail latency (batching, preemption, prefix caching,
  chunked prefill) are preserved, not approximated away.
- It ships two latency models: a **linear** model (`base_ms +
  prefill_ms_per_token × tokens + decode_ms_per_seq × seqs + ctx_ms_per_ktoken
  × ctx`) for fast, empirically-fit estimates, and a **physics** model
  (FLOPs/HBM-bandwidth roofline, dense and MoE aware) for projecting onto
  hardware that hasn't been benchmarked yet — which matters here because the
  "target environment" in this tool's scope may include instance types with
  no existing empirical vLLM numbers.
- Its own accuracy target is reproducing real H100 TTFT/ITL/throughput
  numbers, which is exactly the fidelity bar this tool needs from stage 1.

**How this tool would use it**: not as a component that runs *inside* the
solver's search loop, but as an **offline sweep**, run once per (model,
instance type, workload token-length profile) combination, before scheduling
optimization starts:

1. Replay (or synthesize, matching the trace's ISL/OSL distribution)
   increasing request rates against `vllm-simulated-model` configured for
   that instance type.
2. Record TTFT/ITL percentiles at each rate.
3. Fit `capacity(instance_type, rate) → (TTFT_p95, ITL_p99)`, and extract the
   maximum rate at which the SLO still holds — this single number (or a small
   curve, if latency degrades gracefully rather than as a step function) is
   what stage 2's solver consumes.

This sweep is the only place a simulator is invoked, and it's invoked a
small, fixed number of times (one per instance type in the catalog, times a
handful of rate points) — independent of how large the solver's search space
is.

## Solver Approach

Once `demand(t)` and `capacity(i)` are available as numeric inputs, stage 2 is
a scheduling problem, not a simulation problem:

- **Single instance type**: reduces to choosing `replicas(t) =
  ⌈demand(t)/capacity⌉`, lagged by startup time and smoothed to avoid
  paying for flapping — solvable with a direct dynamic program over
  (time bucket, replica count) state, minimizing cost while respecting the
  demand floor and startup lag. Cheap enough to run in closed form.
- **Heterogeneous fleet** (multiple instance types, e.g. mixing a
  cheaper/smaller GPU with a faster/pricier one, or on-demand vs. spot):
  becomes a small **MILP** — decision variables `x_{i,t}` (replica count of
  type `i` at time `t`), objective = total cost, constraints = capacity
  covering demand + startup lag + integrality. At the time resolution a
  real trace needs (minute-level buckets over a multi-hour trace), this is
  well within reach of an off-the-shelf solver (e.g. HiGHS/CBC via
  OR-Tools or PuLP) — no custom solver needed for a first version.
- If problem size grows (very long traces, very fine time buckets, large
  instance-type catalogs), a rolling-horizon or LP-relaxation-plus-rounding
  heuristic is the fallback, but isn't needed for realistic single-trace
  experiments of the kind this repo runs.

## Deriving `demand(t)` From the Trace

The remaining piece is turning a request-level trace into the numeric
`demand(t)` curve the solver consumes. The simplest approach — bucket
requests into time windows and count arrivals per second — works for
traces where requests are close to i.i.d. and independent of each other. It
breaks down for a workload like `code-generation`, where:

- requests belong to **multi-turn conversations**: turn *n* depends on the
  output of turn *n−1* and is separated by think-time, so "demand" isn't a
  simple arrival-rate curve — it's closer to a set of concurrent, causally
  chained streams;
- system prompts and repo context repeat **across turns and across
  conversations**, which prefix caching can exploit to cut effective
  prefill cost — meaning `capacity(i)` isn't workload-profile-invariant, it
  depends on cache hit rate, which depends on scheduling and routing
  decisions the oracle is also trying to make.

A defensible first version treats each conversation as a source of
concurrent load (using turn timing/think-time to derive concurrent stream
count over time, matching how `inference-perf`'s own `code-generation`
config already models it as staged concurrency) and **ignores prefix-cache
benefit** — i.e., profiles capacity conservatively as if every prefill were a
cold prefill. That gives a valid (if slightly pessimistic) cost floor. Adding
cache-aware capacity is a natural follow-up once the base pipeline exists,
noted below as an open question.

## Open Questions / Risks

- **Tail latency near saturation**: capacity doesn't degrade linearly as
  load approaches the SLO boundary — near-saturation behavior needs enough
  sweep resolution in the offline profiling stage to capture the knee of the
  curve, not just a single max-rate number.
- **KV-cache state as a non-fungible resource**: a "replica" isn't actually
  interchangeable once it's warmed up with cached prefixes; routing
  decisions interact with capacity. First version ignores this (see above);
  a v2 could feed measured cache-hit-rate curves back into stage 1.
- **Discretization error**: time-bucket granularity trades off solver cost
  against fidelity to bursty, sub-bucket arrival patterns; needs validation
  against a finer-grained ground truth (e.g. actually replaying the derived
  schedule through `vllm-simulated-model` end-to-end as a sanity check).
- **Multi-turn causality**: think-time and turn-chaining mean the "trace" is
  not simply replayable at arbitrary speed — the oracle's demand curve must
  respect that turn *n+1* cannot arrive before turn *n*'s response, which
  the profiling/demand-derivation step needs to model explicitly rather than
  just bucketing raw arrival timestamps.
- **Startup-lag interaction with the oracle's own advantage**: the whole
  premise of "clairvoyant" scaling is pre-emptive scale-up; if startup delay
  is large relative to trace-level demand swings, even the oracle pays a
  real cost for it, and that cost is itself an interesting number to report
  (how much of an autoscaler's overshoot is fundamentally unavoidable vs.
  attributable to reactivity, à la `hpa-overshoot`).

## Phased Build-Out

1. **Single instance type, single conversation-agnostic demand curve,
   ignore prefix caching.** Offline sweep via `vllm-simulated-model`'s
   linear latency model → one `capacity` number → closed-form DP scheduler.
   Enough to produce a first oracle-cost number for `code-generation` and
   compare it against a real HPA run.
2. **Heterogeneous instance-type catalog.** Swap the DP for a small MILP;
   add cost/startup-lag data for a second instance type.
3. **Multi-turn-aware demand derivation.** Model conversations as
   causally-chained concurrent streams instead of an i.i.d. arrival curve.
4. **Cache-aware capacity.** Feed prefix-cache hit-rate effects back into
   the offline profiling sweep so capacity isn't uniformly worst-case.
5. **Validation.** Replay the oracle's derived schedule through
   `vllm-simulated-model` end-to-end (not just its offline profiling
   sweeps) to check the discretized solution actually holds the SLO, and
   compare its cost against a real autoscaler run on the same trace.

## Feasibility Verdict

**Buildable.** The naive framing (simulate every candidate schedule) is
intractable, but the problem decomposes into a small, fixed-cost offline
profiling pass (reusing `vllm-simulated-model` as-is, no modifications
needed) feeding a cheap, well-understood scheduling optimization (DP for the
single-instance-type case, small MILP for heterogeneous fleets — both
standard, off-the-shelf-solvable problem shapes). Phase 1 is a modestly
scoped spike: no new simulator work, no new solver technology, just an
offline sweep script plus a DP scheduler and a way to turn a trace into a
demand curve. The open questions (tail latency shape, KV-cache state,
multi-turn causality) affect *accuracy*, not *feasibility* — they're places
where phase 1's oracle will be a slightly loose (but still valid and
useful) upper-bound-on-tightness floor, tightened in later phases.
