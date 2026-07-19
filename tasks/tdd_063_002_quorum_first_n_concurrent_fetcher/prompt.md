# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule QuorumFetcherTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp slow_ok(value, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:ok, value}
    end
  end

  defp slow_error(reason, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:error, reason}
    end
  end

  defp slow_raise(msg, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      raise RuntimeError, msg
    end
  end

  # -------------------------------------------------------
  # Quorum behaviour
  # -------------------------------------------------------

  test "returns as soon as the quorum of successes is reached and cancels the rest" do
    sources = [
      {:a, slow_ok(:ra, 20)},
      {:b, slow_ok(:rb, 20)},
      {:c, slow_ok(:rc, 20)},
      {:d, slow_ok(:rd, 3_000)},
      {:e, slow_ok(:re, 3_000)}
    ]

    start = System.monotonic_time(:millisecond)
    result = QuorumFetcher.fetch_first(sources, 3, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert result[:a] == {:ok, :ra}
    assert result[:b] == {:ok, :rb}
    assert result[:c] == {:ok, :rc}
    assert result[:d] == {:error, :cancelled}
    assert result[:e] == {:error, :cancelled}
    assert elapsed < 500, "should not wait for the slow sources (took #{elapsed}ms)"
  end

  test "sources that finish with an error do not count toward the quorum" do
    sources = [
      {:err, slow_error(:nope, 10)},
      {:win, slow_ok(:yes, 120)}
    ]

    result = QuorumFetcher.fetch_first(sources, 1, 1_000)

    assert result[:err] == {:error, :nope}
    assert result[:win] == {:ok, :yes}
  end

  test "a crashing source is reported as an error, not a success" do
    sources = [
      {:boom, slow_raise("kaboom", 10)},
      {:win, slow_ok(:yes, 120)}
    ]

    result = QuorumFetcher.fetch_first(sources, 1, 1_000)

    assert {:error, reason} = result[:boom]
    assert reason != :cancelled
    assert reason != :timeout
    assert result[:win] == {:ok, :yes}
  end

  # -------------------------------------------------------
  # Timeout behaviour
  # -------------------------------------------------------

  test "still-running sources become :timeout when the quorum can't be met in time" do
    sources = [
      {:a, slow_ok(:a, 10)},
      {:b, slow_ok(:b, 10)},
      {:c, slow_ok(:c, 3_000)},
      {:d, slow_ok(:d, 3_000)},
      {:e, slow_ok(:e, 3_000)}
    ]

    result = QuorumFetcher.fetch_first(sources, 5, 150)

    assert result[:a] == {:ok, :a}
    assert result[:b] == {:ok, :b}
    assert result[:c] == {:error, :timeout}
    assert result[:d] == {:error, :timeout}
    assert result[:e] == {:error, :timeout}
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty sources returns an empty map" do
    assert QuorumFetcher.fetch_first([], 3, 1_000) == %{}
  end

  test "a non-positive quorum cancels every source without running it" do
    sources = [
      {:a, slow_ok(:a, 10)},
      {:b, slow_ok(:b, 10)}
    ]

    result = QuorumFetcher.fetch_first(sources, 0, 1_000)

    assert result == %{a: {:error, :cancelled}, b: {:error, :cancelled}}
  end

  test "supports arbitrary term keys" do
    sources = [
      {"s", slow_ok(1, 10)},
      {42, slow_ok(2, 10)},
      {{:t}, slow_ok(3, 10)}
    ]

    result = QuorumFetcher.fetch_first(sources, 3, 1_000)

    assert result["s"] == {:ok, 1}
    assert result[42] == {:ok, 2}
    assert result[{:t}] == {:ok, 3}
  end

  # -------------------------------------------------------
  # No zombie processes
  # -------------------------------------------------------

  test "cancelled and timed-out sources leave no zombie processes behind" do
    before_pids = MapSet.new(Process.list())

    sources = for i <- 1..10, do: {i, slow_ok(i, 3_000)}

    QuorumFetcher.fetch_first(sources, 2, 100)
    Process.sleep(50)

    new_pids = MapSet.difference(MapSet.new(Process.list()), before_pids)

    assert MapSet.size(new_pids) == 0,
           "expected no leftover processes, found #{inspect(MapSet.to_list(new_pids))}"
  end

  test "a non-positive quorum never invokes any fetch function" do
    parent = self()

    probe = fn name ->
      fn ->
        send(parent, {:invoked, name})
        {:ok, name}
      end
    end

    sources = [{:a, probe.(:a)}, {:b, probe.(:b)}]

    assert QuorumFetcher.fetch_first(sources, -1, 1_000) ==
             %{a: {:error, :cancelled}, b: {:error, :cancelled}}

    refute_receive {:invoked, _}, 100
  end

  test "every source has started before any of them is allowed to complete" do
    parent = self()

    gated = fn name ->
      fn ->
        send(parent, {:started, name, self()})

        receive do
          :go -> {:ok, name}
        end
      end
    end

    sources = [{:a, gated.(:a)}, {:b, gated.(:b)}, {:c, gated.(:c)}]

    caller =
      Task.async(fn -> QuorumFetcher.fetch_first(sources, 1, 5_000) end)

    assert_receive {:started, :a, pid_a}, 1_000
    assert_receive {:started, :b, _}, 1_000
    assert_receive {:started, :c, _}, 1_000

    send(pid_a, :go)

    result = Task.await(caller, 5_000)

    assert result[:a] == {:ok, :a}
    assert result[:b] == {:error, :cancelled}
    assert result[:c] == {:error, :cancelled}
  end

  test "a cancelled source's fetch function is interrupted before it can finish its work" do
    parent = self()

    winner = fn ->
      send(parent, {:started, :w, self()})

      receive do
        :go -> {:ok, :w}
      end
    end

    loser = fn ->
      send(parent, {:started, :slow, self()})

      receive do
        :never -> :ok
      after
        1_000 -> send(parent, {:completed, :slow})
      end

      {:ok, :slow}
    end

    sources = [{:w, winner}, {:slow, loser}]

    caller =
      Task.async(fn -> QuorumFetcher.fetch_first(sources, 1, 5_000) end)

    assert_receive {:started, :w, pid_w}, 1_000
    assert_receive {:started, :slow, _}, 1_000

    send(pid_w, :go)

    result = Task.await(caller, 5_000)

    assert result[:w] == {:ok, :w}
    assert result[:slow] == {:error, :cancelled}
    refute_receive {:completed, :slow}, 1_500
  end

  test "no spawned process is still alive the moment fetch_first returns" do
    parent = self()

    hang = fn name ->
      fn ->
        send(parent, {:pid, name, self()})

        receive do
          :never -> {:ok, name}
        end
      end
    end

    sources = [{:a, hang.(:a)}, {:b, hang.(:b)}, {:c, hang.(:c)}]

    result = QuorumFetcher.fetch_first(sources, 3, 100)

    assert_receive {:pid, :a, pid_a}, 1_000
    assert_receive {:pid, :b, pid_b}, 1_000
    assert_receive {:pid, :c, pid_c}, 1_000

    for pid <- [pid_a, pid_b, pid_c] do
      refute Process.alive?(pid),
             "spawned process #{inspect(pid)} outlived fetch_first"
    end

    assert result[:a] == {:error, :timeout}
    assert result[:b] == {:error, :timeout}
    assert result[:c] == {:error, :timeout}
  end

  test "on timeout, finished failing and crashing sources keep their real outcome" do
    sources = [
      {:err, slow_error(:nope, 10)},
      {:boom, slow_raise("kaboom", 10)},
      {:slow, slow_ok(:s, 3_000)}
    ]

    result = QuorumFetcher.fetch_first(sources, 3, 200)

    assert result[:err] == {:error, :nope}
    assert {:error, reason} = result[:boom]
    assert reason != :timeout
    assert reason != :cancelled
    assert result[:slow] == {:error, :timeout}
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
