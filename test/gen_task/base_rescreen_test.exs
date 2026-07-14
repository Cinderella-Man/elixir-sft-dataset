defmodule GenTask.BaseRescreenTest do
  use ExUnit.Case, async: true

  alias GenTask.{Base, Catalog, Config}

  defp env(map), do: fn key -> map[key] end

  defp sandbox do
    root = Path.join(System.tmp_dir!(), "rescreen_test_#{System.unique_integer([:positive])}")
    logs = Path.join(root, "logs")
    File.mkdir_p!(logs)
    on_exit(fn -> File.rm_rf!(root) end)
    %Config{logs_dir: logs, tasks_dir: Path.join(root, "tasks")}
  end

  describe "GEN_BLIND_RESCREEN" do
    test "off by default, on with 1" do
      assert %Config{blind_rescreen: false} = Config.new([], env(%{}))
      assert %Config{blind_rescreen: true} = Config.new([], env(%{"GEN_BLIND_RESCREEN" => "1"}))
    end
  end

  describe "rescreen?/2" do
    test "never fires while the flag is off" do
      cfg = %Config{blind_rescreen: false}
      refute Base.rescreen?(cfg, 1)
      refute Base.rescreen?(cfg, 5)
    end

    test "with the flag on, fires only for repaired accepts (attempts > 1)" do
      cfg = %Config{blind_rescreen: true}
      # An attempt-1 accept is already blind by construction (Step B never
      # sees the harness) — no extra call.
      refute Base.rescreen?(cfg, 1)
      assert Base.rescreen?(cfg, 2)
      assert Base.rescreen?(cfg, 3)
    end
  end

  describe "screen_row/5 (the S6 evidence row)" do
    @prompt "# Task\n\nDo the thing.\n"
    @harness "defmodule TTest do\nend\n"

    defp green_json do
      %{
        "compiled" => true,
        "tests_passed" => 4,
        "tests_failed" => 0,
        "tests_errors" => 0,
        "tests_total" => 4
      }
    end

    test "a green grade rows green with both content keys" do
      row = Base.screen_row("001_001_x_01", @prompt, @harness, {:ok, green_json()}, "opus")

      assert row.green == true
      assert row.task == "001_001_x_01"
      assert row.sha == GenTask.CycleLog.content_sha(@prompt)
      assert row.harness_sha == GenTask.CycleLog.content_sha(@harness)
      assert row.source == "accept_time_rescreen"
      assert row.tests_passed == 4
    end

    test "a red grade rows green: false with the first failure" do
      json =
        Map.merge(green_json(), %{
          "tests_passed" => 3,
          "tests_failed" => 1,
          "test_failures" => [%{"test" => "test boundary", "message" => "assert failed"}]
        })

      row = Base.screen_row("001_001_x_01", @prompt, @harness, {:ok, json}, "opus")

      assert row.green == false
      assert row.first_failure =~ "test boundary"
    end

    test "an environmental failure rows green: nil, never a verdict (F7)" do
      json =
        Map.merge(green_json(), %{
          "tests_passed" => 0,
          "tests_failed" => 1,
          "test_failures" => [
            %{
              "test" => "test db",
              "message" => "Postgres is required for this task but is not reachable"
            }
          ]
        })

      row = Base.screen_row("001_001_x_01", @prompt, @harness, {:ok, json}, "opus")

      assert row.green == nil
      assert row.error =~ "environmental"
    end

    test "an eval crash rows green: false (a hung candidate is a solver defect)" do
      row = Base.screen_row("001_001_x_01", @prompt, @harness, :timeout_or_crash, "opus")

      assert row.green == false
      assert row.first_failure == "eval timed out or crashed"
    end
  end

  describe "quarantine" do
    test "quarantine! writes the full evidence dir and blocks the idea from re-running" do
      cfg = sandbox()

      files = %{
        "prompt.md" => "# T\n",
        "solution.ex" => "defmodule S do\nend\n",
        "test_harness.exs" => "defmodule ST do\nend\n"
      }

      :ok =
        Base.quarantine!(
          cfg,
          "001_001_x_01",
          files,
          "defmodule Blind do\nend\n",
          {:ok, %{"compiled" => true}},
          "blind re-screen RED: test boundary"
        )

      dir = Path.join([cfg.logs_dir, "quarantine", "001_001_x_01"])

      for f <-
            ~w(prompt.md solution.ex test_harness.exs blind_candidate.ex reason.txt grade.json) do
        assert File.regular?(Path.join(dir, f)), "missing #{f}"
      end

      assert File.read!(Path.join(dir, "reason.txt")) =~ "RED"

      # The loop must not burn calls regenerating a quarantined idea: run/2
      # skips it without touching the transport (opus: nil would crash if used).
      idea = %Catalog.Idea{num: 1, name: "x", desc: "d", slug: "x", task_id: "001_001_x_01"}
      outcome = Base.run(idea, cfg)

      assert outcome.status == :skipped
      assert outcome.reason =~ "quarantined"
    end
  end
end
