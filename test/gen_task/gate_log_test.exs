defmodule GenTask.GateLogTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias GenTask.{Config, GateLog}

  defp cfg(tmp), do: %Config{logs_dir: tmp}

  setup do
    tmp = Path.join(System.tmp_dir!(), "gatelog_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "manifests" do
    test "every shape has unique gate keys and ends with the promotion guard" do
      for shape <- GateLog.shapes() do
        keys = for {k, _desc} <- GateLog.manifest(shape), do: k
        assert keys == Enum.uniq(keys), "duplicate gate key in #{shape}"
        assert List.last(keys) == :promote_guard, "#{shape} must end with :promote_guard"
      end
    end

    test "the base and variation manifests carry the dark gates and the shared cycle gates" do
      base_keys = for {k, _} <- GateLog.manifest(:base), do: k
      variation_keys = for {k, _} <- GateLog.manifest(:variation), do: k

      for k <- [:semantic_floor, :promise_audit, :blind_rescreen] do
        assert k in base_keys, "#{k} missing from :base"
        # F17-9: repaired VARIATIONS re-screen too, and the promise audit covers
        # every root shape — both dark gates appear in both root manifests.
        assert k in variation_keys, "#{k} missing from :variation"
      end

      assert :blind_solve in variation_keys
      assert :distinctness in variation_keys

      for k <- [:autoformat, :green, :quality, :mutation, :stability] do
        assert k in base_keys and k in variation_keys
      end
    end
  end

  describe "verdict lines" do
    test "pass prints gate [k/N], the description, and the detail", %{tmp: tmp} do
      out =
        capture_io(fn ->
          GateLog.pass(cfg(tmp), "015_001_x_01", :base, :green, "compiled, 5/5 tests passed")
        end)

      assert out =~ "gate [2/10]"
      assert out =~ "perfect raw invariants"
      assert out =~ "PASS — compiled, 5/5 tests passed"
    end

    test "skip is the visible form of a dark gate", %{tmp: tmp} do
      out =
        capture_io(fn ->
          GateLog.skip(cfg(tmp), "id", :base, :semantic_floor, "GEN_SEMANTIC_FLOOR unset")
        end)

      assert out =~ "gate [7/10]"
      assert out =~ "SKIPPED — GEN_SEMANTIC_FLOOR unset"
    end

    test "fail flattens a multi-line detail to one console line", %{tmp: tmp} do
      out =
        capture_io(fn ->
          GateLog.fail(cfg(tmp), "id", :base, :quality, "first\nsecond\nthird")
        end)

      [line] = for l <- String.split(out, "\n", trim: true), l =~ "gate [", do: l
      assert line =~ "FAIL — first second third"
    end

    test "an unregistered {shape, key} raises instead of printing a wrong number", %{tmp: tmp} do
      assert_raise ArgumentError, ~r/not registered/, fn ->
        GateLog.pass(cfg(tmp), "id", :base, :not_a_gate, "detail")
      end
    end
  end

  describe "the gates.jsonl ledger" do
    test "every verdict appends one row with idx/total/verdict/detail", %{tmp: tmp} do
      capture_io(fn ->
        GateLog.pass(cfg(tmp), "a", :wtest, :green_vs_module, "3/3")
        GateLog.fail(cfg(tmp), "b", :fim, :candidate_mutant, "survived")
        GateLog.skip(cfg(tmp), "c", :base, :blind_rescreen, "flag off")
      end)

      rows =
        tmp
        |> Path.join("gates.jsonl")
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert [
               %{
                 "id" => "a",
                 "shape" => "wtest",
                 "gate" => "green_vs_module",
                 "verdict" => "pass"
               },
               %{"id" => "b", "verdict" => "fail", "detail" => "survived"},
               %{"id" => "c", "gate" => "blind_rescreen", "verdict" => "skip"}
             ] = rows

      assert Enum.all?(rows, &(is_integer(&1["idx"]) and is_integer(&1["total"]) and &1["ts"]))
    end
  end

  describe "sub-check lines" do
    test "ok, skip and fail forms", %{tmp: _tmp} do
      assert capture_io(fn -> GateLog.sub(3, 17, "no TODO/FIXME markers", :ok) end) =~
               "check [ 3/17] no TODO/FIXME markers ... ok"

      assert capture_io(fn -> GateLog.sub(17, 17, "prompt coverage", {:fail, "x\ny"}) end) =~
               "check [17/17] prompt coverage ... FAIL — x y"

      assert capture_io(fn -> GateLog.sub(9, 17, "S9 reach-ins", :skip) end) =~
               "skipped (no text to check)"
    end
  end
end
