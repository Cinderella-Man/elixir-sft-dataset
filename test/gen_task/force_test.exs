defmodule GenTask.ForceTest do
  # The --force family wipe (T1.9). Sandboxed tasks_dir/logs_dir + an injected
  # git check, so no test can touch the real corpus or shell out to git — except
  # the git_clean_check! tests, which build their own throwaway git repo.
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias GenTask.{Config, Force}

  @tasks_md """
  # Catalog

  ### 15. Heartbeat Monitor
  Build a monitor.

  ### Task 15 - V1 - Rolling Window
  Rolling-window spin.

  ### Task 15 - V2 - Async Checks
  Async spin.

  ### 16. Other Idea
  Untouched.

  ### Task 16 - V1 - Other Variation
  Also untouched.
  """

  setup do
    root = Path.join(System.tmp_dir!(), "force_#{System.unique_integer([:positive])}")
    tasks = Path.join(root, "tasks")
    logs = Path.join(root, "logs")

    family = [
      "015_001_heartbeat_monitor_01",
      "015_001_heartbeat_monitor_02",
      "015_002_rolling_window_01",
      "wt_015_001_heartbeat_monitor",
      "tfim_015_001_heartbeat_monitor_02",
      "bugfix_015_002_rolling_window_01",
      "adapt_015_002_rolling_window",
      "repair_015_001_heartbeat_monitor_1"
    ]

    strangers = ["016_001_other_idea_01", "wt_016_001_other_idea", "150_001_decoy_01"]

    for dir <- family ++ strangers do
      File.mkdir_p!(Path.join(tasks, dir))
      File.write!(Path.join([tasks, dir, "prompt.md"]), "p\n")
    end

    File.mkdir_p!(Path.join(logs, "errors"))
    File.write!(Path.join([logs, "errors", "015_001_heartbeat_monitor_01.log"]), "err\n")
    File.write!(Path.join([logs, "errors", "016_001_other_idea_01.log"]), "err\n")
    File.mkdir_p!(Path.join([logs, "quarantine", "015_001_heartbeat_monitor_01"]))

    tasks_md = Path.join(root, "tasks.md")
    File.write!(tasks_md, @tasks_md)

    on_exit(fn -> File.rm_rf!(root) end)

    cfg = %Config{tasks_dir: tasks, logs_dir: logs, tasks_md: tasks_md, only_idea: 15}
    {:ok, cfg: cfg, tasks: tasks, logs: logs, family: family, strangers: strangers}
  end

  describe "family_dirs/2" do
    test "collects the base family and all five derived prefixes, nothing else", ctx do
      dirs = Force.family_dirs(ctx.cfg, 15)
      names = Enum.map(dirs, &Path.basename/1)

      assert Enum.sort(names) == Enum.sort(ctx.family)
      # 150_* and 016_* must never match 015's patterns.
      refute Enum.any?(names, &String.contains?(&1, "016"))
      refute Enum.any?(names, &String.starts_with?(&1, "150"))
    end
  end

  describe "strip_variations/2 (pure)" do
    test "removes exactly the idea's variation blocks, keeping neighbors intact" do
      {new_content, removed} = Force.strip_variations(@tasks_md, 15)

      assert removed == ["Rolling Window", "Async Checks"]
      refute new_content =~ "Task 15 - V1"
      refute new_content =~ "Rolling-window spin"
      refute new_content =~ "Task 15 - V2"
      assert new_content =~ "### 15. Heartbeat Monitor"
      assert new_content =~ "Build a monitor."
      assert new_content =~ "### Task 16 - V1 - Other Variation"
      assert new_content =~ "Also untouched."
    end

    test "is a no-op for an idea without variation entries" do
      {new_content, removed} = Force.strip_variations(@tasks_md, 16_000)
      assert removed == []
      assert new_content == @tasks_md
    end
  end

  describe "wipe!/2" do
    test "deletes the family dirs, catalog entries, error logs and quarantine — only them",
         ctx do
      report =
        capture_io_and_return(fn ->
          Force.wipe!(ctx.cfg, git_check: fn _paths -> :ok end)
        end)

      assert length(report.dirs) == length(ctx.family)
      assert report.catalog_entries == ["Rolling Window", "Async Checks"]

      for dir <- ctx.family do
        refute File.exists?(Path.join(ctx.tasks, dir)), "#{dir} should be gone"
      end

      for dir <- ctx.strangers do
        assert File.exists?(Path.join(ctx.tasks, dir)), "#{dir} must survive"
      end

      content = File.read!(ctx.cfg.tasks_md)
      refute content =~ "Task 15 - V1"
      assert content =~ "### Task 16 - V1 - Other Variation"

      refute File.exists?(Path.join([ctx.logs, "errors", "015_001_heartbeat_monitor_01.log"]))
      assert File.exists?(Path.join([ctx.logs, "errors", "016_001_other_idea_01.log"]))
      refute File.exists?(Path.join([ctx.logs, "quarantine", "015_001_heartbeat_monitor_01"]))
    end

    test "prints every deletion so the console is the audit trail", ctx do
      out = capture_io(fn -> Force.wipe!(ctx.cfg, git_check: fn _ -> :ok end) end)

      assert out =~ "FORCE WIPE — idea 15"

      for dir <- ctx.family do
        assert out =~ dir
      end

      assert out =~ "removed catalog entry \"Rolling Window\""
      assert out =~ "recoverable with `git checkout"
    end

    test "dry-run prints the plan and deletes nothing", ctx do
      %Config{} = base_cfg = ctx.cfg
      cfg = %Config{base_cfg | dry_run: true}

      out =
        capture_io(fn ->
          Force.wipe!(cfg, git_check: fn _ -> raise "git check must not run in dry-run" end)
        end)

      assert out =~ "DRY-RUN — nothing deleted"

      for dir <- ctx.family do
        assert File.exists?(Path.join(ctx.tasks, dir))
      end

      assert File.read!(ctx.cfg.tasks_md) == @tasks_md
    end

    test "refuses to run without a single positional idea number", ctx do
      %Config{} = base_cfg = ctx.cfg
      cfg = %Config{base_cfg | only_idea: nil}

      assert_raise ArgumentError, ~r/--force requires a single base idea number/, fn ->
        # apply/3 keeps the deliberately invalid only_idea: nil out of the
        # type checker's sight — the raise IS the behavior under test.
        capture_io(fn -> apply(Force, :wipe!, [cfg, [git_check: fn _ -> :ok end]]) end)
      end
    end

    test "a failing git check aborts before anything is deleted", ctx do
      assert_raise ArgumentError, ~r/uncommitted/, fn ->
        capture_io(fn ->
          Force.wipe!(ctx.cfg,
            git_check: fn _ -> raise ArgumentError, "uncommitted changes" end
          )
        end)
      end

      for dir <- ctx.family do
        assert File.exists?(Path.join(ctx.tasks, dir)), "#{dir} must survive an aborted wipe"
      end
    end
  end

  describe "git_clean_check!/1 (real git, throwaway repo)" do
    setup do
      repo = Path.join(System.tmp_dir!(), "force_git_#{System.unique_integer([:positive])}")
      File.mkdir_p!(repo)
      git!(repo, ["init", "-q"])
      git!(repo, ["config", "user.email", "t@t"])
      git!(repo, ["config", "user.name", "t"])
      on_exit(fn -> File.rm_rf!(repo) end)
      {:ok, repo: repo}
    end

    test "accepts fully tracked, unmodified paths", %{repo: repo} do
      dir = Path.join(repo, "fam")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "a.txt"), "x\n")
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-qm", "init"])

      assert :ok = Force.git_clean_check!(["fam"], repo)
    end

    test "refuses untracked content (deletion would be unrecoverable)", %{repo: repo} do
      dir = Path.join(repo, "fam")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "a.txt"), "x\n")

      assert_raise ArgumentError, ~r/uncommitted or untracked/, fn ->
        Force.git_clean_check!(["fam"], repo)
      end
    end

    test "refuses modified tracked content", %{repo: repo} do
      dir = Path.join(repo, "fam")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "a.txt"), "x\n")
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-qm", "init"])
      File.write!(Path.join(dir, "a.txt"), "CHANGED\n")

      assert_raise ArgumentError, ~r/uncommitted or untracked/, fn ->
        Force.git_clean_check!(["fam"], repo)
      end
    end
  end

  defp git!(repo, args) do
    {_out, 0} = System.cmd("git", args, cd: repo, stderr_to_stdout: true)
    :ok
  end

  # capture_io swallows the return value; run the fun in-process (so its output IS
  # captured) and hand the result back by message.
  defp capture_io_and_return(fun) do
    parent = self()
    capture_io(fn -> send(parent, {:captured_result, fun.()}) end)
    assert_received {:captured_result, result}
    result
  end
end
