# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule CalendarSchedulerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial_ndt) do
      Agent.start_link(fn -> initial_ndt end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)

    def advance_seconds(s) do
      Agent.update(__MODULE__, &NaiveDateTime.add(&1, s, :second))
    end

    def advance_days(d), do: advance_seconds(d * 86_400)

    def set(ndt), do: Agent.update(__MODULE__, fn _ -> ndt end)
  end

  defmodule JobSink do
    def ping(test_pid, tag), do: send(test_pid, tag)
    def crash, do: raise("boom")
  end

  # Anchor: Jan 1, 2025 at 00:00 (a Wednesday).
  @t0 ~N[2025-01-01 00:00:00]

  setup do
    start_supervised!({Clock, @t0})

    {:ok, pid} =
      CalendarScheduler.start_link(
        clock: &Clock.now/0,
        tick_interval_ms: :infinity
      )

    %{cs: pid}
  end

  # Delivers a tick, then issues a synchronous public-API call.  Because the
  # scheduler handles messages in order, the reply proves the tick is done.
  defp tick(pid) do
    send(pid, :tick)
    _ = CalendarScheduler.jobs(pid)
    :ok
  end

  # =======================================================
  # Rule validation
  # =======================================================

  test "valid rules return :ok at registration", %{cs: cs} do
    assert :ok =
             CalendarScheduler.register(
               cs,
               "a",
               {:nth_weekday_of_month, 1, :monday, {9, 0}},
               {JobSink, :ping, [self(), :a]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "b",
               {:last_weekday_of_month, :friday, {17, 0}},
               {JobSink, :ping, [self(), :b]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "c",
               {:nth_day_of_month, 15, {12, 0}},
               {JobSink, :ping, [self(), :c]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "d",
               {:last_day_of_month, {23, 59}},
               {JobSink, :ping, [self(), :d]}
             )
  end

  test "invalid rules return :invalid_rule", %{cs: cs} do
    # n out of range (must be 1..4)
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "a",
               {:nth_weekday_of_month, 5, :monday, {9, 0}},
               {JobSink, :ping, [self(), :x]}
             )

    # unknown weekday
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "b",
               {:nth_weekday_of_month, 1, :funday, {9, 0}},
               {JobSink, :ping, [self(), :x]}
             )

    # hour out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "c",
               {:last_day_of_month, {25, 0}},
               {JobSink, :ping, [self(), :x]}
             )

    # minute out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "d",
               {:last_day_of_month, {0, 60}},
               {JobSink, :ping, [self(), :x]}
             )

    # day out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "e",
               {:nth_day_of_month, 32, {0, 0}},
               {JobSink, :ping, [self(), :x]}
             )

    # completely malformed
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "f",
               {:random, :nonsense},
               {JobSink, :ping, [self(), :x]}
             )
  end

  test "duplicate names rejected", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :j]}
      )

    assert {:error, :already_exists} =
             CalendarScheduler.register(
               cs,
               "j",
               {:last_day_of_month, {0, 0}},
               {JobSink, :ping, [self(), :j]}
             )
  end

  test "unregister / jobs / next_run", %{cs: cs} do
    assert {:error, :not_found} = CalendarScheduler.next_run(cs, "ghost")
    assert {:error, :not_found} = CalendarScheduler.unregister(cs, "ghost")

    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 15, {12, 0}},
        {JobSink, :ping, [self(), :j]}
      )

    assert [{"j", {:nth_day_of_month, 15, {12, 0}}, _}] = CalendarScheduler.jobs(cs)
    assert :ok = CalendarScheduler.unregister(cs, "j")
    assert {:error, :not_found} = CalendarScheduler.next_run(cs, "j")
  end

  # =======================================================
  # next_run math for each rule type — the defining behavior
  # =======================================================

  describe "next_run for nth_weekday_of_month" do
    test "first Monday of Jan 2025 from Jan 1 is Jan 6", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_weekday_of_month, 1, :monday, {9, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-06 09:00:00]
    end

    test "second Tuesday of Jan 2025", %{cs: cs} do
      # Jan 1 2025 = Wed.  Tuesdays: Jan 7, Jan 14, Jan 21, Jan 28.
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_weekday_of_month, 2, :tuesday, {10, 30}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-14 10:30:00]
    end

    test "advances to next month after the target passes", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_weekday_of_month, 1, :monday, {9, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      # Set clock to Jan 7 (past Jan 6's Monday) — should skip to Feb
      Clock.set(~N[2025-01-07 00:00:00])
      tick(cs)

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      # Feb 1 2025 = Sat; first Monday is Feb 3.
      assert next == ~N[2025-02-03 09:00:00]
    end
  end

  describe "next_run for last_weekday_of_month" do
    test "last Friday of Jan 2025 is Jan 31 (a Friday)", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_weekday_of_month, :friday, {17, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-31 17:00:00]
    end

    test "last Sunday of Feb 2025", %{cs: cs} do
      # Feb 28 2025 = Fri.  Last Sunday = Feb 23.
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_weekday_of_month, :sunday, {20, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      Clock.set(~N[2025-02-01 00:00:00])

      # Re-register — next_run is computed at registration time from the clock
      :ok = CalendarScheduler.unregister(cs, "j")

      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_weekday_of_month, :sunday, {20, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-02-23 20:00:00]
    end
  end

  describe "next_run for nth_day_of_month" do
    test "15th of January 2025 at noon", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_day_of_month, 15, {12, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-15 12:00:00]
    end

    test "31st skips February (no Feb 31)", %{cs: cs} do
      Clock.set(~N[2025-01-31 23:00:00])

      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_day_of_month, 31, {12, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      # Jan 31 12:00 is already past (clock is Jan 31 23:00).
      # Feb has no 31 → skip.  March has 31 → Mar 31 12:00.
      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-03-31 12:00:00]
    end

    test "31st also skips April (only 30 days), June, September, November", %{cs: cs} do
      # TODO
    end
  end

  describe "next_run for last_day_of_month" do
    test "last day of Jan 2025 is the 31st", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_day_of_month, {23, 59}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-31 23:59:00]
    end

    test "last day of Feb 2024 is the 29th (leap year)", %{cs: cs} do
      Clock.set(~N[2024-02-01 00:00:00])

      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_day_of_month, {12, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2024-02-29 12:00:00]
    end

    test "last day of Feb 2025 is the 28th (non-leap)", %{cs: cs} do
      Clock.set(~N[2025-02-01 00:00:00])

      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_day_of_month, {12, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-02-28 12:00:00]
    end
  end

  # =======================================================
  # Execution on tick
  # =======================================================

  test "job fires on tick when due, recomputes for next month", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :fired]}
      )

    # Initial next_run: Feb 1 2025 00:00 (since clock is Jan 1 00:00 and we need strictly >).
    {:ok, first_next} = CalendarScheduler.next_run(cs, "j")
    assert first_next == ~N[2025-02-01 00:00:00]

    # Advance clock past Feb 1
    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :fired

    # Next run should now be Mar 1
    {:ok, next2} = CalendarScheduler.next_run(cs, "j")
    assert next2 == ~N[2025-03-01 00:00:00]
  end

  test "crashing job does not kill the scheduler", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "bad",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :crash, []}
      )

    :ok =
      CalendarScheduler.register(
        cs,
        "good",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :ok]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :ok
    assert Process.alive?(cs)

    # Both jobs should still be registered and have advanced next_runs
    {:ok, bad_next} = CalendarScheduler.next_run(cs, "bad")
    assert bad_next == ~N[2025-03-01 00:00:00]
  end

  test "multiple due jobs all fire on a single tick", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "a",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :a]}
      )

    :ok =
      CalendarScheduler.register(
        cs,
        "b",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :b]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :a
    assert_received :b
  end

  # =======================================================
  # Year rollover
  # =======================================================

  test "next_run rolls from December to January of the next year", %{cs: cs} do
    Clock.set(~N[2025-12-31 23:59:30])

    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :j]}
      )

    {:ok, next} = CalendarScheduler.next_run(cs, "j")
    assert next == ~N[2026-01-01 00:00:00]
  end

  test "overdue job fires once and recomputes next_run relative to now", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :fired]}
      )

    # Registered at Jan 1 → initial next_run is Feb 1 00:00.
    {:ok, first} = CalendarScheduler.next_run(cs, "j")
    assert first == ~N[2025-02-01 00:00:00]

    # Jump far past the deadline; the scheduler never ticked in between.
    Clock.set(~N[2025-04-05 00:00:00])
    tick(cs)

    # Fires exactly once — no catch-up storm for the skipped Mar 1 occurrence.
    assert_received :fired
    refute_received :fired

    # Recomputed relative to *now* (Apr 5), not relative to the old next_run.
    {:ok, next} = CalendarScheduler.next_run(cs, "j")
    assert next == ~N[2025-05-01 00:00:00]
  end

  test "a second tick at the same clock does not fire the job again", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :fired]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)
    assert_received :fired

    # Clock unchanged; the recomputed next_run is now in the future.
    tick(cs)
    refute_received :fired
  end

  test "registration at exactly the target time skips to the next month", %{cs: cs} do
    # Clock sits exactly on the first Monday's target instant.
    Clock.set(~N[2025-01-06 09:00:00])

    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_weekday_of_month, 1, :monday, {9, 0}},
        {JobSink, :ping, [self(), :j]}
      )

    # Equal is not strictly greater, so Jan 6 must be skipped for Feb 3.
    {:ok, next} = CalendarScheduler.next_run(cs, "j")
    assert next == ~N[2025-02-03 09:00:00]
  end

  test "tick fires a job whose next_run equals now exactly", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :fired]}
      )

    {:ok, first} = CalendarScheduler.next_run(cs, "j")
    assert first == ~N[2025-02-01 00:00:00]

    # Clock lands exactly on next_run — the <= boundary must fire.
    Clock.set(~N[2025-02-01 00:00:00])
    tick(cs)
    assert_received :fired
  end

  test "a job that throws does not kill the scheduler", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "thrower",
        {:nth_day_of_month, 1, {0, 0}},
        {:erlang, :throw, [:boom]}
      )

    :ok =
      CalendarScheduler.register(
        cs,
        "good",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :ok]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    # A throw is only swallowed by the `catch` clause, not `rescue`.
    assert_received :ok
    assert Process.alive?(cs)

    {:ok, next} = CalendarScheduler.next_run(cs, "thrower")
    assert next == ~N[2025-03-01 00:00:00]
  end

  # =======================================================
  # Automatic periodic timer (Process.send_after driven by :tick_interval_ms)
  # =======================================================

  test "a due job fires on the automatic timer, with no hand-sent :tick" do
    # A real, short interval exercises the promised Process.send_after path;
    # the test never sends :tick itself.
    interval = 25

    {:ok, pid} =
      CalendarScheduler.start_link(
        clock: &Clock.now/0,
        tick_interval_ms: interval
      )

    :ok =
      CalendarScheduler.register(
        pid,
        "auto",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :auto_fired]}
      )

    # Registered at Jan 1 → next_run is Feb 1 00:00.  Move the clock just past
    # it so the very next automatic tick finds the job due and executes it.
    Clock.set(~N[2025-02-01 00:00:01])

    # Only the timer can deliver a tick here; wait well beyond one interval.
    assert_receive :auto_fired, 20 * interval
  end
end
```
