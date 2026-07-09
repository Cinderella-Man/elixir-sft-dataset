defmodule EvalTask.Runner do
  @moduledoc """
  Runs a task through compile + harness + scoring, per shape:
  `:single`, `:multifile` (Tier-A / Tier-B), and `:fim`.
  """

  alias EvalTask.{Analysis, Bundle, Fim, Manifest, PhoenixKit}

  @doc "Run a single-file task (dir contains its own harness + a plain-module solution)."
  def run_single(task_dir, sol_file) do
    run_single_explicit(sol_file, Path.join(task_dir, "test_harness.exs"))
  end

  @doc "Run a single-file solution against an explicit harness path (legacy invocation)."
  def run_single_explicit(sol_file, harness) do
    compile = compile_file(sol_file)
    analysis = Analysis.analyze(File.read!(sol_file), :full)
    tests = if compile.compiled, do: run_harness(harness), else: no_tests()
    finish(compile, analysis, tests, %{shape: :single})
  end

  @doc "Run a multi-file (`<file>` bundle) task; Tier-A or Tier-B by inferred archetype."
  def run_multifile(task_dir, sol_file) do
    harness = Path.join(task_dir, "test_harness.exs")
    cfg = Manifest.resolve(task_dir, File.read!(harness))
    files = Bundle.parse(File.read!(sol_file))

    case Bundle.validate(files) do
      {:error, reason} ->
        finish(
          %{
            compiled: false,
            compile_warnings: 0,
            compile_errors: [%{type: "InvalidBundle", message: reason}]
          },
          Analysis.analyze_all(Bundle.lib_sources(files), :full),
          no_tests(),
          %{archetype: cfg.archetype, bundle_files: length(files)}
        )

      :ok ->
        do_run_multifile(files, harness, cfg)
    end
  end

  defp do_run_multifile(files, harness, cfg) do
    tmp = mktemp()
    {sources, migrations} = Bundle.materialize(files, tmp)
    analysis = Analysis.analyze_all(Bundle.lib_sources(files), :full)

    {compile, extra, cleanup} =
      try do
        case cfg.archetype do
          :phoenix_conncase -> compile_tier_b(files, sources, migrations, tmp, cfg)
          :ecto_repo -> compile_tier_repo(files, sources, migrations, tmp, cfg)
          _ -> {compile_bundle(sources) |> Map.put(:tier, "A"), %{tier: "A"}, fn -> :ok end}
        end
      rescue
        e ->
          {%{
             compiled: false,
             compile_warnings: 0,
             compile_errors: [
               %{
                 type: inspect(e.__struct__),
                 message: Exception.message(e) |> String.slice(0, 300)
               }
             ]
           }, %{tier: tier(cfg.archetype)}, fn -> :ok end}
      end

    tests = if compile.compiled, do: run_harness(harness), else: no_tests()
    _ = safe_cleanup(cleanup)
    File.rm_rf!(tmp)

    finish(
      compile,
      analysis,
      tests,
      Map.merge(extra, %{archetype: cfg.archetype, bundle_files: length(files)})
    )
  end

  defp safe_cleanup(fun) do
    fun.()
  rescue
    _ -> :ok
  end

  defp compile_tier_b(files, sources, migrations, tmp, cfg) do
    db = Map.get(cfg, :db, :sqlite)
    ensure_db_apps(db)

    %{prefix: prefix, web_prefix: web, otp_app: otp} = cfg
    repo = Module.concat(prefix, "Repo")
    endpoint = Module.concat(web, "Endpoint")

    # Provision storage (create a fresh, isolated DB) and return a cleanup thunk.
    storage_cleanup = setup_repo_storage(db, otp, prefix, web)

    kit_paths = PhoenixKit.render(tmp, prefix, web, otp, Bundle.module_names(files), db)

    # On a compile failure raise with the REAL diagnostics; the tier-B rescue upstream
    # turns this into compiled:false. A bare `{:ok, …}` match would report a useless
    # truncated MatchError instead.
    diag = compile_or_raise!(sources ++ kit_paths, "solution+kit")
    mig_mods = compile_or_raise!(migrations, "migrations").modules
    {:ok, sup} = Supervisor.start_link([repo, endpoint], strategy: :one_for_one)

    mig_mods
    |> Enum.with_index(1)
    |> Enum.each(fn {mod, v} -> Ecto.Migrator.up(repo, v, mod, log: false) end)

    Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)

    # Stop the repo pool before dropping storage (Postgres refuses DROP DATABASE
    # while connections are open).
    cleanup = fn ->
      _ = Supervisor.stop(sup)
      storage_cleanup.()
    end

    {%{
       compiled: true,
       compile_warnings: length(diag.compile_warnings),
       compile_errors: [],
       tier: "B"
     }, %{tier: "B"}, cleanup}
  end

  # Repo-only tier (`:ecto_repo` archetype, manifest-declared): boots the kit Repo
  # and runs the bundle's migrations exactly like tier B, but renders/starts no web
  # modules — for Ecto-backed tasks with no controller/router surface. The synthetic
  # web prefix only feeds `PhoenixKit.configure`'s (unused) endpoint env entry.
  defp compile_tier_repo(files, sources, migrations, tmp, cfg) do
    db = Map.get(cfg, :db, :sqlite)
    ensure_db_apps(db)

    %{prefix: prefix, otp_app: otp} = cfg
    repo = Module.concat(prefix, "Repo")
    web = cfg[:web_prefix] || "#{prefix}Web"

    storage_cleanup = setup_repo_storage(db, otp, prefix, web)
    kit_paths = PhoenixKit.render_repo(tmp, prefix, otp, Bundle.module_names(files), db)

    diag = compile_or_raise!(sources ++ kit_paths, "solution+repo-kit")
    mig_mods = compile_or_raise!(migrations, "migrations").modules
    {:ok, sup} = Supervisor.start_link([repo], strategy: :one_for_one)

    mig_mods
    |> Enum.with_index(1)
    |> Enum.each(fn {mod, v} -> Ecto.Migrator.up(repo, v, mod, log: false) end)

    Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)

    cleanup = fn ->
      _ = Supervisor.stop(sup)
      storage_cleanup.()
    end

    {%{
       compiled: true,
       compile_warnings: length(diag.compile_warnings),
       compile_errors: [],
       tier: "B"
     }, %{tier: "B"}, cleanup}
  end

  defp ensure_db_apps(:postgres) do
    Application.ensure_all_started(:ecto_sql)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:phoenix)
    Application.ensure_all_started(:jason)
  end

  defp ensure_db_apps(_sqlite) do
    Application.ensure_all_started(:ecto_sql)
    Application.ensure_all_started(:ecto_sqlite3)
    Application.ensure_all_started(:phoenix)
    Application.ensure_all_started(:jason)
  end

  # SQLite: a fresh temp file per run. Cleanup deletes it.
  defp setup_repo_storage(:sqlite, otp, prefix, web) do
    db = Path.join(System.tmp_dir!(), "evaldb_#{uniq_suffix()}.db")
    File.rm_rf(db)
    PhoenixKit.configure(otp, prefix, web, db)
    fn -> File.rm_rf(db) end
  end

  # Postgres: a fresh throwaway database per run on the live server (mirrors the
  # per-run SQLite file, so parallel evals don't collide). CREATE fails loudly if
  # no server is reachable — that's the point: the task goes RED, not skipped.
  defp setup_repo_storage(:postgres, otp, prefix, web) do
    opts = Keyword.put(pg_conn_opts(), :database, "evaldb_#{uniq_suffix()}")
    PhoenixKit.configure_postgres(otp, prefix, web, opts)
    ensure_pg_database!(opts)
    fn -> _ = Ecto.Adapters.Postgres.storage_down(opts) end
  end

  defp pg_conn_opts do
    [
      hostname: System.get_env("EVAL_PG_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("EVAL_PG_PORT", "5432")),
      username: System.get_env("EVAL_PG_USER", "postgres"),
      password: System.get_env("EVAL_PG_PASSWORD", "postgres"),
      maintenance_database: System.get_env("EVAL_PG_MAINTENANCE_DB", "postgres")
    ]
  end

  defp ensure_pg_database!(opts) do
    case Ecto.Adapters.Postgres.storage_up(opts) do
      :ok ->
        :ok

      {:error, :already_up} ->
        :ok

      {:error, reason} ->
        raise """
        Postgres is required for this task but is not reachable at \
        #{opts[:hostname]}:#{opts[:port]} (#{inspect(reason)}).

        Start it with `docker compose up -d db` from the repo root, then re-run. \
        Override the connection with EVAL_PG_HOST / EVAL_PG_PORT / EVAL_PG_USER / \
        EVAL_PG_PASSWORD if your server differs.\
        """
    end
  end

  @doc "Run a FIM task: reconstruct from the prompt skeleton + candidate, run the parent harness."
  def run_fim(task_dir, sol_file) do
    parent = Fim.parent_dir(task_dir)
    harness = Path.join(parent, "test_harness.exs")
    prompt = File.read!(Path.join(task_dir, "prompt.md"))
    candidate = Fim.extract_candidate(File.read!(sol_file))

    recon =
      try do
        {:ok, Fim.reconstruct(prompt, File.read!(sol_file))}
      rescue
        e -> {:error, Exception.message(e)}
      end

    case recon do
      {:error, reason} ->
        finish(
          %{
            compiled: false,
            compile_warnings: 0,
            compile_errors: [%{type: "FimReconstruct", message: reason}]
          },
          Analysis.analyze(candidate, :fim),
          no_tests(),
          %{parent: Path.basename(parent)}
        )

      {:ok, module_src} ->
        tmp = Path.join(System.tmp_dir!(), "evalfim_#{uniq_suffix()}.ex")
        File.write!(tmp, module_src)
        compile = compile_file(tmp)
        analysis = Analysis.analyze(candidate, :fim)
        tests = if compile.compiled, do: run_harness(harness), else: no_tests()
        File.rm(tmp)
        finish(compile, analysis, tests, %{parent: Path.basename(parent)})
    end
  end

  @doc """
  Run a `wtest` task (`wt_<a>_<b>_<slug>/`): grade the module (`solution.ex`, plain or
  `<file>` bundle) against the reference `test_harness.exs` — i.e. confirm the gold
  harness passes and, for a candidate harness, that it is consistent with the module.
  Structurally identical to `:single`/`:multifile`, dispatched by the module's content.
  """
  def run_write_test(task_dir, sol_file) do
    result =
      if Bundle.bundle?(File.read!(sol_file)),
        do: run_multifile(task_dir, sol_file),
        else: run_single(task_dir, sol_file)

    Map.put(result, :shape, :write_test)
  end

  @doc """
  Run a `tfim` task (`tfim_<a>_<b>_<slug>_0N/`): splice the candidate test block into
  the harness skeleton from `prompt.md`, then run the reconstructed harness against the
  PARENT `_01`'s reference module (`solution.ex`, plain or bundle). Green ⇔ the completed
  harness passes the reference module. Analysis is on the candidate block (`:fim` mode).
  """
  def run_test_fim(task_dir, sol_file) do
    parent = Fim.test_fim_parent_dir(task_dir)
    prompt = File.read!(Path.join(task_dir, "prompt.md"))
    candidate_raw = File.read!(sol_file)
    analysis = Analysis.analyze(Fim.extract_candidate(candidate_raw), :fim)
    extra = %{parent: Path.basename(parent), shape: :test_fim}

    case reconstruct_harness(prompt, candidate_raw) do
      {:error, reason} ->
        finish(
          %{
            compiled: false,
            compile_warnings: 0,
            compile_errors: [%{type: "TestFimReconstruct", message: reason}]
          },
          analysis,
          no_tests(),
          extra
        )

      {:ok, harness_src} ->
        module_src = File.read!(Path.join(parent, "solution.ex"))
        base = grade_harness_against_module(module_src, harness_src, parent)

        base
        |> Map.merge(%{analysis: analysis, score: Analysis.score(base, analysis, base)})
        |> Map.merge(extra)
    end
  end

  defp reconstruct_harness(prompt, candidate_raw) do
    # force_splice: the candidate is a `test` block, never a whole module — always splice
    # it into the harness skeleton (even if it contains the substring `defmodule`).
    {:ok, Fim.reconstruct(prompt, candidate_raw, true)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Run `harness_src` against a reference module (plain module or `<file>` bundle) by
  # staging a throwaway task dir and delegating to the existing single/multifile runner.
  # The parent's manifest.exs (if any) is copied into the staged dir: archetype/db config
  # must survive reconstruction — a Plug.Test harness over an Ecto bundle cannot be
  # inferred from the harness text alone.
  defp grade_harness_against_module(module_src, harness_src, parent_dir) do
    if Bundle.bundle?(module_src) do
      tmp = mktemp()
      File.write!(Path.join(tmp, "solution.ex"), module_src)
      File.write!(Path.join(tmp, "test_harness.exs"), harness_src)

      parent_manifest = Path.join(parent_dir, "manifest.exs")

      if File.regular?(parent_manifest),
        do: File.cp!(parent_manifest, Path.join(tmp, "manifest.exs"))

      result = run_multifile(tmp, Path.join(tmp, "solution.ex"))
      File.rm_rf!(tmp)
      result
    else
      mod = Path.join(System.tmp_dir!(), "tfmod_#{uniq_suffix()}.ex")
      har = Path.join(System.tmp_dir!(), "tfhar_#{uniq_suffix()}.exs")
      File.write!(mod, module_src)
      File.write!(har, harness_src)
      result = run_single_explicit(mod, har)
      File.rm(mod)
      File.rm(har)
      result
    end
  end

  # ---------- compile / test helpers ----------

  defp compile_file(path) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.compile_file(path)
          :ok
        rescue
          e -> {:error, e}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    warnings = Enum.filter(diagnostics, &(&1.severity == :warning))

    case result do
      :ok ->
        %{compiled: true, compile_warnings: length(warnings), compile_errors: []}

      {:error, %{__struct__: type} = e} ->
        %{
          compiled: false,
          compile_warnings: length(warnings),
          compile_errors: [%{type: inspect(type), message: Exception.message(e)}]
        }

      {:error, {kind, reason}} ->
        %{
          compiled: false,
          compile_warnings: length(warnings),
          compile_errors: [%{type: "#{inspect(kind)}", message: inspect(reason)}]
        }
    end
  end

  defp compile_bundle(sources) do
    # `compile/2` returns `{:error, errors, _}` on a compile failure — a bare `{:ok, …}`
    # match would raise MatchError and bury the real compiler diagnostics in a truncated
    # inspect of the match failure.
    case Kernel.ParallelCompiler.compile(sources, return_diagnostics: true) do
      {:ok, _mods, diag} ->
        %{compiled: true, compile_warnings: length(diag.compile_warnings), compile_errors: []}

      {:error, errors, _diag} ->
        %{compiled: false, compile_warnings: 0, compile_errors: diagnostics_to_errors(errors)}
    end
  rescue
    e ->
      %{
        compiled: false,
        compile_warnings: 0,
        compile_errors: [
          %{type: inspect(e.__struct__), message: Exception.message(e) |> String.slice(0, 200)}
        ]
      }
  end

  # Compile `paths`, returning `%{modules, compile_warnings}`; raises with the real
  # compiler diagnostics on failure (callers inside a rescue report compiled:false).
  defp compile_or_raise!(paths, what) do
    case Kernel.ParallelCompiler.compile(paths, return_diagnostics: true) do
      {:ok, mods, diag} ->
        %{modules: mods, compile_warnings: diag.compile_warnings}

      {:error, errors, _diag} ->
        details = errors |> diagnostics_to_errors() |> Enum.map_join("; ", & &1.message)
        raise "#{what} failed to compile: #{details}"
    end
  end

  # Normalize `Kernel.ParallelCompiler` error diagnostics (maps with :message/:file/
  # :position, or legacy tuples) into the evaluator's compile_errors shape.
  defp diagnostics_to_errors(errors) do
    Enum.map(errors, fn
      %{message: msg} = d ->
        loc = "#{Map.get(d, :file, "?")}:#{inspect(Map.get(d, :position, "?"))}"
        %{type: "CompileError", message: "#{loc}: #{msg}" |> String.slice(0, 500)}

      other ->
        %{type: "CompileError", message: inspect(other) |> String.slice(0, 500)}
    end)
  end

  defp run_harness(harness_file) do
    :logger.update_handler_config(:default, :config, %{type: :standard_error})
    {:ok, _} = EvalTask.FailureCollector.start_link()
    # Under bare `elixir` (run_all's invocation) no apps are auto-started. Start the
    # common set harnesses rely on (Plug.Upload/MIME/crypto for plug tasks, etc.).
    for app <- [
          :crypto,
          :mime,
          :plug_crypto,
          :plug,
          :jason,
          :stream_data,
          :ecto_sql,
          :ecto_sqlite3
        ] do
      Application.ensure_all_started(app)
    end

    # seed: 0 pins test order (and StreamData generation) — without it a flaky
    # harness can pass its accept-grade once and fail forever after in validate.exs.
    ExUnit.start(autorun: false, seed: 0, formatters: [EvalTask.FailureCollector])

    {compile_result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.compile_file(harness_file)
          :ok
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    harness_warnings = Enum.count(diagnostics, &(&1.severity == :warning))

    case compile_result do
      {:error, message} ->
        %{
          no_tests()
          | tests_errors: 1,
            test_failures: [
              %{test: "harness_load", message: "Test harness compilation failed: #{message}"}
            ]
        }
        |> Map.put(:harness_warnings, harness_warnings)

      :ok ->
        # `skipped` (@tag :skip) must be subtracted like `excluded` — a skipped test
        # never ran and MUST NOT count as passed (an all-skip harness used to grade
        # tests_passed == total and score 1.0).
        %{failures: failures, total: total, excluded: excluded, skipped: skipped} =
          ExUnit.run()

        %{
          tests_ran: true,
          tests_passed: max(total - failures - excluded - skipped, 0),
          tests_failed: failures,
          tests_errors: 0,
          tests_excluded: excluded,
          tests_skipped: skipped,
          tests_total: total,
          test_failures: EvalTask.FailureCollector.get_failures(),
          harness_warnings: harness_warnings
        }
    end
  rescue
    e ->
      %{
        no_tests()
        | tests_errors: 1,
          test_failures: [
            %{test: "crash", message: "Test execution crashed: #{Exception.message(e)}"}
          ]
      }
  end

  defp no_tests do
    %{
      tests_ran: false,
      tests_passed: 0,
      tests_failed: 0,
      tests_errors: 0,
      tests_excluded: 0,
      tests_skipped: 0,
      tests_total: 0,
      test_failures: []
    }
  end

  defp finish(compile, analysis, tests, extra) do
    # Warnings emitted while compiling the test harness count the same as
    # warnings from the solution: fold them into compile_warnings so the
    # scorer's warnings-as-errors gate sees the full picture.
    harness_warnings = Map.get(tests, :harness_warnings, 0)
    compile = %{compile | compile_warnings: compile.compile_warnings + harness_warnings}
    tests = Map.delete(tests, :harness_warnings)

    score = Analysis.score(compile, analysis, tests)

    compile
    |> Map.merge(tests)
    |> Map.merge(%{analysis: analysis, score: score})
    |> Map.merge(extra)
  end

  defp mktemp do
    d = Path.join(System.tmp_dir!(), "eval_#{uniq_suffix()}")
    File.mkdir_p!(d)
    d
  end

  # Unique across SEPARATE OS processes too — System.unique_integer is only
  # unique within a single BEAM, and run_all spawns one BEAM per task in parallel.
  defp uniq_suffix, do: "#{System.pid()}_#{System.unique_integer([:positive])}"

  defp tier(:phoenix_conncase), do: "B"
  defp tier(:ecto_repo), do: "B"
  defp tier(_), do: "A"
end
