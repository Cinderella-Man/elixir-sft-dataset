Implement the private `do_attempt/9` function. It performs a single attempt of the
retry loop and recurses to perform subsequent attempts.

The function has the signature
`do_attempt(func, clock_fn, random_fn, started_at, base_delay, budget, max_delay, prev_delay, attempts)`.

It should first increment `attempts` (this attempt counts as one). Then it invokes the
zero-arity `func`:

- If `func` returns `{:ok, result}`, return `{:ok, result}` immediately.
- If `func` returns `{:error, reason}`, compute the current time by calling `clock_fn`
  and derive `elapsed = now - started_at`. Then compute the next decorrelated-jitter
  delay: set `jitter_max = prev_delay * 3`, draw `next_delay = random_fn.(base_delay, jitter_max)`,
  and cap it with `capped_delay = min(next_delay, max_delay)`.

  Before scheduling the retry, check whether `elapsed + capped_delay > budget`. If it
  would exceed the budget, do NOT retry — return `{:error, :budget_exhausted, reason, attempts}`.

  Otherwise, wait until `now + capped_delay` by calling `await_clock/2`, then recurse
  into `do_attempt/9` for the next attempt. On the recursive call, keep every argument
  the same except pass `capped_delay` as the new `prev_delay` and the incremented
  `attempts`.

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
    started_at = clock_fn.()
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    budget = Keyword.get(opts, :budget_ms, 30_000)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    do_attempt(func, clock_fn, random_fn, started_at, base_delay, budget, max_delay, base_delay, 0)
  end

  defp do_attempt(func, clock_fn, random_fn, started_at, base_delay, budget, max_delay, prev_delay, attempts) do
    # TODO
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