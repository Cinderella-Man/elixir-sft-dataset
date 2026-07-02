defmodule EvalTask.FimTest do
  use ExUnit.Case, async: true
  alias EvalTask.Fim

  test "parent_dir derives the _01 sibling" do
    assert Fim.parent_dir("tasks/001_001_rate_limiter_03") == "tasks/001_001_rate_limiter_01"
  end

  test "extract_candidate strips a wrapping elixir fence" do
    assert Fim.extract_candidate("```elixir\ndef x, do: 1\n```") == "def x, do: 1"
    assert Fim.extract_candidate("def x, do: 1") == "def x, do: 1"
  end

  test "splice replaces a stub-body def (# TODO inside)" do
    skeleton = "defmodule A do\n  def go(x) do\n    # TODO\n  end\nend"
    result = Fim.splice(skeleton, "  def go(x) do\n    x + 1\n  end")
    assert result =~ "x + 1"
    refute result =~ "# TODO"
    assert Code.string_to_quoted!(result)
  end

  test "splice replaces a placeholder line (#TODO funcname)" do
    skeleton = "defmodule A do\n  #TODO defp helper\nend"
    result = Fim.splice(skeleton, "  defp helper, do: :ok")
    assert result =~ "defp helper, do: :ok"
    refute result =~ "#TODO"
  end

  test "reconstruct uses a whole-module candidate verbatim" do
    prompt = "blah\n```elixir\ndefmodule A do\n  def go do\n    # TODO\n  end\nend\n```"
    whole = "defmodule A do\n  def go, do: :whole\nend"
    assert Fim.reconstruct(prompt, whole) == whole
  end

  test "mutate replaces every clause body with raise" do
    m = Fim.mutate("def a, do: 1\ndef b(x) do\n  x * 2\nend")
    assert m =~ ~s(raise "MUTATION")
    refute m =~ "x * 2"
  end

  # --- test-FIM (tfim) additions ---

  test "test_fim_parent_dir strips the tfim_ prefix and the subtask index" do
    assert Fim.test_fim_parent_dir("tasks/tfim_107_001_event_aggregator_02") ==
             "tasks/107_001_event_aggregator_01"
  end

  test "reconstruct picks the ```elixir fence containing # TODO, not the first fence" do
    # A tfim prompt has two fences: the module (no TODO) then the harness (with TODO).
    prompt = """
    ## Module
    ```elixir
    defmodule Mod do
      def go, do: :ok
    end
    ```
    ## Harness
    ```elixir
    defmodule ModTest do
      use ExUnit.Case
      test "works" do
        # TODO
      end
    end
    ```
    """

    candidate = "  test \"works\" do\n    assert Mod.go() == :ok\n  end"
    result = Fim.reconstruct(prompt, candidate)

    # The reconstructed source is the HARNESS (has use ExUnit.Case), not the module.
    assert result =~ "use ExUnit.Case"
    assert result =~ "assert Mod.go() == :ok"
    refute result =~ "# TODO"
    refute result =~ "def go, do: :ok"
    assert Code.string_to_quoted!(result)
  end

  test "splice replaces a `test` macro block body (ExUnit opener)" do
    skeleton = "defmodule T do\n  use ExUnit.Case\n  test \"x\" do\n    # TODO\n  end\nend"
    result = Fim.splice(skeleton, "  test \"x\" do\n    assert 1 == 1\n  end")
    assert result =~ "assert 1 == 1"
    refute result =~ "# TODO"
    assert Code.string_to_quoted!(result)
  end

  test "splice replaces a `describe` block body (ExUnit opener)" do
    skeleton = "defmodule T do\n  describe \"g\" do\n    # TODO\n  end\nend"
    result = Fim.splice(skeleton, "  describe \"g\" do\n    test \"a\", do: assert(true)\n  end")
    assert result =~ "test \"a\""
    refute result =~ "# TODO"
  end

  test "reconstruct(force_splice: true) splices even when the candidate contains defmodule" do
    # A tfim gold test block may legitimately contain the substring `defmodule` (an inline
    # module or a string literal). It must still be spliced into the harness skeleton, not
    # returned verbatim as if it were a whole module.
    prompt = "```elixir\ndefmodule T do\n  use ExUnit.Case\n  test \"m\" do\n    # TODO\n  end\nend\n```"
    candidate = "  test \"m\" do\n    src = \"defmodule Inline do end\"\n    assert is_binary(src)\n  end"

    forced = Fim.reconstruct(prompt, candidate, true)
    assert forced =~ "use ExUnit.Case"
    assert forced =~ "defmodule Inline do end"
    refute forced =~ "# TODO"
    assert Code.string_to_quoted!(forced)

    # Default (module-FIM) behaviour still short-circuits on defmodule.
    assert Fim.reconstruct(prompt, candidate) == candidate
  end

  test "extract_skeleton picks the LAST ```elixir fence with # TODO (harness, not module)" do
    # Even if the module fence contains a `# TODO`-shaped markdown heading, the harness
    # (last fence) is selected.
    prompt = """
    ```elixir
    defmodule Mod do
      @moduledoc "# TODO: document me"
      def go, do: :ok
    end
    ```
    ```elixir
    defmodule ModTest do
      use ExUnit.Case
      test "w" do
        # TODO
      end
    end
    ```
    """

    result = Fim.reconstruct(prompt, "  test \"w\" do\n    assert Mod.go() == :ok\n  end", true)
    assert result =~ "use ExUnit.Case"
    refute result =~ "def go, do: :ok"
    assert result =~ "assert Mod.go() == :ok"
  end
end
