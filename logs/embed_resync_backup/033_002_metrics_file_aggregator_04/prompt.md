# Task: implement `update_timestamps/2`

You are working on the `MetricAggregator` module (below). Every function is
already implemented **except** the private function `update_timestamps/2`, whose
body has been replaced with `# TODO`. Implement it.

## What `update_timestamps/2` must do

`update_timestamps/2` maintains the running earliest/latest timestamp seen while
folding over the file. It takes the accumulator map (`acc`) and a `DateTime`
struct (`dt`) for the current line, and returns the accumulator with its
`:timestamps` field updated.

The `:timestamps` field holds either:

- `nil` — when no valid line has been seen yet, or
- a `{min_dt, max_dt}` tuple — the earliest and latest `DateTime`s seen so far.

Update `:timestamps` (using `Map.update!/3`) as follows:

- If the current value is `nil`, set it to `{dt, dt}` (this `dt` is both the
  earliest and latest so far).
- If the current value is `{min_dt, max_dt}`, produce a new tuple where:
  - the new minimum is `dt` when `dt` is strictly earlier than `min_dt`,
    otherwise `min_dt`;
  - the new maximum is `dt` when `dt` is strictly later than `max_dt`,
    otherwise `max_dt`.

Use `DateTime.compare/2` (which returns `:lt`, `:eq`, or `:gt`) to compare
timestamps. Return the updated accumulator.

## Module

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

  Returns `{:error, reason}` if the file cannot be opened.
  """
  @spec summarize(String.t()) :: {:ok, map()} | {:error, term()}
  def summarize(path) do
    case File.stat(path) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _} ->
        report =
          path
          |> File.stream!(:line, [])
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
    # TODO
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