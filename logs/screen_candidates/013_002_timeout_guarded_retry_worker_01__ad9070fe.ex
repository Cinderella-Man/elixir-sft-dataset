defmodule TimeoutRetryWorker do
  @moduledoc """
  A `GenServer` that executes zero-arity functions with per-attempt timeouts,
  exponential backoff and randomized jitter between retries.

  Each attempt runs inside a freshly spawned `Task`, guarded with
  `Task.yield/2` + `Task.shutdown/2` so that a slow or hung function cannot
  block the worker. A failing attempt (an `{:error, reason}` return, a timeout,
  or an abnormal task exit) is retried until `:max_retries` is reached.

  The retry wait itself is implemented with `Process.send_after/3`, never with
  `:timer.sleep/1`, so the server stays responsive: many callers may have
  executions in flight concurrently and each is tracked independently. Callers
  block (with an `:infinity` call timeout) and are answered asynchronously via
  `GenServer.reply/2` in completion order.

  ## Injection points

  Two dependencies can be injected at `start_link/1` time to make behaviour
  deterministic under test:

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
      It is retained for the lifetime of the process but is not used to
      implement the delay (`Process.send_after/3` does the waiting).
    * `:random` — a one-arity function taking a positive integer `max` and
      returning an integer in `0..max-1`. Defaults to
      `fn max -> :rand.uniform(max) - 1 end`. This is the only source of jitter.

  ## Backoff

  The retry that becomes attempt `n` (attempts are 0-indexed; attempt `0` is the
  initial try) waits:

      delay  = min(base_delay_ms * 2 ** (n - 1), max_delay_ms)
      jitter = if delay == 0, do: 0, else: random.(delay)
      wait   = delay + jitter

  The exponent is clamped so huge attempt counts cannot produce astronomically
  large intermediate values; growth saturates at `:max_delay_ms` anyway.
  """

  use GenServer

  @default_max_retries 3
  @default_base_delay_ms 100
  @default_max_delay_ms 10_000
  @default_attempt_timeout_ms 5_000

  # Clamp for `2 ** exponent` so that absurd attempt numbers cannot blow up into
  # gigantic intermediate integers. 2 ** 62 already dwarfs any sane :max_delay_ms.
  @max_exponent 62

  @typedoc "Result of the user-supplied function."
  @type func_result :: {:ok, term()} | {:error, term()}

  @typedoc "The zero-arity function executed (and retried) by the worker."
  @type func :: (-> func_result())

  @typedoc "Per-call options accepted by `execute/3`."
  @type execute_opt ::
          {:max_retries, non_neg_integer()}
          | {:base_delay_ms, non_neg_integer()}
          | {:max_delay_ms, non_neg_integer()}
          | {:attempt_timeout_ms, non_neg_integer()}

  @typedoc "Options accepted by `start_link/1`."
  @type start_opt ::
          {:clock, (-> integer())}
          | {:random, (pos_integer() -> non_neg_integer())}
          | {:name, GenServer.name()}

  @typedoc "Value returned by `execute/3`."
  @type execute_result :: {:ok, term()} | {:error, :max_retries_exceeded, term()}

  defmodule Execution do
    @moduledoc false

    @enforce_keys [:id, :from, :func, :opts]
    defstruct [
      :id,
      :from,
      :func,
      :opts,
      attempt: 0,
      task: nil,
      monitor_ref: nil,
      last_reason: nil
    ]
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the worker.

  Supported options:

    * `:clock` — zero-arity function returning milliseconds. Defaults to
      `fn -> System.monotonic_time(:millisecond) end`.
    * `:random` — one-arity function taking `max` and returning an integer in
      `0..max-1`. Defaults to `fn max -> :rand.uniform(max) - 1 end`.
    * `:name` — optional registration name.

  Any other key is ignored. Returns whatever `GenServer.start_link/3` returns.
  """
  @spec start_link([start_opt()]) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Runs `func` on the worker, retrying failures with exponential backoff.

  `func` must return `{:ok, value}` or `{:error, reason}`. Each attempt is run in
  a `Task` bounded by `:attempt_timeout_ms`; a timeout is shut down and treated
  as a failure with reason `:timeout`, and an abnormal task exit is treated as a
  failure with reason `{:task_crashed, exit_reason}`.

  Options (all per-call, unknown keys ignored):

    * `:max_retries` — retries after the initial attempt (default `3`), so `func`
      may be invoked up to `max_retries + 1` times.
    * `:base_delay_ms` — base backoff unit (default `100`).
    * `:max_delay_ms` — backoff ceiling before jitter (default `10_000`).
    * `:attempt_timeout_ms` — per-attempt timeout (default `5_000`).

  The caller blocks (call timeout `:infinity`) until the execution finishes and
  receives exactly one of:

    * `{:ok, value}` — some attempt succeeded; `value` is passed through as-is.
    * `{:error, :max_retries_exceeded, reason}` — every allowed attempt failed;
      `reason` is the last failing attempt's reason.
  """
  @spec execute(GenServer.server(), func(), [execute_opt()]) :: execute_result()
  def execute(server, func, opts \\ []) when is_function(func, 0) and is_list(opts) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      random: Keyword.get(opts, :random, fn max -> :rand.uniform(max) - 1 end),
      executions: %{},
      next_id: 1
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:execute, func, opts}, from, state) do
    id = state.next_id

    execution = %Execution{
      id: id,
      from: from,
      func: func,
      opts: normalize_opts(opts),
      attempt: 0
    }

    state = %{state | next_id: id + 1, executions: Map.put(state.executions, id, execution)}

    # Kick off attempt 0 asynchronously so the caller is never blocked in-callback.
    send(self(), {:attempt, id})

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:attempt, id}, state) do
    case Map.fetch(state.executions, id) do
      {:ok, execution} -> {:noreply, run_attempt(execution, state)}
      :error -> {:noreply, state}
    end
  end

  def handle_info({:attempt_result, id, ref, result}, state) do
    case Map.fetch(state.executions, id) do
      {:ok, %Execution{monitor_ref: ^ref} = execution} ->
        {:noreply, handle_attempt_result(execution, result, state)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case find_by_monitor(state.executions, ref) do
      {:ok, execution} ->
        state = demonitor_execution(execution, state)

        case reason do
          :normal ->
            # The task's own result message (if any) already carries the outcome.
            {:noreply, state}

          other ->
            {:noreply, handle_failure(execution, {:task_crashed, other}, state)}
        end

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ----------------------------------------------------------------------------
  # Attempt execution
  # ----------------------------------------------------------------------------

  defp run_attempt(%Execution{} = execution, state) do
    timeout = execution.opts.attempt_timeout_ms
    task = Task.async(execution.func)
    execution = %{execution | task: task, monitor_ref: task.ref}
    state = put_execution(execution, state)

    case Task.yield(task, timeout) do
      {:ok, {:ok, value}} ->
        state = demonitor_execution(execution, state)
        complete(execution, {:ok, value}, state)

      {:ok, {:error, reason}} ->
        state = demonitor_execution(execution, state)
        handle_failure(execution, reason, state)

      {:exit, exit_reason} ->
        state = demonitor_execution(execution, state)
        handle_failure(execution, {:task_crashed, exit_reason}, state)

      nil ->
        _ = Task.shutdown(task, :brutal_kill)
        state = demonitor_execution(execution, state)
        handle_failure(execution, :timeout, state)
    end
  end

  defp handle_attempt_result(%Execution{} = execution, {:ok, value}, state) do
    complete(execution, {:ok, value}, state)
  end

  defp handle_attempt_result(%Execution{} = execution, {:error, reason}, state) do
    handle_failure(execution, reason, state)
  end

  defp handle_failure(%Execution{} = execution, reason, state) do
    execution = %{execution | last_reason: reason, task: nil, monitor_ref: nil}

    if execution.attempt < execution.opts.max_retries do
      next_attempt = execution.attempt + 1
      wait = backoff_wait(next_attempt, execution.opts, state.random)
      execution = %{execution | attempt: next_attempt}
      state = put_execution(execution, state)
      _timer = Process.send_after(self(), {:attempt, execution.id}, wait)
      state
    else
      complete(execution, {:error, :max_retries_exceeded, reason}, state)
    end
  end

  defp complete(%Execution{} = execution, reply, state) do
    state = %{state | executions: Map.delete(state.executions, execution.id)}
    GenServer.reply(execution.from, reply)
    state
  end

  # ----------------------------------------------------------------------------
  # Backoff & jitter
  # ----------------------------------------------------------------------------

  defp backoff_wait(attempt, opts, random) when attempt >= 1 do
    exponent = min(attempt - 1, @max_exponent)
    delay = min(opts.base_delay_ms * Integer.pow(2, exponent), opts.max_delay_ms)
    delay = max(delay, 0)
    delay + jitter(delay, random)
  end

  defp jitter(0, _random), do: 0
  defp jitter(delay, random) when delay > 0, do: random.(delay)

  # ----------------------------------------------------------------------------
  # Bookkeeping helpers
  # ----------------------------------------------------------------------------

  defp normalize_opts(opts) do
    %{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, @default_base_delay_ms),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, @default_max_delay_ms),
      attempt_timeout_ms: Keyword.get(opts, :attempt_timeout_ms, @default_attempt_timeout_ms)
    }
  end

  defp put_execution(%Execution{} = execution, state) do
    %{state | executions: Map.put(state.executions, execution.id, execution)}
  end

  defp find_by_monitor(executions, ref) do
    Enum.reduce_while(executions, :error, fn
      {_id, %Execution{monitor_ref: ^ref} = execution}, _acc -> {:halt, {:ok, execution}}
      _entry, acc -> {:cont, acc}
    end)
  end

  defp demonitor_execution(%Execution{monitor_ref: nil} = _execution, state), do: state

  defp demonitor_execution(%Execution{} = execution, state) do
    Process.demonitor(execution.monitor_ref, [:flush])
    put_execution(%{execution | monitor_ref: nil}, state)
  end
end