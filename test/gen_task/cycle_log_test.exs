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
end
