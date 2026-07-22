Implement the private `do_execute/5` function. It receives `func` (the zero-arity
function to run), `attempt` (the current 0-indexed attempt number), `opts` (the
keyword list passed to `execute/3`), `from` (the GenServer caller to reply to), and
`state`.

Read `:max_retries` from `opts` (default `3`), then invoke `func.()` and branch on
its return shape:

- `{:ok, result}` — reply to the caller with `{:ok, result}` using `GenServer.reply/2`.
- `{:error, :permanent, reason}` — reply immediately with `{:error, :permanent, reason}`,
  performing no retries regardless of the remaining retry budget.
- `{:error, :transient, reason}` — a retryable failure. If `attempt` has reached
  `max_retries` (i.e. `attempt >= max_retries`), the retry budget is exhausted, so
  reply with `{:error, :retries_exhausted, reason}`. Otherwise schedule the next
  retry by calling `schedule_retry(func, attempt + 1, opts, from, reason, state)`.

`do_execute/5` does not return anything meaningful to its caller — replies happen via
`GenServer.reply/2` and retries via `schedule_retry/6`; the calling `handle_call`/
`handle_info` clauses respond with `{:noreply, state}`.

```elixir
defmodule ClassifiedRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff,
  classifying errors as transient (retryable) or permanent (non-retryable),
  with an optional on_retry callback.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Runs `func`, retrying classified errors per `opts`. Returns the result."
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()}
          | {:error, :permanent, any()}
          | {:error, :retries_exhausted, any()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  # Real-clock granularity of the tick-gated retry wait.
  @tick_ms 1

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    random = Keyword.get(opts, :random, fn max -> :rand.uniform(max) - 1 end)
    {:ok, %{clock: clock, random: random}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    do_execute(func, 0, opts, from, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry_at, func, attempt, opts, from, target}, state) do
    # Tick-gated wait: re-tick until the injected clock reaches the target,
    # so a fake clock drives retries deterministically while the server keeps
    # serving other callers between ticks.
    if state.clock.() >= target do
      do_execute(func, attempt, opts, from, state)
    else
      Process.send_after(self(), {:retry_at, func, attempt, opts, from, target}, @tick_ms)
    end

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp do_execute(func, attempt, opts, from, state) do
    # TODO
  end

  defp schedule_retry(func, next_attempt, opts, from, reason, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)
    on_retry = Keyword.get(opts, :on_retry)

    n = next_attempt - 1
    shift = min(n, 50)
    delay = min(base_delay <<< shift, max_delay)

    jitter = if delay > 0, do: state.random.(delay), else: 0
    total_wait = delay + jitter

    # Invoke on_retry callback if provided
    if on_retry, do: on_retry.(next_attempt, reason, total_wait)

    target = state.clock.() + total_wait
    Process.send_after(self(), {:retry_at, func, next_attempt, opts, from, target}, @tick_ms)
  end
end
```