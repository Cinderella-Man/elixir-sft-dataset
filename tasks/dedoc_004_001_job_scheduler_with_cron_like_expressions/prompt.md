# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Scheduler do
  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {gen_opts, init_opts} = split_opts(opts)
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  def register(server, name, cron_expression, {mod, fun, args} = mfa)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, name, cron_expression, mfa})
  end

  def unregister(server, name) do
    GenServer.call(server, {:unregister, name})
  end

  def jobs(server) do
    GenServer.call(server, :jobs)
  end

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
