defmodule BudgetRetryWorker do
  @moduledoc """
  A GenServer that executes functions with retries governed by a total time
  budget and decorrelated jitter (AWS-style backoff).

  The supplied function runs inside the GenServer process. Retries are scheduled
  with `Process.send_after/3` so the server never blocks other callers while a
  given execution is waiting for its next attempt. Waiting is driven by the
  injected `:clock`, allowing deterministic, time-controlled testing.
  """

  use GenServer

  @poll_interval 1

  # --- Public API ---

  @doc """
  Starts the worker.

  Options:

    * `:clock` — zero-arity fun returning the current time in milliseconds
      (defaults to monotonic time).
    * `:random` — two-arity fun `(min, max)` returning an integer in `min..max`.
    * `:name` — optional process registration name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Runs `func`, retrying with decorrelated-jitter backoff until it succeeds or the
  time budget in `opts` is exhausted. Blocks the caller until a result is known.
  """
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
    base_delay = Keyword.get(opts, :base_delay_ms, 100)

    exec = %{
      from: from,
      func: func,
      started_at: state.clock.(),
      base_delay: base_delay,
      budget: Keyword.get(opts, :budget_ms, 30_000),
      max_delay: Keyword.get(opts, :max_delay_ms, 10_000),
      prev_delay: base_delay,
      attempts: 0
    }

    run_attempt(exec, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:poll, exec}, state) do
    if state.clock.() >= exec.target do
      run_attempt(Map.delete(exec, :target), state)
    else
      Process.send_after(self(), {:poll, exec}, @poll_interval)
    end

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp run_attempt(exec, state) do
    exec = %{exec | attempts: exec.attempts + 1}

    case exec.func.() do
      {:ok, result} ->
        GenServer.reply(exec.from, {:ok, result})

      {:error, reason} ->
        schedule_or_exhaust(exec, reason, state)
    end

    :ok
  end

  defp schedule_or_exhaust(exec, reason, state) do
    now = state.clock.()
    elapsed = now - exec.started_at

    jitter_max = exec.prev_delay * 3
    next_delay = state.random.(exec.base_delay, jitter_max)
    capped_delay = min(next_delay, exec.max_delay)

    if elapsed + capped_delay > exec.budget do
      GenServer.reply(exec.from, {:error, :budget_exhausted, reason, exec.attempts})
    else
      next_exec = %{exec | prev_delay: capped_delay, target: now + capped_delay}
      Process.send_after(self(), {:poll, next_exec}, @poll_interval)
    end
  end
end
