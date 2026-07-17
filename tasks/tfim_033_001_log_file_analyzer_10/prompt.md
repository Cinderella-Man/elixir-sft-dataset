# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  Returns `{:error, reason}` if the file does not exist or cannot be opened
  (for example when `path` points at a directory).
  """
  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) do
    # File.stream!/3 is lazy and raises on the first pull, so we probe the path
    # eagerly with File.open/2. This catches missing files as well as paths that
    # exist but cannot be read (directories, permission errors, ...).
    case File.open(path, [:read]) do
      {:error, reason} ->
        {:error, reason}

      {:ok, io_device} ->
        File.close(io_device)
        stream_report(path)
    end
  end

  # ---------------------------------------------------------------------------
  # Streaming
  # ---------------------------------------------------------------------------

  # Stream the file line by line, folding into a single accumulator. Any I/O
  # failure that only surfaces once the stream is pulled is converted into an
  # {:error, reason} tuple rather than an exception.
  defp stream_report(path) do
    report =
      path
      |> File.stream!(:line, [])
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.map(&String.trim_trailing(&1, "\r"))
      |> Enum.reduce(initial_acc(), &process_line/2)
      |> build_report()

    {:ok, report}
  rescue
    error in File.Error -> {:error, error.reason}
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
    with {:ok, obj} when is_map(obj) <- Jason.decode(trimmed),
         {:ok, ts_string} <- fetch_string(obj, "timestamp"),
         {:ok, level} <- fetch_string(obj, "level"),
         {:ok, message} <- fetch_string(obj, "message"),
         true <- Map.has_key?(obj, "metadata") && is_map(obj["metadata"]),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok, %{timestamp: dt, level: level, message: message}}
    else
      _ -> :error
    end
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

## Test harness — implement the `# TODO` test

```elixir
defmodule LogAnalyzerTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tmp_path(name) do
    dir = System.tmp_dir!()

    Path.join(
      dir,
      "log_analyzer_test_#{name}_#{System.pid()}_#{System.unique_integer([:positive])}.log"
    )
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
    # TODO
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

  test "path that exists but cannot be opened returns an error tuple" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "log_analyzer_test_dir_#{System.pid()}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:error, _reason} = LogAnalyzer.analyze(dir)
  end

  test "valid JSON that is not a top-level object counts as malformed" do
    path = tmp_path("not_object")

    write_lines(path, ["[1, 2, 3]", "\"just a string\"", "42", "null", "true"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.malformed_count == 5
    assert report.counts_by_level == %{}
    assert report.error_rate == 0.0
    assert report.time_range == nil
  end

  test "non-string timestamp values are counted as malformed" do
    path = tmp_path("nonstring_ts")

    lines = [
      log_line(1_705_327_402, "info", "numeric timestamp"),
      log_line(%{"iso" => "2024-01-15T14:03:22Z"}, "info", "object timestamp"),
      log_line("2024-01-15T14:03:22Z", "info", "good line")
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.malformed_count == 2
    assert report.counts_by_level == %{"info" => 1}
  end

  test "timestamps with offsets bucket into their UTC hour and time range" do
    path = tmp_path("offsets")

    lines = [
      log_line("2024-05-01T01:30:00+02:00", "error", "east of utc"),
      log_line("2024-05-01T00:30:00-05:00", "error", "west of utc")
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)

    assert report.errors_per_hour == %{
             {{2024, 4, 30}, 23} => 1,
             {{2024, 5, 1}, 5} => 1
           }

    {:ok, expected_first, _} = DateTime.from_iso8601("2024-04-30T23:30:00Z")
    {:ok, expected_last, _} = DateTime.from_iso8601("2024-05-01T05:30:00Z")
    {first, last} = report.time_range
    assert DateTime.compare(first, expected_first) == :eq
    assert DateTime.compare(last, expected_last) == :eq
  end
end
```
