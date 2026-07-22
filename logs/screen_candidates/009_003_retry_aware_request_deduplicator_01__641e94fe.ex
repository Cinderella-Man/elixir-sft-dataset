defmodule RetryDedup do
  @moduledoc """
  A GenServer that deduplicates concurrent identical requests and retries
  failed executions with exponential backoff before returning to callers.

  Like a standard request coalescer, only one execution runs per key at a
  time: the first caller for a key triggers an asynchronous execution while
  every concurrent caller for the same key joins a shared wait list. When the
  execution finally settles (success or exhausted retries), all waiting callers
  receive the same normalised result and the key is cleared so that later calls
  start a fresh execution.

  The user-supplied function is never run inside `handle_call/3`; it always runs
  in a spawned process so the GenServer stays responsive.
  """

  use GenServer

  @type server :: GenServer.server()
  @type key :: term()
  @type result :: {:ok, term()} | {:error, term()}

  @default_max_retries 3
  @default_base_delay_ms 100
  @default_max_delay_ms 5000

  # Internal per-key execution state.
  #
  #   * `:waiters`       - list of `GenServer.from()` awaiting the result
  #   * `:func`          - the zero-arity function to (re)run
  #   * `:ref`           - generation reference matching tasks/timers
  #   * `:attempt`       - number of retries scheduled so far (0 during the
  #                        initial attempt, 1-based once retries begin)
  #   * `:max_retries`   - maximum retries after the initial failure
  #   * `:base_delay_ms` - initial backoff delay
  #   * `:max_delay_ms`  - cap on the backoff delay

  @doc """
  Starts the deduplicating retry server.

  Accepts a `:name` option that is used for process registration; all other
  options are ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, gen_opts)
  end

  @doc """
  Executes `func` for `key`, deduplicating and retrying as needed.

  If no execution is in flight for `key`, `func` is run asynchronously and the
  caller blocks until a final result is available. If an execution (or its
  retry sequence) is already in progress for `key`, the caller joins the wait
  list without triggering another execution.

  ## Options

    * `:max_retries` - maximum retry attempts after the initial failure
      (default `#{@default_max_retries}`)
    * `:base_delay_ms` - initial retry delay in milliseconds
      (default `#{@default_base_delay_ms}`)
    * `:max_delay_ms` - cap on the retry delay in milliseconds
      (default `#{@default_max_delay_ms}`)

  ## Return values

  `{:ok, value}` and `{:error, reason}` returned by `func` are passed through
  unchanged. Any other term `v` is normalised to `{:ok, v}`. A raised exception
  is treated as `{:error, {:exception, exception}}` for retry purposes.
  """
  @spec execute(server(), key(), (-> term()), keyword()) :: result()
  def execute(server, key, func, opts \\ []) when is_function(func, 0) and is_list(opts) do
    GenServer.call(server, {:execute, key, func, opts}, :infinity)
  end

  @doc """
  Returns the current retry status for `key`.

  Returns `:idle` when no execution is in progress, or while the initial
  attempt is still running and no retry has yet been scheduled. Once at least
  one retry has been scheduled it returns `{:retrying, attempt, max_retries}`
  where `attempt` is 1-based, counting from the first retry.
  """
  @spec status(server(), key()) :: :idle | {:retrying, pos_integer(), non_neg_integer()}
  def status(server, key) do
    GenServer.call(server, {:status, key})
  end

  ## GenServer callbacks

  @impl true
  @spec init(term()) :: {:ok, %{executions: map()}}
  def init(_opts) do
    {:ok, %{executions: %{}}}
  end

  @impl true
  def handle_call({:execute, key, func, opts}, from, state) do
    case Map.get(state.executions, key) do
      nil ->
        ref = make_ref()

        exec = %{
          waiters: [from],
          func: func,
          ref: ref,
          attempt: 0,
          max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
          base_delay_ms: Keyword.get(opts, :base_delay_ms, @default_base_delay_ms),
          max_delay_ms: Keyword.get(opts, :max_delay_ms, @default_max_delay_ms)
        }

        run_task(key, ref, func)
        {:noreply, put_exec(state, key, exec)}

      exec ->
        exec = %{exec | waiters: [from | exec.waiters]}
        {:noreply, put_exec(state, key, exec)}
    end
  end

  @impl true
  def handle_call({:status, key}, _from, state) do
    reply =
      case Map.get(state.executions, key) do
        nil -> :idle
        %{attempt: 0} -> :idle
        %{attempt: attempt, max_retries: max} -> {:retrying, attempt, max}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info({:result, key, ref, outcome}, state) do
    case Map.get(state.executions, key) do
      %{ref: ^ref} = exec -> handle_outcome(key, exec, outcome, state)
      _other -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({:retry, key, ref}, state) do
    case Map.get(state.executions, key) do
      %{ref: ^ref, func: func} -> run_task(key, ref, func)
      _other -> :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  # Decides whether to reply to waiters or schedule another retry.
  @spec handle_outcome(key(), map(), result(), map()) :: {:noreply, map()}
  defp handle_outcome(key, exec, {:ok, _value} = ok, state) do
    reply_all(exec.waiters, ok)
    {:noreply, drop_exec(state, key)}
  end

  defp handle_outcome(key, exec, {:error, _reason} = err, state) do
    if exec.attempt < exec.max_retries do
      delay = backoff_delay(exec)
      Process.send_after(self(), {:retry, key, exec.ref}, delay)
      exec = %{exec | attempt: exec.attempt + 1}
      {:noreply, put_exec(state, key, exec)}
    else
      reply_all(exec.waiters, err)
      {:noreply, drop_exec(state, key)}
    end
  end

  # Computes `min(base_delay_ms * 2^attempt, max_delay_ms)` for the next retry,
  # where `attempt` is the number of retries already completed (0 on the first
  # failure).
  @spec backoff_delay(map()) :: non_neg_integer()
  defp backoff_delay(exec) do
    min(exec.base_delay_ms * Integer.pow(2, exec.attempt), exec.max_delay_ms)
  end

  # Spawns a process that runs `func`, normalises its outcome and reports back.
  @spec run_task(key(), reference(), (-> term())) :: pid()
  defp run_task(key, ref, func) do
    server = self()

    spawn(fn ->
      outcome =
        try do
          normalize(func.())
        rescue
          exception -> {:error, {:exception, exception}}
        end

      send(server, {:result, key, ref, outcome})
    end)
  end

  @spec normalize(term()) :: result()
  defp normalize({:ok, value}), do: {:ok, value}
  defp normalize({:error, reason}), do: {:error, reason}
  defp normalize(other), do: {:ok, other}

  @spec reply_all([GenServer.from()], result()) :: :ok
  defp reply_all(waiters, result) do
    Enum.each(waiters, fn from -> GenServer.reply(from, result) end)
  end

  @spec put_exec(map(), key(), map()) :: map()
  defp put_exec(state, key, exec) do
    %{state | executions: Map.put(state.executions, key, exec)}
  end

  @spec drop_exec(map(), key()) :: map()
  defp drop_exec(state, key) do
    %{state | executions: Map.delete(state.executions, key)}
  end
end