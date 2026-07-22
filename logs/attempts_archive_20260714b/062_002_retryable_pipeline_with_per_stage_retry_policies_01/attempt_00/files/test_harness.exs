defmodule PipelineTest do
  use ExUnit.Case, async: false

  defp ok_stage(fun), do: fn input -> {:ok, fun.(input)} end
  defp always_fail(reason), do: fn _input -> {:error, reason} end

  test "new/0 returns a Pipeline struct" do
    assert %Pipeline{} = Pipeline.new()
  end

  test "empty pipeline returns input unchanged with empty metadata" do
    assert {:ok, 42, []} = Pipeline.run(Pipeline.new(), 42)
  end

  test "single successful stage with no retries has attempts: 1" do
    pipeline = Pipeline.new() |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, 84, [%{stage: :double, attempts: 1, duration_us: d}]} =
             Pipeline.run(pipeline, 42)

    assert is_integer(d) and d >= 0
  end

  test "three stages thread results in order" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:add_one, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))
      |> Pipeline.stage(:to_string, ok_stage(&Integer.to_string/1))

    assert {:ok, "10", metadata} = Pipeline.run(pipeline, 4)
    assert Enum.map(metadata, & &1.stage) == [:add_one, :double, :to_string]
    assert Enum.all?(metadata, &(&1.attempts == 1))
  end

  test "a flaky stage succeeds after retries and reports attempts" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 3, do: {:error, :flaky}, else: {:ok, v * 10}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, flaky, retries: 5)

    assert {:ok, 20, [%{stage: :s, attempts: 3}]} = Pipeline.run(pipeline, 2)
  end

  test "exhausting the retry budget halts with the attempts count" do
    pipeline = Pipeline.new() |> Pipeline.stage(:x, always_fail(:nope), retries: 2)
    assert {:error, :x, :nope, 3} = Pipeline.run(pipeline, 1)
  end

  test "default retries is zero (single attempt)" do
    pipeline = Pipeline.new() |> Pipeline.stage(:x, always_fail(:boom))
    assert {:error, :x, :boom, 1} = Pipeline.run(pipeline, 1)
  end

  test "stages after a permanently failing stage are never called" do
    {:ok, ran?} = Agent.start_link(fn -> false end)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fail, always_fail(:dead), retries: 1)
      |> Pipeline.stage(:next, fn v ->
        Agent.update(ran?, fn _ -> true end)
        {:ok, v}
      end)

    assert {:error, :fail, :dead, 2} = Pipeline.run(pipeline, 0)
    refute Agent.get(ran?, & &1)
  end

  test "duration accumulates across attempts" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    slow_flaky = fn v ->
      Process.sleep(5)
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 3, do: {:error, :retry}, else: {:ok, v}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, slow_flaky, retries: 5)

    assert {:ok, 7, [%{attempts: 3, duration_us: d}]} = Pipeline.run(pipeline, 7)
    # 3 attempts sleeping ~5ms each
    assert d >= 10_000
  end

  test "backoff option still succeeds within budget" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :again}, else: {:ok, v + 1}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, flaky, retries: 3, backoff_ms: 2)
    assert {:ok, 6, [%{attempts: 2}]} = Pipeline.run(pipeline, 5)
  end

  test "only the failing stage is retried; earlier stages run once" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    first = fn v -> {:ok, v + 1} end

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :x}, else: {:ok, v}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, first)
      |> Pipeline.stage(:flaky, flaky, retries: 3)

    assert {:ok, 6, [%{stage: :first, attempts: 1}, %{stage: :flaky, attempts: 2}]} =
             Pipeline.run(pipeline, 5)
  end
end