# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Scheduler do
  @moduledoc """
  A GenServer that accepts job registrations with cron-like schedules
  and executes them at the right times.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type server :: GenServer.server()
  @type job_name :: atom() | String.t()
  @type cron_expression :: String.t()
  @type mfa_tuple :: {module(), atom(), [term()]}
  @type job_entry :: {job_name(), cron_expression(), NaiveDateTime.t()}
  @type option ::
          {:clock, (-> NaiveDateTime.t())}
          | {:name, GenServer.name()}
          | {:tick_interval_ms, pos_integer() | :infinity}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the Scheduler process.

  ## Options

    * `:clock` – zero-arity function returning `NaiveDateTime` for the current
      time. Defaults to `fn -> NaiveDateTime.utc_now() end`.
    * `:name` – optional process registration name.
    * `:tick_interval_ms` – milliseconds between ticks (default `1_000`).
      Set to `:infinity` to disable automatic ticking.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = split_opts(opts)
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Registers a named job.

  Returns `:ok` on success, `{:error, :invalid_cron}` if the expression is
  malformed, or `{:error, :already_exists}` if a job with the same name is
  already registered.
  """
  @spec register(server(), job_name(), cron_expression(), mfa_tuple()) ::
          :ok | {:error, :invalid_cron | :already_exists}
  def register(server, name, cron_expression, {mod, fun, args} = mfa)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, name, cron_expression, mfa})
  end

  @doc """
  Removes a registered job.

  Returns `:ok` or `{:error, :not_found}`.
  """
  @spec unregister(server(), job_name()) :: :ok | {:error, :not_found}
  def unregister(server, name) do
    GenServer.call(server, {:unregister, name})
  end

  @doc """
  Returns a list of `{name, cron_expression, next_run}` tuples for every
  registered job.
  """
  @spec jobs(server()) :: [job_entry()]
  def jobs(server) do
    GenServer.call(server, :jobs)
  end

  @doc """
  Returns `{:ok, next_run}` for a registered job, or `{:error, :not_found}`.
  """
  @spec next_run(server(), job_name()) ::
          {:ok, NaiveDateTime.t()} | {:error, :not_found}
  def next_run(server, name) do
    GenServer.call(server, {:next_run, name})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> NaiveDateTime.utc_now() end)
    tick_interval = Keyword.get(opts, :tick_interval_ms, 1_000)

    if tick_interval != :infinity do
      Process.send_after(self(), :tick, tick_interval)
    end

    {:ok, %{clock: clock, tick_interval: tick_interval, jobs: %{}}}
  end

  @impl true
  def handle_call({:register, name, cron_expr, mfa}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        case parse_cron(cron_expr) do
          {:ok, parsed} ->
            now = state.clock.()
            next = next_run_time(parsed, now)

            job = %{
              cron_expression: cron_expr,
              parsed: parsed,
              mfa: mfa,
              next_run: next
            }

            {:reply, :ok, put_in(state, [:jobs, name], job)}

          :error ->
            {:reply, {:error, :invalid_cron}, state}
        end
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    if Map.has_key?(state.jobs, name) do
      {:reply, :ok, %{state | jobs: Map.delete(state.jobs, name)}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:jobs, _from, state) do
    list =
      Enum.map(state.jobs, fn {name, job} ->
        {name, job.cron_expression, job.next_run}
      end)

    {:reply, list, state}
  end

  def handle_call({:next_run, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, job} -> {:reply, {:ok, job.next_run}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    now = state.clock.()

    updated_jobs =
      Map.new(state.jobs, fn {name, job} ->
        if NaiveDateTime.compare(job.next_run, now) != :gt do
          {mod, fun, args} = job.mfa

          try do
            apply(mod, fun, args)
          rescue
            _ -> :ok
          catch
            _, _ -> :ok
          end

          {name, %{job | next_run: next_run_time(job.parsed, now)}}
        else
          {name, job}
        end
      end)

    if state.tick_interval != :infinity do
      Process.send_after(self(), :tick, state.tick_interval)
    end

    {:noreply, %{state | jobs: updated_jobs}}
  end

  # Ignore unexpected messages
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Cron parsing
  # ---------------------------------------------------------------------------

  @field_ranges %{
    minute: {0, 59},
    hour: {0, 23},
    day: {1, 31},
    month: {1, 12},
    weekday: {0, 6}
  }

  @field_order [:minute, :hour, :day, :month, :weekday]

  defp parse_cron(expression) when is_binary(expression) do
    parts = String.split(expression)

    if length(parts) != 5 do
      :error
    else
      fields = Enum.zip(@field_order, parts)

      result =
        Enum.reduce_while(fields, %{}, fn {field, token}, acc ->
          {lo, hi} = Map.fetch!(@field_ranges, field)

          case parse_field(token, lo, hi) do
            {:ok, values} -> {:cont, Map.put(acc, field, values)}
            :error -> {:halt, :error}
          end
        end)

      case result do
        :error -> :error
        map -> {:ok, map}
      end
    end
  end

  # Parse a single cron field token into a sorted MapSet of integers.
  defp parse_field(token, lo, hi) do
    token
    |> String.split(",")
    |> Enum.reduce_while(MapSet.new(), fn part, acc ->
      case parse_part(part, lo, hi) do
        {:ok, values} -> {:cont, MapSet.union(acc, values)}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      set -> {:ok, set}
    end
  end

  # A part is either a range/value optionally followed by /step, or * optionally
  # followed by /step.
  defp parse_part(part, lo, hi) do
    case String.split(part, "/") do
      [base] ->
        parse_range_or_star(base, lo, hi)

      [base, step_str] ->
        with {:ok, step} <- parse_int(step_str),
             true <- step > 0 || :error,
             {:ok, values} <- parse_range_or_star(base, lo, hi) do
          # apply step: keep only values whose offset from the range start is
          # divisible by the step.
          sorted = Enum.sort(values)
          start = List.first(sorted)

          filtered =
            Enum.filter(sorted, fn v -> rem(v - start, step) == 0 end)

          {:ok, MapSet.new(filtered)}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_range_or_star("*", lo, hi) do
    {:ok, MapSet.new(lo..hi)}
  end

  defp parse_range_or_star(other, lo, hi) do
    parse_range_or_value(other, lo, hi)
  end

  defp parse_range_or_value(str, lo, hi) do
    case String.split(str, "-") do
      [single] ->
        case parse_int(single) do
          {:ok, v} when v >= lo and v <= hi -> {:ok, MapSet.new([v])}
          _ -> :error
        end

      [from_str, to_str] ->
        with {:ok, from} <- parse_int(from_str),
             {:ok, to} <- parse_int(to_str),
             true <- (from >= lo && to <= hi && from <= to) || :error do
          {:ok, MapSet.new(from..to)}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  # ---------------------------------------------------------------------------
  # Next-run calculation
  # ---------------------------------------------------------------------------

  defp next_run_time(parsed, now) do
    # Start from the next whole minute after `now`.
    candidate =
      now
      |> NaiveDateTime.truncate(:second)
      |> Map.put(:second, 0)
      |> NaiveDateTime.add(60, :second)

    scan(parsed, candidate, 0)
  end

  # Safety limit: don't scan more than ~4 years of minutes (≈ 2_200_000).
  # In practice we jump by days/hours so this is very generous.
  @max_iterations 2_200_000

  defp scan(_parsed, _candidate, iteration) when iteration >= @max_iterations do
    raise "Scheduler: could not find a matching time within scan limit"
  end

  defp scan(parsed, candidate, iteration) do
    cond do
      # Month mismatch → advance to the first day of the next matching month.
      not MapSet.member?(parsed.month, candidate.month) ->
        scan(parsed, advance_to_next_month(parsed, candidate), iteration + 1)

      # Day-of-month mismatch → advance to next day at 00:00.
      not MapSet.member?(parsed.day, candidate.day) ->
        scan(parsed, next_day(candidate), iteration + 1)

      # Day-of-week mismatch → advance to next day at 00:00.
      not MapSet.member?(parsed.weekday, day_of_week(candidate)) ->
        scan(parsed, next_day(candidate), iteration + 1)

      # Hour mismatch → advance to next hour at :00.
      not MapSet.member?(parsed.hour, candidate.hour) ->
        scan(parsed, next_hour(candidate), iteration + 1)

      # Minute mismatch → advance one minute.
      not MapSet.member?(parsed.minute, candidate.minute) ->
        scan(parsed, NaiveDateTime.add(candidate, 60, :second), iteration + 1)

      # All fields match!
      true ->
        candidate
    end
  end

  # Advance to midnight of the next day.
  defp next_day(dt) do
    dt
    |> NaiveDateTime.add(86_400, :second)
    |> Map.merge(%{hour: 0, minute: 0, second: 0})
  end

  # Advance to the top of the next hour.
  defp next_hour(dt) do
    dt
    |> Map.put(:minute, 0)
    |> NaiveDateTime.add(3_600, :second)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
  end

  # Jump forward to the 1st of the next month that matches the cron month field.
  defp advance_to_next_month(parsed, dt) do
    {year, month} = next_month_year(dt.year, dt.month, parsed.month)

    %NaiveDateTime{
      year: year,
      month: month,
      day: 1,
      hour: 0,
      minute: 0,
      second: 0,
      microsecond: {0, 0}
    }
  end

  defp next_month_year(year, current_month, valid_months) do
    # Look for the next valid month starting from current_month + 1.
    case Enum.find(Enum.sort(valid_months), fn m -> m > current_month end) do
      nil ->
        # Wrap to next year, pick the smallest valid month.
        {year + 1, Enum.min(valid_months)}

      m ->
        {year, m}
    end
  end

  # Returns 0 = Sunday, 1 = Monday, … 6 = Saturday to match standard cron.
  defp day_of_week(dt) do
    # Elixir's Date.day_of_week/1 returns 1 = Monday … 7 = Sunday.
    case Date.day_of_week(dt) do
      7 -> 0
      n -> n
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp split_opts(opts) do
    {name_opts, rest} = Keyword.split(opts, [:name])
    gen_opts = if name_opts[:name], do: [name: name_opts[:name]], else: []
    {gen_opts, rest}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SchedulerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(seconds), do: Agent.update(__MODULE__, &NaiveDateTime.add(&1, seconds, :second))
    def set(dt), do: Agent.update(__MODULE__, fn _ -> dt end)
  end

  # --- Job execution tracker ---

  defmodule JobTracker do
    use Agent

    def start_link(_opts) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(name), do: Agent.update(__MODULE__, &[name | &1])
    def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1))
    def count(name), do: Agent.get(__MODULE__, fn list -> Enum.count(list, &(&1 == name)) end)
    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)
  end

  # Monday, January 5 2026, 10:00:00
  @start_time ~N[2026-01-05 10:00:00]

  setup do
    start_supervised!({Clock, @start_time})
    start_supervised!({JobTracker, []})

    {:ok, pid} =
      Scheduler.start_link(
        clock: &Clock.now/0,
        # disable auto-ticking in tests
        tick_interval_ms: :infinity
      )

    %{s: pid}
  end

  # Helper: send a :tick and wait for the GenServer to process it
  defp tick(pid) do
    send(pid, :tick)
    :sys.get_state(pid)
  end

  # -------------------------------------------------------
  # Registration
  # -------------------------------------------------------

  test "register returns :ok for a valid cron expression", %{s: s} do
    assert :ok = Scheduler.register(s, "job1", "*/5 * * * *", {JobTracker, :record, ["job1"]})
  end

  test "register returns error for too few fields", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "*/5 * *", {IO, :puts, ["hi"]})
  end

  test "register returns error for out-of-range minute (60)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "60 * * * *", {IO, :puts, ["hi"]})
  end

  test "register returns error for out-of-range hour (25)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "0 25 * * *", {IO, :puts, ["hi"]})
  end

  test "register returns error for out-of-range day-of-week (7)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "0 0 * * 7", {IO, :puts, ["hi"]})
  end

  test "register returns error for duplicate name", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})

    assert {:error, :already_exists} =
             Scheduler.register(s, "j", "*/5 * * * *", {JobTracker, :record, ["j"]})
  end

  # -------------------------------------------------------
  # Unregister
  # -------------------------------------------------------

  test "unregister returns :ok for an existing job", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})
    assert :ok = Scheduler.unregister(s, "j")
  end

  test "unregister returns error for an unknown job", %{s: s} do
    # TODO
  end

  # -------------------------------------------------------
  # Listing jobs
  # -------------------------------------------------------

  test "jobs/1 lists all registered jobs", %{s: s} do
    :ok = Scheduler.register(s, "j1", "30 11 * * *", {JobTracker, :record, ["j1"]})
    :ok = Scheduler.register(s, "j2", "0 12 * * *", {JobTracker, :record, ["j2"]})

    jobs = Scheduler.jobs(s)
    names = jobs |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    assert names == ["j1", "j2"]
  end

  test "jobs/1 returns empty list when no jobs registered", %{s: s} do
    assert Scheduler.jobs(s) == []
  end

  # -------------------------------------------------------
  # next_run calculation
  # -------------------------------------------------------

  test "next_run returns the correct next datetime for a specific time", %{s: s} do
    # At 10:00, next "30 11 * * *" is today at 11:30
    :ok = Scheduler.register(s, "j", "30 11 * * *", {JobTracker, :record, ["j"]})
    assert {:ok, ~N[2026-01-05 11:30:00]} = Scheduler.next_run(s, "j")
  end

  test "next_run wraps to next day when time has passed", %{s: s} do
    # At 10:00, "0 9 * * *" (9:00) already passed today → next is tomorrow
    :ok = Scheduler.register(s, "j", "0 9 * * *", {JobTracker, :record, ["j"]})
    assert {:ok, ~N[2026-01-06 09:00:00]} = Scheduler.next_run(s, "j")
  end

  test "next_run returns error for unknown job", %{s: s} do
    assert {:error, :not_found} = Scheduler.next_run(s, "nope")
  end

  # -------------------------------------------------------
  # Basic execution
  # -------------------------------------------------------

  test "job fires when clock reaches its scheduled time", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)

    assert JobTracker.count("j") == 1
  end

  test "job does NOT fire before its scheduled time", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:29:00])
    tick(s)

    assert JobTracker.count("j") == 0
  end

  test "job does not fire twice on the same tick", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)
    tick(s)

    assert JobTracker.count("j") == 1
  end

  # -------------------------------------------------------
  # Recurring execution
  # -------------------------------------------------------

  test "job recurs correctly after firing", %{s: s} do
    # Every hour at minute 0
    :ok = Scheduler.register(s, "j", "0 * * * *", {JobTracker, :record, ["j"]})

    # Fire at 11:00
    Clock.set(~N[2026-01-05 11:00:00])
    tick(s)
    assert JobTracker.count("j") == 1

    # After firing, next_run should advance to 12:00
    assert {:ok, ~N[2026-01-05 12:00:00]} = Scheduler.next_run(s, "j")

    # Fire again at 12:00
    Clock.set(~N[2026-01-05 12:00:00])
    tick(s)
    assert JobTracker.count("j") == 2
  end

  test "every-minute job fires each minute", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:01:00])
    tick(s)
    assert JobTracker.count("j") == 1

    Clock.set(~N[2026-01-05 10:02:00])
    tick(s)
    assert JobTracker.count("j") == 2

    Clock.set(~N[2026-01-05 10:03:00])
    tick(s)
    assert JobTracker.count("j") == 3
  end

  # -------------------------------------------------------
  # Two jobs at the same time
  # -------------------------------------------------------

  test "two jobs scheduled for the same time both fire", %{s: s} do
    :ok = Scheduler.register(s, "a", "30 10 * * *", {JobTracker, :record, ["a"]})
    :ok = Scheduler.register(s, "b", "30 10 * * *", {JobTracker, :record, ["b"]})

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)

    assert JobTracker.count("a") == 1
    assert JobTracker.count("b") == 1
  end

  # -------------------------------------------------------
  # Unregister while pending
  # -------------------------------------------------------

  test "unregistering a pending job prevents it from firing", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})
    :ok = Scheduler.unregister(s, "j")

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)

    assert JobTracker.count("j") == 0
  end

  test "re-registering after unregister works", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})
    :ok = Scheduler.unregister(s, "j")
    :ok = Scheduler.register(s, "j", "45 10 * * *", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-05 10:45:00]} = Scheduler.next_run(s, "j")

    Clock.set(~N[2026-01-05 10:45:00])
    tick(s)
    assert JobTracker.count("j") == 1
  end

  # -------------------------------------------------------
  # Cron expression features
  # -------------------------------------------------------

  test "step expression */15 fires at 0, 15, 30, 45", %{s: s} do
    :ok = Scheduler.register(s, "j", "*/15 * * * *", {JobTracker, :record, ["j"]})

    for minute <- [0, 15, 30, 45] do
      Clock.set(~N[2026-01-05 11:00:00] |> NaiveDateTime.add(minute * 60, :second))
      tick(s)
    end

    assert JobTracker.count("j") == 4
  end

  test "range expression 1-3 in hour field", %{s: s} do
    :ok = Scheduler.register(s, "j", "0 1-3 * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next match is 1:00 tomorrow (hours 1,2,3 have passed today)
    assert {:ok, next} = Scheduler.next_run(s, "j")
    assert next.hour in [1, 2, 3]
    assert next.minute == 0
    # Should be tomorrow since 1-3 are all before 10
    assert NaiveDateTime.compare(next, @start_time) == :gt
  end

  test "comma-separated values in minute field", %{s: s} do
    :ok = Scheduler.register(s, "j", "0,30 * * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next is 10:30 (advancing at least 1 minute, minute 0 is behind)
    assert {:ok, ~N[2026-01-05 10:30:00]} = Scheduler.next_run(s, "j")
  end

  test "range with step 10-30/10 matches 10, 20, 30", %{s: s} do
    :ok = Scheduler.register(s, "j", "10-30/10 * * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next is 10:10
    assert {:ok, ~N[2026-01-05 10:10:00]} = Scheduler.next_run(s, "j")

    # Fire at 10:10, next should be 10:20
    Clock.set(~N[2026-01-05 10:10:00])
    tick(s)
    assert {:ok, ~N[2026-01-05 10:20:00]} = Scheduler.next_run(s, "j")
    assert JobTracker.count("j") == 1

    # Fire at 10:20, next should be 10:30
    Clock.set(~N[2026-01-05 10:20:00])
    tick(s)
    assert {:ok, ~N[2026-01-05 10:30:00]} = Scheduler.next_run(s, "j")
    assert JobTracker.count("j") == 2
  end

  # -------------------------------------------------------
  # Day-of-week
  # -------------------------------------------------------

  test "day-of-week 0 (Sunday) schedules to next Sunday", %{s: s} do
    # We start on Monday Jan 5. Next Sunday is Jan 11.
    :ok = Scheduler.register(s, "j", "0 9 * * 0", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-11 09:00:00]} = Scheduler.next_run(s, "j")
  end

  test "day-of-week 1 (Monday) schedules to next Monday", %{s: s} do
    # We're on Monday 10:00. Next Monday-matching time at 09:00 is next week.
    :ok = Scheduler.register(s, "j", "0 9 * * 1", {JobTracker, :record, ["j"]})

    # 09:00 today already passed, so next Monday is Jan 12
    assert {:ok, ~N[2026-01-12 09:00:00]} = Scheduler.next_run(s, "j")
  end

  test "day-of-week job fires on the correct day", %{s: s} do
    # Wednesday = 3. Next Wednesday from Mon Jan 5 is Jan 7.
    :ok = Scheduler.register(s, "j", "0 12 * * 3", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-07 12:00:00]} = Scheduler.next_run(s, "j")

    Clock.set(~N[2026-01-07 12:00:00])
    tick(s)
    assert JobTracker.count("j") == 1

    # After firing, next should be the following Wednesday, Jan 14
    assert {:ok, ~N[2026-01-14 12:00:00]} = Scheduler.next_run(s, "j")
  end

  # -------------------------------------------------------
  # Specific day-of-month and month
  # -------------------------------------------------------

  test "specific day-of-month", %{s: s} do
    :ok = Scheduler.register(s, "j", "0 12 15 * *", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-15 12:00:00]} = Scheduler.next_run(s, "j")
  end

  test "specific month", %{s: s} do
    :ok = Scheduler.register(s, "j", "0 0 1 3 *", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-03-01 00:00:00]} = Scheduler.next_run(s, "j")
  end

  test "job that only matches Feb 28 in non-leap year", %{s: s} do
    # 2026 is not a leap year. "0 0 29 2 *" should skip to 2028 (next leap year)
    # Actually Feb 29 doesn't exist in 2026 or 2027. 2028 is a leap year.
    :ok = Scheduler.register(s, "j", "0 0 29 2 *", {JobTracker, :record, ["j"]})

    assert {:ok, next} = Scheduler.next_run(s, "j")
    assert next == ~N[2028-02-29 00:00:00]
  end

  # -------------------------------------------------------
  # Multiple keys interleaved
  # -------------------------------------------------------

  test "independent jobs with different schedules", %{s: s} do
    :ok = Scheduler.register(s, "fast", "*/5 * * * *", {JobTracker, :record, ["fast"]})
    :ok = Scheduler.register(s, "slow", "0 * * * *", {JobTracker, :record, ["slow"]})

    # At 10:05, "fast" fires but "slow" doesn't (next is 11:00)
    Clock.set(~N[2026-01-05 10:05:00])
    tick(s)
    assert JobTracker.count("fast") == 1
    assert JobTracker.count("slow") == 0

    # At 11:00, both fire
    Clock.set(~N[2026-01-05 11:00:00])
    tick(s)
    assert JobTracker.count("fast") == 2
    assert JobTracker.count("slow") == 1
  end
end
```
