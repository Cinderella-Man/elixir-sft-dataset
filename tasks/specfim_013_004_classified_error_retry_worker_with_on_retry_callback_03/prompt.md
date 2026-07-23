# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`execute/3` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `execute/3` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `execute/3` missing

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
  # TODO: @spec
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
    max_retries = Keyword.get(opts, :max_retries, 3)

    case func.() do
      {:ok, result} ->
        GenServer.reply(from, {:ok, result})

      {:error, :permanent, reason} ->
        GenServer.reply(from, {:error, :permanent, reason})

      {:error, :transient, reason} ->
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :retries_exhausted, reason})
        else
          schedule_retry(func, attempt + 1, opts, from, reason, state)
        end
    end
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

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
