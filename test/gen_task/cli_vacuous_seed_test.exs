defmodule GenTask.CLIVacuousSeedTest do
  use ExUnit.Case, async: true

  alias GenTask.{CLI, Config, CycleLog}

  # The gate decision must come from the cached verdict alone — no eval subprocess
  # runs in these tests (a cache hit short-circuits Mutation.gate_base entirely).

  setup do
    logs = Path.join(System.tmp_dir!(), "vacuous_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(logs)
    on_exit(fn -> File.rm_rf!(logs) end)
    %{cfg: %Config{logs_dir: logs}}
  end

  @files %{
    "solution.ex" => "defmodule X do\n  def go, do: :ok\nend\n",
    "test_harness.exs" => "defmodule XTest do\n  use ExUnit.Case\nend\n"
  }

  defp cache_verdict(cfg, task_id, verdict) do
    sha = CycleLog.content_sha(@files["solution.ex"] <> @files["test_harness.exs"])
    CycleLog.record_seed_verdict(cfg, task_id, sha, verdict)
  end

  test "a cached vacuous verdict blocks (returns true)", %{cfg: cfg} do
    cache_verdict(cfg, "001_001_x_01", %{"vacuous" => true, "why" => "fn not exercised"})
    assert CLI.vacuous_seed?(cfg, %{task_id: "001_001_x_01"}, @files)
  end

  test "a cached non-vacuous verdict derives (returns false)", %{cfg: cfg} do
    cache_verdict(cfg, "001_001_x_01", %{"vacuous" => false})
    refute CLI.vacuous_seed?(cfg, %{task_id: "001_001_x_01"}, @files)
  end

  test "the verdict is content-keyed: editing the harness invalidates the cache", %{cfg: cfg} do
    cache_verdict(cfg, "001_001_x_01", %{"vacuous" => true, "why" => "old harness"})
    fixed = %{@files | "test_harness.exs" => "defmodule XTest do\n  # fixed\nend\n"}

    # Different content hash → cache miss → the self-check runs Mutation.gate_base,
    # whose unparsable-source guard reports {:survived, "could not be constructed"}
    # WITHOUT any eval subprocess... but this solution parses fine, so instead prove
    # cache-key sensitivity structurally: the cached verdict for the OLD content must
    # not be found under the NEW content's sha.
    sha_new = CycleLog.content_sha(fixed["solution.ex"] <> fixed["test_harness.exs"])
    assert CycleLog.cached_seed_verdict(cfg, "001_001_x_01", sha_new) == :miss
  end

  test "verdicts for other tasks do not leak", %{cfg: cfg} do
    cache_verdict(cfg, "002_001_other_01", %{"vacuous" => true, "why" => "x"})
    sha = CycleLog.content_sha(@files["solution.ex"] <> @files["test_harness.exs"])
    assert CycleLog.cached_seed_verdict(cfg, "001_001_x_01", sha) == :miss
  end
end
