defmodule GenTask.CycleLogTest do
  use ExUnit.Case, async: true

  alias GenTask.{Config, CycleLog}

  defp cfg(tmp), do: %Config{logs_dir: tmp}

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "cycle_log_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "record_attempt/7 + reset_attempts/2" do
    test "persists files, grade, and meta for one attempt" do
      tmp = tmp_dir()
      files = %{"solution.ex" => "defmodule A do\nend\n", "test_harness.exs" => "# h"}
      grade = {:ok, %{"compiled" => true, "tests_failed" => 2}}

      :ok =
        CycleLog.record_attempt(cfg(tmp), "042_001_x_01", 0, files, grade, :rejected, "2 fail")

      base = Path.join([tmp, "attempts", "042_001_x_01", "attempt_00"])
      assert File.read!(Path.join([base, "files", "solution.ex"])) == "defmodule A do\nend\n"
      assert File.read!(Path.join([base, "files", "test_harness.exs"])) == "# h"

      assert %{"compiled" => true, "tests_failed" => 2} =
               Jason.decode!(File.read!(Path.join(base, "grade.json")))

      meta = Jason.decode!(File.read!(Path.join(base, "meta.json")))
      assert meta["id"] == "042_001_x_01"
      assert meta["attempt"] == 0
      assert meta["status"] == "rejected"
      assert meta["repair_report"] == "2 fail"
      assert is_binary(meta["ts"])
    end

    test "a rejected→accepted chain leaves one dir per attempt" do
      tmp = tmp_dir()
      files = %{"solution.ex" => "v1"}

      :ok = CycleLog.record_attempt(cfg(tmp), "t", 0, files, :timeout_or_crash, :rejected, "boom")

      :ok =
        CycleLog.record_attempt(
          cfg(tmp),
          "t",
          1,
          %{files | "solution.ex" => "v2"},
          {:ok, %{"compiled" => true}},
          :accepted,
          nil
        )

      root = Path.join([tmp, "attempts", "t"])
      assert File.ls!(root) |> Enum.sort() == ["attempt_00", "attempt_01"]

      assert Jason.decode!(File.read!(Path.join([root, "attempt_00", "grade.json"]))) ==
               %{"timeout_or_crash" => true}

      assert File.read!(Path.join([root, "attempt_01", "files", "solution.ex"])) == "v2"

      meta1 = Jason.decode!(File.read!(Path.join([root, "attempt_01", "meta.json"])))
      assert meta1["status"] == "accepted"
      assert meta1["repair_report"] == nil
    end

    test "reset_attempts/2 clears prior history for the id only" do
      tmp = tmp_dir()
      files = %{"solution.ex" => "x"}
      :ok = CycleLog.record_attempt(cfg(tmp), "a", 0, files, :timeout_or_crash, :rejected, "r")
      :ok = CycleLog.record_attempt(cfg(tmp), "b", 0, files, :timeout_or_crash, :rejected, "r")

      :ok = CycleLog.reset_attempts(cfg(tmp), "a")

      refute File.exists?(Path.join([tmp, "attempts", "a"]))
      assert File.exists?(Path.join([tmp, "attempts", "b", "attempt_00"]))
    end
  end

  describe "gate-sha keying of permanent reject ledgers (T1.7)" do
    test "gate_sha/1 is stable per module set and differs across sets" do
      a = CycleLog.gate_sha([GenTask.Mutation])
      assert a == CycleLog.gate_sha([GenTask.Mutation])
      assert a != CycleLog.gate_sha([GenTask.Evaluator])
      assert a =~ ~r/^[0-9a-f]{64}$/
    end

    test "a tfim reject from the CURRENT gate blocks; a different gate re-opens; legacy blocks" do
      tmp = tmp_dir()
      gate = CycleLog.gate_sha([GenTask.Mutation])

      CycleLog.record_tfim_rejected(cfg(tmp), "099_009_x", "current-gate", "H", gate)
      CycleLog.record_tfim_rejected(cfg(tmp), "099_009_x", "old-gate", "H", "deadbeef")
      CycleLog.record_tfim_rejected(cfg(tmp), "099_009_x", "legacy-unstamped", "H")

      rejected = CycleLog.rejected_tfim_targets(cfg(tmp), "099_009_x", "H", gate)

      assert MapSet.member?(rejected, "current-gate")
      refute MapSet.member?(rejected, "old-gate")
      assert MapSet.member?(rejected, "legacy-unstamped")
    end

    test "fim rejects follow the same rule" do
      tmp = tmp_dir()
      gate = CycleLog.gate_sha([GenTask.Mutation])

      CycleLog.record_fim_rejected(cfg(tmp), "099_009_x", "kept/1", gate)
      CycleLog.record_fim_rejected(cfg(tmp), "099_009_x", "reopened/2", "deadbeef")
      CycleLog.record_fim_rejected(cfg(tmp), "099_009_x", "legacy/1")

      targets = CycleLog.rejected_fim_targets(cfg(tmp), "099_009_x", gate)

      assert "kept/1" in targets
      refute "reopened/2" in targets
      assert "legacy/1" in targets
    end

    test "a nil current gate sha (raw readers, audit tools) filters nothing" do
      tmp = tmp_dir()
      CycleLog.record_tfim_rejected(cfg(tmp), "099_009_x", "stamped", "H", "deadbeef")
      rejected = CycleLog.rejected_tfim_targets(cfg(tmp), "099_009_x", "H")
      assert MapSet.member?(rejected, "stamped")
    end
  end
end
