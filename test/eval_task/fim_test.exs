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

  describe "build_skeleton/2 (deterministic skeleton, inverse of reconstruct)" do
    test "stubs only the target clause; splicing the candidate back is clean" do
      parent = """
      defmodule A do
        @impl true
        def handle_call(:a, _from, s), do: {:reply, :a, s}

        @impl true
        def handle_call(:b, _from, s) do
          {:reply, :b, s}
        end
      end
      """

      candidate = "@impl true\ndef handle_call(:b, _from, s) do\n  {:reply, :b, s}\nend"
      skeleton = Fim.build_skeleton(parent, candidate)

      # only the :b clause is stubbed; :a stays complete
      assert skeleton =~ "def handle_call(:a, _from, s), do: {:reply, :a, s}"
      assert skeleton =~ ~r/def handle_call\(:b, _from, s\) do\s*# TODO\s*end/

      # round-trip: reconstruct compiles, no leftover marker, no duplicate clause/@impl
      whole = Fim.splice(skeleton, candidate)
      refute whole =~ "# TODO"
      assert {:ok, _} = Code.string_to_quoted(whole)
      assert length(Regex.scan(~r/def handle_call\(:b/, whole)) == 1
    end

    test "a one-liner + block multi-clause candidate collapses to one stub (no dup)" do
      parent = """
      defmodule A do
        defp draw(s, %{b: nil}, r), do: {r, s}
        defp draw(s, %{b: b}, r) do
          {min(r, b), s}
        end
      end
      """

      candidate =
        "defp draw(s, %{b: nil}, r), do: {r, s}\ndefp draw(s, %{b: b}, r) do\n  {min(r, b), s}\nend"

      whole = Fim.splice(Fim.build_skeleton(parent, candidate), candidate)
      assert {:ok, _} = Code.string_to_quoted(whole)
      # both clauses present exactly once — no redundant clause
      assert length(Regex.scan(~r/defp draw\(s, %\{b: nil\}/, whole)) == 1
    end

    test "rewrite_skeleton swaps only the # TODO-bearing fence" do
      prompt = "Do X.\n\n```elixir\ndef old, do: :stub # TODO\n```\n\n```elixir\n:example\n```"
      out = Fim.rewrite_skeleton(prompt, "def new do\n  # TODO\nend")
      assert out =~ "def new do"
      assert out =~ ":example"
      refute out =~ "def old"
    end
  end

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
    prompt =
      "```elixir\ndefmodule T do\n  use ExUnit.Case\n  test \"m\" do\n    # TODO\n  end\nend\n```"

    candidate =
      "  test \"m\" do\n    src = \"defmodule Inline do end\"\n    assert is_binary(src)\n  end"

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

  describe "canonical_candidate/2" do
    @cc_parent "defmodule A do\n  @doc \"x\"\n  def go(x) do\n    x + 1\n  end\n\n  def stop(y), do: y\nend"

    test "returns the parent's own lines for a dedented candidate" do
      dedented = "def go(x) do\n  x + 1\nend"

      assert Fim.canonical_candidate(@cc_parent, dedented) ==
               "  def go(x) do\n    x + 1\n  end"
    end

    test "raises when the candidate is not in the parent" do
      assert_raise RuntimeError, ~r/not found/, fn ->
        Fim.canonical_candidate(@cc_parent, "def go(x) do\n  x * 999\nend")
      end
    end
  end

  describe "reconstruct_bundle/3" do
    # A 3-file bundle: the hole lives in the middle file. The prompt fence is the
    # marker-stripped bundle with `call/2` stubbed — exactly what the gen loop's
    # deterministic skeleton and the embed-resync tool produce.
    @parent """
    <file path="lib/app/view.ex">
    defmodule App.View do
      def render(u), do: %{name: u.name}
    end
    </file>

    <file path="lib/app/plug.ex">
    defmodule App.Plug do
      def init(opts), do: opts

      def call(conn, opts) do
        {conn, opts}
      end
    end
    </file>

    <file path="priv/repo/migrations/001_create.exs">
    defmodule App.Repo.Migrations.Create do
      use Ecto.Migration

      def change do
        create table(:things)
      end
    end
    </file>
    """

    defp bundle_prompt do
      stripped = EvalTask.Bundle.strip_markers(String.trim_trailing(@parent, "\n"))
      gold = "  def call(conn, opts) do\n    {conn, opts}\n  end"
      skeleton = Fim.build_skeleton(stripped, gold)
      "Implement `call/2`.\n\n```elixir\n" <> skeleton <> "\n```\n"
    end

    test "gold candidate round-trips to the exact parent bundle" do
      gold = "  def call(conn, opts) do\n    {conn, opts}\n  end"
      out = Fim.reconstruct_bundle(@parent, bundle_prompt(), gold)

      assert EvalTask.Bundle.parse(out) == EvalTask.Bundle.parse(@parent)
    end

    test "a different candidate lands in the holed file only" do
      cand = "  def call(conn, _opts) do\n    conn\n  end"
      out = Fim.reconstruct_bundle(@parent, bundle_prompt(), cand)
      files = Map.new(EvalTask.Bundle.parse(out))
      parent_files = Map.new(EvalTask.Bundle.parse(@parent))

      assert files["lib/app/view.ex"] == parent_files["lib/app/view.ex"]

      assert files["priv/repo/migrations/001_create.exs"] ==
               parent_files["priv/repo/migrations/001_create.exs"]

      assert files["lib/app/plug.ex"] =~ "def call(conn, _opts)"
      refute files["lib/app/plug.ex"] =~ "# TODO"
      assert Code.string_to_quoted!(files["lib/app/plug.ex"])
    end

    test "a whole-module candidate replaces the holed file verbatim" do
      whole = "defmodule App.Plug do\n  def init(o), do: o\n  def call(c, _), do: c\nend"
      out = Fim.reconstruct_bundle(@parent, bundle_prompt(), whole)
      files = Map.new(EvalTask.Bundle.parse(out))

      assert files["lib/app/plug.ex"] == whole
    end

    test "raises when the skeleton diverges from more than one file (stale prompt)" do
      stale =
        bundle_prompt()
        |> String.replace("def render(u), do: %{name: u.name}", "def render(u), do: u")

      assert_raise RuntimeError, ~r/diverges from 2 parent files/, fn ->
        Fim.reconstruct_bundle(@parent, stale, "  def call(c, o), do: {c, o}")
      end
    end

    test "raises when no file is holed" do
      prompt = "```elixir\n# TODO\n" <> EvalTask.Bundle.strip_markers(@parent) <> "\n```"

      assert_raise RuntimeError, ~r/no hole found/, fn ->
        Fim.reconstruct_bundle(@parent, prompt, "  def call(c, o), do: {c, o}")
      end
    end
  end
end
