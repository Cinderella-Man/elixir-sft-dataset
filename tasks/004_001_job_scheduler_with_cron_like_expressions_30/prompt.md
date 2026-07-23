# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `jobs`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Write me an Elixir GenServer module called `Scheduler` that accepts job registrations with cron-like schedules and executes them at the right times.

I need these functions in the public API:

- `Scheduler.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime` representing the current time. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) that controls how frequently the GenServer checks for due jobs via `Process.send_after(self(), :tick, tick_interval_ms)`. Setting it to `:infinity` disables automatic ticking entirely (useful for testing).

- `Scheduler.register(server, name, cron_expression, {mod, fun, args})` which registers a named job. `name` is a string or atom identifier that must be unique. `cron_expression` is a string with exactly 5 space-separated fields: minute (0–59), hour (0–23), day-of-month (1–31), month (1–12), day-of-week (0–6, where 0 = Sunday). Return `:ok` on success. Return `{:error, :invalid_cron}` if the expression cannot be parsed, any value is out of range, or the expression can never match any real datetime because no allowed day-of-month exists in any allowed month (e.g. `0 0 31 4 *` — April has 30 days — or a day of 30–31 in February; `0 0 29 2 *` is valid, since leap years have a February 29th). Return `{:error, :already_exists}` if a job with that name is already registered. Upon successful registration, the GenServer must immediately calculate the job's next run time based on the current clock value.

- `Scheduler.unregister(server, name)` which removes a registered job. Return `:ok` if the job was found and removed. Return `{:error, :not_found}` if no job with that name exists.

- `Scheduler.jobs(server)` which returns a list of `{name, cron_expression, next_run}` tuples for all registered jobs, where `next_run` is a `NaiveDateTime`.

- `Scheduler.next_run(server, name)` which returns `{:ok, next_run_datetime}` for a registered job or `{:error, :not_found}` if the job doesn't exist.

The cron expression parser must support the following syntax in each of the 5 fields:
- `*` — matches every valid value for that field
- A specific integer (e.g. `5`)
- Comma-separated lists (e.g. `1,15,30`)
- Ranges with a dash (e.g. `1-5`)
- Step values with a slash (e.g. `*/5` or `10-30/5`). The step must be a positive integer; a step of `0` (as in `*/0`) is invalid. Stepping starts from the lower bound of the base range — the field's minimum for `*`, or the range's start otherwise — and selects every Nth matching value. For example, `*/15` in the minute field matches 0, 15, 30, 45; `10-30/10` matches 10, 20, 30; and `5-25/7` matches 5, 12, 19 (offsets 0, 7, 14 from the start value 5).

When calculating the next run time from a given `NaiveDateTime`, the scheduler should find the earliest future datetime that matches all five cron fields simultaneously. It must advance at least one minute from the given time (truncating seconds to zero) and scan forward. Be careful with day-of-week: if the cron specifies a day-of-week, only datetimes falling on matching weekdays should be considered.

On each `:tick` message, the GenServer should read the current time from the clock function, find all jobs whose `next_run` is less than or equal to the current time, execute each one by calling `apply(mod, fun, args)`, and then recalculate their next run time from the current time. Multiple jobs that are due at the same tick must all execute. After processing, if `tick_interval_ms` is not `:infinity`, schedule the next tick with `Process.send_after`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `jobs` missing

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

  def jobs(server) do
    # TODO
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
            if satisfiable?(parsed) do
              register_job(name, cron_expr, parsed, mfa, state)
            else
              {:reply, {:error, :invalid_cron}, state}
            end

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

  defp register_job(name, cron_expr, parsed, mfa, state) do
    now = state.clock.()
    next = next_run_time(parsed, now)

    job = %{
      cron_expression: cron_expr,
      parsed: parsed,
      mfa: mfa,
      next_run: next
    }

    {:reply, :ok, put_in(state, [:jobs, name], job)}
  end

  # An in-range expression is satisfiable iff some allowed (month, day) pair
  # can exist on a calendar: the day must not exceed the longest length that
  # month ever has (29 for February — leap years exist). Minute, hour, and
  # weekday fields can never make an in-range expression unsatisfiable on
  # their own, since every valid calendar date falls on every weekday across
  # years. Without this check, `next_run_time/2` would scan until its
  # iteration cap and raise inside the server.
  defp satisfiable?(parsed) do
    Enum.any?(parsed.month, fn month ->
      Enum.any?(parsed.day, fn day -> day <= max_month_day(month) end)
    end)
  end

  defp max_month_day(2), do: 29
  defp max_month_day(month) when month in [4, 6, 9, 11], do: 30
  defp max_month_day(_month), do: 31

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

Output only `jobs` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
