# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `parse_timestamp` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Write me an Elixir module called `MetricAggregator` that parses a structured
metrics file and produces a statistical summary report.

Each line of the input file is an independent JSON object with these fields:
- `"timestamp"` — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`)
- `"name"`      — a non-empty string identifying the metric (e.g. `"cpu_usage"`)
- `"value"`     — a number (integer or float)
- `"tags"`      — a JSON object of string key/value pairs (arbitrary)

I need one public function:

    MetricAggregator.summarize(path :: String.t()) :: {:ok, report} | {:error, reason}

Where `report` is a plain map with exactly these keys:

- `:per_metric`       — a map from metric name string to a stats map containing:
                          `:count`  — integer number of samples
                          `:min`    — number (smallest value seen)
                          `:max`    — number (largest value seen)
                          `:sum`    — number (sum of all values)
                          `:mean`   — float (sum / count)
                         Only metrics actually seen in the file appear.
- `:total_samples`    — integer count of all valid lines processed
- `:time_range`       — a `{first_dt, last_dt}` tuple of `DateTime` structs
                         (the earliest and latest timestamps across all valid
                         lines); `nil` if no valid lines
- `:samples_per_hour` — a map from a `{date_tuple, hour}` tuple
                         (e.g. `{{2024,1,15}, 14}`) to integer count of
                         valid samples in that UTC hour bucket; only hours
                         with at least one sample appear
- `:unique_tags`      — a map from tag key string to a `MapSet` of all
                         distinct tag values seen for that key across
                         all valid lines
- `:malformed_count`  — integer count of lines that could not be parsed as
                         valid JSON or were missing/invalid required fields

Lines that are blank or contain only whitespace should be skipped silently
(they don't count as malformed).

Error handling rules:
- If the file does not exist or cannot be opened, return `{:error, reason}`.
- Every other failure (bad JSON, missing fields, wrong types) is counted in
  `:malformed_count`; the line is skipped and processing continues.
- A line is considered malformed if ANY of these is true:
  - It is not valid JSON
  - The top-level JSON value is not an object
  - Any of `"timestamp"`, `"name"`, `"value"`, or `"tags"` is absent
  - `"timestamp"` cannot be parsed as an ISO 8601 datetime
  - `"name"` is not a non-empty string
  - `"value"` is not a number (integer or float)
  - `"tags"` is not a JSON object

Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp
parsing. No other external dependencies.

Stream the file line-by-line so the module can handle files larger than memory.

Give me the complete module in a single file.

## The module with `parse_timestamp` missing

```elixir
defmodule MetricAggregator do
  @moduledoc """
  Parses a structured, newline-delimited JSON metrics file and produces a
  statistical summary report.

  Each line must be a JSON object with the fields:
    "timestamp" – ISO 8601 datetime string
    "name"      – non-empty string identifying the metric
    "value"     – number (integer or float)
    "tags"      – JSON object of string key/value pairs

  Blank / whitespace-only lines are silently skipped.
  Lines that cannot be parsed (bad JSON, missing fields, wrong types)
  increment :malformed_count and are otherwise ignored.

  Requires the `jason` dependency in mix.exs:
      {:jason, "~> 1.4"}
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Summarize the metrics file at `path`.

  Returns `{:ok, report}` on success, where `report` is a map with keys:

    :per_metric       – %{name_string => %{count, min, max, sum, mean}}
    :total_samples    – integer
    :time_range       – {first_dt, last_dt} | nil
    :samples_per_hour – %{{date_tuple, hour} => integer}
    :unique_tags      – %{tag_key => MapSet.t(tag_values)}
    :malformed_count  – integer

  Returns `{:error, reason}` if the file does not exist or cannot be opened
  (for example when `path` points at a directory).
  """
  @spec summarize(String.t()) :: {:ok, map()} | {:error, term()}
  def summarize(path) do
    with :ok <- ensure_readable(path) do
      report =
        path
        |> File.stream!(:line, [])
        |> Stream.map(&String.trim_trailing(&1, "\n"))
        |> Stream.map(&String.trim_trailing(&1, "\r"))
        |> Enum.reduce(initial_acc(), &process_line/2)
        |> build_report()

      {:ok, report}
    end
  rescue
    error in [File.Error] -> {:error, error.reason}
  end

  # ---------------------------------------------------------------------------
  # Openability check
  # ---------------------------------------------------------------------------

  # Opening the path (rather than only stat-ing it) rejects directories,
  # permission problems and other non-streamable entries up front.
  defp ensure_readable(path) do
    case File.open(path, [:read]) do
      {:ok, io_device} ->
        File.close(io_device)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Accumulator helpers
  # ---------------------------------------------------------------------------

  defp initial_acc do
    %{
      per_metric: %{},
      timestamps: nil,
      samples_per_hour: %{},
      unique_tags: %{},
      total: 0,
      malformed: 0
    }
  end

  # ---------------------------------------------------------------------------
  # Per-line processing
  # ---------------------------------------------------------------------------

  defp process_line(raw_line, acc) do
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

  defp parse_line(trimmed) do
    with {:ok, obj} when is_map(obj) <- Jason.decode(trimmed),
         {:ok, ts_string} <- fetch_string(obj, "timestamp"),
         {:ok, name} <- fetch_nonempty_string(obj, "name"),
         {:ok, value} <- fetch_number(obj, "value"),
         {:ok, tags} <- fetch_tags(obj, "tags"),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok, %{timestamp: dt, name: name, value: value, tags: tags}}
    else
      _ -> :error
    end
  end

  defp fetch_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp fetch_nonempty_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> :error
    end
  end

  defp fetch_number(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_number(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp fetch_tags(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp parse_timestamp(ts_string) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Accumulation
  # ---------------------------------------------------------------------------

  defp accumulate(acc, %{timestamp: dt, name: name, value: value, tags: tags}) do
    acc
    |> update_metric_stats(name, value)
    |> update_timestamps(dt)
    |> update_samples_per_hour(dt)
    |> update_unique_tags(tags)
    |> Map.update!(:total, &(&1 + 1))
  end

  defp update_metric_stats(acc, name, value) do
    Map.update!(acc, :per_metric, fn metrics ->
      Map.update(metrics, name, %{count: 1, min: value, max: value, sum: value}, fn stats ->
        %{
          stats
          | count: stats.count + 1,
            min: min(stats.min, value),
            max: max(stats.max, value),
            sum: stats.sum + value
        }
      end)
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

  defp update_samples_per_hour(acc, dt) do
    bucket = hour_bucket(dt)

    Map.update!(acc, :samples_per_hour, fn sph ->
      Map.update(sph, bucket, 1, &(&1 + 1))
    end)
  end

  defp update_unique_tags(acc, tags) do
    Map.update!(acc, :unique_tags, fn ut ->
      Enum.reduce(tags, ut, fn {k, v}, tag_acc ->
        Map.update(tag_acc, k, MapSet.new([v]), &MapSet.put(&1, v))
      end)
    end)
  end

  defp hour_bucket(%DateTime{year: y, month: m, day: d, hour: h}) do
    {{y, m, d}, h}
  end

  # ---------------------------------------------------------------------------
  # Report construction
  # ---------------------------------------------------------------------------

  defp build_report(acc) do
    %{
      per_metric: finalize_metrics(acc.per_metric),
      total_samples: acc.total,
      time_range: acc.timestamps,
      samples_per_hour: acc.samples_per_hour,
      unique_tags: acc.unique_tags,
      malformed_count: acc.malformed
    }
  end

  defp finalize_metrics(per_metric) do
    Map.new(per_metric, fn {name, stats} ->
      {name, Map.put(stats, :mean, stats.sum / stats.count)}
    end)
  end
end
```

Reply with `parse_timestamp` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
