#!/usr/bin/env elixir
# eval_task_v2.exs — integrated 3-shape evaluator prototype (single-file | multifile | FIM).
# Reuses eval_task.exs scoring VERBATIM for single-file (backward compat by construction).
for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"], p <- Path.wildcard(pattern), do: Code.prepend_path(p)

defmodule V2.FailureCollector do
  @moduledoc false
  use GenServer
  @t :eval_task_failures_v2
  def start_link(_ \\ []) do
    if :ets.whereis(@t) != :undefined, do: :ets.delete(@t)
    :ets.new(@t, [:named_table, :public, :ordered_set])
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  def get_failures, do: @t |> :ets.tab2list() |> Enum.map(fn {_k, f} -> f end)
  @impl true
  def init(_), do: {:ok, 0}
  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: nil}}, c), do: {:noreply, c}
  def handle_cast({:test_finished, %ExUnit.Test{} = t}, c) do
    :ets.insert(@t, {c, %{test: to_string(t.name), module: inspect(t.module), message: fmt(t.state)}})
    {:noreply, c + 1}
  end
  def handle_cast(_, c), do: {:noreply, c}
  defp fmt({:failed, fs}) when is_list(fs), do: Enum.map_join(fs, "\n", fn
    {_k, %ExUnit.AssertionError{} = e, _} -> Exception.message(e)
    {_k, e, _} when is_exception(e) -> Exception.message(e)
    {k, r, _} -> "#{inspect(k)}: #{inspect(r, limit: 200)}" end)
  defp fmt(o), do: inspect(o, limit: 200)
end

defmodule V2 do
  # ---------- shape detection ----------
  def detect(task_dir, sol_file) do
    has_harness = File.regular?(Path.join(task_dir, "test_harness.exs"))
    src = if File.regular?(sol_file), do: File.read!(sol_file), else: ""
    cond do
      not has_harness -> :fim
      String.contains?(src, "<file path=") -> :multifile
      true -> :single
    end
  end

  def run(task_dir, sol_file) do
    shape = detect(task_dir, sol_file)
    base = %{task: Path.basename(task_dir), shape: shape, solution_file: sol_file}
    result =
      case shape do
        :single -> run_single(task_dir, sol_file)
        :multifile -> run_multifile(task_dir, sol_file)
        :fim -> run_fim(task_dir, sol_file)
      end
    Map.merge(base, result)
  end

  # ---------- SINGLE (verbatim eval_task.exs path) ----------
  defp run_single(task_dir, sol_file) do
    harness = Path.join(task_dir, "test_harness.exs")
    compile = compile_one(sol_file)
    analysis = analyze_source(File.read!(sol_file))
    tests = if compile.compiled, do: run_harness(harness), else: no_tests()
    score(compile, analysis, tests, :full)
  end

  # ---------- MULTIFILE (Tier-A + Tier-B kit) ----------
  defp run_multifile(task_dir, sol_file) do
    harness = Path.join(task_dir, "test_harness.exs")
    hsrc = File.read!(harness)
    archetype =
      cond do
        hsrc =~ ~r/use\s+\w+Web\.ConnCase/ -> :phoenix_conncase
        hsrc =~ ~r/use Plug\.Test/ or hsrc =~ ~r/import Plug\.Test/ -> :plug_selfcontained
        true -> :pure_otp
      end
    blocks = parse_bundle(File.read!(sol_file))
    tmp = mktemp()
    src_paths = for {p, b} <- blocks, String.ends_with?(p, ".ex"), do: write(tmp, p, b)
    mig_paths = for {p, b} <- blocks, String.ends_with?(p, ".exs"), String.contains?(p, "migrations"), do: write(tmp, p, b)
    lib_srcs = for {p, b} <- blocks, String.ends_with?(p, ".ex"), String.starts_with?(p, "lib/"), do: b
    analysis = analyze_sources(lib_srcs)

    compile =
      try do
        if archetype == :phoenix_conncase do
          [_, webp] = Regex.run(~r/use\s+(\w+)\.ConnCase/, hsrc)
          prefix = String.replace_suffix(webp, "Web", "")
          otp = Macro.underscore(prefix) |> String.to_atom()
          db = Path.join(System.tmp_dir!(), "v2mf_#{uniq()}.db"); File.rm_rf(db)
          repo_m = Module.concat(prefix, "Repo"); endp_m = Module.concat(webp, "Endpoint")
          kit_paths = render_phoenix_kit(tmp, prefix, webp, otp)
          Application.put_env(otp, repo_m, database: db, pool: Ecto.Adapters.SQL.Sandbox, pool_size: 5)
          Application.put_env(otp, endp_m, secret_key_base: String.duplicate("z",64), server: false,
            render_errors: [formats: [json: Module.concat(webp,"ErrorJSON")], layout: false])
          {:ok, _, diag} = Kernel.ParallelCompiler.compile(src_paths ++ kit_paths, return_diagnostics: true)
          {:ok, migmods, _} = Kernel.ParallelCompiler.compile(mig_paths, return_diagnostics: true)
          {:ok, _} = Supervisor.start_link([repo_m, endp_m], strategy: :one_for_one)
          migmods |> Enum.with_index(1) |> Enum.each(fn {m,i} -> Ecto.Migrator.up(repo_m, i, m, log: false) end)
          Ecto.Adapters.SQL.Sandbox.mode(repo_m, :manual)
          %{compiled: true, compile_warnings: length(diag.compile_warnings), compile_warning_messages: [], compile_errors: [], tier: "B", archetype: archetype}
        else
          {:ok, _m, diag} = Kernel.ParallelCompiler.compile(src_paths, return_diagnostics: true)
          %{compiled: true, compile_warnings: length(diag.compile_warnings), compile_warning_messages: [], compile_errors: [], tier: "A", archetype: archetype}
        end
      rescue e -> %{compiled: false, compile_warnings: 0, compile_warning_messages: [], compile_errors: [%{type: inspect(e.__struct__), message: Exception.message(e) |> String.slice(0,160)}], archetype: archetype}
      end
    tests = if compile.compiled, do: run_harness(harness), else: no_tests()
    File.rm_rf!(tmp)
    Map.put(score(compile, analysis, tests, :full) |> Map.merge(Map.take(compile, [:tier, :archetype])), :bundle_files, length(blocks))
  end

  defp render_phoenix_kit(tmp, prefix, webp, otp) do
    %{
      "kit_repo.ex" => "defmodule #{prefix}.Repo do\n  use Ecto.Repo, otp_app: #{inspect(otp)}, adapter: Ecto.Adapters.SQLite3\nend",
      "kit_web.ex" => """
      defmodule #{webp} do
        def controller do
          quote do
            use Phoenix.Controller, formats: [:json]
            import Plug.Conn
            unquote(#{webp}.verified_routes())
          end
        end
        def router, do: quote(do: (use Phoenix.Router))
        def verified_routes do
          quote do
            use Phoenix.VerifiedRoutes, endpoint: #{webp}.Endpoint, router: #{webp}.Router
          end
        end
        defmacro __using__(w), do: apply(__MODULE__, w, [])
      end
      """,
      "kit_err.ex" => """
      defmodule #{webp}.ErrorJSON do
        def render(t,_), do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(t)}}
      end
      defmodule #{webp}.Endpoint do
        use Phoenix.Endpoint, otp_app: #{inspect(otp)}
        plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
        plug #{webp}.Router
      end
      """,
      "kit_conncase.ex" => """
      defmodule #{webp}.ConnCase do
        use ExUnit.CaseTemplate
        using do
          quote do
            use #{webp}, :verified_routes
            import Plug.Conn
            import Phoenix.ConnTest
            @endpoint #{webp}.Endpoint
          end
        end
        setup tags do
          pid = Ecto.Adapters.SQL.Sandbox.start_owner!(#{prefix}.Repo, shared: not tags[:async])
          on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
          {:ok, conn: Phoenix.ConnTest.build_conn()}
        end
      end
      """
    }
    |> Enum.map(fn {n, b} -> f = Path.join(tmp, n); File.write!(f, b); f end)
  end

  # ---------- FIM ----------
  defp run_fim(task_dir, sol_file) do
    base = Path.basename(task_dir)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
    harness = Path.join(["tasks", parent, "test_harness.exs"])
    prompt = File.read!(Path.join(task_dir, "prompt.md"))
    [_, skeleton] = Regex.run(~r/```elixir\n(.*?)\n```/s, prompt)
    candidate = extract_candidate(File.read!(sol_file))
    recon = if String.contains?(candidate, "defmodule"), do: candidate, else: splice(skeleton, candidate)
    tmp = Path.join(System.tmp_dir!(), "v2fim_#{uniq()}.ex")
    File.write!(tmp, recon)
    compile = compile_one(tmp)
    analysis = analyze_source(candidate, :fim)        # analysis on candidate FUNCTION only
    tests = if compile.compiled, do: run_harness(harness), else: no_tests()
    File.rm(tmp)
    Map.merge(score(compile, analysis, tests, :fim), %{parent: parent})
  end

  # candidate = strip a leading ```elixir fence if the model wrapped it
  defp extract_candidate(s) do
    case Regex.run(~r/```(?:elixir)?\n(.*?)\n```/s, s) do
      [_, code] -> code
      _ -> s
    end
  end

  defp splice(skeleton, cand) do
    lines = String.split(skeleton, "\n")
    mi = Enum.find_index(lines, &(&1 =~ ~r/#\s*TODO/i))
    after_m = Regex.replace(~r/^\s*#\s*TODO:?/i, Enum.at(lines, mi), "") |> String.trim()
    {lo, hi} =
      if after_m == "" do
        di = Enum.reduce_while((mi-1)..0//-1, nil, fn j,_ -> if Enum.at(lines,j)=~~r/^\s*(def|defp|defmacro|defmacrop)\s/, do: {:halt,j}, else: {:cont,nil} end)
        ind = Regex.run(~r/^(\s*)/, Enum.at(lines,di)) |> hd()
        ei = Enum.reduce_while((mi+1)..(length(lines)-1), nil, fn j,_ -> if Enum.at(lines,j)==ind<>"end", do: {:halt,j}, else: {:cont,nil} end)
        {di, ei}
      else {mi, mi} end
    (Enum.slice(lines,0,lo) ++ [cand] ++ Enum.slice(lines,(hi+1)..-1//1)) |> Enum.join("\n")
  end

  # ---------- shared: compile / test / analysis / score (from eval_task.exs) ----------
  defp compile_one(path) do
    {res, diag} = Code.with_diagnostics(fn ->
      try do Code.compile_file(path); :ok rescue e -> {:error, e} catch k, r -> {:error, {k, r}} end
    end)
    warns = Enum.filter(diag, &(&1.severity == :warning))
    case res do
      :ok -> %{compiled: true, compile_warnings: length(warns), compile_warning_messages: [], compile_errors: []}
      {:error, %{__struct__: t} = e} -> %{compiled: false, compile_warnings: length(warns), compile_warning_messages: [], compile_errors: [%{type: inspect(t), message: Exception.message(e)}]}
      {:error, {k, r}} -> %{compiled: false, compile_warnings: length(warns), compile_warning_messages: [], compile_errors: [%{type: inspect(k), message: inspect(r)}]}
    end
  end

  defp run_harness(harness) do
    :logger.update_handler_config(:default, :config, %{type: :standard_error})
    {:ok, _} = V2.FailureCollector.start_link()
    Application.ensure_all_started(:stream_data)
    ExUnit.start(autorun: false, formatters: [V2.FailureCollector])
    case (try do Code.compile_file(harness); :ok rescue e -> {:error, Exception.message(e)} end) do
      {:error, m} -> Map.merge(no_tests(), %{tests_errors: 1, test_failures: [%{test: "harness_load", message: m}]})
      :ok ->
        %{failures: f, total: t, excluded: x} = ExUnit.run()
        %{tests_ran: true, tests_passed: max(t-f-x,0), tests_failed: f, tests_errors: 0, tests_excluded: x, tests_total: t, test_failures: V2.FailureCollector.get_failures()}
    end
  rescue e -> Map.merge(no_tests(), %{tests_errors: 1, test_failures: [%{test: "crash", message: Exception.message(e)}]})
  end

  defp no_tests, do: %{tests_ran: false, tests_passed: 0, tests_failed: 0, tests_errors: 0, tests_excluded: 0, tests_total: 0, test_failures: []}

  # analyze_source — VERBATIM from eval_task.exs, plus a :fim mode + multi-source fold
  def analyze_source(source, mode \\ :full) do
    lines = String.split(source, "\n")
    lens = Enum.map(lines, &String.length/1)
    %{
      has_moduledoc: String.contains?(source, "@moduledoc"),
      has_typespecs: Regex.match?(~r/@spec\s/, source),
      has_doc_on_public_fns: Regex.match?(~r/@doc\s/, source),
      line_count: length(lines), max_line_length: Enum.max(lens, fn -> 0 end),
      lines_over_98: Enum.count(lens, &(&1 > 98)),
      public_fn_count: length(Regex.scan(~r/^\s*def\s+\w+/m, source)),
      defp_count: length(Regex.scan(~r/^\s*defp\s+\w+/m, source)),
      todo_count: length(Regex.scan(~r/#\s*(TODO|FIXME|HACK|XXX)/i, source)),
      pipe_chain_count: length(Regex.scan(~r/\|>/m, source)),
      sql_injection_risk: Regex.match?(~r/".*\#\{.*\}.*FROM|WHERE.*\#\{/m, source),
      credo_issues: [], mode: mode
    }
  end
  def analyze_sources(srcs), do: analyze_source(Enum.join(srcs, "\n"), :full)

  defp analysis_checks(a) do
    doc_checks =
      if a.mode == :fim do
        []  # FIM: a single function has no moduledoc/@spec/@doc — drop those checks
      else
        [{2, 2, a.has_moduledoc, "@moduledoc"}, {2, 2, a.has_typespecs, "@spec"}, {1, 1, a.has_doc_on_public_fns, "@doc"}]
      end
    doc_checks ++ [
      {1, 1, a.lines_over_98 == 0, "no lines >98"},
      {1, 1, a.todo_count == 0, "no TODO"},
      {1, 1, !a.sql_injection_risk, "no SQLi"},
      {2, 2, true, "credo"}
    ]
  end

  defp score(compile, analysis, tests, mode) do
    comp = if compile.compiled, do: max(0.0, 1.0 - compile.compile_warnings * 0.1), else: 0.0
    tscore = if tests.tests_total > 0, do: tests.tests_passed / tests.tests_total, else: 0.0
    checks = analysis_checks(analysis)
    pts = checks |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    maxpts = checks |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    ascore = if maxpts > 0, do: min(pts / maxpts, 1.0), else: 1.0
    overall = if compile.compiled, do: tscore*0.7 + ascore*0.2 + comp*0.1, else: 0.0
    Map.merge(compile, Map.merge(tests, %{
      analysis: analysis, analysis_max: maxpts,
      score: %{compilation: Float.round(comp,2), tests: Float.round(tscore,2), analysis: Float.round(ascore,2), overall: Float.round(overall,2), mode: mode}
    }))
  end

  # ---------- bundle + temp helpers ----------
  def parse_bundle(t), do: Regex.scan(~r/<file path="([^"]+)">\n(.*?)\n<\/file>/s, t) |> Enum.map(fn [_,p,b] -> {p,b} end)
  defp mktemp, do: (d = Path.join(System.tmp_dir!(), "v2_#{uniq()}"); File.mkdir_p!(d); d)
  defp write(tmp, p, b), do: (f = Path.join(tmp, p); File.mkdir_p!(Path.dirname(f)); File.write!(f, b); f)
  defp uniq, do: System.unique_integer([:positive])
end

[task_dir | rest] = System.argv()
sol = case rest do [f|_] -> f; [] -> Path.join(task_dir, "solution.ex") end
IO.puts(:json.encode(V2.run(task_dir, sol)))
