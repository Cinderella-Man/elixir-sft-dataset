defmodule EvalTask.PhoenixKit do
  @moduledoc """
  Prefix-parameterized Phoenix + Ecto (SQLite) host kit for `:phoenix_conncase`
  multi-file tasks. The bundle ships only DOMAIN modules (schema, context,
  controller, router, JSON view, migration); this kit supplies the app infra the
  harness's `use <Web>.ConnCase` needs: the Repo, the web-entry module, the
  Endpoint, a default ErrorJSON, and the ConnCase.

  Override rule (S4-D3): any infra module the BUNDLE already defines is NOT
  injected by the kit — the bundle wins. `<Web>.ConnCase` is always injected
  (a bundle never ships its own test case template).
  """

  @doc """
  Render the kit modules into `dir`, skipping any module the bundle already
  defines (`bundle_modules`). Returns the written file paths.
  """
  @spec render(String.t(), String.t(), String.t(), atom(), [String.t()], :sqlite | :postgres) ::
          [String.t()]
  def render(dir, prefix, web, otp, bundle_modules, db \\ :sqlite) do
    candidates = [
      {"#{prefix}.Repo", "kit_repo.ex", repo(prefix, otp, db)},
      {web, "kit_web.ex", web_entry(web, otp)},
      {"#{web}.Endpoint", "kit_endpoint.ex", endpoint(web, otp)},
      {"#{web}.ErrorJSON", "kit_error_json.ex", error_json(web)},
      # ConnCase is test support — always injected.
      {"__conn_case__", "kit_conn_case.ex", conn_case(prefix, web)}
    ]

    for {mod, file, code} <- candidates, mod == "__conn_case__" or mod not in bundle_modules do
      path = Path.join(dir, file)
      File.write!(path, code)
      path
    end
  end

  @doc """
  Render only the Repo module — for `:ecto_repo` (repo-only) tasks that have an
  Ecto surface but no web layer. Same override rule: a bundle-defined Repo wins.
  """
  @spec render_repo(String.t(), String.t(), atom(), [String.t()], :sqlite | :postgres) ::
          [String.t()]
  def render_repo(dir, prefix, otp, bundle_modules, db \\ :sqlite) do
    for {mod, file, code} <- [{"#{prefix}.Repo", "kit_repo.ex", repo(prefix, otp, db)}],
        mod not in bundle_modules do
      path = Path.join(dir, file)
      File.write!(path, code)
      path
    end
  end

  @doc "SQLite Repo + Endpoint `Application.put_env` config. Call before compile + boot."
  @spec configure(atom(), String.t(), String.t(), String.t()) :: :ok
  def configure(otp, prefix, web, db_path) do
    Application.put_env(otp, Module.concat(prefix, "Repo"),
      database: db_path,
      pool: Ecto.Adapters.SQL.Sandbox,
      pool_size: 5
    )

    configure_endpoint(otp, web)
  end

  @doc """
  Postgres Repo + Endpoint config. `pg_opts` carries `:hostname`/`:port`/`:username`/
  `:password`/`:database`. Call before compile + boot.
  """
  @spec configure_postgres(atom(), String.t(), String.t(), keyword()) :: :ok
  def configure_postgres(otp, prefix, web, pg_opts) do
    Application.put_env(
      otp,
      Module.concat(prefix, "Repo"),
      Keyword.merge(pg_opts, pool: Ecto.Adapters.SQL.Sandbox, pool_size: 5)
    )

    configure_endpoint(otp, web)
  end

  defp configure_endpoint(otp, web) do
    Application.put_env(otp, Module.concat(web, "Endpoint"),
      secret_key_base: String.duplicate("z", 64),
      server: false,
      render_errors: [formats: [json: Module.concat(web, "ErrorJSON")], layout: false]
    )

    :ok
  end

  defp repo(prefix, otp, db) do
    adapter =
      case db do
        :postgres -> "Ecto.Adapters.Postgres"
        _ -> "Ecto.Adapters.SQLite3"
      end

    """
    defmodule #{prefix}.Repo do
      use Ecto.Repo, otp_app: #{inspect(otp)}, adapter: #{adapter}
    end
    """
  end

  defp web_entry(web, _otp) do
    """
    defmodule #{web} do
      def controller do
        quote do
          use Phoenix.Controller, formats: [:json]
          import Plug.Conn
          unquote(#{web}.verified_routes())
        end
      end

      def router do
        quote do
          use Phoenix.Router
        end
      end

      def verified_routes do
        quote do
          use Phoenix.VerifiedRoutes, endpoint: #{web}.Endpoint, router: #{web}.Router
        end
      end

      defmacro __using__(which), do: apply(__MODULE__, which, [])
    end
    """
  end

  defp endpoint(web, otp) do
    """
    defmodule #{web}.Endpoint do
      use Phoenix.Endpoint, otp_app: #{inspect(otp)}
      plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
      plug #{web}.Router
    end
    """
  end

  defp error_json(web) do
    """
    defmodule #{web}.ErrorJSON do
      def render(template, _assigns),
        do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
    end
    """
  end

  defp conn_case(prefix, web) do
    """
    defmodule #{web}.ConnCase do
      use ExUnit.CaseTemplate

      using do
        quote do
          use #{web}, :verified_routes
          import Plug.Conn
          import Phoenix.ConnTest
          @endpoint #{web}.Endpoint
        end
      end

      setup tags do
        pid = Ecto.Adapters.SQL.Sandbox.start_owner!(#{prefix}.Repo, shared: not tags[:async])
        on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
        {:ok, conn: Phoenix.ConnTest.build_conn()}
      end
    end
    """
  end
end
