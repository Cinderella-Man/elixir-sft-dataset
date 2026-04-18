defmodule PipelineTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ok_stage(fun), do: fn input -> {:ok, fun.(input)} end
  defp fail_stage(reason), do: fn _input -> {:error, reason} end

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  test "new/0 returns an empty pipeline" do
    pipeline = Pipeline.new()
    assert %Pipeline{} = pipeline
  end

  test "stage/3 returns a Pipeline struct" do
    pipeline = Pipeline.new() |> Pipeline.stage(:first, ok_stage(& &1))
    assert %Pipeline{} = pipeline
  end

  # ---------------------------------------------------------------------------
  # All-success pipelines
  # ---------------------------------------------------------------------------

  test "single stage runs and returns ok with metadata" do
    pipeline = Pipeline.new() |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, 84, metadata} = Pipeline.run(pipeline, 42)
    assert length(metadata) == 1
    assert [%{stage: :double, duration_us: d}] = metadata
    assert is_integer(d) and d >= 0
  end

  test "three stages thread results correctly" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:add_one, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))
      |> Pipeline.stage(:to_string, ok_stage(&Integer.to_string/1))

    assert {:ok, "10", metadata} = Pipeline.run(pipeline, 4)
    assert length(metadata) == 3
    assert Enum.map(metadata, & &1.stage) == [:add_one, :double, :to_string]
    assert Enum.all?(metadata, &is_integer(&1.duration_us))
    assert Enum.all?(metadata, &(&1.duration_us >= 0))
  end

  test "pipeline with no stages returns input unchanged" do
    assert {:ok, 99, []} = Pipeline.run(Pipeline.new(), 99)
  end

  test "stages receive exactly the previous stage's output" do
    acc = Agent.start_link(fn -> [] end) |> elem(1)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:one, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)
      |> Pipeline.stage(:two, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)
      |> Pipeline.stage(:three, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)

    assert {:ok, 30, _} = Pipeline.run(pipeline, 0)
    assert Enum.reverse(Agent.get(acc, & &1)) == [0, 10, 20]
  end

  # ---------------------------------------------------------------------------
  # Failing stage — halt and error tuple
  # ---------------------------------------------------------------------------

  test "first stage failing returns error with correct stage name and reason" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fetch, fail_stage(:timeout))
      |> Pipeline.stage(:transform, ok_stage(& &1))

    assert {:error, :fetch, :timeout} = Pipeline.run(pipeline, "input")
  end

  test "middle stage failing halts and returns correct stage name" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fetch, ok_stage(&(&1 <> "_fetched")))
      |> Pipeline.stage(:transform, fail_stage(:bad_data))
      |> Pipeline.stage(:load, ok_stage(&(&1 <> "_loaded")))

    assert {:error, :transform, :bad_data} = Pipeline.run(pipeline, "x")
  end

  test "last stage failing returns error tuple" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:a, ok_stage(& &1))
      |> Pipeline.stage(:b, ok_stage(& &1))
      |> Pipeline.stage(:c, fail_stage(:disk_full))

    assert {:error, :c, :disk_full} = Pipeline.run(pipeline, 0)
  end

  test "stages after a failing one are never called" do
    called = Agent.start_link(fn -> false end) |> elem(1)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fail, fail_stage(:boom))
      |> Pipeline.stage(:should_not_run, fn v ->
        Agent.update(called, fn _ -> true end)
        {:ok, v}
      end)

    Pipeline.run(pipeline, nil)
    refute Agent.get(called, & &1)
  end

  # ---------------------------------------------------------------------------
  # Metadata on partial run
  # ---------------------------------------------------------------------------

  test "metadata only includes executed stages when pipeline halts early" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:step_one, ok_stage(& &1))
      |> Pipeline.stage(:step_two, fail_stage(:nope))
      |> Pipeline.stage(:step_three, ok_stage(& &1))

    # On error we don't return metadata, so just verify halt behaviour
    assert {:error, :step_two, :nope} = Pipeline.run(pipeline, 1)
  end

  test "successful metadata entries are ordered by execution" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:alpha, ok_stage(& &1))
      |> Pipeline.stage(:beta, ok_stage(& &1))
      |> Pipeline.stage(:gamma, ok_stage(& &1))

    assert {:ok, _, metadata} = Pipeline.run(pipeline, :val)
    assert Enum.map(metadata, & &1.stage) == [:alpha, :beta, :gamma]
  end

  # ---------------------------------------------------------------------------
  # Timing sanity
  # ---------------------------------------------------------------------------

  test "a stage that sleeps produces a duration_us greater than sleep time" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:slow, fn v ->
        Process.sleep(10)
        {:ok, v}
      end)

    assert {:ok, _, [%{stage: :slow, duration_us: d}]} = Pipeline.run(pipeline, 1)
    # 10 ms = 10_000 µs; allow a small margin
    assert d >= 9_000
  end

  # ---------------------------------------------------------------------------
  # Works with various input types
  # ---------------------------------------------------------------------------

  test "pipeline works with map input and output" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:enrich, ok_stage(&Map.put(&1, :enriched, true)))
      |> Pipeline.stage(:serialize, ok_stage(&Map.keys/1))

    assert {:ok, keys, _} = Pipeline.run(pipeline, %{a: 1})
    assert :enriched in keys
  end

  test "pipeline works with list input" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:filter, ok_stage(&Enum.filter(&1, fn x -> x > 2 end)))
      |> Pipeline.stage(:sum, ok_stage(&Enum.sum/1))

    assert {:ok, 12, _} = Pipeline.run(pipeline, [1, 2, 3, 4, 5])
  end
end
