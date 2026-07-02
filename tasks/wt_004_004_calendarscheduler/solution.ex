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

  @spec register(GenServer.server(), term(), tuple(), {module(), atom(), list()}) ::
          :ok | {:error, :invalid_rule | :already_exists}
  def register(server, job_name, rule, {mod, fun, args} = mfa)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, job_name, rule, mfa})
  end

  @spec unregister(GenServer.server(), term()) :: :ok | {:error, :not_found}
  def unregister(server, job_name), do: GenServer.call(server, {:unregister, job_name})

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
