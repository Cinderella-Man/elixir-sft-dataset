defmodule Scheduler do
  @moduledoc """
  A GenServer that runs registered jobs on cron-like schedules.

  Jobs are registered with a name, a 5-field cron expression
  (`minute hour day-of-month month day-of-week`) and an MFA tuple. On each tick the
  scheduler reads the current time from a configurable clock function, executes every job
  whose next run time has arrived, and recalculates that job's next run time.

  Supported field syntax:

    * `*` — every valid value for the field
    * `5` — a single value
    * `1,15,30` — a comma-separated list
    * `1-5` — an inclusive range
    * `*/5` or `10-30/5` — step values

  The clock is injectable via the `:clock` option, and automatic ticking can be disabled
  with `tick_interval_ms: :infinity`, which makes the scheduler fully deterministic under
  test (send `:tick` manually).
  """

  use GenServer

  @typedoc "A job identifier."
  @type job_name :: String.t() | atom()

  @typedoc "The module/function/arguments invoked when a job runs."
  @type mfa_tuple :: {module(), atom(), list()}

  @typedoc "A parsed cron expression: allowed values for each of the 5 fields."
  @type schedule :: %{
          minute: MapSet.t(non_neg_integer()),
          hour: MapSet.t(non_neg_integer()),
          day: MapSet.t(non_neg_integer()),
          month: MapSet.t(non_neg_integer()),
          weekday: MapSet.t(non_neg_integer()),
          day_wild?: boolean(),
          weekday_wild?: boolean()
        }

  @default_tick_interval 1_000

  # Upper bound on the minutes scanned when searching for the next matching datetime.
  # Eight years of minutes comfortably covers the worst realistic case (Feb 29 on a
  # constrained weekday), while still guaranteeing termination.
  @max_scan_minutes 8 * 366 * 24 * 60

  @field_ranges [
    minute: 0..59,
    hour: 0..23,
    day: 1..31,
    month: 1..12,
    weekday: 0..6
  ]

  defmodule Job do
    @moduledoc false
    defstruct [:name, :cron, :schedule, :mfa, :next_run]
  end

  ## Public API

  @doc """
  Starts the scheduler.

  ## Options

    * `:clock` — zero-arity function returning the current `NaiveDateTime`. Defaults to
      `fn -> NaiveDateTime.utc_now() end`.
    * `:name` — optional name for process registration.
    * `:tick_interval_ms` — milliseconds between ticks, or `:infinity` to disable
      automatic ticking. Defaults to `1_000`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Registers a job under `name` with the given cron expression and MFA tuple.

  Returns `:ok`, `{:error, :invalid_cron}` if the expression is unparseable, out of range
  or can never match a real datetime, or `{:error, :already_exists}` if the name is taken.
  """
  @spec register(GenServer.server(), job_name(), String.t(), mfa_tuple()) ::
          :ok | {:error, :invalid_cron | :already_exists}
  def register(server, name, cron_expression, {mod, fun, args})
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, name, cron_expression, {mod, fun, args}})
  end

  @doc """
  Removes the job registered under `name`.

  Returns `:ok` or `{:error, :not_found}`.
  """
  @spec unregister(GenServer.server(), job_name()) :: :ok | {:error, :not_found}
  def unregister(server, name) do
    GenServer.call(server, {:unregister, name})
  end

  @doc """
  Lists all registered jobs as `{name, cron_expression, next_run}` tuples.
  """
  @spec jobs(GenServer.server()) :: [{job_name(), String.t(), NaiveDateTime.t()}]
  def jobs(server) do
    GenServer.call(server, :jobs)
  end

  @doc """
  Returns `{:ok, next_run}` for the named job, or `{:error, :not_found}`.
  """
  @spec next_run(GenServer.server(), job_name()) ::
          {:ok, NaiveDateTime.t()} | {:error, :not_found}
  def next_run(server, name) do
    GenServer.call(server, {:next_run, name})
  end

  ## GenServer callbacks

  @impl GenServer
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> NaiveDateTime.utc_now() end)
    tick_interval_ms = Keyword.get(opts, :tick_interval_ms, @default_tick_interval)

    state = %{clock: clock, tick_interval_ms: tick_interval_ms, jobs: %{}}
    schedule_tick(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register, name, cron, mfa}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        case parse_cron(cron) do
          {:ok, schedule} ->
            now = current_time(state)

            job = %Job{
              name: name,
              cron: cron,
              schedule: schedule,
              mfa: mfa,
              next_run: next_run_after(schedule, now)
            }

            {:reply, :ok, put_in(state.jobs[name], job)}

          :error ->
            {:reply, {:error, :invalid_cron}, state}
        end
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.pop(state.jobs, name) do
      {nil, _jobs} -> {:reply, {:error, :not_found}, state}
      {_job, jobs} -> {:reply, :ok, %{state | jobs: jobs}}
    end
  end

  def handle_call(:jobs, _from, state) do
    listing = Enum.map(state.jobs, fn {_name, job} -> {job.name, job.cron, job.next_run} end)
    {:reply, listing, state}
  end

  def handle_call({:next_run, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, job} -> {:reply, {:ok, job.next_run}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info(:tick, state) do
    now = current_time(state)

    jobs =
      Map.new(state.jobs, fn {name, job} ->
        if due?(job, now) do
          run_job(job)
          {name, %Job{job | next_run: next_run_after(job.schedule, now)}}
        else
          {name, job}
        end
      end)

    state = %{state | jobs: jobs}
    schedule_tick(state)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  ## Internal helpers

  defp current_time(state), do: NaiveDateTime.truncate(state.clock.(), :second)

  defp schedule_tick(%{tick_interval_ms: :infinity}), do: :ok

  defp schedule_tick(%{tick_interval_ms: interval}) do
    Process.send_after(self(), :tick, interval)
    :ok
  end

  defp due?(%Job{next_run: nil}, _now), do: false

  defp due?(%Job{next_run: next_run}, now) do
    NaiveDateTime.compare(next_run, now) != :gt
  end

  defp run_job(%Job{mfa: {mod, fun, args}}) do
    apply(mod, fun, args)
  rescue
    _exception -> :error
  catch
    _kind, _reason -> :error
  end

  ## Cron parsing

  defp parse_cron(expression) when is_binary(expression) do
    fields = String.split(expression, " ", trim: true)

    with 5 <- length(fields),
         {:ok, values} <- parse_fields(fields) do
      [minute, hour, day, month, weekday] = values
      [day_field, _, _] = [Enum.at(fields, 2), nil, nil]
      weekday_field = Enum.at(fields, 4)

      schedule = %{
        minute: minute,
        hour: hour,
        day: day,
        month: month,
        weekday: weekday,
        day_wild?: day_field == "*",
        weekday_wild?: weekday_field == "*"
      }

      if satisfiable?(schedule), do: {:ok, schedule}, else: :error
    else
      _other -> :error
    end
  end

  defp parse_cron(_expression), do: :error

  defp parse_fields(fields) do
    @field_ranges
    |> Enum.zip(fields)
    |> Enum.reduce_while({:ok, []}, fn {{_key, range}, field}, {:ok, acc} ->
      case parse_field(field, range) do
        {:ok, set} -> {:cont, {:ok, [set | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :error -> :error
    end
  end

  defp parse_field(field, range) do
    field
    |> String.split(",", trim: true)
    |> case do
      [] ->
        :error

      parts ->
        Enum.reduce_while(parts, {:ok, MapSet.new()}, fn part, {:ok, acc} ->
          case parse_part(part, range) do
            {:ok, values} -> {:cont, {:ok, MapSet.union(acc, MapSet.new(values))}}
            :error -> {:halt, :error}
          end
        end)
        |> case do
          {:ok, set} -> if MapSet.size(set) == 0, do: :error, else: {:ok, set}
          :error -> :error
        end
    end
  end

  defp parse_part(part, range) do
    case String.split(part, "/", trim: false) do
      [base] -> parse_base(base, range)
      [base, step] -> parse_stepped(base, step, range)
      _other -> :error
    end
  end

  defp parse_stepped(base, step, range) do
    with {:ok, step_value} when step_value > 0 <- parse_integer(step),
         {:ok, values} <- parse_base(base, range) do
      first = Enum.min(values)
      {:ok, values |> Enum.sort() |> Enum.filter(&(rem(&1 - first, step_value) == 0))}
    else
      _other -> :error
    end
  end

  defp parse_base("*", first..last//_step), do: {:ok, Enum.to_list(first..last)}

  defp parse_base(base, range) do
    case String.split(base, "-", trim: false) do
      [single] ->
        with {:ok, value} <- parse_integer(single),
             true <- value in range do
          {:ok, [value]}
        else
          _other -> :error
        end

      [from, to] ->
        with {:ok, low} <- parse_integer(from),
             {:ok, high} <- parse_integer(to),
             true <- low in range and high in range and low <= high do
          {:ok, Enum.to_list(low..high)}
        else
          _other -> :error
        end

      _other ->
        :error
    end
  end

  defp parse_integer(string) do
    case Integer.parse(string) do
      {value, ""} -> {:ok, value}
      _other -> :error
    end
  end

  # A schedule is unsatisfiable when no allowed day-of-month exists in any allowed month.
  # February is treated as having 29 days, since leap years occur.
  defp satisfiable?(schedule) do
    Enum.any?(schedule.month, fn month ->
      max_day = max_days_in_month(month)
      Enum.any?(schedule.day, &(&1 <= max_day))
    end)
  end

  defp max_days_in_month(2), do: 29
  defp max_days_in_month(month) when month in [4, 6, 9, 11], do: 30
  defp max_days_in_month(_month), do: 31

  ## Next-run calculation

  defp next_run_after(schedule, from) do
    start =
      from
      |> truncate_to_minute()
      |> NaiveDateTime.add(60, :second)

    scan(schedule, start, 0)
  end

  defp truncate_to_minute(datetime) do
    %NaiveDateTime{datetime | second: 0, microsecond: {0, 0}}
  end

  defp scan(_schedule, _candidate, steps) when steps > @max_scan_minutes, do: nil

  defp scan(schedule, candidate, steps) do
    cond do
      matches?(schedule, candidate) ->
        candidate

      not month_matches?(schedule, candidate) ->
        scan(schedule, advance_to_next_month(candidate), steps + 1)

      not day_matches?(schedule, candidate) ->
        scan(schedule, advance_to_next_day(candidate), steps + 1)

      not hour_matches?(schedule, candidate) ->
        scan(schedule, NaiveDateTime.add(candidate, 3600 - candidate.minute * 60, :second),
          steps + 1
        )

      true ->
        scan(schedule, NaiveDateTime.add(candidate, 60, :second), steps + 1)
    end
  end

  defp advance_to_next_month(%NaiveDateTime{year: year, month: 12} = _datetime) do
    %NaiveDateTime{
      year: year + 1,
      month: 1,
      day: 1,
      hour: 0,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      calendar: Calendar.ISO
    }
  end

  defp advance_to_next_month(%NaiveDateTime{year: year, month: month}) do
    %NaiveDateTime{
      year: year,
      month: month + 1,
      day: 1,
      hour: 0,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      calendar: Calendar.ISO
    }
  end

  defp advance_to_next_day(datetime) do
    datetime
    |> NaiveDateTime.add(1, :day)
    |> Map.merge(%{hour: 0, minute: 0, second: 0, microsecond: {0, 0}})
  end

  defp matches?(schedule, datetime) do
    month_matches?(schedule, datetime) and day_matches?(schedule, datetime) and
      hour_matches?(schedule, datetime) and MapSet.member?(schedule.minute, datetime.minute)
  end

  defp month_matches?(schedule, datetime), do: MapSet.member?(schedule.month, datetime.month)

  defp hour_matches?(schedule, datetime), do: MapSet.member?(schedule.hour, datetime.hour)

  # Standard cron semantics: when both day-of-month and day-of-week are restricted the
  # day matches if either matches; otherwise only the restricted field applies.
  defp day_matches?(schedule, datetime) do
    dom? = MapSet.member?(schedule.day, datetime.day)
    dow? = MapSet.member?(schedule.weekday, day_of_week(datetime))

    cond do
      schedule.day_wild? and schedule.weekday_wild? -> true
      schedule.day_wild? -> dow?
      schedule.weekday_wild? -> dom?
      true -> dom? or dow?
    end
  end

  # Convert Elixir's ISO day of week (1 = Monday .. 7 = Sunday) to cron's (0 = Sunday).
  defp day_of_week(datetime) do
    rem(Date.day_of_week(datetime), 7)
  end
end