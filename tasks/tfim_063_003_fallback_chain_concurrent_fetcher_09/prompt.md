# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule FallbackFetcher do
  @moduledoc """
  Fetches from multiple sources concurrently under a single global timeout,
  where each source carries an ordered chain of fallback functions.

  Sources run concurrently with one another; within a source the fallbacks are
  attempted sequentially until one succeeds or the chain is exhausted. Any
  source still working when the shared deadline fires is killed and reported as
  `{:error, :timeout}`.
  """

  @doc """
  Fetch from all sources concurrently, returning within `timeout_ms`.

  Returns `%{name => result_tuple}` where each value is `{:ok, value}`,
  `{:error, {:all_failed, reasons}}`, or `{:error, :timeout}`.
  """
  @spec fetch_all([{term(), [(-> {:ok, term()} | {:error, term()})]}], non_neg_integer()) ::
          %{term() => {:ok, term()} | {:error, term()}}
  def fetch_all([], _timeout_ms), do: %{}

  def fetch_all(sources, timeout_ms)
      when is_list(sources) and is_integer(timeout_ms) and timeout_ms >= 0 do
    tagged =
      Enum.map(sources, fn {name, fetch_fns} ->
        task = Task.async(fn -> run_chain(fetch_fns, []) end)
        {name, task}
      end)

    tasks = Enum.map(tagged, fn {_name, task} -> task end)
    yields = Task.yield_many(tasks, timeout_ms)

    ref_to_result =
      Enum.reduce(yields, %{}, fn {task, outcome}, acc ->
        result =
          case outcome do
            {:ok, {:ok, value}} ->
              {:ok, value}

            {:ok, {:error, reasons}} ->
              {:error, {:all_failed, reasons}}

            {:exit, reason} ->
              {:error, reason}

            nil ->
              Task.shutdown(task, :brutal_kill)
              {:error, :timeout}
          end

        Map.put(acc, task.ref, result)
      end)

    Map.new(tagged, fn {name, task} -> {name, Map.fetch!(ref_to_result, task.ref)} end)
  end

  # Tries each fallback in order. Returns `{:ok, value}` on the first success,
  # or `{:error, reasons}` (reasons in attempt order) if the chain is exhausted.
  defp run_chain([], reasons), do: {:error, Enum.reverse(reasons)}

  defp run_chain([fetch_fn | rest], reasons) do
    case safe_call(fetch_fn) do
      {:ok, _} = ok -> ok
      {:error, reason} -> run_chain(rest, [reason | reasons])
    end
  end

  # Normalises any exception, throw, exit, or unexpected return into a tagged
  # `{:ok, _} | {:error, _}` tuple so a fallback can never crash the caller.
  defp safe_call(fetch_fn) do
    case fetch_fn.() do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, value -> {:error, {kind, value}}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule FallbackFetcherTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp fast_ok(value), do: fn -> {:ok, value} end
  defp fast_error(reason), do: fn -> {:error, reason} end
  defp fast_raise(msg), do: fn -> raise RuntimeError, msg end

  defp slow_ok(value, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:ok, value}
    end
  end

  # -------------------------------------------------------
  # Fallback-chain behaviour
  # -------------------------------------------------------

  test "uses the first fallback when it succeeds" do
    result = FallbackFetcher.fetch_all([{:a, [fast_ok(:first), fast_ok(:second)]}], 1_000)
    assert result[:a] == {:ok, :first}
  end

  test "falls through to the next fallback on error" do
    result = FallbackFetcher.fetch_all([{:a, [fast_error(:down), fast_ok(:backup)]}], 1_000)
    assert result[:a] == {:ok, :backup}
  end

  test "treats a raising fallback as a failure and continues" do
    result = FallbackFetcher.fetch_all([{:a, [fast_raise("boom"), fast_ok(:recovered)]}], 1_000)
    assert result[:a] == {:ok, :recovered}
  end

  test "reports all_failed with the ordered list of reasons when every fallback fails" do
    result =
      FallbackFetcher.fetch_all(
        [{:a, [fast_error(:one), fast_error(:two), fast_raise("three")]}],
        1_000
      )

    assert {:error, {:all_failed, reasons}} = result[:a]
    assert length(reasons) == 3
    assert Enum.at(reasons, 0) == :one
    assert Enum.at(reasons, 1) == :two
    assert %RuntimeError{message: "three"} = Enum.at(reasons, 2)
  end

  # -------------------------------------------------------
  # Timeout behaviour
  # -------------------------------------------------------

  test "a chain that overruns the global timeout is reported as :timeout" do
    sources = [
      {:fast, [fast_ok(:done)]},
      {:slow, [slow_ok(:never, 2_000)]}
    ]

    result = FallbackFetcher.fetch_all(sources, 150)

    assert result[:fast] == {:ok, :done}
    assert result[:slow] == {:error, :timeout}
  end

  # -------------------------------------------------------
  # Concurrency
  # -------------------------------------------------------

  test "sources run concurrently, not sequentially" do
    sources = for i <- 1..5, do: {i, [slow_ok(i, 100)]}

    start = System.monotonic_time(:millisecond)
    result = FallbackFetcher.fetch_all(sources, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert Enum.all?(1..5, fn i -> result[i] == {:ok, i} end)
    assert elapsed < 300, "fetches appear sequential (took #{elapsed}ms)"
  end

  # -------------------------------------------------------
  # Edge cases and no zombies
  # -------------------------------------------------------

  test "empty sources returns an empty map" do
    assert FallbackFetcher.fetch_all([], 1_000) == %{}
  end

  test "timed-out chains leave no zombie processes behind" do
    # TODO
  end

  test "mixes success, exhausted fallbacks, and timeout" do
    sources = [
      {:ok_src, [fast_error(:x), fast_ok(:good)]},
      {:dead, [fast_error(:a), fast_error(:b)]},
      {:slow, [slow_ok(:never, 2_000)]}
    ]

    result = FallbackFetcher.fetch_all(sources, 150)

    assert result[:ok_src] == {:ok, :good}
    assert {:error, {:all_failed, [:a, :b]}} = result[:dead]
    assert result[:slow] == {:error, :timeout}
  end
end
```
