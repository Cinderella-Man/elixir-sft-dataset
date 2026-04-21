Implement the private `validate_opts/1` function. It should accept a keyword list of options and validate the configuration for a retry job.

Extract the following options, providing defaults if they are missing:
- `:max_attempts` (default: 3)
- `:base_delay_ms` (default: 1000)
- `:backoff_factor` (default: 2.0)

Validate these values against the following rules:
- `max_attempts` must be an integer greater than or equal to 1.
- `base_delay_ms` must be an integer greater than or equal to 0.
- `backoff_factor` must be a number (integer or float) greater than or equal to 1.0.

If all values are valid, return `{:ok, max_attempts, base_delay_ms, float_backoff_factor}`. Ensure the backoff factor is cast to a float in the return tuple (e.g., by multiplying it by 1.0).

If any of the validation rules fail, return `:error`.

```elixir
defmodule RetryScheduler do
  @moduledoc """
  A GenServer that runs **one-shot** jobs at a specified future time with
  exponential-backoff retries on failure.

  Each job has a bounded lifecycle:

      :pending  -(success)->   :completed  (terminal)
      :pending  -(failure, retries left)->  :pending (with later next_attempt_at)
      :pending  -(failure, no retries)->   :dead    (terminal)

  Terminal jobs remain in the registry for inspection via `status/2` and
  `jobs/1`.  They are never re-executed but can be removed via `cancel/2`.

  Retry delays grow geometrically: delay_ms = base_delay_ms * backoff_factor^(attempts_so_far - 1).
  So the first retry (after failure #1) waits `base_delay_ms`, the second
  retry waits `base_delay_ms * backoff_factor`, and so on.

  An attempt is classified as **success** when the mfa returns `:ok` or
  `{:ok, _}`.  Anything else — `:error`, `{:error, _}`, an unexpected return
  value, a raised exception, or a thrown value — counts as **failure**.

  ## Options

    * `:name`              – process registration name (optional)
    * `:clock`             – zero-arity function returning a `NaiveDateTime`
                             (default: `fn -> NaiveDateTime.utc_now() end`)
    * `:tick_interval_ms`  – polling interval in ms; `:infinity` disables
                             auto-ticking (default `1_000`)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec schedule(GenServer.server(), term(), NaiveDateTime.t(), {module(), atom(), list()}, keyword()) ::
          :ok | {:error, :already_exists | :invalid_opts}
  def schedule(server, job_name, %NaiveDateTime{} = run_at, {mod, fun, args} = mfa, opts \\ [])
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:schedule, job_name, run_at, mfa, opts})
  end

  @spec cancel(GenServer.server(), term()) :: :ok | {:error, :not_found}
  def cancel(server, job_name), do: GenServer.call(server, {:cancel, job_name})

  @spec status(GenServer.server(), term()) ::
          {:ok, :pending | :completed | :dead, non_neg_integer()}
          | {:error, :not_found}
  def status(server, job_name), do: GenServer.call(server, {:status, job_name})

  @spec jobs(GenServer.server()) ::
          [{term(), :pending | :completed | :dead, NaiveDateTime.t(), non_neg_integer()}]
  def jobs(server), do: GenServer.call(server, :jobs)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> NaiveDateTime.utc_now() end)
    tick_interval = Keyword.get(opts, :tick_interval_ms, 1_000)

    schedule_tick(tick_interval)

    {:ok,
     %{
       jobs: %{},
       clock: clock,
       tick_interval_ms: tick_interval
     }}
  end

  @impl true
  def handle_call({:schedule, name, run_at, mfa, opts}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        case validate_opts(opts) do
          {:ok, max_attempts, base_delay_ms, backoff_factor} ->
            job = %{
              mfa: mfa,
              status: :pending,
              attempts_so_far: 0,
              next_attempt_at: run_at,
              max_attempts: max_attempts,
              base_delay_ms: base_delay_ms,
              backoff_factor: backoff_factor
            }

            {:reply, :ok, %{state | jobs: Map.put(state.jobs, name, job)}}

          :error ->
            {:reply, {:error, :invalid_opts}, state}
        end
    end
  end

  def handle_call({:cancel, name}, _from, state) do
    case Map.pop(state.jobs, name) do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_, new_jobs} -> {:reply, :ok, %{state | jobs: new_jobs}}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, job} -> {:reply, {:ok, job.status, job.attempts_so_far}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:jobs, _from, state) do
    list =
      Enum.map(state.jobs, fn {name, j} ->
        {name, j.status, j.next_attempt_at, j.attempts_so_far}
      end)

    {:reply, list, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = state.clock.()

    new_jobs =
      Enum.reduce(state.jobs, %{}, fn {name, job}, acc ->
        updated =
          if job.status == :pending and NaiveDateTime.compare(job.next_attempt_at, now) != :gt do
            process_attempt(job, now)
          else
            job
          end

        Map.put(acc, name, updated)
      end)

    schedule_tick(state.tick_interval_ms)
    {:noreply, %{state | jobs: new_jobs}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Attempt processing — the heart of the retry logic
  # ---------------------------------------------------------------------------

  defp process_attempt(job, now) do
    outcome = safe_execute(job.mfa)
    attempts = job.attempts_so_far + 1

    case outcome do
      :success ->
        %{job | status: :completed, attempts_so_far: attempts, next_attempt_at: now}

      :failure when attempts >= job.max_attempts ->
        %{job | status: :dead, attempts_so_far: attempts, next_attempt_at: now}

      :failure ->
        delay_ms = round(job.base_delay_ms * :math.pow(job.backoff_factor, attempts - 1))
        next = NaiveDateTime.add(now, delay_ms, :millisecond)

        %{
          job
          | status: :pending,
            attempts_so_far: attempts,
            next_attempt_at: next
        }
    end
  end

  # Runs the mfa inside a try/rescue/catch and classifies the outcome.
  defp safe_execute({mod, fun, args}) do
    try do
      case apply(mod, fun, args) do
        :ok -> :success
        {:ok, _} -> :success
        _ -> :failure
      end
    rescue
      _ -> :failure
    catch
      _, _ -> :failure
    end
  end

  # ---------------------------------------------------------------------------
  # Option validation
  # ---------------------------------------------------------------------------

  defp validate_opts(opts) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp schedule_tick(:infinity), do: :ok
  defp schedule_tick(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :tick, ms)
  end
end
```