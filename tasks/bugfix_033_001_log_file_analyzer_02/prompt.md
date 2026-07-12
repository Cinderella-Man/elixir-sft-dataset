# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `LogAnalyzer` that parses a structured log file
and produces an analysis report.

Each line of the input file is an independent JSON object with these fields:
- `"timestamp"` — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`)
- `"level"`     — a string such as `"debug"`, `"info"`, `"warn"`, `"error"`
- `"message"`   — a string
- `"metadata"`  — a JSON object (arbitrary key/value pairs)

I need one public function:

    LogAnalyzer.analyze(path :: String.t()) :: {:ok, report} | {:error, reason}

Where `report` is a plain map with exactly these keys:

- `:counts_by_level`  — a map from level string to integer count
                         (only levels actually seen in the file appear)
- `:error_rate`       — a float between 0.0 and 1.0 representing
                         errors / total_valid_lines; 0.0 if no valid lines
- `:top_errors`       — a list of at most 10 `{message, count}` tuples,
                         taken only from lines whose level is `"error"`,
                         sorted descending by count, then alphabetically
                         by message to break ties
- `:time_range`       — a `{first_dt, last_dt}` tuple of `DateTime` structs
                         (the earliest and latest timestamps seen across
                         all valid lines); `nil` if no valid lines
- `:errors_per_hour`  — a map from a `NaiveDateTime`-like label (use a plain
                         `{date, hour}` tuple, e.g. `{{2024,1,15}, 14}`) to
                         integer count of error lines in that UTC hour bucket;
                         only hours that contain at least one error appear
- `:malformed_count`  — integer count of lines that could not be parsed as
                         valid JSON or were missing any required field or had
                         a non-string timestamp that could not be decoded

Lines that are blank or contain only whitespace should be skipped silently
(they don't count as malformed).

Error handling rules:
- If the file does not exist or cannot be opened, return `{:error, reason}`.
- Every other failure (bad JSON, missing fields, unparseable timestamp)
  is counted in `:malformed_count`; the line is skipped and processing continues.
- A line is considered malformed if ANY of these is true:
  - It is not valid JSON
  - The top-level JSON value is not an object
  - Any of `"timestamp"`, `"level"`, `"message"`, or `"metadata"` is absent
  - `"timestamp"` cannot be parsed as an ISO 8601 datetime

Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp
parsing. No other external dependencies.

Stream the file line-by-line so the module can handle files larger than memory.

Give me the complete module in a single file.

## The buggy module

```elixir
defmodule LogAnalyzer do
  @moduledoc """
  Parses a structured, newline-delimited JSON log file and produces an
  analysis report.

  Each line must be a JSON object with the fields:
    "timestamp" – ISO 8601 datetime string
    "level"     – severity string (e.g. "debug", "info", "warn", "error")
    "message"   – string
    "metadata"  – JSON object (arbitrary key/value pairs)

  Blank / whitespace-only lines are silently skipped.
  Lines that cannot be parsed (bad JSON, missing fields, bad timestamp)
  increment :malformed_count and are otherwise ignored.

  Requires the `jason` dependency in mix.exs:
      {:jason, "~> 1.4"}
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Analyze the log file at `path`.

  Returns `{:ok, report}` on success, where `report` is a map with keys:

    :counts_by_level  – %{level_string => integer}
    :error_rate       – float in [0.0, 1.0]
    :top_errors       – [{message, count}] (up to 10, desc by count)
    :time_range       – {first_dt, last_dt} | nil
    :errors_per_hour  – %{{date_tuple, hour} => integer}
    :malformed_count  – integer

  Returns `{:error, reason}` if the file cannot be opened.
  """
  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) do
    stream =
      path
      |> File.stream!(:line, [])

    # File.stream!/3 is lazy; it only raises on the first pull if the file is
    # missing, so we attempt to stat the file eagerly to produce a clean error.
    case File.stat(path) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _} ->
        report =
          stream
          |> Stream.map(&String.trim_trailing(&1, "\n"))
          |> Stream.map(&String.trim_trailing(&1, "\r"))
          |> Enum.reduce(initial_acc(), &process_line/2)
          |> build_report()

        {:ok, report}
    end
  end

  # ---------------------------------------------------------------------------
  # Accumulator helpers
  # ---------------------------------------------------------------------------

  # We accumulate everything we need in a single pass over the file.
  #
  #   counts_by_level  – %{level => count}
  #   error_messages   – %{message => count}   (only for level == "error")
  #   timestamps       – {min_dt, max_dt} | nil
  #   errors_per_hour  – %{{date, hour} => count}
  #   total            – total valid lines seen
  #   malformed        – malformed line count

  defp initial_acc do
    %{
      counts_by_level: %{},
      error_messages: %{},
      timestamps: nil,
      errors_per_hour: %{},
      total: 0,
      malformed: 0
    }
  end

  # ---------------------------------------------------------------------------
  # Per-line processing
  # ---------------------------------------------------------------------------

  defp process_line(raw_line, acc) do
    # Silently skip blank lines.
    trimmed = String.trim(raw_line)

    if trimmed == "" do
      acc
    else
      case parse_line(trimmed) do
        {:ok, entry} ->
          accumulate(acc, entry)

        :error ->
          %{acc | malformed: acc.malformed + 1}
      end
    end
  end

  # Attempt to parse a single non-blank line into a validated entry map.
  # Returns {:ok, entry} or :error.
  defp parse_line(trimmed) do
    with {:ok, obj} when is_map(obj) <- Jason.decode(trimmed),
         {:ok, ts_string} <- fetch_string(obj, "timestamp"),
         {:ok, level} <- fetch_string(obj, "level"),
         {:ok, message} <- fetch_string(obj, "message"),
         false <- Map.has_key?(obj, "metadata") && is_map(obj["metadata"]),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok, %{timestamp: dt, level: level, message: message}}
    else
      _ -> :error
    end
  end

  # Fetch a key from a map and verify its value is a string.
  defp fetch_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  # Parse an ISO 8601 string into a DateTime using the standard library.
  # DateTime.from_iso8601/1 handles offsets; we normalise to UTC.
  defp parse_timestamp(ts_string) do
    case DateTime.from_iso8601(ts_string) do
      {:ok, dt, _offset} ->
        {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}

      {:error, _} ->
        :error
    end
  end

  # ---------------------------------------------------------------------------
  # Accumulation
  # ---------------------------------------------------------------------------

  defp accumulate(acc, %{timestamp: dt, level: level, message: message}) do
    acc
    |> update_counts(level)
    |> update_timestamps(dt)
    |> maybe_update_errors(level, message, dt)
    |> Map.update!(:total, &(&1 + 1))
  end

  defp update_counts(acc, level) do
    Map.update!(acc, :counts_by_level, fn counts ->
      Map.update(counts, level, 1, &(&1 + 1))
    end)
  end

  defp update_timestamps(acc, dt) do
    Map.update!(acc, :timestamps, fn
      nil ->
        {dt, dt}

      {min_dt, max_dt} ->
        new_min = if DateTime.compare(dt, min_dt) == :lt, do: dt, else: min_dt
        new_max = if DateTime.compare(dt, max_dt) == :gt, do: dt, else: max_dt
        {new_min, new_max}
    end)
  end

  defp maybe_update_errors(acc, "error", message, dt) do
    acc
    |> Map.update!(:error_messages, fn msgs ->
      Map.update(msgs, message, 1, &(&1 + 1))
    end)
    |> Map.update!(:errors_per_hour, fn eph ->
      bucket = hour_bucket(dt)
      Map.update(eph, bucket, 1, &(&1 + 1))
    end)
  end

  defp maybe_update_errors(acc, _level, _message, _dt), do: acc

  # Build a {date_tuple, hour} bucket key from a UTC DateTime.
  defp hour_bucket(%DateTime{year: y, month: m, day: d, hour: h}) do
    {{y, m, d}, h}
  end

  # ---------------------------------------------------------------------------
  # Report construction
  # ---------------------------------------------------------------------------

  defp build_report(acc) do
    %{
      counts_by_level: acc.counts_by_level,
      error_rate: compute_error_rate(acc),
      top_errors: compute_top_errors(acc.error_messages),
      time_range: acc.timestamps,
      errors_per_hour: acc.errors_per_hour,
      malformed_count: acc.malformed
    }
  end

  defp compute_error_rate(%{total: 0}), do: 0.0

  defp compute_error_rate(%{counts_by_level: counts, total: total}) do
    error_count = Map.get(counts, "error", 0)
    error_count / total
  end

  # Sort descending by count, then ascending alphabetically by message.
  # Take at most 10.
  defp compute_top_errors(error_messages) do
    error_messages
    |> Enum.sort(fn {msg_a, cnt_a}, {msg_b, cnt_b} ->
      cond do
        cnt_a != cnt_b -> cnt_a > cnt_b
        true -> msg_a <= msg_b
      end
    end)
    |> Enum.take(10)
  end
end
```

## Failing test report

```
9 of 15 test(s) failed:

  * test counts per log level are correct
      
      
      Assertion with == failed
      code:  assert r.counts_by_level == %{"info" => 2, "debug" => 1, "error" => 5, "warn" => 1}
      left:  %{}
      right: %{"debug" => 1, "error" => 5, "info" => 2, "warn" => 1}
      

  * test error rate is errors / valid lines
      
      
      Expected the difference between 0.0 and 0.5555555555555556 (0.5555555555555556) to be less than or equal to 0.0001
      

  * test malformed count is correct
      
      
      Assertion with == failed
      code:  assert r.malformed_count == 2
      left:  11
      right: 2
      

  * test top errors are sorted by frequency then alphabetically
      
      
      Assertion with == failed
      code:  assert r.top_errors == [{"db timeout", 3}, {"disk full", 1}, {"null pointer", 1}]
      left:  []
      right: [{"db timeout", 3}, {"disk full", 1}, {"null pointer", 1}]
      

  (…5 more)
```
