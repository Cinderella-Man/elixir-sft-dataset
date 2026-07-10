defmodule GenTask.EvaluatorTest do
  use ExUnit.Case, async: true

  alias GenTask.Evaluator

  @green %{
    "compiled" => true,
    "tests_total" => 10,
    "tests_passed" => 10,
    "tests_failed" => 0,
    "tests_errors" => 0
  }

  describe "green?/1" do
    test "true when compiled, has tests, and no failures/errors" do
      assert Evaluator.green?(@green)
      assert Evaluator.green?({:ok, @green})
    end

    test "false on a timeout/crash" do
      refute Evaluator.green?(:timeout_or_crash)
    end

    test "false when not compiled" do
      refute Evaluator.green?(%{@green | "compiled" => false})
    end

    test "false when there are zero tests" do
      refute Evaluator.green?(%{@green | "tests_total" => 0})
    end

    test "false when a test failed" do
      refute Evaluator.green?(%{@green | "tests_failed" => 1})
    end

    test "false when a test errored" do
      refute Evaluator.green?(%{@green | "tests_errors" => 1})
    end

    test "false when no test actually passed (all skipped/excluded \u2014 docs/05 #19)" do
      # tests_total > 0 alone is satisfiable by an all-@tag-:skip harness whose
      # tests never ran; green? must demand positive evidence of a passing run.
      refute Evaluator.green?(%{@green | "tests_passed" => 0})
    end

    test "tolerates missing count keys (treated as zero)" do
      refute Evaluator.green?(%{"compiled" => true})
    end
  end

  describe "killed_by_tests?/1" do
    @killed %{"compiled" => true, "tests_total" => 10, "tests_passed" => 3, "tests_failed" => 7}

    test "true when the mutant compiled and tests ran and failed" do
      assert Evaluator.killed_by_tests?(@killed)
      assert Evaluator.killed_by_tests?({:ok, @killed})
    end

    test "false when the mutant did not compile (docs/05 #18)" do
      refute Evaluator.killed_by_tests?(%{@killed | "compiled" => false})
    end

    test "false when no test failed (harness load error / all skipped)" do
      refute Evaluator.killed_by_tests?(%{@killed | "tests_failed" => 0})
      refute Evaluator.killed_by_tests?(%{"compiled" => true, "tests_errors" => 1})
    end

    test "false on eval timeout" do
      refute Evaluator.killed_by_tests?(:timeout_or_crash)
    end
  end

  describe "errored_against_mutant?/1" do
    # The 074 macro-family shape (docs/10 §5.1): a gutted `defmacro` raises while the
    # harness COMPILES against the mutant — tests_errors with zero tests run. With
    # reference-green established by the caller, that error is mutation-caused.
    @errored %{"compiled" => true, "tests_total" => 0, "tests_errors" => 1}

    test "true when the mutant compiled and the harness errored" do
      assert Evaluator.errored_against_mutant?(@errored)
      assert Evaluator.errored_against_mutant?({:ok, @errored})
      assert Evaluator.errored_against_mutant?(%{@errored | "tests_total" => 5})
    end

    test "false when the mutant itself did not compile (tier-B manifest missing)" do
      refute Evaluator.errored_against_mutant?(%{@errored | "compiled" => false})
    end

    test "false without errors, and on eval timeout" do
      refute Evaluator.errored_against_mutant?(%{"compiled" => true, "tests_errors" => 0})
      refute Evaluator.errored_against_mutant?(:timeout_or_crash)
    end
  end

  describe "last_json_line/1" do
    test "returns the last brace-prefixed line" do
      out = "compiling...\n{\"a\":1}\nnoise\n{\"b\":2}\n"
      assert Evaluator.last_json_line(out) == "{\"b\":2}"
    end

    test "falls back to {} when no JSON line is present" do
      assert Evaluator.last_json_line("no json here\n") == "{}"
    end
  end

  describe "quality_shortfall/1" do
    @full %{
      "compile_warnings" => 0,
      "analysis" => %{
        "has_moduledoc" => true,
        "has_typespecs" => true,
        "has_doc_on_public_fns" => true,
        "todo_count" => 0
      }
    }

    test "nil when the solution meets the house style" do
      assert Evaluator.quality_shortfall(@full) == nil
    end

    test "flags a missing @spec" do
      json = put_in(@full, ["analysis", "has_typespecs"], false)
      assert Evaluator.quality_shortfall(json) =~ "@spec"
    end

    test "flags compile warnings" do
      assert Evaluator.quality_shortfall(%{@full | "compile_warnings" => 3}) =~ "compile warning"
    end

    test "flags over-98-column lines and SQL interpolation" do
      json =
        @full
        |> put_in(["analysis", "lines_over_98"], 2)
        |> put_in(["analysis", "sql_injection_risk"], true)

      report = Evaluator.quality_shortfall(json)
      assert report =~ "98 columns"
      assert report =~ "parameterized"
    end

    test "flags a TODO marker and joins multiple shortfalls" do
      json =
        @full
        |> put_in(["analysis", "has_moduledoc"], false)
        |> put_in(["analysis", "todo_count"], 1)

      report = Evaluator.quality_shortfall(json)
      assert report =~ "@moduledoc"
      assert report =~ "TODO"
      assert report =~ ";"
    end
  end

  describe "repair_report/1" do
    test "describes a timeout/crash" do
      report = Evaluator.repair_report(:timeout_or_crash)
      assert report =~ "timed out or crashed"
    end

    test "routes a failed timeout the same way" do
      assert Evaluator.repair_report({:failed, :timeout_or_crash}) =~ "timed out or crashed"
    end

    test "describes a vacuous harness (mutant survived)" do
      report =
        Evaluator.repair_report(
          {:vacuous, "the raise-mutant of `split/2` still passes the tests"}
        )

      assert report =~ "Mutation gate failed"
      assert report =~ "split/2"
      assert report =~ "test_harness.exs"
    end

    test "describes a house-style quality shortfall" do
      report = Evaluator.repair_report({:quality, "no @spec on any public function"})
      assert report =~ "house style"
      assert report =~ "@spec"
      assert report =~ "ZERO warnings"
    end

    test "shapes compile errors from the json" do
      json = %{
        "compiled" => false,
        "compile_errors" => [
          %{"type" => "CompileError", "message" => "undefined function foo/0"}
        ]
      }

      report = Evaluator.repair_report({:failed, {:ok, json}})
      assert report =~ "Compilation failed"
      assert report =~ "CompileError: undefined function foo/0"
    end

    test "shapes test failures from the json" do
      json = %{
        "compiled" => true,
        "tests_failed" => 2,
        "tests_errors" => 0,
        "test_failures" => [
          %{"test" => "test adds", "module" => "FooTest", "message" => "expected 2 got 3"}
        ]
      }

      report = Evaluator.repair_report({:failed, {:ok, json}})
      assert report =~ "Tests failed (2 failed, 0 errors)"
      assert report =~ "test adds (FooTest): expected 2 got 3"
    end

    test "falls back for a compile failure with no diagnostics" do
      report = Evaluator.repair_report({:failed, {:ok, %{"compiled" => false}}})
      assert report =~ "Compilation failed (no diagnostics captured)."
    end

    test "falls back for a green-but-unaccepted json" do
      json = %{"compiled" => true, "tests_total" => 5, "tests_failed" => 0, "tests_errors" => 0}
      report = Evaluator.repair_report({:failed, {:ok, json}})
      assert report =~ "did not pass"
    end
  end
end
