Implement the private `parse_line/1` function.

It receives a single already-trimmed, non-empty line of input (a `String.t()`)
and must attempt to turn it into a validated metric entry. It returns either
`{:ok, entry}` on success or the atom `:error` on any validation failure.

The function must succeed only when ALL of the following hold, using a `with`
pipeline so that any failing step short-circuits to `:error`:

1. The line is valid JSON that decodes (via `Jason.decode/1`) to a map (a
   top-level JSON object). If decoding fails or the decoded value is not a map,
   the line is malformed.
2. `"timestamp"` is present and is a string — use the `fetch_string/2` helper.
3. `"name"` is present and is a non-empty string — use the
   `fetch_nonempty_string/2` helper.
4. `"value"` is present and is a number (integer or float) — use the
   `fetch_number/2` helper.
5. `"tags"` is present and is a JSON object (a map) — use the `fetch_tags/2`
   helper.
6. The timestamp string parses as an ISO 8601 datetime — use the
   `parse_timestamp/1` helper, which yields a UTC `DateTime`.

On success, return `{:ok, %{timestamp: dt, name: name, value: value, tags: tags}}`
where `dt` is the parsed `DateTime`. On any failure of the above steps, return
`:error` (map the `else` clause of the `with` to `:error`).

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
    # TODO
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