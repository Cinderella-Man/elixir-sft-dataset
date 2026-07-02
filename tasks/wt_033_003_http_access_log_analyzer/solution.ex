defmodule AccessLogAnalyzer do
  @moduledoc """
  Parses a structured, newline-delimited JSON HTTP access log file and produces
  a traffic analysis report.

  Each line must be a JSON object with the fields:
    "timestamp"   – ISO 8601 datetime string
    "method"      – HTTP method string
    "path"        – request path string
    "status_code" – integer HTTP status code
    "duration_ms" – number (response time in milliseconds)

  Blank / whitespace-only lines are silently skipped.
  Lines that cannot be parsed increment :malformed_count and are otherwise ignored.

  Requires the `jason` dependency in mix.exs:
      {:jason, "~> 1.4"}
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) do
    case File.stat(path) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _} ->
        report =
          path
          |> File.stream!([], :line)
          |> Stream.map(&String.trim_trailing(&1, "\n"))
          |> Stream.map(&String.trim_trailing(&1, "\r"))
          |> Enum.reduce(initial_acc(), &process_line/2)
          |> build_report()

        {:ok, report}
    end
  end

  # ---------------------------------------------------------------------------
  # Accumulator
  # ---------------------------------------------------------------------------

  defp initial_acc do
    %{
      by_method: %{},
      by_status: %{},
      path_counts: %{},
      duration_sum: 0.0,
      max_duration: nil,
      timestamps: nil,
      requests_per_minute: %{},
      total: 0,
      error_count: 0,
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
         {:ok, method} <- fetch_string(obj, "method"),
         {:ok, req_path} <- fetch_string(obj, "path"),
         {:ok, status_code} <- fetch_integer(obj, "status_code"),
         {:ok, duration_ms} <- fetch_number(obj, "duration_ms"),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok,
       %{
         timestamp: dt,
         method: method,
         path: req_path,
         status_code: status_code,
         duration_ms: duration_ms
       }}
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

  defp fetch_integer(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp fetch_number(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_number(value) -> {:ok, value}
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

  defp accumulate(acc, entry) do
    acc
    |> update_method(entry.method)
    |> update_status(entry.status_code)
    |> update_path(entry.path)
    |> update_duration(entry.path, entry.duration_ms)
    |> update_timestamps(entry.timestamp)
    |> update_requests_per_minute(entry.timestamp)
    |> update_error_count(entry.status_code)
    |> Map.update!(:total, &(&1 + 1))
  end

  defp update_method(acc, method) do
    Map.update!(acc, :by_method, fn m -> Map.update(m, method, 1, &(&1 + 1)) end)
  end

  defp update_status(acc, status_code) do
    Map.update!(acc, :by_status, fn m -> Map.update(m, status_code, 1, &(&1 + 1)) end)
  end

  defp update_path(acc, path) do
    Map.update!(acc, :path_counts, fn m -> Map.update(m, path, 1, &(&1 + 1)) end)
  end

  defp update_duration(acc, path, duration_ms) do
    acc = %{acc | duration_sum: acc.duration_sum + duration_ms}

    case acc.max_duration do
      nil ->
        %{acc | max_duration: {path, duration_ms}}

      {existing_path, existing_dur} ->
        cond do
          duration_ms > existing_dur ->
            %{acc | max_duration: {path, duration_ms}}

          duration_ms == existing_dur and path < existing_path ->
            %{acc | max_duration: {path, duration_ms}}

          true ->
            acc
        end
    end
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

  defp update_requests_per_minute(acc, dt) do
    bucket = minute_bucket(dt)

    Map.update!(acc, :requests_per_minute, fn rpm ->
      Map.update(rpm, bucket, 1, &(&1 + 1))
    end)
  end

  defp update_error_count(acc, status_code) when status_code >= 400 do
    %{acc | error_count: acc.error_count + 1}
  end

  defp update_error_count(acc, _status_code), do: acc

  defp minute_bucket(%DateTime{year: y, month: mo, day: d, hour: h, minute: m}) do
    {{y, mo, d}, {h, m}}
  end

  # ---------------------------------------------------------------------------
  # Report construction
  # ---------------------------------------------------------------------------

  defp build_report(acc) do
    %{
      requests_by_method: acc.by_method,
      requests_by_status: acc.by_status,
      top_paths: compute_top_paths(acc.path_counts),
      avg_duration: compute_avg_duration(acc),
      max_duration: acc.max_duration,
      error_rate: compute_error_rate(acc),
      requests_per_minute: acc.requests_per_minute,
      time_range: acc.timestamps,
      malformed_count: acc.malformed
    }
  end

  defp compute_top_paths(path_counts) do
    path_counts
    |> Enum.sort(fn {path_a, cnt_a}, {path_b, cnt_b} ->
      cond do
        cnt_a != cnt_b -> cnt_a > cnt_b
        true -> path_a <= path_b
      end
    end)
    |> Enum.take(10)
  end

  defp compute_avg_duration(%{total: 0}), do: 0.0

  defp compute_avg_duration(%{duration_sum: sum, total: total}) do
    sum / total
  end

  defp compute_error_rate(%{total: 0}), do: 0.0

  defp compute_error_rate(%{error_count: errors, total: total}) do
    errors / total
  end
end
