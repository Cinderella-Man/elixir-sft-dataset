I've this idea:

```
### 80. Directed Acyclic Graph with Topological Sort
Build a DAG module. The interface is `DAG.new()`, `DAG.add_vertex(dag, vertex)`, `DAG.add_edge(dag, from, to)` (fails if it would create a cycle), `DAG.topological_sort(dag)` returning a valid ordering, and `DAG.predecessors(dag, vertex)` / `DAG.successors(dag, vertex)`. Verify by building a known dependency graph, asserting the topological sort is valid (every vertex appears before its dependents), that adding a cycle-creating edge returns an error, and that predecessor/successor queries return correct results.
```

Can you convert it to something looking like a prompt that I could give to AI to actually code this? Here's an example of previously generated prompt:

```
Write me an Elixir GenServer module called `RateLimiter` that enforces per-key rate limits using a sliding window algorithm.

I need these functions in the public API:

- `RateLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `RateLimiter.check(server, key, max_requests, window_ms)` which checks whether a request for the given key is allowed. If allowed, return `{:ok, remaining}` where remaining is how many more requests are available in the current window. If not allowed, return `{:error, :rate_limited, retry_after_ms}` where retry_after_ms tells the caller how long to wait.

Each key must be tracked independently — rate limiting "user:1" should have no effect on "user:2". The sliding window should work correctly at boundaries, meaning if I make 3 requests allowed per 1000ms window and I make them at time 0, then at time 1001 I should be allowed again.

You also need to make sure expired entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any tracking data for windows that have fully expired.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

Can you create a similar one? Furthermore, additionally to the prompt could you generate a test harness that would verify that the generated code (based on the prompt that you will generate) actually does what it should? I have attached previously generated test harness as a template so you understand what I'm talking about.
```