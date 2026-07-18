# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `TimeoutRetryWorker` that executes a function with exponential backoff, jitter, and per-attempt timeouts on failure.

I need these functions in the public API:

- `TimeoutRetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a one-arity function that takes a max integer and returns a random integer in `0..max-1`. If not provided, default to `fn max -> :rand.uniform(max) - 1 end`. It should also accept a `:name` option for process registration.

- `TimeoutRetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. Each attempt must be run inside a spawned `Task` with a timeout enforced via `Task.yield/2` + `Task.shutdown/2`. If the task completes and returns `{:ok, result}`, return `{:ok, result}` immediately. If the task completes and returns `{:error, reason}`, schedule a retry with exponential backoff. If the task times out (yield returns nil), shut it down and treat it as an `{:error, :timeout}` failure for retry purposes. The opts keyword list must support: `:max_retries` (integer, default 3), `:base_delay_ms` (integer, default 100), `:max_delay_ms` (integer, default 10_000), and `:attempt_timeout_ms` (integer, default 5_000). The call should block the caller until the function eventually succeeds or all retries are exhausted. When all retries are exhausted return `{:error, :max_retries_exceeded, reason}` where reason is the last error reason (or `:timeout` if the last attempt timed out).

The backoff delay for attempt N (0-indexed, so first retry is attempt 1) should be calculated as `min(base_delay_ms * 2^N, max_delay_ms)`. Then add random jitter in the range `0..delay-1` on top, so the actual wait is `delay + jitter` where jitter is obtained by calling the injected `:random` function with `delay` as the argument. Retries must be scheduled using `Process.send_after` so the GenServer doesn't block other callers while waiting.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts retries.

The function passed to execute will be called inside a Task process spawned from within the GenServer's `handle_info`. Each retry should spawn a fresh Task and apply the timeout again.

## Behavior contract to pin down

Please make the following observable details exact, since I want to depend on them:

### `start_link/1`

- `opts` is a keyword list and should default to `[]`, so `start_link()` works with no arguments.
- Return whatever `GenServer.start_link/3` returns (`{:ok, pid}` etc.).
- When `:name` is present, register under that name; when absent, start unregistered. Passing `:name` must not break anything else — the rest of `opts` is just configuration.
- The module must double as a supervisable child: starting it as `{TimeoutRetryWorker, opts}` (for example via `start_supervised!/1` or under any supervisor) must launch the worker, handing `opts` straight through to `start_link/1`. Using `use GenServer` gives you this child spec for free.
- `:clock` and `:random` are resolved once at init and held for the lifetime of the process. `:random` is the only source of jitter: whenever jitter is applied, it is obtained by calling the injected function, never by calling `:rand` directly. `:clock` is accepted, defaulted, and retained, but must not be used to implement the retry delay itself (`Process.send_after` does the waiting).
- Any other keys in `opts` are ignored.

### `execute/3`

- `opts` defaults to `[]`, so `execute(server, func)` is valid and uses every default.
- The caller blocks until the execution finishes: the underlying `GenServer.call` uses an `:infinity` timeout, so a long chain of retries never produces a call timeout — the caller waits as long as the retry schedule takes.
- `func` is expected to return either `{:ok, value}` or `{:error, reason}`. Those are the only two shapes the contract covers; `value` and `reason` may be any term (including `nil`).
- Exactly two return shapes come back from `execute/3`:
  - `{:ok, value}` — some attempt returned `{:ok, value}`; `value` is passed through untouched.
  - `{:error, :max_retries_exceeded, reason}` — every allowed attempt failed. `reason` is the reason from the **last** failing attempt: the `reason` in its `{:error, reason}`, or `:timeout` if that last attempt hit `:attempt_timeout_ms`.
- Unknown keys in `opts` are ignored; each key falls back to its default independently, so partial option lists are fine.
- Options are per-call, not per-server: two concurrent executions may use completely different `:max_retries`, delays, and timeouts.

### Attempt counting

- Attempts are 0-indexed. Attempt `0` is the initial try; attempt `N` is the Nth retry.
- After a failing attempt `N`, a retry is scheduled only while `N < max_retries`; once `N` reaches `max_retries` the execution is exhausted and the caller is replied to immediately, with no further delay.
- So the total number of times `func` can be invoked is `max_retries + 1`. Boundary cases:
  - `max_retries: 0` → `func` runs exactly once; a failure replies `{:error, :max_retries_exceeded, reason}` right away, with no backoff wait and no call to the `:random` function.
  - `max_retries: 3` (the default) → up to 4 invocations, with retries scheduled after attempts 0, 1 and 2.
  - A success on any attempt ends the execution immediately; no further attempts and no further delays.

### Delay and jitter

- The delay for the retry that will become attempt `N` (i.e. scheduled after attempt `N-1` failed) is `min(base_delay_ms * 2^(N-1), max_delay_ms)`. First retry (attempt 1) therefore waits `min(base_delay_ms, max_delay_ms)`, the second `min(base_delay_ms * 2, max_delay_ms)`, and so on.
- The exponent must be clamped so that very high attempt numbers cannot blow up into an astronomically large intermediate value; the growth saturates at `max_delay_ms` regardless.
- Jitter: the `:random` function is called with the computed `delay` and its return value is added, so the total wait is `delay + jitter`. Guard the degenerate case — when `delay` is `0` (e.g. `base_delay_ms: 0`, or `max_delay_ms: 0`), the `:random` function must **not** be called and the jitter is `0`, giving a total wait of `0`.
- With a deterministic injected `:random`, the total wait for each retry must be exactly reproducible from the formula above.

### Failure handling and concurrency

- A timed-out attempt is shut down (not left running) before its failure is processed, and its failure reason for both retry purposes and the final `{:error, :max_retries_exceeded, :timeout}` is `:timeout`.
- If an attempt process exits abnormally, the worker itself must stay alive: the execution's monitor bookkeeping is cleaned up and the failure is treated as a retryable error whose reason is `{:task_crashed, exit_reason}`; if it is the last allowed attempt, that same term is the `reason` in `{:error, :max_retries_exceeded, {:task_crashed, exit_reason}}`.
- The server keeps one independent record per in-flight execution, keyed so that results and monitor messages are routed back to the right caller. A stray result or `:DOWN` message for an execution the server no longer tracks is ignored — it must not crash the server and must not produce a duplicate reply.
- Each caller receives exactly one reply, delivered via `GenServer.reply/2`. Replies come back in completion order, not call order: an execution that succeeds on attempt 0 replies before one that is still waiting out a backoff, even if the latter was called first. No caller's backoff wait may delay another caller's reply — the waiting happens through `Process.send_after`, never by sleeping in a callback.
- The server is stateless with respect to completed executions: calling `execute/3` again on the same server behaves identically to the first call, with attempt counters and backoff starting over from zero.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `init` missing

```elixir
defmodule TimeoutRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff, jitter,
  and per-attempt timeouts enforced via Task.yield/Task.shutdown.

  Each attempt runs inside a supervised, unlinked Task so that an abnormal
  exit in the user function cannot bring down the worker; such an exit is
  surfaced as a retryable `{:task_crashed, reason}` failure.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @doc "Starts the worker. Accepts `:name`, `:clock`, and `:random` options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Runs `func`, retrying on failure until the timeout in `opts`. Returns the result."
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :max_retries_exceeded, any()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  def init(opts) do
    # TODO
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    state = launch_attempt(func, 0, opts, from, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, func, attempt, opts, from}, state) do
    state = launch_attempt(func, attempt, opts, from, state)
    {:noreply, state}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    # Defensive: a stray result for an execution we no longer track is ignored.
    Process.demonitor(ref, [:flush])

    case Map.pop(state.tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {%{from: from, func: func, attempt: attempt, opts: opts}, new_tasks} ->
        state = %{state | tasks: new_tasks}
        handle_task_result(result, func, attempt, opts, from, state)
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {%{from: from, func: func, attempt: attempt, opts: opts}, new_tasks} ->
        state = %{state | tasks: new_tasks}
        handle_task_result({:error, {:task_crashed, reason}}, func, attempt, opts, from, state)
    end
  end

  # --- Private Helpers ---

  defp launch_attempt(func, attempt, opts, from, state) do
    timeout = Keyword.get(opts, :attempt_timeout_ms, 5_000)

    task = Task.Supervisor.async_nolink(state.supervisor, fn -> func.() end)

    outcome =
      case Task.yield(task, timeout) do
        {:ok, result} ->
          result

        {:exit, reason} ->
          {:error, {:task_crashed, reason}}

        nil ->
          _ = Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end

    {_, state} = handle_task_result_sync(outcome, func, attempt, opts, from, state)
    state
  end

  defp handle_task_result_sync(result, func, attempt, opts, from, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    case result do
      {:ok, value} ->
        GenServer.reply(from, {:ok, value})
        {:ok, state}

      {:error, reason} ->
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :max_retries_exceeded, reason})
          {:exhausted, state}
        else
          schedule_retry(func, attempt + 1, opts, from, state)
          {:retrying, state}
        end
    end
  end

  defp handle_task_result(result, func, attempt, opts, from, state) do
    {_, new_state} = handle_task_result_sync(result, func, attempt, opts, from, state)
    {:noreply, new_state}
  end

  defp schedule_retry(func, next_attempt, opts, from, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    n = next_attempt - 1
    shift = min(n, 50)
    delay = min(base_delay <<< shift, max_delay)

    jitter = if delay > 0, do: state.random.(delay), else: 0
    total_wait = delay + jitter

    Process.send_after(self(), {:retry, func, next_attempt, opts, from}, total_wait)
  end
end
```

Give me only the complete implementation of `init` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
