# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir GenServer module called `RetryScheduler` that executes **one-shot** jobs at a specified future time, retrying with exponential backoff if the job fails.

The motivation: unlike a recurring scheduler, a retry scheduler runs each job a bounded number of times — once on the scheduled time, then up to N-1 retries on failure, with each retry delayed by an increasing backoff. Once the job either succeeds or exhausts its retry budget, it enters a terminal state and is kept in the registry for inspection but never re-executed.

I need these functions in the public API:

- `RetryScheduler.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime`. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) for the `Process.send_after(self(), :tick, ...)` period. Setting it to `:infinity` disables auto-ticking (useful for testing).

- `RetryScheduler.schedule(server, name, run_at, {mod, fun, args}, opts \\ [])` where:
  - `name` is a unique string or atom identifier for the job
  - `run_at` is a `NaiveDateTime` specifying when the first attempt should happen
  - The mfa tuple is what gets invoked
  - `opts` may contain `:max_attempts` (default 3), `:base_delay_ms` (default 1_000), and `:backoff_factor` (default 2.0, must be >= 1.0)

  Returns `:ok` on success, `{:error, :already_exists}` if the name is taken, or `{:error, :invalid_opts}` if any option is out of range. A job scheduled with run_at in the past is still valid — it will fire on the next tick whose clock time is >= run_at.

- `RetryScheduler.cancel(server, name)` — removes a job from the registry if it exists. Returns `:ok` or `{:error, :not_found}`. Cancellation is valid in any state, including terminal states (:completed, :dead); the job is simply removed.

- `RetryScheduler.status(server, name)` — returns `{:ok, status, attempts_so_far}` where `status` is one of `:pending` (not yet attempted, or currently waiting for a retry), `:completed` (successful attempt), or `:dead` (exhausted retry budget). Returns `{:error, :not_found}` if no such job.

- `RetryScheduler.jobs(server)` — returns a list of `{name, status, next_attempt_at, attempts_so_far}` tuples for all jobs. Jobs in `:completed` or `:dead` state still have a `next_attempt_at` value, which refers to the attempt that ultimately succeeded or failed.

On each `:tick` message, the scheduler should:
1. Read `now` from the clock.
2. Find all jobs where `status == :pending` AND `next_attempt_at <= now`. Jobs in `:completed` or `:dead` are never re-picked.
3. For each due job, execute `apply(mod, fun, args)` inside a try/rescue/catch and classify the outcome:
   - Return value is `:ok` or matches `{:ok, _}` → **success**
   - Return value is `:error` or matches `{:error, _}` → **failure**
   - Function raises an exception → **failure**
   - Function throws → **failure**
   - Any other return value → **failure**
4. Update the job's state:
   - Always increment `attempts_so_far` by 1.
   - On success: set `status = :completed`.
   - On failure, if `attempts_so_far >= max_attempts`: set `status = :dead`.
   - On failure, if `attempts_so_far < max_attempts`: keep `status = :pending`, set `next_attempt_at = now + delay_ms` where `delay_ms = round(base_delay_ms * backoff_factor ^ (attempts_so_far - 1))`. In other words, the first retry (after the 1st failure, attempts_so_far becomes 1) waits `base_delay_ms`. The second retry waits `base_delay_ms * backoff_factor`. The third waits `base_delay_ms * backoff_factor^2`, etc.
5. Schedule the next tick if `tick_interval_ms != :infinity`.

Important: `max_attempts` is the **total** number of attempts, not the number of retries. If `max_attempts: 3`, the job will be attempted at most 3 times total (1 initial + 2 retries). A job that succeeds on its first attempt never enters backoff.

Each job's state should include at minimum: `mfa`, `status`, `attempts_so_far`, `next_attempt_at`, `max_attempts`, `base_delay_ms`, `backoff_factor`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The buggy module

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

  Retry delays grow geometrically:
  `delay_ms = base_delay_ms * backoff_factor^(attempts_so_far - 1)`.
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

  @spec schedule(
          GenServer.server(),
          term(),
          NaiveDateTime.t(),
          {module(), atom(), list()},
          keyword()
        ) ::
          :ok | {:error, :already_exists | :invalid_opts}
  @doc """
  Schedules `mfa` to run at `run_at` under `job_name`, retrying with geometric backoff
  per `opts`. Returns `:ok` or `{:error, :already_scheduled}`.
  """
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
        {:reply, {:ok, :already_exists}, state}

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
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 1_000)
    backoff_factor = Keyword.get(opts, :backoff_factor, 2.0)

    cond do
      not is_integer(max_attempts) or max_attempts < 1 -> :error
      not is_integer(base_delay_ms) or base_delay_ms < 0 -> :error
      not is_number(backoff_factor) or backoff_factor < 1.0 -> :error
      true -> {:ok, max_attempts, base_delay_ms, backoff_factor * 1.0}
    end
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

## Failing test report

```
1 of 18 test(s) failed:

  * test duplicate name returns :already_exists
      
      
      match (=) failed
      code:  assert {:error, :already_exists} = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
      left:  {:error, :already_exists}
      right: {:ok, :already_exists}
```
