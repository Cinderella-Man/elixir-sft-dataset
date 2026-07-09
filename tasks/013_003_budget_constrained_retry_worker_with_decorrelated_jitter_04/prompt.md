The `BudgetRetryWorker` GenServer executes a zero-arity function with retries
governed by a total time budget and decorrelated jitter (AWS-style backoff).
Implement the private `retry_loop/4` function.

`retry_loop(func, opts, clock_fn, random_fn)` drives a single `execute` call to
completion. It must:

1. Record the execution's start time by calling the injected `clock_fn` (a
   zero-arity function returning the current time in milliseconds) and remember
   it as `started_at`.
2. Read the per-execution options from the `opts` keyword list, applying
   defaults: `:base_delay_ms` (default `100`), `:budget_ms` (default `30_000`),
   and `:max_delay_ms` (default `10_000`).
3. Kick off the attempt loop by delegating to `do_attempt/9`, seeding the
   `prev_delay` argument with the base delay and the `attempts` counter with `0`.

It returns whatever `do_attempt/9` returns — either `{:ok, result}` on success or
`{:error, :budget_exhausted, reason, attempts}` when the budget runs out.

```elixir
defmodule BudgetRetryWorker do
  @moduledoc """
  A GenServer that executes functions with retries governed by a total time
  budget and decorrelated jitter (AWS-style backoff).
  """

  use GenServer

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :budget_exhausted, any(), pos_integer()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    random =
      Keyword.get(opts, :random, fn min, max ->
        min + :rand.uniform(max - min + 1) - 1
      end)

    {:ok, %{clock: clock, random: random}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    clock_fn = state.clock
    random_fn = state.random

    spawn_link(fn ->
      result = retry_loop(func, opts, clock_fn, random_fn)
      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp retry_loop(func, opts, clock_fn, random_fn) do
    # TODO
  end

  defp do_attempt(
         func,
         clock_fn,
         random_fn,
         started_at,
         base_delay,
         budget,
         max_delay,
         prev_delay,
         attempts
       ) do
    attempts = attempts + 1

    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        now = clock_fn.()
        elapsed = now - started_at

        jitter_max = prev_delay * 3
        next_delay = random_fn.(base_delay, jitter_max)
        capped_delay = min(next_delay, max_delay)

        if elapsed + capped_delay > budget do
          {:error, :budget_exhausted, reason, attempts}
        else
          target_time = now + capped_delay
          await_clock(target_time, clock_fn)

          do_attempt(
            func,
            clock_fn,
            random_fn,
            started_at,
            base_delay,
            budget,
            max_delay,
            capped_delay,
            attempts
          )
        end
    end
  end

  defp await_clock(target_time, clock_fn) do
    if clock_fn.() < target_time do
      receive do
      after
        0 -> await_clock(target_time, clock_fn)
      end
    end
  end
end
```