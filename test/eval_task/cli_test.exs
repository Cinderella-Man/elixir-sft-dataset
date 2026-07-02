defmodule EvalTask.CLITest do
  use ExUnit.Case, async: true

  alias EvalTask.CLI

  defp tmp(name) do
    d = Path.join(System.tmp_dir!(), "#{name}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(d)
    on_exit(fn -> File.rm_rf!(d) end)
    d
  end

  describe "detect/2 shape classification" do
    test "wt_ prefix → :write_test (even though it carries a harness)" do
      d = tmp("wt_001_001_x")
      File.write!(Path.join(d, "solution.ex"), "defmodule X do\nend")
      File.write!(Path.join(d, "test_harness.exs"), "defmodule XTest do\nend")
      assert CLI.detect(d, Path.join(d, "solution.ex")) == :write_test
    end

    test "tfim_ prefix → :test_fim (before the harness-less :fim default)" do
      d = tmp("tfim_001_001_x_02")
      File.write!(Path.join(d, "solution.ex"), "  test \"a\", do: assert(true)")
      File.write!(Path.join(d, "prompt.md"), "```elixir\n# TODO\n```")
      assert CLI.detect(d, Path.join(d, "solution.ex")) == :test_fim
    end

    test "a harness-less dir with a # TODO prompt is still :fim" do
      d = tmp("001_001_x_02")
      File.write!(Path.join(d, "solution.ex"), "def go, do: 1")
      File.write!(Path.join(d, "prompt.md"), "```elixir\n# TODO\n```")
      assert CLI.detect(d, Path.join(d, "solution.ex")) == :fim
    end

    test "a plain dir with a harness is :single" do
      d = tmp("001_001_x_01")
      File.write!(Path.join(d, "solution.ex"), "defmodule X do\nend")
      File.write!(Path.join(d, "test_harness.exs"), "defmodule XTest do\nend")
      assert CLI.detect(d, Path.join(d, "solution.ex")) == :single
    end
  end
end
