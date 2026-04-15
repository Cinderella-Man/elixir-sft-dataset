defmodule LogAnalyzerTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tmp_path(name) do
    dir = System.tmp_dir!()
    Path.join(dir, "log_analyzer_test_#{name}_#{System.unique_integer([:positive])}.log")
  end

  defp write_lines(path, lines) do
    File.write!(path, Enum.join(lines, "\n") <> "\n")
  end

  defp log_line(timestamp, level, message, metadata \\ %{}) do
    Jason.encode!(%{
      "timestamp" => timestamp,
      "level" => level,
      "message" => message,
      "metadata" => metadata
    })
  end

  # ---------------------------------------------------------------------------
  # Known-distribution fixture
  #
  # Layout (all times UTC):
  #   2024-01-15T10:00:00Z  info   "server started"
  #   2024-01-15T10:05:00Z  debug  "ping"
  #   2024-01-15T10:10:00Z  error  "db timeout"
  #   2024-01-15T10:15:00Z  error  "db timeout"
  #   2024-01-15T10:20:00Z  error  "disk full"
  #   2024-01-15T11:00:00Z  error  "db timeout"
  #   2024-01-15T11:30:00Z  warn   "high memory"
  #   2024-01-15T11:45:00Z  error  "null pointer"
  #   2024-01-15T12:00:00Z  info   "shutdown"
  #   <blank line>
  #   <malformed JSON>
  #   <missing field>
  # ---------------------------------------------------------------------------

  defp write_fixture(path) do
    lines = [
      log_line("2024-01-15T10:00:00Z", "info", "server started"),
      log_line("2024-01-15T10:05:00Z", "debug", "ping"),
      log_line("2024-01-15T10:10:00Z", "error", "db timeout"),
      log_line("2024-01-15T10:15:00Z", "error", "db timeout"),
      log_line("2024-01-15T10:20:00Z", "error", "disk full"),
      log_line("2024-01-15T11:00:00Z", "error", "db timeout"),
      log_line("2024-01-15T11:30:00Z", "warn", "high memory"),
      log_line("2024-01-15T11:45:00Z", "error", "null pointer"),
      log_line("2024-01-15T12:00:00Z", "info", "shutdown"),
      "",
      "not json at all!!!",
      Jason.encode!(%{"timestamp" => "2024-01-15T12:01:00Z", "level" => "info"})
      # ^^^ missing "message" and "metadata"
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
    {:ok, report} = LogAnalyzer.analyze(path)
    %{report: report}
  end

  test "counts per log level are correct", %{report: r} do
    assert r.counts_by_level == %{
             "info" => 2,
             "debug" => 1,
             "error" => 5,
             "warn" => 1
           }
  end

  test "error rate is errors / valid lines", %{report: r} do
    # 5 errors out of 9 valid lines
    assert_in_delta r.error_rate, 5 / 9, 0.0001
  end

  test "malformed count is correct", %{report: r} do
    # "not json at all!!!" + line missing required fields = 2
    assert r.malformed_count == 2
  end

  test "top errors are sorted by frequency then alphabetically", %{report: r} do
    # db timeout: 3, disk full: 1, null pointer: 1
    # tie between "disk full" and "null pointer" broken alphabetically
    assert r.top_errors == [
             {"db timeout", 3},
             {"disk full", 1},
             {"null pointer", 1}
           ]
  end

  test "top errors contains at most 10 entries", %{report: r} do
    assert length(r.top_errors) <= 10
  end

  test "time range covers first and last valid timestamps", %{report: r} do
    {:ok, expected_first, _} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
    {:ok, expected_last, _} = DateTime.from_iso8601("2024-01-15T12:00:00Z")

    {first, last} = r.time_range
    assert DateTime.compare(first, expected_first) == :eq
    assert DateTime.compare(last, expected_last) == :eq
  end

  test "errors per hour buckets are correct", %{report: r} do
    # Hour 10: errors at 10:10, 10:15, 10:20 → 3
    # Hour 11: errors at 11:00, 11:45 → 2
    assert r.errors_per_hour == %{
             {{2024, 1, 15}, 10} => 3,
             {{2024, 1, 15}, 11} => 2
           }
  end

  test "errors_per_hour only includes hours with at least one error", %{report: r} do
    refute Map.has_key?(r.errors_per_hour, {{2024, 1, 15}, 12})
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "empty file returns zero counts" do
    path = tmp_path("empty")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.counts_by_level == %{}
    assert report.error_rate == 0.0
    assert report.top_errors == []
    assert report.time_range == nil
    assert report.errors_per_hour == %{}
    assert report.malformed_count == 0
  end

  test "file with only blank lines returns zero counts" do
    path = tmp_path("blanks")
    write_lines(path, ["", "   ", "\t"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.malformed_count == 0
    assert report.time_range == nil
  end

  test "file with only malformed lines" do
    path = tmp_path("all_bad")
    write_lines(path, ["oops", "{}", ~s({"ts": "x"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.malformed_count == 3
    assert report.error_rate == 0.0
    assert report.time_range == nil
  end

  test "nonexistent file returns an error tuple" do
    assert {:error, _reason} = LogAnalyzer.analyze("/no/such/file/ever.log")
  end

  test "top errors caps at 10 distinct messages" do
    path = tmp_path("top10")

    # 15 distinct error messages, each appearing once
    lines =
      for i <- 1..15 do
        log_line("2024-06-01T00:00:0#{rem(i, 10)}Z", "error", "error message #{i}")
      end

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert length(report.top_errors) == 10
  end

  test "single valid line produces consistent report" do
    path = tmp_path("single")
    write_lines(path, [log_line("2024-03-20T08:30:00Z", "info", "hello")])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.counts_by_level == %{"info" => 1}
    assert report.error_rate == 0.0
    assert report.malformed_count == 0
    {first, last} = report.time_range
    assert DateTime.compare(first, last) == :eq
  end

  test "errors_per_hour spans multiple calendar days correctly" do
    path = tmp_path("multiday")

    lines = [
      log_line("2024-01-01T23:59:00Z", "error", "midnight error"),
      log_line("2024-01-02T00:01:00Z", "error", "new day error")
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)

    assert report.errors_per_hour == %{
             {{2024, 1, 1}, 23} => 1,
             {{2024, 1, 2}, 0} => 1
           }
  end
end
