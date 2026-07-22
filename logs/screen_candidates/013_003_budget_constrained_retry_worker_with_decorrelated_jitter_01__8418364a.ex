defmodule BudgetRetryWorker do
  @moduledoc """
  A `GenServer` that runs a zero-arity function with retries governed by a
  total wall-clock **time budget** and **decorrelated jitter** backoff.

  ## Behaviour

  `execute/3` invokes the supplied function inside the worker process.

    * `{:ok, result}` is returned to the caller immediately.
    * `{:error, reason}` schedules a retry — provided the budget allows it.

  The backoff is AWS-style *decorrelated jitter*. A per-execution `prev_delay`
  starts at `:base_delay_ms`; every retry computes

      next_delay   = random(base_delay_ms, prev_delay * 3)
      capped_delay = min(next_delay, max_delay_ms)

  and `capped_delay` becomes both the wait and the new `prev_delay`.

  Before scheduling, the worker checks whether
  `elapsed_since_start + capped_delay > budget_ms`. If so, no retry is
  scheduled and the caller receives
  `{:error, :budget_exhausted, reason, attempts}` right away.

  Retries are scheduled with `Process.send_after/3` and callers are answered
  with `GenServer.reply/2`, so the worker never blocks while waiting out a
  backoff. Many concurrent `execute/3` calls are tracked independently.

  Time and randomness are injectable (`:clock`, `:random`) which makes the
  backoff schedule fully deterministic under test.
  """

  use GenServer

  @default_budget_ms 30_000
  @default_base_delay_ms 100
  @default_max_delay_ms 10_000

  @typedoc "Zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  @typedoc "Two-arity function returning a random integer in `min..max`."
  @type random :: (integer(), integer() -> integer())

  @typedoc "Zero-arity function attempted by `execute/3`."
  @type task_fun :: (-> {:ok, term()} | {:error, term()})

  @typedoc "Result of an `execute/3` call."
  @type execute_result :: {:ok, term()} | {:error, :budget_exhausted, term(), pos_integer()}

  defmodule Execution do
    @moduledoc false

    @enforce_keys [
      :from,
      :func,
      :started_at,
      :budget_ms,
      :base_delay_ms,
      :max_delay_ms,
      :prev_delay,
      :attempts
    ]
    defstruct [
      :from,
      :func,
      :started_at,
      :budget_ms,
      :base_delay_ms,
      :max_delay_ms,
      :prev_delay,
      :attempts
    ]
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the worker.

  ## Options

    * `:clock` — zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:random` — two-arity function `(min, max)` returning a random integer in
      `min..max`. Defaults to a `:rand`-backed uniform draw.
    * `:name` — optional name used to register the process.

  Any other option is forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {clock, opts} = Keyword.pop(opts, :clock, &default_clock/0)
    {random, opts} = Keyword.pop(opts, :random, &default_random/2)
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: Keyword.put(opts, :name, name), else: opts

    GenServer.start_link(__MODULE__, %{clock: clock, random: random}, server_opts)
  end

  @doc """
  Runs `func` on `server`, retrying failures until it succeeds or the time
  budget is exhausted.

  The call blocks the caller (but not the worker) until a final answer is
  available.

  ## Options

    * `:budget_ms` — total wall-clock time allowed, measured from the first
      attempt. Defaults to `#{@default_budget_ms}`.
    * `:base_delay_ms` — lower bound of the jitter window and the initial
      `prev_delay`. Defaults to `#{@default_base_delay_ms}`.
    * `:max_delay_ms` — upper bound applied to every computed delay. Defaults
      to `#{@default_max_delay_ms}`.

  Returns `{:ok, result}` on success, or
  `{:error, :budget_exhausted, last_reason, attempts}` when the budget runs out.
  """
  @spec execute(GenServer.server(), task_fun(), keyword()) :: execute_result()
  def execute(server, func, opts \\ []) when is_function(func, 0) and is_list(opts) do
    budget_ms = Keyword.get(opts, :budget_ms, @default_budget_ms)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, @default_base_delay_ms)
    max_delay_ms = Keyword.get(opts, :max_delay_ms, @default_max_delay_ms)

    config = %{
      budget_ms: budget_ms,
      base_delay_ms: base_delay_ms,
      max_delay_ms: max_delay_ms
    }

    GenServer.call(server, {:execute, func, config}, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @doc false
  @impl GenServer
  def init(%{clock: clock, random: random}) do
    {:ok, %{clock: clock, random: random, executions: %{}, next_ref: 0}}
  end

  @doc false
  @impl GenServer
  def handle_call({:execute, func, config}, from, state) do
    execution = %Execution{
      from: from,
      func: func,
      started_at: state.clock.(),
      budget_ms: config.budget_ms,
      base_delay_ms: config.base_delay_ms,
      max_delay_ms: config.max_delay_ms,
      prev_delay: config.base_delay_ms,
      attempts: 0
    }

    {:noreply, attempt(execution, state)}
  end

  @doc false
  @impl GenServer
  def handle_info({:retry, id}, state) do
    case Map.pop(state.executions, id) do
      {nil, _executions} ->
        {:noreply, state}

      {execution, executions} ->
        {:noreply, attempt(execution, %{state | executions: executions})}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp attempt(%Execution{} = execution, state) do
    execution = %{execution | attempts: execution.attempts + 1}

    case safe_call(execution.func) do
      {:ok, result} ->
        GenServer.reply(execution.from, {:ok, result})
        state

      {:error, reason} ->
        maybe_schedule_retry(execution, reason, state)
    end
  end

  defp safe_call(func) do
    case func.() do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_return, other}}
    end
  end

  defp maybe_schedule_retry(%Execution{} = execution, reason, state) do
    capped_delay = next_delay(execution, state.random)
    elapsed = state.clock.() - execution.started_at

    if elapsed + capped_delay > execution.budget_ms do
      GenServer.reply(
        execution.from,
        {:error, :budget_exhausted, reason, execution.attempts}
      )

      state
    else
      id = state.next_ref
      execution = %{execution | prev_delay: capped_delay}
      Process.send_after(self(), {:retry, id}, capped_delay)

      %{
        state
        | executions: Map.put(state.executions, id, execution),
          next_ref: id + 1
      }
    end
  end

  defp next_delay(%Execution{} = execution, random) do
    min = execution.base_delay_ms
    max = Kernel.max(min, execution.prev_delay * 3)

    random.(min, max)
    |> Kernel.min(execution.max_delay_ms)
    |> Kernel.max(0)
  end

  defp default_clock, do: System.monotonic_time(:millisecond)

  defp default_random(min, max), do: min + :rand.uniform(max - min + 1) - 1
end