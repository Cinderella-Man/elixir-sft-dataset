# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule MetricAggregatorTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tmp_path(name) do
    dir = System.tmp_dir!()

    Path.join(
      dir,
      "metric_agg_test_#{name}_#{System.pid()}_#{System.unique_integer([:positive])}.jsonl"
    )
  end

  defp write_lines(path, lines) do
    File.write!(path, Enum.join(lines, "\n") <> "\n")
  end

  defp metric_line(timestamp, name, value, tags \\ %{}) do
    Jason.encode!(%{
      "timestamp" => timestamp,
      "name" => name,
      "value" => value,
      "tags" => tags
    })
  end

  # ---------------------------------------------------------------------------
  # Known-distribution fixture
  #
  # Layout (all times UTC):
  #   2024-01-15T10:00:00Z  cpu_usage   45.2   {host: "a"}
  #   2024-01-15T10:05:00Z  cpu_usage   78.9   {host: "b"}
  #   2024-01-15T10:10:00Z  cpu_usage   23.1   {host: "a"}
  #   2024-01-15T10:20:00Z  mem_usage   1024   {host: "a", region: "us"}
  #   2024-01-15T11:00:00Z  mem_usage   2048   {host: "b", region: "eu"}
  #   2024-01-15T11:30:00Z  cpu_usage   90.0   {host: "c"}
  #   2024-01-15T12:00:00Z  disk_io     500    {host: "a"}
  #   <blank line>
  #   <malformed JSON>
  #   <missing "value" field>
  # ---------------------------------------------------------------------------

  defp write_fixture(path) do
    lines = [
      metric_line("2024-01-15T10:00:00Z", "cpu_usage", 45.2, %{"host" => "a"}),
      metric_line("2024-01-15T10:05:00Z", "cpu_usage", 78.9, %{"host" => "b"}),
      metric_line("2024-01-15T10:10:00Z", "cpu_usage", 23.1, %{"host" => "a"}),
      metric_line("2024-01-15T10:20:00Z", "mem_usage", 1024, %{"host" => "a", "region" => "us"}),
      metric_line("2024-01-15T11:00:00Z", "mem_usage", 2048, %{"host" => "b", "region" => "eu"}),
      metric_line("2024-01-15T11:30:00Z", "cpu_usage", 90.0, %{"host" => "c"}),
      metric_line("2024-01-15T12:00:00Z", "disk_io", 500, %{"host" => "a"}),
      "",
      "not json at all!!!",
      Jason.encode!(%{"timestamp" => "2024-01-15T12:01:00Z", "name" => "oops"})
      # ^^^ missing "value" and "tags"
    ]

    write_lines(path, lines)
  end

  # ---------------------------------------------------------------------------
  # Main fixture tests
  # ---------------------------------------------------------------------------

  setup do
    path = tmp_path("fixture")
    write_fixture(path)
    on_exit(fn -> File.rm(path) end)
    {:ok, report} = MetricAggregator.summarize(path)
    %{report: report}
  end

  test "per_metric stats for cpu_usage are correct", %{report: r} do
    cpu = r.per_metric["cpu_usage"]
    assert cpu.count == 4
    assert_in_delta cpu.min, 23.1, 0.001
    assert_in_delta cpu.max, 90.0, 0.001
    assert_in_delta cpu.sum, 237.2, 0.001
    assert_in_delta cpu.mean, 237.2 / 4, 0.001
  end

  test "per_metric stats for mem_usage are correct", %{report: r} do
    mem = r.per_metric["mem_usage"]
    assert mem.count == 2
    assert mem.min == 1024
    assert mem.max == 2048
    assert mem.sum == 3072
    assert_in_delta mem.mean, 1536.0, 0.001
  end

  test "per_metric stats for disk_io are correct", %{report: r} do
    # TODO
  end

  test "total_samples is correct", %{report: r} do
    assert r.total_samples == 7
  end

  test "malformed count is correct", %{report: r} do
    # "not json at all!!!" + line missing required fields = 2
    assert r.malformed_count == 2
  end

  test "time range covers first and last valid timestamps", %{report: r} do
    {:ok, expected_first, _} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
    {:ok, expected_last, _} = DateTime.from_iso8601("2024-01-15T12:00:00Z")

    {first, last} = r.time_range
    assert DateTime.compare(first, expected_first) == :eq
    assert DateTime.compare(last, expected_last) == :eq
  end

  test "samples_per_hour buckets are correct", %{report: r} do
    # Hour 10: 4 samples (10:00, 10:05, 10:10, 10:20)
    # Hour 11: 2 samples (11:00, 11:30)
    # Hour 12: 1 sample  (12:00)
    assert r.samples_per_hour == %{
             {{2024, 1, 15}, 10} => 4,
             {{2024, 1, 15}, 11} => 2,
             {{2024, 1, 15}, 12} => 1
           }
  end

  test "unique_tags collects distinct values per key", %{report: r} do
    assert MapSet.equal?(r.unique_tags["host"], MapSet.new(["a", "b", "c"]))
    assert MapSet.equal?(r.unique_tags["region"], MapSet.new(["us", "eu"]))
  end

  test "unique_tags only contains keys actually present", %{report: r} do
    assert Map.keys(r.unique_tags) |> Enum.sort() == ["host", "region"]
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "empty file returns zero counts" do
    path = tmp_path("empty")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.per_metric == %{}
    assert report.total_samples == 0
    assert report.time_range == nil
    assert report.samples_per_hour == %{}
    assert report.unique_tags == %{}
    assert report.malformed_count == 0
  end

  test "file with only blank lines returns zero counts" do
    path = tmp_path("blanks")
    write_lines(path, ["", "   ", "\t"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 0
    assert report.time_range == nil
  end

  test "file with only malformed lines" do
    path = tmp_path("all_bad")
    write_lines(path, ["oops", "{}", ~s({"name": "x"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 3
    assert report.total_samples == 0
    assert report.time_range == nil
  end

  test "nonexistent file returns an error tuple" do
    assert {:error, _reason} = MetricAggregator.summarize("/no/such/file/ever.jsonl")
  end

  test "single valid line produces consistent report" do
    path = tmp_path("single")
    write_lines(path, [metric_line("2024-03-20T08:30:00Z", "latency", 42.5, %{"env" => "prod"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.per_metric["latency"].count == 1
    assert_in_delta report.per_metric["latency"].mean, 42.5, 0.001
    assert report.total_samples == 1
    assert report.malformed_count == 0
    {first, last} = report.time_range
    assert DateTime.compare(first, last) == :eq
  end

  test "line with empty name string is malformed" do
    path = tmp_path("empty_name")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "name" => "",
        "value" => 1,
        "tags" => %{}
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 1
    assert report.total_samples == 0
  end

  test "line with string value is malformed" do
    path = tmp_path("string_value")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "name" => "x",
        "value" => "not_a_number",
        "tags" => %{}
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 1
    assert report.total_samples == 0
  end

  test "samples_per_hour spans multiple calendar days" do
    path = tmp_path("multiday")

    lines = [
      metric_line("2024-01-01T23:59:00Z", "x", 1),
      metric_line("2024-01-02T00:01:00Z", "x", 2)
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)

    assert report.samples_per_hour == %{
             {{2024, 1, 1}, 23} => 1,
             {{2024, 1, 2}, 0} => 1
           }
  end

  test "integer and float values are both accepted" do
    path = tmp_path("mixed_types")

    lines = [
      metric_line("2024-01-01T00:00:00Z", "m", 10),
      metric_line("2024-01-01T00:01:00Z", "m", 3.5)
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.per_metric["m"].count == 2
    assert report.per_metric["m"].min == 3.5
    assert report.per_metric["m"].max == 10
    assert_in_delta report.per_metric["m"].sum, 13.5, 0.001
  end

  test "line with unparsable timestamp is counted as malformed" do
    path = tmp_path("bad_timestamp")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "not-a-real-datetime",
        "name" => "x",
        "value" => 1,
        "tags" => %{}
      }),
      Jason.encode!(%{
        "timestamp" => "2024-13-45T99:99:99Z",
        "name" => "x",
        "value" => 1,
        "tags" => %{}
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 2
    assert report.total_samples == 0
    assert report.per_metric == %{}
    assert report.time_range == nil
  end

  test "line whose tags field is not an object is malformed" do
    path = tmp_path("bad_tags")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "name" => "x",
        "value" => 1,
        "tags" => ["a", "b"]
      }),
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:01:00Z",
        "name" => "x",
        "value" => 1,
        "tags" => "host=a"
      }),
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:02:00Z",
        "name" => "x",
        "value" => 1,
        "tags" => 7
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 3
    assert report.total_samples == 0
    assert report.unique_tags == %{}
  end

  test "lines whose top-level JSON value is not an object are malformed" do
    path = tmp_path("not_object")
    write_lines(path, ["[1, 2, 3]", "42", "\"hello\"", "true", "null"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 5
    assert report.total_samples == 0
    assert report.time_range == nil
  end

  test "path that cannot be opened as a file returns an error tuple" do
    dir = Path.join(System.tmp_dir!(), "metric_agg_dir_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:error, _reason} = MetricAggregator.summarize(dir)
  end

  test "report contains exactly the documented keys and stats keys", %{report: r} do
    assert Enum.sort(Map.keys(r)) == [
             :malformed_count,
             :per_metric,
             :samples_per_hour,
             :time_range,
             :total_samples,
             :unique_tags
           ]

    assert Enum.sort(Map.keys(r.per_metric["cpu_usage"])) == [:count, :max, :mean, :min, :sum]
    assert is_float(r.per_metric["mem_usage"].mean)
  end
end
```
