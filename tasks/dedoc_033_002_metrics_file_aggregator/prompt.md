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
defmodule MetricAggregator do
  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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
