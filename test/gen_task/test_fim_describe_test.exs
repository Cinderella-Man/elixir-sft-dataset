defmodule GenTask.TestFimDescribeTest do
  # Describe-carving (decision 4, 2026-07-12): nested `test` blocks are carvable
  # tfim targets. §5.3.1 recommends describe grouping, so a top-level-only carver
  # minted zero units from 32 harnesses / 426 nested tests.
  use ExUnit.Case, async: true

  alias GenTask.TestFim

  @harness """
  defmodule CalcTest do
    use ExUnit.Case, async: false

    setup do
      {:ok, base: 40}
    end

    test "top-level addition", %{base: b} do
      assert Calc.add(b, 2) == 42
    end

    describe "scaling" do
      setup %{base: b} do
        {:ok, scaled: b * 10}
      end

      test "multiplies", %{scaled: s} do
        assert Calc.mul(s, 2) == 800
      end

      test "divides", %{scaled: s} do
        assert Calc.div(s, 4) == 100
      end
    end

    describe "edge cases" do
      test "multiplies" do
        assert Calc.mul(0, 5) == 0
      end
    end
  end
  """

  test "carvable_blocks finds top-level and nested tests in source order" do
    quals = @harness |> TestFim.carvable_blocks() |> Enum.map(&TestFim.qual/1)

    assert quals == [
             "top-level addition",
             "scaling multiplies",
             "scaling divides",
             "edge cases multiplies"
           ]
  end

  test "same-named tests in different describes get distinct quals" do
    quals = @harness |> TestFim.carvable_blocks() |> Enum.map(&TestFim.qual/1)
    assert "scaling multiplies" in quals
    assert "edge cases multiplies" in quals
  end

  test "skeletonize stubs a nested test at its own indentation" do
    [_, mul | _] = nested = TestFim.carvable_blocks(@harness)
    assert TestFim.qual(mul) == "scaling multiplies"

    skeleton = TestFim.skeletonize(@harness, mul)

    assert skeleton =~ ~s(    test "multiplies", %{scaled: s} do\n      # TODO\n    end)
    refute skeleton =~ "Calc.mul(s, 2)"
    # everything else intact
    assert skeleton =~ "Calc.div(s, 4)"
    assert skeleton =~ "Calc.add(b, 2)"
    assert length(nested) == 4
  end

  test "skeletonize is byte-identical to the historical form for top-level targets" do
    [top | _] = TestFim.carvable_blocks(@harness)
    assert TestFim.qual(top) == "top-level addition"

    skeleton = TestFim.skeletonize(@harness, top)
    assert skeleton =~ ~s(  test "top-level addition", %{base: b} do\n    # TODO\n  end)
  end

  test "splice round-trip: skeleton + gold reconstructs the exact harness" do
    for cand <- TestFim.carvable_blocks(@harness) do
      gold = @harness |> String.split("\n") |> Enum.slice(cand.s..cand.e) |> Enum.join("\n")
      skeleton = TestFim.skeletonize(@harness, cand)
      prompt = TestFim.prompt_md("defmodule Calc do\nend", skeleton, "test", "tfim_x_01")

      assert EvalTask.Fim.reconstruct(prompt, gold, true) == String.trim_trailing(@harness),
             "round-trip failed for #{TestFim.qual(cand)}"
    end
  end

  test "isolate keeps the target's describe (and its setup), drops siblings and other blocks" do
    [_, mul | _] = TestFim.carvable_blocks(@harness)
    iso = TestFim.isolate_for_test(@harness, mul)

    # target + its describe-scoped setup + module-level setup stay
    assert iso =~ ~s(describe "scaling")
    assert iso =~ "scaled: b * 10"
    assert iso =~ "Calc.mul(s, 2)"
    assert iso =~ "{:ok, base: 40}"
    # sibling nested test, other describe, and top-level test go
    refute iso =~ "Calc.div(s, 4)"
    refute iso =~ ~s(describe "edge cases")
    refute iso =~ "Calc.add(b, 2)"
    assert match?({:ok, _}, Code.string_to_quoted(iso))
  end

  test "isolate for a top-level target drops every describe wholesale" do
    [top | _] = TestFim.carvable_blocks(@harness)
    iso = TestFim.isolate_for_test(@harness, top)

    assert iso =~ "Calc.add(b, 2)"
    refute iso =~ "describe"
    refute iso =~ "Calc.mul"
  end

  test "qual_from_prompt reads the describe context back from a child prompt" do
    [_, mul | _] = TestFim.carvable_blocks(@harness)

    prompt =
      TestFim.prompt_md(
        "defmodule Calc do\nend",
        TestFim.skeletonize(@harness, mul),
        "test",
        "t_01"
      )

    assert TestFim.qual_from_prompt(prompt, "multiplies") == "scaling multiplies"

    [top | _] = TestFim.carvable_blocks(@harness)

    top_prompt =
      TestFim.prompt_md(
        "defmodule Calc do\nend",
        TestFim.skeletonize(@harness, top),
        "test",
        "t_01"
      )

    assert TestFim.qual_from_prompt(top_prompt, "top-level addition") == "top-level addition"
  end
end
