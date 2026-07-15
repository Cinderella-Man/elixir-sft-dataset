System.put_env("SCRIPTS_NO_AUTORUN", "1")
Code.require_file("scripts/rubric_judge.exs")

defmodule Scripts.RubricJudgeTest do
  # async: false — done_keys tests point RUBRIC_JUDGE_LEDGER at a sandbox.
  use ExUnit.Case, async: false

  defp scores(a, b, c),
    do: %{
      "scores" => %{
        "requirement_conformance" => a,
        "logical_correctness" => b,
        "edge_case_consideration" => c
      }
    }

  describe "agreement/1" do
    test "within one point agrees; a two-point gap does not" do
      ag = RubricJudge.agreement([scores(5, 5, 5), scores(4, 5, 3)])
      assert ag["requirement_conformance"] == true
      assert ag["logical_correctness"] == true
      assert ag["edge_case_consideration"] == false
    end

    test "an errored judge yields nil — an unknown, never an agreement" do
      ag = RubricJudge.agreement([scores(5, 5, 5), %{"error" => "boom"}])
      assert Enum.all?(Map.values(ag), &is_nil/1)
    end
  end

  describe "validate_rubric/1 (the reply contract)" do
    defp rubric_json(map), do: %{"rubric.json" => Jason.encode!(map)}

    test "accepts a complete verdict" do
      good = Map.put(scores(5, 4, 5), "issues", [])
      assert :ok = RubricJudge.validate_rubric(rubric_json(good))
    end

    test "rejects a missing axis, an out-of-range score, and a bad issue" do
      no_axis = %{"scores" => %{"logical_correctness" => 5}, "issues" => []}
      assert {:error, _} = RubricJudge.validate_rubric(rubric_json(no_axis))

      out_of_range = Map.put(scores(5, 4, 6), "issues", [])
      assert {:error, _} = RubricJudge.validate_rubric(rubric_json(out_of_range))

      bad_issue =
        Map.put(scores(5, 4, 3), "issues", [
          %{"axis" => "style", "evidence" => "x", "why" => "y", "severity" => "high"}
        ])

      assert {:error, _} = RubricJudge.validate_rubric(rubric_json(bad_issue))
    end
  end

  describe "done_keys/0 resume semantics" do
    setup do
      dir = Path.join(System.tmp_dir!(), "rubric_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      ledger = Path.join(dir, "ledger.jsonl")
      System.put_env("RUBRIC_JUDGE_LEDGER", ledger)

      on_exit(fn ->
        System.delete_env("RUBRIC_JUDGE_LEDGER")
        File.rm_rf!(dir)
      end)

      %{ledger: ledger}
    end

    defp row(task, judges) do
      %{
        "task" => task,
        "prompt_sha" => "p",
        "solution_sha" => "s",
        "harness_sha" => "h",
        "rubric_sha" => "r",
        "judges" => judges
      }
    end

    test "a complete row counts as done; a row with a judge error re-runs", %{ledger: ledger} do
      complete = row("a_01", [scores(5, 5, 5), scores(5, 5, 4)])
      errored = row("b_01", [scores(5, 5, 5), %{"error" => "error_max_turns"}])
      File.write!(ledger, Jason.encode!(complete) <> "\n" <> Jason.encode!(errored) <> "\n")

      keys = RubricJudge.done_keys()
      assert MapSet.member?(keys, "a_01|p|s|h|r")
      refute MapSet.member?(keys, "b_01|p|s|h|r")
    end
  end
end
