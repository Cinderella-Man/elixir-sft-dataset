# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `unregister` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `CalendarScheduler` that accepts job registrations with **calendar-aware rules** (rather than cron expressions) and executes them at the right times.

The motivation: cron can't express rules like "first Monday of every month" or "last weekday of the month" without complex workarounds. This module uses a small set of higher-level tuple-based rules that directly encode these common calendar patterns. Unlike cron, the next-run calculation can't scan minute-by-minute — it has to use calendar math.

I need these functions in the public API:

- `CalendarScheduler.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime`. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) for the `Process.send_after(self(), :tick, ...)` period. Setting it to `:infinity` disables auto-ticking.

- `CalendarScheduler.register(server, name, rule, {mod, fun, args})` registers a job with a calendar rule. Returns `:ok`, `{:error, :invalid_rule}`, or `{:error, :already_exists}`. The supported rule shapes are exactly these four tuples:

  1. `{:nth_weekday_of_month, n, weekday, {hour, minute}}` — e.g. `{:nth_weekday_of_month, 1, :monday, {9, 0}}` = first Monday of each month at 09:00. `n` must be an integer in 1..4, `weekday` must be one of `:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday`, `hour` in 0..23, `minute` in 0..59.

  2. `{:last_weekday_of_month, weekday, {hour, minute}}` — e.g. `{:last_weekday_of_month, :friday, {17, 0}}` = last Friday of each month at 17:00.

  3. `{:nth_day_of_month, day, {hour, minute}}` — e.g. `{:nth_day_of_month, 15, {12, 0}}` = the 15th of each month at noon. `day` must be in 1..31. If a given month doesn't have that day (e.g. February 31), that month is **skipped** — the next_run will be the next month in which the day exists.

  4. `{:last_day_of_month, {hour, minute}}` — the last calendar day of each month. Correctly handles 28/29/30/31-day months.

- `CalendarScheduler.unregister(server, name)` — removes a job. Returns `:ok` or `{:error, :not_found}`.

- `CalendarScheduler.jobs(server)` — returns a list of `{name, rule, next_run}` tuples.

- `CalendarScheduler.next_run(server, name)` — returns `{:ok, next_run_datetime}` or `{:error, :not_found}`.

**The next-run algorithm** must be calendar-walking, not minute-scanning:

1. Start with `{year, month}` from the current clock time.
2. Compute the rule's target datetime within that month (if one exists — `:nth_day_of_month, 31` in February does not). This is a pure calendar computation:
   - For `:nth_weekday_of_month, n, weekday`: find the 1st of the month, compute days until the first matching weekday (use ISO day-of-week where Monday=1), then add `(n-1)*7`. If the resulting day number exceeds the month's length, the rule has no target in this month.
   - For `:last_weekday_of_month, weekday`: find the last day of the month, walk backwards until the weekday matches.
   - For `:nth_day_of_month, day`: valid if `day <= days_in_month(year, month)`.
   - For `:last_day_of_month`: always valid, uses `Calendar.ISO.days_in_month(year, month)`.
3. If the target datetime exists and is strictly greater than the given time, return it.
4. Otherwise advance to the next month (rolling year on December → January) and repeat from step 2.

Use `Calendar.ISO.days_in_month(year, month)` for month-length. Use `Date.day_of_week(date)` to get ISO weekday (Monday=1..Sunday=7). Weekday atoms map as: `:monday` → 1, `:tuesday` → 2, ..., `:sunday` → 7.

At registration, compute the initial `next_run` relative to the current clock.

On each `:tick`, read `now`, find all jobs whose `next_run <= now`, execute each one via `apply(mod, fun, args)` wrapped in try/rescue/catch so a crashing job doesn't kill the scheduler, and recompute `next_run` relative to `now`. Schedule the next tick if `tick_interval_ms != :infinity`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `unregister` missing

```elixir
defmodule CalendarScheduler do
  @moduledoc """
  A GenServer that executes jobs on calendar-aware rules.

  Unlike cron, this scheduler uses four higher-level rule tuples that
  directly encode common calendar patterns:

    * `{:nth_weekday_of_month, n, weekday, {hour, minute}}`
      e.g. first Monday of each month at 09:00
    * `{:last_weekday_of_month, weekday, {hour, minute}}`
      e.g. last Friday of each month at 17:00
    * `{:nth_day_of_month, day, {hour, minute}}`
      e.g. 15th of each month at noon.  Months without that day are skipped.
    * `{:last_day_of_month, {hour, minute}}`
      handles 28/29/30/31-day months correctly.

  The next-run algorithm walks the calendar by month rather than scanning
  minute-by-minute.  For each candidate month, it computes the rule's target
  datetime (if any exists — "day 31" doesn't exist in February) and returns
  the first one strictly later than the reference time.

  ## Options

    * `:name`              – process registration name (optional)
    * `:clock`             – zero-arity function returning a `NaiveDateTime`
                             (default: `fn -> NaiveDateTime.utc_now() end`)
    * `:tick_interval_ms`  – polling interval in ms; `:infinity` disables
                             auto-ticking (default `1_000`)

  """

  use GenServer

  @weekdays %{
    monday: 1,
    tuesday: 2,
    wednesday: 3,
    thursday: 4,
    friday: 5,
    saturday: 6,
    sunday: 7
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Registers `job_name` to run `mfa` on the calendar `rule`. Returns `:ok` or error."
  @spec register(GenServer.server(), term(), tuple(), {module(), atom(), list()}) ::
          :ok | {:error, :invalid_rule | :already_exists}
  def register(server, job_name, rule, {mod, fun, args} = mfa)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, job_name, rule, mfa})
  end

  def unregister(server, job_name) do
    # TODO
  end

  @spec jobs(GenServer.server()) :: [{term(), tuple(), NaiveDateTime.t()}]
  def jobs(server), do: GenServer.call(server, :jobs)

  @spec next_run(GenServer.server(), term()) :: {:ok, NaiveDateTime.t()} | {:error, :not_found}
  def next_run(server, job_name), do: GenServer.call(server, {:next_run, job_name})

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
  def handle_call({:register, name, rule, mfa}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      not valid_rule?(rule) ->
        {:reply, {:error, :invalid_rule}, state}

      true ->
        now = state.clock.()
        job = %{mfa: mfa, rule: rule, next_run: compute_next_run(rule, now)}
        {:reply, :ok, %{state | jobs: Map.put(state.jobs, name, job)}}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.pop(state.jobs, name) do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_, new_jobs} -> {:reply, :ok, %{state | jobs: new_jobs}}
    end
  end

  def handle_call(:jobs, _from, state) do
    list = Enum.map(state.jobs, fn {n, j} -> {n, j.rule, j.next_run} end)
    {:reply, list, state}
  end

  def handle_call({:next_run, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, j} -> {:reply, {:ok, j.next_run}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    now = state.clock.()

    new_jobs =
      Enum.reduce(state.jobs, %{}, fn {name, job}, acc ->
        if NaiveDateTime.compare(job.next_run, now) != :gt do
          _ = safe_execute(job.mfa)
          updated = %{job | next_run: compute_next_run(job.rule, now)}
          Map.put(acc, name, updated)
        else
          Map.put(acc, name, job)
        end
      end)

    schedule_tick(state.tick_interval_ms)
    {:noreply, %{state | jobs: new_jobs}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Rule validation
  # ---------------------------------------------------------------------------

  defp valid_rule?({:nth_weekday_of_month, n, wd, {h, m}})
       when is_integer(n) and n in 1..4 and is_integer(h) and h in 0..23 and
              is_integer(m) and m in 0..59 do
    Map.has_key?(@weekdays, wd)
  end

  defp valid_rule?({:last_weekday_of_month, wd, {h, m}})
       when is_integer(h) and h in 0..23 and is_integer(m) and m in 0..59 do
    Map.has_key?(@weekdays, wd)
  end

  defp valid_rule?({:nth_day_of_month, d, {h, m}})
       when is_integer(d) and d in 1..31 and is_integer(h) and h in 0..23 and
              is_integer(m) and m in 0..59 do
    true
  end

  defp valid_rule?({:last_day_of_month, {h, m}})
       when is_integer(h) and h in 0..23 and is_integer(m) and m in 0..59 do
    true
  end

  defp valid_rule?(_), do: false

  # ---------------------------------------------------------------------------
  # The next-run calendar walk — the heart of this module
  # ---------------------------------------------------------------------------

  # Find the first datetime strictly greater than `after_ndt` that matches
  # `rule`, walking month-by-month.  We bound the walk at 60 months (5 years)
  # to prevent infinite loops on malformed rules, though validated rules
  # should always match within at most 12 months.
  defp compute_next_run(rule, after_ndt) do
    walk_months(rule, after_ndt, after_ndt.year, after_ndt.month, 60)
  end

  defp walk_months(_rule, _after, _year, _month, 0) do
    # Defensive fallback — should never fire for validated rules.
    raise "CalendarScheduler: rule did not match in 60 months — malformed rule?"
  end

  defp walk_months(rule, after_ndt, year, month, budget) do
    case target_in_month(rule, year, month) do
      {:ok, candidate} ->
        if NaiveDateTime.compare(candidate, after_ndt) == :gt do
          candidate
        else
          {next_year, next_month} = bump_month(year, month)
          walk_months(rule, after_ndt, next_year, next_month, budget - 1)
        end

      :no_match ->
        {next_year, next_month} = bump_month(year, month)
        walk_months(rule, after_ndt, next_year, next_month, budget - 1)
    end
  end

  defp bump_month(year, 12), do: {year + 1, 1}
  defp bump_month(year, month), do: {year, month + 1}

  # For each rule type, compute the target datetime within the given
  # {year, month}, or return :no_match if the rule has no target there.
  defp target_in_month({:nth_weekday_of_month, n, wd, {h, m}}, year, month) do
    target_dow = @weekdays[wd]
    first = Date.new!(year, month, 1)
    first_dow = Date.day_of_week(first)

    # Days from the 1st to the first occurrence of the target weekday (0..6).
    days_to_first = rem(target_dow - first_dow + 7, 7)
    nth_day = 1 + days_to_first + (n - 1) * 7

    if nth_day <= Calendar.ISO.days_in_month(year, month) do
      {:ok, NaiveDateTime.new!(year, month, nth_day, h, m, 0)}
    else
      :no_match
    end
  end

  defp target_in_month({:last_weekday_of_month, wd, {h, m}}, year, month) do
    target_dow = @weekdays[wd]
    last_day_num = Calendar.ISO.days_in_month(year, month)
    last_date = Date.new!(year, month, last_day_num)
    last_dow = Date.day_of_week(last_date)

    # Steps back from the last day to the most recent target weekday (0..6).
    steps_back = rem(last_dow - target_dow + 7, 7)
    day = last_day_num - steps_back

    {:ok, NaiveDateTime.new!(year, month, day, h, m, 0)}
  end

  defp target_in_month({:nth_day_of_month, day, {h, m}}, year, month) do
    if day <= Calendar.ISO.days_in_month(year, month) do
      {:ok, NaiveDateTime.new!(year, month, day, h, m, 0)}
    else
      :no_match
    end
  end

  defp target_in_month({:last_day_of_month, {h, m}}, year, month) do
    last = Calendar.ISO.days_in_month(year, month)
    {:ok, NaiveDateTime.new!(year, month, last, h, m, 0)}
  end

  # ---------------------------------------------------------------------------
  # Execution helper
  # ---------------------------------------------------------------------------

  defp safe_execute({mod, fun, args}) do
    try do
      apply(mod, fun, args)
    rescue
      _ -> :crashed
    catch
      _, _ -> :crashed
    end
  end

  defp schedule_tick(:infinity), do: :ok

  defp schedule_tick(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :tick, ms)
  end
end
```

Give me only the complete implementation of `unregister` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
