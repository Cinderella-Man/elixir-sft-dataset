defmodule GenTask.AcceptGatesTest do
  # End-to-end (subprocess-eval, zero-LLM) proof that the docs/12 §5.1 gates fire on
  # the REAL accept paths. Each test drives `Cycle.run/3` or `WriteTest.run/2` against
  # the actual evaluator (`scripts/eval_task.exs`) with `max_retries: 0`, so no repair
  # (and therefore no LLM transport) is ever invoked: an accept must pass every gate on
  # attempt 0, and a reject is final. async: false — `WriteTest.run/2` attaches the
  # global per-cycle log handler.
  use ExUnit.Case, async: false

  @moduletag timeout: 240_000

  alias GenTask.{Config, Cycle, WriteTest}

  @solution """
  defmodule Adder do
    @moduledoc "Adds and subtracts integers."

    @doc "Sum of `a` and `b`."
    @spec add(integer(), integer()) :: integer()
    def add(a, b), do: a + b

    @doc "Difference of `a` and `b`."
    @spec sub(integer(), integer()) :: integer()
    def sub(a, b), do: a - b
  end
  """

  @green_harness """
  defmodule AdderTest do
    use ExUnit.Case, async: false

    test "adds", do: assert(Adder.add(1, 2) == 3)
    test "subtracts", do: assert(Adder.sub(5, 2) == 3)
    test "add identity", do: assert(Adder.add(0, 7) == 7)
  end
  """

  @prompt "Write me an Adder module with add/2 and sub/2 for integers.\n"

  setup do
    tmp = Path.join(System.tmp_dir!(), "acc_gates_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  defp cfg(tmp) do
    %Config{
      max_retries: 0,
      per_fn_mutation: false,
      quality_gate: true,
      tasks_dir: Path.join(tmp, "tasks"),
      staging_dir: Path.join(tmp, "staging"),
      logs_dir: Path.join(tmp, "logs")
    }
  end

  defp ctx(tmp, id) do
    %{
      dir: Path.join([tmp, "staging", id]),
      mutant_dir: Path.join([tmp, "staging", id <> "_mut"]),
      id: id
    }
  end

  defp triplet(harness) do
    %{"prompt.md" => @prompt, "solution.ex" => @solution, "test_harness.exs" => harness}
  end

  test "a clean triplet passes every gate; the result carries the honest mutation mode",
       %{tmp: tmp} do
    result = Cycle.run(triplet(@green_harness), ctx(tmp, "acc_ok"), cfg(tmp))

    assert result.status == :accepted
    assert result.mutant_failed == true
    # per_fn_mutation: false → the whole-solution mutant ran (docs/12 item 5).
    assert result.mutation == "whole"
    # The stability confirmation passed — no flake was recorded.
    refute File.exists?(Path.join([tmp, "logs", "flaky.jsonl"]))
  end

  test "the test-count floor rejects a green harness below max(3, public_fn_count)",
       %{tmp: tmp} do
    two_tests = """
    defmodule AdderTest do
      use ExUnit.Case, async: false

      test "adds", do: assert(Adder.add(1, 2) == 3)
      test "subtracts", do: assert(Adder.sub(5, 2) == 3)
    end
    """

    result = Cycle.run(triplet(two_tests), ctx(tmp, "acc_floor"), cfg(tmp))

    assert result.status == :rejected
    assert result.reason =~ "house style"
    assert result.reason =~ "only 2 test(s)"
    assert result.mutation == nil
  end

  test "an S9 hard anti-pattern (exact raise-message pin) rejects a green harness",
       %{tmp: tmp} do
    pinned = """
    defmodule AdderTest do
      use ExUnit.Case, async: false

      test "adds", do: assert(Adder.add(1, 2) == 3)
      test "subtracts", do: assert(Adder.sub(5, 2) == 3)

      test "message pin" do
        assert_raise ArgumentError, "boom", fn -> raise ArgumentError, "boom" end
      end
    end
    """

    result = Cycle.run(triplet(pinned), ctx(tmp, "acc_s9"), cfg(tmp))

    assert result.status == :rejected
    assert result.reason =~ "exact exception message"
  end

  test "the stability confirmation catches an order-dependent harness and logs the flake",
       %{tmp: tmp} do
    # Green at the evaluator's pinned seed 0, red at ANY other seed — a deterministic
    # stand-in for order-dependence that proves the EVAL_SEED threading end-to-end.
    seed_pinned = """
    defmodule AdderTest do
      use ExUnit.Case, async: false

      test "order-dependent", do: assert(ExUnit.configuration()[:seed] == 0)
      test "adds", do: assert(Adder.add(1, 2) == 3)
      test "subtracts", do: assert(Adder.sub(5, 2) == 3)
    end
    """

    result = Cycle.run(triplet(seed_pinned), ctx(tmp, "acc_flake"), cfg(tmp))

    assert result.status == :rejected
    assert result.reason =~ "stability confirmation failed"
    assert result.reason =~ "seed #{Cycle.confirmation_seed("acc_flake")}"

    # Flake evidence landed in the validate.exs ledger shape.
    flaky = Path.join([tmp, "logs", "flaky.jsonl"])
    assert File.exists?(flaky)
    entry = flaky |> File.read!() |> String.trim() |> Jason.decode!()
    assert entry["task"] == "acc_flake"
    assert entry["detail"] =~ "stability-confirmation"
    assert [%{"test" => name} | _] = entry["failures"]
    assert name =~ "order-dependent"
  end

  test "a wt_ mint is rejected when the gold harness compiles with warnings; an accepted " <>
         "mint records inherited coverage, not a mutant kill",
       %{tmp: tmp} do
    warning_harness = """
    defmodule AdderTest do
      use ExUnit.Case, async: false

      test "adds" do
        unused = 1
        assert Adder.add(1, 2) == 3
      end
    end
    """

    seed = fn task_id, harness ->
      %{
        num: 42,
        slug: "adder",
        b: 1,
        task_id: task_id,
        files: %{
          "prompt.md" => @prompt,
          "solution.ex" => @solution,
          "test_harness.exs" => harness
        }
      }
    end

    config = cfg(tmp)
    File.mkdir_p!(config.tasks_dir)

    # Warnings → rejected (docs/12 item 1 at the wt_ accept site).
    assert [rejected] = WriteTest.run(seed.("042_001_adder_01", warning_harness), config)
    assert rejected.status == :rejected
    assert rejected.reason =~ "warning"
    assert rejected.mutant_failed == false
    assert rejected.mutation == nil

    # Clean gold → accepted with the honest "inherited" mode (docs/12 item 5): no
    # mutant EVER runs at a wt_ mint, so mutant_failed must not claim a kill.
    assert [accepted] = WriteTest.run(seed.("043_001_adder_01", @green_harness), config)
    assert accepted.status == :accepted
    assert accepted.mutant_failed == false
    assert accepted.mutation == "inherited"
  end
end
