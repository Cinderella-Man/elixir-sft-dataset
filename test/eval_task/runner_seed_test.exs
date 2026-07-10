defmodule EvalTask.RunnerSeedTest do
  # EVAL_SEED threads an ExUnit seed override into the evaluator subprocess so the
  # generation loop's stability-confirmation re-grade can break the pinned test order
  # (docs/12 §5.1 item 6). async: false — the tests mutate the process environment.
  use ExUnit.Case, async: false

  alias EvalTask.Runner

  setup do
    original = System.get_env("EVAL_SEED")

    on_exit(fn ->
      if original, do: System.put_env("EVAL_SEED", original), else: System.delete_env("EVAL_SEED")
    end)

    :ok
  end

  test "defaults to the pinned seed 0 when EVAL_SEED is unset" do
    System.delete_env("EVAL_SEED")
    assert Runner.ex_unit_seed() == 0
  end

  test "reads a valid integer override" do
    System.put_env("EVAL_SEED", "12345")
    assert Runner.ex_unit_seed() == 12_345
  end

  test "falls back to 0 on a malformed or negative value (deterministic, never crashes)" do
    for bad <- ["abc", "12x", "", "-5"] do
      System.put_env("EVAL_SEED", bad)
      assert Runner.ex_unit_seed() == 0
    end
  end
end
