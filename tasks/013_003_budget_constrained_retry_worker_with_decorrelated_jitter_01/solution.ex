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
    started_at = state.clock.()
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    exec_state = %{started_at: started_at, prev_delay: base_delay, attempts: 0}
    do_execute(func, opts, from, exec_state, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, func, opts, from, exec_state}, state) do
    do_execute(func, opts, from, exec_state, state)
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp do_execute(func, opts, from, exec_state, state) do
    exec_state = %{exec_state | attempts: exec_state.attempts + 1}

    case func.() do
      {:ok, result} ->
        GenServer.reply(from, {:ok, result})

      {:error, reason} ->
        maybe_schedule_retry(func, opts, from, exec_state, reason, state)
    end
  end

  defp maybe_schedule_retry(func, opts, from, exec_state, reason, state) do
    budget = Keyword.get(opts, :budget_ms, 30_000)
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    now = state.clock.()
    elapsed = now - exec_state.started_at

    # Decorrelated jitter: random(base_delay, prev_delay * 3)
    jitter_max = exec_state.prev_delay * 3
    next_delay = state.random.(base_delay, jitter_max)
    capped_delay = min(next_delay, max_delay)

    if elapsed + capped_delay > budget do
      GenServer.reply(from, {:error, :budget_exhausted, reason, exec_state.attempts})
    else
      new_exec_state = %{exec_state | prev_delay: capped_delay}
      Process.send_after(self(), {:retry, func, opts, from, new_exec_state}, capped_delay)
    end
  end
end
