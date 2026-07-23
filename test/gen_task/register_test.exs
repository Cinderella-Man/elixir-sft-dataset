defmodule GenTask.RegisterTest do
  use ExUnit.Case, async: true

  alias GenTask.{
    Adapt,
    BundleFimTemplate,
    Bugfix,
    Dedoc,
    Register,
    SfimTemplate,
    SpecFimTemplate,
    TddTemplate,
    TestFim,
    WriteTest
  }

  @spec_text "Build a widget that frobnicates."
  @mod "defmodule W do\n  def go, do: :ok\nend"
  @harness "defmodule WTest do\n  use ExUnit.Case\n  test \"go\" do\n    assert W.go() == :ok\n  end\nend"
  @skeleton_mod "defmodule W do\n  def go do\n    # TODO\n  end\nend"
  @skeleton_harness "defmodule WTest do\n  use ExUnit.Case\n  test \"go\" do\n    # TODO\n  end\nend"
  @specfim_skeleton "defmodule W do\n  # TODO: @spec\n  def go, do: :ok\nend"
  @report "1 of 2 test(s) failed:\n\n  * test go\n      boom"

  # A unit id that Register maps to variant `v` — found by search so the tests
  # stay correct even if the hash function's constants ever change.
  defp id_for(v) do
    Enum.find(Stream.map(0..1000, &"unit_#{&1}"), fn id -> Register.variant(id) == v end)
  end

  defp render(:bugfix, id),
    do: Bugfix.prompt_md(%{files: %{"prompt.md" => @spec_text}}, @mod, @report, id)

  defp render(:wt, id), do: WriteTest.prompt_md(@mod, @spec_text, id)
  defp render(:adapt, id), do: Adapt.prompt_md(@mod, @spec_text, id)
  defp render(:dedoc, id), do: Dedoc.prompt_md(@mod, id)
  defp render(:tdd, id), do: TddTemplate.prompt(@harness, id)
  defp render(:tfim_test, id), do: TestFim.prompt_md(@mod, @skeleton_harness, "test", id)
  defp render(:tfim_property, id), do: TestFim.prompt_md(@mod, @skeleton_harness, "property", id)
  defp render(:sfim, id), do: SfimTemplate.prompt("go", @spec_text, @skeleton_mod, id)
  defp render(:specfim, id), do: SpecFimTemplate.prompt("go", 0, @specfim_skeleton, id)

  defp render(:bundlefim, id),
    do: BundleFimTemplate.prompt("lib/w.ex", @spec_text, "# TODO\n\ndefmodule X do\nend", id)

  # docs/20 §2 — the frozen anchors every variant of a shape must carry
  # byte-exactly, verified against the parsers that own them.
  @frozen %{
    bugfix: ["## The buggy module\n\n```elixir\n", "## Failing test report\n\n```\n"],
    wt: ["\n## Original specification\n", "\n## Module under test\n\n```elixir\n"],
    adapt: ["\n## Existing code (your starting point)\n\n```elixir\n", "\n## New specification\n"],
    dedoc: ["\n## The module\n\n```elixir\n"],
    tdd: ["\n## The test suite\n\n```elixir\n"],
    tfim_test: [
      "\n## Module under test\n\n```elixir\n",
      "## Test harness — implement the `# TODO` test\n"
    ],
    tfim_property: [
      "\n## Module under test\n\n```elixir\n",
      "## Test harness — implement the `# TODO` property\n"
    ],
    sfim: ["\n## The task\n\n", "\n## The module with `go` missing\n\n```elixir\n"],
    specfim: ["\n## The module with the `@spec` for `go/0` missing\n\n```elixir\n"],
    bundlefim: ["\n## The task\n\n", "\n## The bundle with `lib/w.ex` missing\n\n```elixir\n"]
  }

  # H1 titles that shape sniffers require as the FIRST line (format_corpus +
  # the sfim/bundlefim resync gates) — frozen in every variant.
  @frozen_h1 %{
    sfim: "# Implement the missing function\n",
    bundlefim: "# Implement the missing file\n"
  }

  test "every variant of every shape carries its frozen anchors byte-exactly" do
    for {shape, anchors} <- @frozen, v <- 0..(Register.n_variants() - 1) do
      body = render(shape, id_for(v))

      for anchor <- anchors do
        assert String.contains?(body, anchor),
               "#{shape} v#{v} lost frozen anchor #{inspect(anchor)}"
      end

      case @frozen_h1[shape] do
        nil -> :ok
        h1 -> assert String.starts_with?(body, h1), "#{shape} v#{v} H1 must be the first line"
      end
    end
  end

  test "variant 0 renders byte-identically to the pre-rotation builders (golden fixtures)" do
    id0 = id_for(0)

    for {shape, fixture} <- [
          bugfix: "bugfix",
          wt: "wt",
          adapt: "adapt",
          dedoc: "dedoc",
          tdd: "tdd",
          tfim_test: "tfim_test",
          tfim_property: "tfim_property",
          sfim: "sfim",
          specfim: "specfim",
          bundlefim: "bundlefim"
        ] do
      golden = File.read!("test/fixtures/register_v0/#{fixture}.md")
      assert render(shape, id0) == golden, "#{shape} v0 drifted from the captured golden bytes"
    end
  end

  test "specfim name/arity recovery regex matches every variant (resync contract)" do
    re = ~r/the `@spec` for\n?`([a-z_0-9?!]+\/\d+)` has been removed/

    for v <- 0..(Register.n_variants() - 1) do
      body = render(:specfim, id_for(v))
      assert [_, "go/0"] = Regex.run(re, body), "specfim v#{v} breaks the recovery regex"
    end
  end

  test "sfim/tfim skeleton extraction finds the TODO fence in every variant" do
    for shape <- [:sfim, :tfim_test], v <- 0..(Register.n_variants() - 1) do
      body = render(shape, id_for(v))
      assert EvalTask.Fim.extract_skeleton(body) =~ "# TODO"
    end
  end

  test "rotated prose never adds S9 timer-scan vocabulary" do
    for {shape, _} <- @frozen, v <- 0..(Register.n_variants() - 1) do
      body = render(shape, id_for(v))
      refute body =~ "Process.send_after", "#{shape} v#{v}"
      refute Regex.match?(~r/:\w*(?:interval|period)\w*/, body), "#{shape} v#{v}"
    end
  end

  test "variant selection is a stable function of the dir basename only" do
    assert Register.variant("wt_001_001_x") == Register.variant("tasks/wt_001_001_x")
    assert Enum.all?(0..2, fn v -> Register.variant(id_for(v)) == v end)
  end
end
