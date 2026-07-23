# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `compute_error_rate`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Design Brief: `LogAnalyzer`

## Problem

We have structured log files and need a way to parse one and produce an analysis report. Each line of the input file is an independent JSON object with these fields:

- `"timestamp"` — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`)
- `"level"`     — a string such as `"debug"`, `"info"`, `"warn"`, `"error"`
- `"message"`   — a string
- `"metadata"`  — a JSON object (arbitrary key/value pairs)

The deliverable is an Elixir module called `LogAnalyzer` that parses such a file and returns the report described below.

## Constraints

- Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp parsing. No other external dependencies.
- Stream the file line-by-line so the module can handle files larger than memory.
- Timestamps that carry an offset (e.g. `"2024-05-01T01:30:00+02:00"`) must be normalized to UTC before bucketing into `:errors_per_hour`, so a line at `+02:00` 01:30 falls in the `23` hour bucket of the previous UTC day.
- Lines that are blank or contain only whitespace should be skipped silently (they don't count as malformed).
- Error handling rules:
  - If the file does not exist or cannot be opened, return `{:error, reason}`.
  - Every other failure (bad JSON, missing fields, unparseable timestamp) is counted in `:malformed_count`; the line is skipped and processing continues.
  - A line is considered malformed if ANY of these is true:
    - It is not valid JSON
    - The top-level JSON value is not an object
    - Any of `"timestamp"`, `"level"`, `"message"`, or `"metadata"` is absent
    - `"timestamp"` is present but is not a string (e.g. a number or a nested object)
    - `"timestamp"` is a string that cannot be parsed as an ISO 8601 datetime
- Deliver the complete module in a single file.

## Required Interface

1. Provide exactly one public function:

       LogAnalyzer.analyze(path :: String.t()) :: {:ok, report} | {:error, reason}

2. On success, `report` is a plain map with exactly these keys:

   1. `:counts_by_level` — a map from level string to integer count (only levels actually seen in the file appear)
   2. `:error_rate` — a float between 0.0 and 1.0 representing errors / total_valid_lines; 0.0 if no valid lines
   3. `:top_errors` — a list of at most 10 `{message, count}` tuples, taken only from lines whose level is `"error"`, sorted descending by count, then alphabetically by message to break ties
   4. `:time_range` — a `{first_dt, last_dt}` tuple of `DateTime` structs (the earliest and latest timestamps seen across all valid lines); `nil` if no valid lines
   5. `:errors_per_hour` — a map from a `NaiveDateTime`-like label (use a plain `{date, hour}` tuple, e.g. `{{2024,1,15}, 14}`) to integer count of error lines in that UTC hour bucket; only hours that contain at least one error appear
   6. `:malformed_count` — integer count of lines that could not be parsed as valid JSON or were missing any required field or had a non-string timestamp that could not be decoded

## Acceptance Criteria

- `LogAnalyzer.analyze/1` returns `{:ok, report}` on success and `{:error, reason}` when the file does not exist or cannot be opened.
- The returned `report` map contains exactly the six keys above, each carrying the value described.
- `:counts_by_level` includes only levels actually seen in the file.
- `:error_rate` is a float between 0.0 and 1.0 equal to errors / total_valid_lines, and is 0.0 when there are no valid lines.
- `:top_errors` holds at most 10 `{message, count}` tuples drawn only from `"error"`-level lines, sorted descending by count with alphabetical message ordering breaking ties.
- `:time_range` is a `{first_dt, last_dt}` tuple of `DateTime` structs spanning the earliest and latest timestamps across all valid lines, or `nil` when there are no valid lines.
- `:errors_per_hour` maps each `{date, hour}` tuple (e.g. `{{2024,1,15}, 14}`) to the integer count of error lines in that UTC hour bucket, listing only hours with at least one error, with offset timestamps normalized to UTC first (so `+02:00` 01:30 lands in the `23` hour bucket of the previous UTC day).
- `:malformed_count` correctly counts every malformed line per the rules above, while blank/whitespace-only lines are skipped silently and never counted as malformed.
- Malformed lines are skipped and processing continues; only a missing/unopenable file yields `{:error, reason}`.
- The module uses `Jason` and the standard `DateTime` module with no other external dependencies, streams the file line-by-line to handle files larger than memory, and is delivered complete in a single file.

## The module with `compute_error_rate` missing

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

  Returns `{:error, reason}` if the file does not exist or cannot be opened
  (for example when `path` points at a directory).
  """
  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) do
    # File.stream!/3 is lazy and raises on the first pull, so we probe the path
    # eagerly with File.open/2. This catches missing files as well as paths that
    # exist but cannot be read (directories, permission errors, ...).
    case File.open(path, [:read]) do
      {:error, reason} ->
        {:error, reason}

      {:ok, io_device} ->
        File.close(io_device)
        stream_report(path)
    end
  end

  # ---------------------------------------------------------------------------
  # Streaming
  # ---------------------------------------------------------------------------

  # Stream the file line by line, folding into a single accumulator. Any I/O
  # failure that only surfaces once the stream is pulled is converted into an
  # {:error, reason} tuple rather than an exception.
  defp stream_report(path) do
    report =
      path
      |> File.stream!(:line, [])
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.map(&String.trim_trailing(&1, "\r"))
      |> Enum.reduce(initial_acc(), &process_line/2)
      |> build_report()

    {:ok, report}
  rescue
    error in File.Error -> {:error, error.reason}
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
         true <- Map.has_key?(obj, "metadata") && is_map(obj["metadata"]),
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

  defp compute_error_rate(%{total: 0}) do
    # TODO
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

Output only `compute_error_rate` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
