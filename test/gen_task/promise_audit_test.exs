defmodule GenTask.PromiseAuditTest do
  # T1.10 (docs/17 §5): the accept-time promise audit. Pure helpers are tested
  # directly; the end-to-end paths drive PromiseAudit.run/4 with a fake auditor
  # transport and REAL eval subprocesses on a tiny task (accept_gates_test
  # pattern), so the anchor → gold → bite → re-cycle pipeline is proven against
  # the actual grading machinery with zero LLM calls.
  use ExUnit.Case, async: false

  @moduletag timeout: 240_000

  import ExUnit.CaptureIO

  alias GenTask.{Config, PromiseAudit}

  @prompt """
  Write me an Elixir module called Adder.

  - `Adder.add(a, b)` returns the sum of the two integers.
  - `Adder.sub(a, b)` returns the difference of the two integers.
  - `Adder.add(0, b)` always returns exactly `b` (adding zero is an identity).
  """

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

  @harness """
  defmodule AdderTest do
    use ExUnit.Case, async: false

    test "adds", do: assert(Adder.add(1, 2) == 3)
    test "subtracts", do: assert(Adder.sub(5, 2) == 3)
    test "adds negatives", do: assert(Adder.add(-1, -2) == -3)
  end
  """

  # A buggy solution violating the identity promise (add(0, b) returns b + 1).
  @buggy_solution """
  defmodule Adder do
    @moduledoc "Adds and subtracts integers."

    @doc "Sum of `a` and `b`."
    @spec add(integer(), integer()) :: integer()
    def add(0, b), do: b + 1
    def add(a, b), do: a + b

    @doc "Difference of `a` and `b`."
    @spec sub(integer(), integer()) :: integer()
    def sub(a, b), do: a - b
  end
  """

  setup do
    tmp = Path.join(System.tmp_dir!(), "paudit_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  defp cfg(tmp, opts) do
    struct!(
      %Config{
        promise_audit: true,
        max_retries: 1,
        per_fn_mutation: false,
        eval_timeout_s: 60,
        staging_dir: Path.join(tmp, "staging"),
        logs_dir: Path.join(tmp, "logs"),
        tasks_dir: Path.join(tmp, "tasks")
      },
      opts
    )
  end

  defp result(solution) do
    %{
      status: :accepted,
      files: %{
        "prompt.md" => @prompt,
        "solution.ex" => solution,
        "test_harness.exs" => @harness
      },
      grade: {:ok, %{"compiled" => true, "tests_total" => 3, "tests_passed" => 3}},
      attempts: 1,
      mutant_failed: true,
      mutation: "whole",
      reason: nil
    }
  end

  # ---------------------------------------------------------------------------
  # Pure helpers
  # ---------------------------------------------------------------------------

  describe "candidates/1" do
    test "extracts blocks with their PROMISE anchors at any indentation" do
      body = """
      # PROMISE: "`Adder.add(0, b)` always returns exactly `b` (adding zero is an identity)."
          test "identity", do: assert(Adder.add(0, 1) == 1)
      """

      assert {:ok, [cand]} = PromiseAudit.candidates(body)
      assert cand.name == "identity"
      assert cand.quote =~ "adding zero is an identity"
      assert cand.src =~ ~s(test "identity")
    end

    test "the NOTHING TO ADD sentinel is a clean empty outcome" do
      assert :nothing = PromiseAudit.candidates("# NOTHING TO ADD\n")
    end

    test "an unparseable reply is an error, not a crash" do
      assert {:error, _} = PromiseAudit.candidates("test \"unclosed do\n")
    end
  end

  describe "anchored?/2" do
    test "whitespace-normalized verbatim quotes anchor; paraphrases and stubs do not" do
      assert PromiseAudit.anchored?(
               "`Adder.add(0, b)` always returns exactly `b` (adding zero is an identity).",
               @prompt
             )

      # Line-wrap differences must not break anchoring.
      assert PromiseAudit.anchored?(
               "`Adder.add(0,   b)` always returns\n exactly `b` (adding zero is an identity).",
               @prompt
             )

      refute PromiseAudit.anchored?("adding zero yields the same number back", @prompt)
      refute PromiseAudit.anchored?("returns the sum", @prompt)
    end
  end

  describe "grow/2" do
    test "inserts before the final end and reports the exact span" do
      {merged, s, e} = PromiseAudit.grow(@harness, ["  test \"x\", do: assert(true)"])
      lines = String.split(merged, "\n")

      assert Enum.at(lines, s - 1) == ""
      assert Enum.at(lines, s) =~ ~s(test "x")
      assert e == s
      assert List.last(String.split(String.trim_trailing(merged), "\n")) == "end"
      assert PromiseAudit.existing_test_names(merged) |> MapSet.member?("x")
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end paths (fake auditor, real evals)
  # ---------------------------------------------------------------------------

  defmodule FakeAuditorMixed do
    # One good anchored coverage test, one unanchored test (dropped), one
    # duplicate-name test (dropped).
    def call(_system, _user, _cfg) do
      body = """
      # PROMISE: "`Adder.add(0, b)` always returns exactly `b` (adding zero is an identity)."
      test "adding zero is an identity", do: assert(Adder.add(0, 41) == 41)

      # PROMISE: "this sentence appears nowhere in the prompt at all, sadly"
      test "unanchored", do: assert(Adder.add(1, 1) == 2)

      # PROMISE: "`Adder.add(a, b)` returns the sum of the two integers."
      test "adds", do: assert(Adder.add(2, 2) == 4)
      """

      {:ok, ~s(<file path="added_tests.exs">\n#{body}</file>), %{}}
    end
  end

  defmodule FakeAuditorNothing do
    def call(_system, _user, _cfg),
      do: {:ok, ~s(<file path="added_tests.exs">\n# NOTHING TO ADD\n</file>), %{}}
  end

  defmodule FakeAuditorDefectThenFix do
    # First call: the audit reply pinning the violated identity promise.
    # Second call: the repair reply (the re-cycle's fixer) correcting add(0, b).
    def call(system, _user, _cfg) do
      if String.contains?(system, "auditing an accepted training task") or
           String.contains?(system, "expert Elixir reviewer") do
        {:ok,
         ~s(<file path="added_tests.exs">\n# PROMISE: "`Adder.add\(0, b\)` always returns exactly `b` \(adding zero is an identity\)."\ntest "adding zero is an identity", do: assert\(Adder.add\(0, 41\) == 41\)\n</file>),
         %{}}
      else
        fixed = """
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

        {:ok, ~s(<file path="solution.ex">\n#{fixed}</file>), %{}}
      end
    end
  end

  test "flag off: SKIPPED, result untouched", %{tmp: tmp} do
    cfg = cfg(tmp, promise_audit: false)
    r = result(@solution)

    out =
      capture_io(fn -> send(self(), {:res, PromiseAudit.run(r, "t_audit_off", :base, cfg)}) end)

    assert_received {:res, {:ok, ^r}}
    assert out =~ "SKIPPED — EXPLICITLY DISABLED (GEN_PROMISE_AUDIT=0"
  end

  test "NOTHING TO ADD passes the gate unchanged", %{tmp: tmp} do
    cfg = cfg(tmp, opus: FakeAuditorNothing)
    r = result(@solution)

    out =
      capture_io(fn -> send(self(), {:res, PromiseAudit.run(r, "t_audit_none", :base, cfg)}) end)

    assert_received {:res, {:ok, ^r}}
    assert out =~ "NOTHING TO ADD"
  end

  test "coverage candidate is anchored, graded green, bite-proven and merged; junk is dropped",
       %{tmp: tmp} do
    cfg = cfg(tmp, opus: FakeAuditorMixed)
    r = result(@solution)

    out =
      capture_io(fn -> send(self(), {:res, PromiseAudit.run(r, "t_audit_mix", :base, cfg)}) end)

    assert_received {:res, {:ok, r2}}
    assert r2.status == :accepted
    names = PromiseAudit.existing_test_names(r2.files["test_harness.exs"])
    assert MapSet.member?(names, "adding zero is an identity")
    refute MapSet.member?(names, "unanchored")
    # The shipped harness must not carry PROMISE anchors (S10 chatter class).
    refute r2.files["test_harness.exs"] =~ "PROMISE"
    assert out =~ ~s(promise test "adding zero is an identity" ... KEPT \(coverage\))
    assert out =~ ~s(promise test "unanchored" ... dropped)
    assert out =~ ~s(promise test "adds" ... dropped — duplicates an existing test name)
    assert out =~ "gate [7/9]"
  end

  test "a failing anchored test machine-proves the defect and the re-cycle repairs the module",
       %{tmp: tmp} do
    cfg = cfg(tmp, opus: FakeAuditorDefectThenFix)
    r = result(@buggy_solution)

    out =
      capture_io(fn ->
        send(self(), {:res, PromiseAudit.run(r, "t_audit_defect", :base, cfg)})
      end)

    assert_received {:res, {:ok, r2}}
    assert r2.status == :accepted
    # The module was really fixed against the proven-defect test.
    refute r2.files["solution.ex"] =~ "b + 1"
    assert r2.files["test_harness.exs"] =~ "adding zero is an identity"
    assert r2.attempts > r.attempts
    assert out =~ ~s(KEPT \(defect\))
    assert out =~ "proven-defect"
  end
end
