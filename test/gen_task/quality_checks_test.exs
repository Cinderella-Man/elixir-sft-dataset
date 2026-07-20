defmodule GenTask.QualityChecksTest do
  # quality_checks/2 is the named-check list behind the quality gate (T1.9 gate
  # transparency). The binding property: quality_shortfall/2 must be EXACTLY the
  # joined {:fail, msg} entries of quality_checks/2 — the printed checks and the
  # accept decision can never disagree.
  use ExUnit.Case, async: true

  alias GenTask.Evaluator

  @clean_json %{
    "compiled" => true,
    "compile_warnings" => 0,
    "tests_total" => 5,
    "tests_passed" => 5,
    "analysis" => %{
      "has_moduledoc" => true,
      "has_typespecs" => true,
      "has_doc_on_public_fns" => true,
      "todo_count" => 0,
      "lines_over_98" => 0,
      "sql_injection_risk" => false,
      "public_fn_count" => 3
    }
  }

  @dirty_harness """
  defmodule XTest do
    use ExUnit.Case, async: false
    test "peeks" do
      assert :sys.get_state(pid).count == 1
      assert inspect(x) == "[1]"
    end
  end
  """

  test "a clean grade with no files: JSON checks ok, text checks skipped" do
    checks = Evaluator.quality_checks(@clean_json)

    assert length(checks) == 19
    json_backed = Enum.take(checks, 8)
    text_backed = Enum.drop(checks, 8)

    assert Enum.all?(json_backed, fn {_label, r} -> r == :ok end)
    assert Enum.all?(text_backed, fn {_label, r} -> r == :skip end)
    assert Evaluator.quality_shortfall(@clean_json) == nil
  end

  test "shortfall is exactly the joined fail messages, in check order" do
    json = put_in(@clean_json, ["analysis", "has_moduledoc"], false)
    files = %{"test_harness.exs" => @dirty_harness, "prompt.md" => "p", "solution.ex" => "x"}

    checks = Evaluator.quality_checks(json, files)
    fails = for {_label, {:fail, msg}} <- checks, do: msg

    assert length(fails) >= 3
    assert Evaluator.quality_shortfall(json, files) == Enum.join(fails, "; ")

    # And the order is the manifest order: moduledoc (a JSON check) before the
    # S9 harness checks.
    assert [first | _] = fails
    assert first == "no @moduledoc"
  end

  test "every check carries a stable, human-readable label" do
    labels = for {label, _} <- Evaluator.quality_checks(@clean_json), do: label

    assert "zero compile warnings" in labels
    assert "test-count floor: max(3, public function count)" in labels
    assert "S9: no :sys.get_state/:sys.replace_state reach-ins" in labels
    assert "no generation-process chatter in comments" in labels
    assert "prompt documents every API function the harness calls" in labels
    assert labels == Enum.uniq(labels)
  end
end
