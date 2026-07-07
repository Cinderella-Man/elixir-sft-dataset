# Fill in the middle: `LogAnalyzer.parse_line/1`

Implement the private `parse_line/1` function. It receives a single non-blank,
already-trimmed line (a `String.t()`) and must attempt to decode and validate it
into a normalized log entry.

It should:

- Decode the line as JSON using `Jason.decode/1`, requiring the decoded value to
  be a map (a JSON object). If it is not valid JSON, or the top-level value is not
  an object, the line is malformed.
- Extract the `"timestamp"`, `"level"`, and `"message"` fields, each of which must
  be present and a string. Use the `fetch_string/2` helper for this.
- Require a `"metadata"` field that is present and is itself a map (JSON object).
- Parse the timestamp string into a UTC `DateTime` using the `parse_timestamp/1`
  helper.
- On success, return `{:ok, entry}` where `entry` is a map with keys
  `:timestamp` (the parsed `DateTime`), `:level` (the level string), and
  `:message` (the message string).
- If ANY of the above steps fail (bad JSON, non-object, a missing or non-string
  required field, missing/non-object `metadata`, or an unparseable timestamp),
  return `:error`.

A `with` expression whose `else` clause funnels every failure to `:error` is a
natural fit here.

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
    # TODO
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