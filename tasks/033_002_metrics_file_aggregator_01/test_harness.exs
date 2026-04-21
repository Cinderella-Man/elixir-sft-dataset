defmodule MetricAggregatorTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tmp_path(name) do
    dir = System.tmp_dir!()
    Path.join(dir, "metric_agg_test_#{name}_#{System.unique_integer([:positive])}.jsonl")
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
    disk = r.per_metric["disk_io"]
    assert disk.count == 1
    assert disk.min == 500
    assert disk.max == 500
    assert disk.sum == 500
    assert_in_delta disk.mean, 500.0, 0.001
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
      Jason.encode!(%{"timestamp" => "2024-01-01T00:00:00Z", "name" => "", "value" => 1, "tags" => %{}})
    ])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 1
    assert report.total_samples == 0
  end

  test "line with string value is malformed" do
    path = tmp_path("string_value")
    write_lines(path, [
      Jason.encode!(%{"timestamp" => "2024-01-01T00:00:00Z", "name" => "x", "value" => "not_a_number", "tags" => %{}})
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
end
