defmodule GenTask.DeriveMinersTest do
  use ExUnit.Case, async: true

  alias GenTask.{Config, DeriveMiners}

  @seed %{task_id: "999_001_ghost_family_01"}

  # The miner scripts write for real through their own CLIs — a dry-run Config
  # must short-circuit BEFORE any script is loaded or driven. Found live
  # 2026-07-23: GEN_DRY_RUN=1 topup sfim-minted tasks/109_001_..._14/_15.
  test "dry_run skips every deterministic miner without touching disk" do
    cfg = %Config{dry_run: true}
    before = Path.wildcard("tasks/999_001_*")

    for run <- [:sfim_run, :tdd_run, :specfim_run, :bundlefim_run] do
      [out] = apply(DeriveMiners, run, [@seed, cfg])
      assert out.status == :skipped
      assert out.reason =~ "dry-run"
    end

    assert Path.wildcard("tasks/999_001_*") == before
  end

  test "a sandboxed tasks_dir still skips (repo-root-only) when not dry" do
    cfg = %Config{dry_run: false, tasks_dir: System.tmp_dir!()}
    [out] = DeriveMiners.sfim_run(@seed, cfg)
    assert out.status == :skipped
    assert out.reason =~ "repo-root-only"
  end
end
