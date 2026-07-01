# Integrated prototype of the proposed multifile evaluator.
# Usage: mix run eval_multifile.exs <task_dir> [solution_file]
[task_dir | rest] = System.argv()
sol_file = case rest do
  [f | _] -> f
  [] -> Path.join(task_dir, "solution.ex")
end
harness = Path.join(task_dir, "test_harness.exs")
harness_src = File.read!(harness)

# --- 1. parse <file> bundle ---
blocks = Regex.scan(~r/<file path="([^"]+)">\n(.*?)\n<\/file>/s, File.read!(sol_file))
         |> Enum.map(fn [_, p, b] -> {p, b} end)

# --- 2. infer archetype from the harness (tests the "no manifest needed" hypothesis) ---
archetype = cond do
  harness_src =~ ~r/use\s+\w+Web\.ConnCase/ -> :phoenix_conncase
  harness_src =~ ~r/use Plug\.Test/ or harness_src =~ ~r/import Plug\.Test/ -> :plug_selfcontained
  true -> :pure_otp
end

tmp = Path.join(System.tmp_dir!(), "evalmf_#{System.unique_integer([:positive])}")
src_paths = for {p,b} <- blocks, String.ends_with?(p,".ex") do
  f=Path.join(tmp,p); File.mkdir_p!(Path.dirname(f)); File.write!(f,b); f end
mig_paths = for {p,b} <- blocks, String.ends_with?(p,".exs"), String.contains?(p,"migrations") do
  f=Path.join(tmp,p); File.mkdir_p!(Path.dirname(f)); File.write!(f,b); f end

run_harness = fn ->
  ExUnit.start(autorun: false)
  Code.compile_file(harness)
  ExUnit.run()
end

result =
  try do
    case archetype do
      a when a in [:pure_otp, :plug_selfcontained] ->
        {:ok, mods, diag} = Kernel.ParallelCompiler.compile(src_paths, return_diagnostics: true)
        res = run_harness.()
        %{compiled: true, modules: length(mods), warnings: length(diag.compile_warnings), archetype: a,
          tests_total: res.total, tests_failed: res.failures, tests_excluded: res.excluded}

      :phoenix_conncase ->
        # infer prefix from `use <Web>.ConnCase`
        [_, webp] = Regex.run(~r/use\s+(\w+)\.ConnCase/, harness_src)
        prefix = String.replace_suffix(webp, "Web", "")
        otp = Macro.underscore(prefix) |> String.to_atom()
        db = Path.join(System.tmp_dir!(), "evalmf_#{System.unique_integer([:positive])}.db"); File.rm_rf(db)
        repo_m = Module.concat(prefix, "Repo"); endp_m = Module.concat(webp, "Endpoint")
        kit = %{
          "kr.ex" => "defmodule #{prefix}.Repo do\n  use Ecto.Repo, otp_app: #{inspect(otp)}, adapter: Ecto.Adapters.SQLite3\nend",
          "kw.ex" => """
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
          "ke.ex" => """
          defmodule #{webp}.ErrorJSON do
            def render(t,_), do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(t)}}
          end
          defmodule #{webp}.Endpoint do
            use Phoenix.Endpoint, otp_app: #{inspect(otp)}
            plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
            plug #{webp}.Router
          end
          """,
          "kc.ex" => """
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
        kit_paths = for {n,b} <- kit do f=Path.join(tmp,"kit_"<>n); File.write!(f,b); f end
        Application.put_env(otp, repo_m, database: db, pool: Ecto.Adapters.SQL.Sandbox, pool_size: 5)
        Application.put_env(otp, endp_m, secret_key_base: String.duplicate("z",64), server: false,
          render_errors: [formats: [json: Module.concat(webp,"ErrorJSON")], layout: false])
        {:ok, _, diag} = Kernel.ParallelCompiler.compile(src_paths ++ kit_paths, return_diagnostics: true)
        {:ok, migmods, _} = Kernel.ParallelCompiler.compile(mig_paths, return_diagnostics: true)
        {:ok, _} = Supervisor.start_link([repo_m, endp_m], strategy: :one_for_one)
        migmods |> Enum.with_index(1) |> Enum.each(fn {m,i} -> Ecto.Migrator.up(repo_m, i, m, log: false) end)
        Ecto.Adapters.SQL.Sandbox.mode(repo_m, :manual)
        res = run_harness.()
        %{compiled: true, warnings: length(diag.compile_warnings), archetype: :phoenix_conncase,
          prefix: prefix, otp_app: otp, tests_total: res.total, tests_failed: res.failures, tests_excluded: res.excluded}
    end
  rescue
    e -> %{compiled: false, archetype: archetype, error: Exception.message(e)}
  end

File.rm_rf!(tmp)
IO.puts(:json.encode(Map.put(result, :task, Path.basename(task_dir))))
