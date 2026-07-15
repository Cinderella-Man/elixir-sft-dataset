System.put_env("SCRIPTS_NO_AUTORUN", "1")
Code.require_file("scripts/close_gaps.exs")

defmodule Scripts.CloseGapsTest do
  # async: false — done? tests point the CLOSE_GAPS_* env at a sandbox.
  use ExUnit.Case, async: false

  alias GenTask.CycleLog

  defp gap(evidence, why),
    do: %{"class" => "harness_gap", "evidence" => evidence, "why" => why, "severity" => "medium"}

  describe "gaps_sha/1 (the findings half of the resume key)" do
    test "order-independent over harness_gap findings; other classes ignored" do
      a = gap("e1", "w1")
      b = gap("e2", "w2")
      gold = %{"class" => "gold_defect", "evidence" => "g", "why" => "w", "severity" => "high"}

      assert CloseGaps.gaps_sha([a, b]) == CloseGaps.gaps_sha([b, a])
      assert CloseGaps.gaps_sha([a, b]) == CloseGaps.gaps_sha([a, b, gold])
      refute CloseGaps.gaps_sha([a]) == CloseGaps.gaps_sha([a, b])
    end
  end

  describe "done?/2 (harness sha + findings digest, with ts-compat for old rows)" do
    setup do
      root = Path.join(System.tmp_dir!(), "close_gaps_test_#{System.unique_integer([:positive])}")
      tasks = Path.join(root, "tasks")
      File.mkdir_p!(Path.join(tasks, "001_001_x_01"))
      harness = "defmodule XTest do\nend\n"
      File.write!(Path.join([tasks, "001_001_x_01", "test_harness.exs"]), harness)

      review = Path.join(root, "review.jsonl")
      ledger = Path.join(root, "close_gaps.jsonl")
      File.write!(review, "")
      File.write!(ledger, "")

      System.put_env("CLOSE_GAPS_TASKS_DIR", tasks)
      System.put_env("CLOSE_GAPS_REVIEW_LEDGER", review)
      System.put_env("CLOSE_GAPS_LEDGER", ledger)

      on_exit(fn ->
        for v <- ~w(CLOSE_GAPS_TASKS_DIR CLOSE_GAPS_REVIEW_LEDGER CLOSE_GAPS_LEDGER),
            do: System.delete_env(v)

        File.rm_rf!(root)
      end)

      %{harness_sha: CycleLog.content_sha(harness), review: review, ledger: ledger}
    end

    defp applied_row(harness_sha, extra) do
      Map.merge(
        %{
          "verdict" => "applied",
          "harness_sha_after" => harness_sha,
          "ts" => "2026-07-14T12:00:00Z"
        },
        extra
      )
    end

    defp review_row(task, ts), do: %{"task" => task, "ts" => ts, "confirmed" => []}

    test "an applied row for the same harness AND same findings digest is done", ctx do
      findings = [gap("e1", "w1")]
      row = applied_row(ctx.harness_sha, %{"gaps_sha" => CloseGaps.gaps_sha(findings)})
      File.write!(ctx.ledger, Jason.encode!(row) <> "\n")

      assert CloseGaps.done?("001_001_x_01", findings)
    end

    test "NEW findings on an already-applied harness re-open the family", ctx do
      old_findings = [gap("e1", "w1")]
      new_findings = [gap("e2", "brand new gap")]
      row = applied_row(ctx.harness_sha, %{"gaps_sha" => CloseGaps.gaps_sha(old_findings)})
      File.write!(ctx.ledger, Jason.encode!(row) <> "\n")
      # the new review row postdates the applied row
      File.write!(
        ctx.review,
        Jason.encode!(review_row("001_001_x_01", "2026-07-15T05:00:00Z")) <> "\n"
      )

      refute CloseGaps.done?("001_001_x_01", new_findings)
    end

    test "a legacy row (no gaps_sha) counts only when it postdates the review row", ctx do
      findings = [gap("e1", "w1")]
      legacy = applied_row(ctx.harness_sha, %{})

      # review row OLDER than the applied row -> done
      File.write!(
        ctx.review,
        Jason.encode!(review_row("001_001_x_01", "2026-07-13T00:00:00Z")) <> "\n"
      )

      File.write!(ctx.ledger, Jason.encode!(legacy) <> "\n")
      assert CloseGaps.done?("001_001_x_01", findings)

      # review row NEWER than the applied row -> todo again
      File.write!(
        ctx.review,
        Jason.encode!(review_row("001_001_x_01", "2026-07-15T05:00:00Z")) <> "\n"
      )

      refute CloseGaps.done?("001_001_x_01", findings)
    end

    test "a changed harness re-opens regardless of digest", ctx do
      findings = [gap("e1", "w1")]
      row = applied_row("some_other_sha", %{"gaps_sha" => CloseGaps.gaps_sha(findings)})
      File.write!(ctx.ledger, Jason.encode!(row) <> "\n")

      refute CloseGaps.done?("001_001_x_01", findings)
    end
  end
end
