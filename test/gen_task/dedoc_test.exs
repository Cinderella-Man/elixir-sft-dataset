defmodule GenTask.DedocTest do
  use ExUnit.Case, async: true

  alias GenTask.{Catalog, Config, CycleLog, Dedoc}

  # A sandbox with its own tasks_dir AND logs_dir, so no test can touch the real
  # corpus, the real strip ledger, or the real dialyzer ledger.
  defp sandbox do
    root = Path.join(System.tmp_dir!(), "dedoc_test_#{System.unique_integer([:positive])}")
    tasks = Path.join(root, "tasks")
    logs = Path.join(root, "logs")
    File.mkdir_p!(tasks)
    File.mkdir_p!(logs)
    on_exit(fn -> File.rm_rf!(root) end)
    %Config{tasks_dir: tasks, logs_dir: logs}
  end

  defp write_dir(cfg, id, files) do
    dir = Path.join(cfg.tasks_dir, id)
    File.mkdir_p!(dir)
    for {name, body} <- files, do: File.write!(Path.join(dir, name), body)
    dir
  end

  @documented """
  defmodule Widget do
    @moduledoc \"\"\"
    A widget that does widget things.

    Multi-line moduledoc body.
    \"\"\"

    @type t :: %{id: integer(), name: String.t()}

    @doc "Runs the widget."
    @spec run(t()) :: :ok | {:error, term()}
    def run(_widget), do: :ok

    @doc \"\"\"
    Stops the widget.
    \"\"\"
    @spec stop(t(), timeout :: non_neg_integer()) ::
            :ok
            | {:error, term()}
    def stop(_widget, _timeout) do
      :ok
    end

    @doc false
    @impl_marker :kept_attribute
    def hidden, do: :ok

    @typep internal :: :a | :b

    @spec classify(internal()) :: atom()
    defp classify(x), do: x

    @doc "Fetches."
    @spec fetch(t()) :: {:ok, term()} | :error
    def fetch(_widget), do: :error
  end
  """

  defp trio_files do
    %{
      "prompt.md" => "# Widget\n\nBuild the widget.\n",
      "solution.ex" => @documented,
      "test_harness.exs" =>
        "defmodule WidgetTest do\n  use ExUnit.Case\n\n  test \"t\" do\n    assert Widget.run(%{}) == :ok\n  end\nend\n"
    }
  end

  defp seed_for(cfg, task_id) do
    [s] = Catalog.all_seeds(cfg) |> Enum.filter(&(&1.task_id == task_id))
    s
  end

  defp dialyzer_row!(cfg, src, outcome) do
    sha = CycleLog.content_sha(src)

    File.write!(
      Path.join(cfg.logs_dir, "dialyzer_golds.jsonl"),
      Jason.encode!(%{key: sha <> ":gatesha", task: "any", outcome: outcome}) <> "\n",
      [:append]
    )
  end

  # ------------------------------------------------------------------
  # strip/1
  # ------------------------------------------------------------------

  describe "strip/1" do
    test "removes every doc/spec/type attribute and keeps the code" do
      stripped = Dedoc.strip(@documented)

      refute stripped =~ "@moduledoc"
      refute stripped =~ "@doc"
      refute stripped =~ "@spec"
      refute stripped =~ "@type"
      refute stripped =~ "@typep"
      refute stripped =~ "widget things"
      refute stripped =~ "Stops the widget"

      assert stripped =~ "def run(_widget), do: :ok"
      assert stripped =~ "def stop(_widget, _timeout) do"
      assert stripped =~ "defp classify(x), do: x"
      # Token boundary: a spec ending in `:error` must not read as ending in
      # the continuation word "or" and swallow the following def line.
      assert stripped =~ "def fetch(_widget), do: :error"
      # Non-doc attributes survive.
      assert stripped =~ "@impl_marker :kept_attribute"
    end

    test "handles a multi-line @spec that continues on :: and | lines" do
      stripped = Dedoc.strip(@documented)
      refute stripped =~ ":: non_neg_integer()"
      refute stripped =~ "| {:error, term()}"
    end

    test "output is formatter-canonical and still parses" do
      stripped = Dedoc.strip(@documented)

      assert stripped ==
               stripped |> Code.format_string!() |> IO.iodata_to_binary() |> Kernel.<>("\n")

      assert {:ok, _} = Code.string_to_quoted(stripped)
    end

    test "is idempotent" do
      once = Dedoc.strip(@documented)
      assert Dedoc.strip(once) == once
    end
  end

  # ------------------------------------------------------------------
  # house_trio?/1, dedoc_id/1, prompt_md/1
  # ------------------------------------------------------------------

  test "house_trio? demands @moduledoc + @doc + @spec" do
    assert Dedoc.house_trio?(@documented)
    refute Dedoc.house_trio?("defmodule X do\n  @moduledoc \"m\"\n  def f, do: 1\nend\n")
  end

  test "dedoc_id drops the trailing _01" do
    assert Dedoc.dedoc_id("104_004_usage_recycling_connection_pool_01") ==
             "dedoc_104_004_usage_recycling_connection_pool"
  end

  test "prompt_md embeds the stripped module and the documentation contract" do
    stripped = Dedoc.strip(@documented)
    prompt = Dedoc.prompt_md(stripped, "dedoc_x")

    assert prompt =~ "# Document this module"
    assert prompt =~ "```elixir"
    assert prompt =~ "def run(_widget), do: :ok"
    assert prompt =~ "@moduledoc"
    assert prompt =~ "@spec"
    assert prompt =~ "Do not change any behavior"
  end

  # ------------------------------------------------------------------
  # dialyzer gate
  # ------------------------------------------------------------------

  test "dialyzer_clean_or_waived? matches the CURRENT sha only, last row wins" do
    cfg = sandbox()

    refute Dedoc.dialyzer_clean_or_waived?(cfg, @documented)

    dialyzer_row!(cfg, @documented, "warnings")
    refute Dedoc.dialyzer_clean_or_waived?(cfg, @documented)

    dialyzer_row!(cfg, @documented, "clean")
    assert Dedoc.dialyzer_clean_or_waived?(cfg, @documented)

    refute Dedoc.dialyzer_clean_or_waived?(cfg, @documented <> "# drifted\n")
  end

  # ------------------------------------------------------------------
  # run/2 cheap paths (no evals)
  # ------------------------------------------------------------------

  test "run/2 is a no-op when skip_dedoc is set or the dir already exists" do
    cfg = sandbox()
    write_dir(cfg, "001_001_widget_01", trio_files())
    seed = %{num: 1, slug: "widget", b: 1, task_id: "001_001_widget_01", files: trio_files()}

    assert Dedoc.run(seed, %{cfg | skip_dedoc: true}) == []

    write_dir(cfg, "dedoc_001_001_widget", %{"prompt.md" => "x"})
    assert Dedoc.run(seed, cfg) == []
  end

  test "run/2 skips with a reason when the dialyzer verdict is missing" do
    cfg = sandbox()
    write_dir(cfg, "001_001_widget_01", trio_files())
    seed = %{num: 1, slug: "widget", b: 1, task_id: "001_001_widget_01", files: trio_files()}

    assert [outcome] = Dedoc.run(seed, cfg)
    assert outcome.status == :skipped
    assert outcome.reason =~ "dialyzer"
  end

  test "run/2 skips an under-documented parent" do
    cfg = sandbox()
    files = Map.put(trio_files(), "solution.ex", "defmodule X do\n  def f, do: 1\nend\n")
    write_dir(cfg, "001_001_widget_01", files)
    seed = %{num: 1, slug: "widget", b: 1, task_id: "001_001_widget_01", files: files}

    assert [outcome] = Dedoc.run(seed, cfg)
    assert outcome.status == :skipped
    assert outcome.reason =~ "trio"
  end

  # ------------------------------------------------------------------
  # missing_units/2
  # ------------------------------------------------------------------

  test "missing_units counts 1 only for a complete, trio'd, dialyzer-clean parent" do
    cfg = sandbox()
    write_dir(cfg, "001_001_widget_01", trio_files())
    seed = seed_for(cfg, "001_001_widget_01")

    # No dialyzer verdict yet → 0.
    assert Dedoc.missing_units(seed, cfg) == 0

    dialyzer_row!(cfg, @documented, "clean")
    assert Dedoc.missing_units(seed, cfg) == 1

    # Existing dedoc_ dir → 0.
    write_dir(cfg, "dedoc_001_001_widget", %{"prompt.md" => "x"})
    assert Dedoc.missing_units(seed, cfg) == 0
  end

  test "missing_units is 0 for an under-documented or incomplete parent" do
    cfg = sandbox()

    write_dir(
      cfg,
      "002_001_bare_01",
      Map.put(trio_files(), "solution.ex", "defmodule Y do\n  def f, do: 1\nend\n")
    )

    assert Dedoc.missing_units(seed_for(cfg, "002_001_bare_01"), cfg) == 0

    write_dir(cfg, "003_001_noharness_01", Map.delete(trio_files(), "test_harness.exs"))
    assert Dedoc.missing_units(seed_for(cfg, "003_001_noharness_01"), cfg) == 0
  end
end
