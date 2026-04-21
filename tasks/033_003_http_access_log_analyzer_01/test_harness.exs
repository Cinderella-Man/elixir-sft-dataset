defmodule AccessLogAnalyzerTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tmp_path(name) do
    dir = System.tmp_dir!()
    Path.join(dir, "access_log_test_#{name}_#{System.unique_integer([:positive])}.jsonl")
  end

  defp write_lines(path, lines) do
    File.write!(path, Enum.join(lines, "\n") <> "\n")
  end

  defp access_line(timestamp, method, path, status_code, duration_ms) do
    Jason.encode!(%{
      "timestamp" => timestamp,
      "method" => method,
      "path" => path,
      "status_code" => status_code,
      "duration_ms" => duration_ms
    })
  end

  # ---------------------------------------------------------------------------
  # Known-distribution fixture
  #
  # Layout (all times UTC):
  #   2024-01-15T10:00:00Z  GET   /api/users      200  12.5
  #   2024-01-15T10:00:30Z  GET   /api/users      200  15.0
  #   2024-01-15T10:01:00Z  POST  /api/users      201  45.3
  #   2024-01-15T10:01:30Z  GET   /api/products   200  8.2
  #   2024-01-15T10:02:00Z  GET   /api/users      404  3.1
  #   2024-01-15T11:00:00Z  GET   /api/products   500  250.0
  #   2024-01-15T11:05:00Z  DELETE /api/users/1   204  22.0
  #   2024-01-15T12:00:00Z  GET   /healthcheck    200  1.5
  #   <blank line>
  #   <malformed JSON>
  #   <missing status_code>
  # ---------------------------------------------------------------------------

  defp write_fixture(path) do
    lines = [
      access_line("2024-01-15T10:00:00Z", "GET", "/api/users", 200, 12.5),
      access_line("2024-01-15T10:00:30Z", "GET", "/api/users", 200, 15.0),
      access_line("2024-01-15T10:01:00Z", "POST", "/api/users", 201, 45.3),
      access_line("2024-01-15T10:01:30Z", "GET", "/api/products", 200, 8.2),
      access_line("2024-01-15T10:02:00Z", "GET", "/api/users", 404, 3.1),
      access_line("2024-01-15T11:00:00Z", "GET", "/api/products", 500, 250.0),
      access_line("2024-01-15T11:05:00Z", "DELETE", "/api/users/1", 204, 22.0),
      access_line("2024-01-15T12:00:00Z", "GET", "/healthcheck", 200, 1.5),
      "",
      "not json!!!",
      Jason.encode!(%{"timestamp" => "2024-01-15T12:01:00Z", "method" => "GET", "path" => "/x"})
      # ^^^ missing status_code and duration_ms
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
    {:ok, report} = AccessLogAnalyzer.analyze(path)
    %{report: report}
  end

  test "requests_by_method counts are correct", %{report: r} do
    assert r.requests_by_method == %{
             "GET" => 6,
             "POST" => 1,
             "DELETE" => 1
           }
  end

  test "requests_by_status counts are correct", %{report: r} do
    assert r.requests_by_status == %{
             200 => 4,
             201 => 1,
             204 => 1,
             404 => 1,
             500 => 1
           }
  end

  test "top_paths sorted by frequency then alphabetically", %{report: r} do
    # /api/users: 3, /api/products: 2, /api/users/1: 1, /healthcheck: 1
    assert r.top_paths == [
             {"/api/users", 3},
             {"/api/products", 2},
             {"/api/users/1", 1},
             {"/healthcheck", 1}
           ]
  end

  test "top_paths contains at most 10 entries", %{report: r} do
    assert length(r.top_paths) <= 10
  end

  test "avg_duration is correct", %{report: r} do
    # (12.5 + 15.0 + 45.3 + 8.2 + 3.1 + 250.0 + 22.0 + 1.5) / 8
    expected = (12.5 + 15.0 + 45.3 + 8.2 + 3.1 + 250.0 + 22.0 + 1.5) / 8
    assert_in_delta r.avg_duration, expected, 0.001
  end

  test "max_duration picks the slowest request", %{report: r} do
    assert r.max_duration == {"/api/products", 250.0}
  end

  test "error_rate counts status >= 400", %{report: r} do
    # 404 + 500 = 2 errors out of 8 valid lines
    assert_in_delta r.error_rate, 2 / 8, 0.0001
  end

  test "malformed count is correct", %{report: r} do
    assert r.malformed_count == 2
  end

  test "time range covers first and last valid timestamps", %{report: r} do
    {:ok, expected_first, _} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
    {:ok, expected_last, _} = DateTime.from_iso8601("2024-01-15T12:00:00Z")

    {first, last} = r.time_range
    assert DateTime.compare(first, expected_first) == :eq
    assert DateTime.compare(last, expected_last) == :eq
  end

  test "requests_per_minute buckets are correct", %{report: r} do
    assert r.requests_per_minute == %{
             {{2024, 1, 15}, {10, 0}} => 2,
             {{2024, 1, 15}, {10, 1}} => 2,
             {{2024, 1, 15}, {10, 2}} => 1,
             {{2024, 1, 15}, {11, 0}} => 1,
             {{2024, 1, 15}, {11, 5}} => 1,
             {{2024, 1, 15}, {12, 0}} => 1
           }
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "empty file returns zero counts" do
    path = tmp_path("empty")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.requests_by_method == %{}
    assert report.requests_by_status == %{}
    assert report.top_paths == []
    assert report.avg_duration == 0.0
    assert report.max_duration == nil
    assert report.error_rate == 0.0
    assert report.time_range == nil
    assert report.requests_per_minute == %{}
    assert report.malformed_count == 0
  end

  test "file with only blank lines returns zero counts" do
    path = tmp_path("blanks")
    write_lines(path, ["", "   ", "\t"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 0
    assert report.time_range == nil
  end

  test "file with only malformed lines" do
    path = tmp_path("all_bad")
    write_lines(path, ["oops", "{}", ~s({"method": "GET"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 3
    assert report.avg_duration == 0.0
    assert report.time_range == nil
  end

  test "nonexistent file returns an error tuple" do
    assert {:error, _reason} = AccessLogAnalyzer.analyze("/no/such/file/ever.jsonl")
  end

  test "single valid line produces consistent report" do
    path = tmp_path("single")
    write_lines(path, [access_line("2024-03-20T08:30:00Z", "GET", "/ping", 200, 5.0)])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.requests_by_method == %{"GET" => 1}
    assert report.avg_duration == 5.0
    assert report.max_duration == {"/ping", 5.0}
    assert report.error_rate == 0.0
    assert report.malformed_count == 0
    {first, last} = report.time_range
    assert DateTime.compare(first, last) == :eq
  end

  test "max_duration tie is broken alphabetically by path" do
    path = tmp_path("tie")

    lines = [
      access_line("2024-01-01T00:00:00Z", "GET", "/z", 200, 100.0),
      access_line("2024-01-01T00:01:00Z", "GET", "/a", 200, 100.0)
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.max_duration == {"/a", 100.0}
  end

  test "top_paths caps at 10 distinct paths" do
    path = tmp_path("top10")

    lines =
      for i <- 1..15 do
        access_line("2024-06-01T00:00:0#{rem(i, 10)}Z", "GET", "/path/#{i}", 200, 1.0)
      end

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert length(report.top_paths) == 10
  end

  test "status_code as float is malformed" do
    path = tmp_path("float_status")
    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "method" => "GET",
        "path" => "/x",
        "status_code" => 200.0,
        "duration_ms" => 5
      })
    ])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 1
  end

  test "requests_per_minute spans multiple calendar days" do
    path = tmp_path("multiday")

    lines = [
      access_line("2024-01-01T23:59:00Z", "GET", "/a", 200, 1.0),
      access_line("2024-01-02T00:01:00Z", "GET", "/b", 200, 2.0)
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)

    assert report.requests_per_minute == %{
             {{2024, 1, 1}, {23, 59}} => 1,
             {{2024, 1, 2}, {0, 1}} => 1
           }
  end
end
