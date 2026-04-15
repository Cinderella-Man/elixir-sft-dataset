<file path="mix.exs">
defmodule SoftCrud.MixProject do
  use Mix.Project

  def project do
    [
      app: :soft_crud,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {SoftCrud.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
</file>

<file path="config/config.exs">
import Config

config :soft_crud,
  ecto_repos: [SoftCrud.Repo],
  generators: [timestamp_type: :utc_datetime]

config :soft_crud, SoftCrudWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SoftCrudWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SoftCrud.PubSub

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
</file>

<file path="config/dev.exs">
import Config

config :soft_crud, SoftCrud.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "soft_crud_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :soft_crud, SoftCrudWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-that-is-at-least-64-bytes-long-for-phoenix-to-accept-it",
  watchers: []
</file>

<file path="config/test.exs">
import Config

config :soft_crud, SoftCrud.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "soft_crud_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :soft_crud, SoftCrudWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-that-is-at-least-64-bytes-long-for-phoenix-to-accept-it-ok",
  server: false

config :logger, level: :warning
</file>

<file path="config/runtime.exs">
import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL environment variable is not set"

  config :soft_crud, SoftCrud.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE environment variable is not set"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :soft_crud, SoftCrudWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
</file>

<file path="lib/soft_crud/application.ex">
defmodule SoftCrud.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SoftCrud.Repo,
      {Phoenix.PubSub, name: SoftCrud.PubSub},
      SoftCrudWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SoftCrud.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SoftCrudWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
</file>

<file path="lib/soft_crud/repo.ex">
defmodule SoftCrud.Repo do
  use Ecto.Repo,
    otp_app: :soft_crud,
    adapter: Ecto.Adapters.Postgres
end
</file>

<file path="lib/soft_crud/documents/document.ex">
defmodule SoftCrud.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field :title, :string
    field :content, :string
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating and updating title/content."
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
    |> validate_length(:title, min: 1)
  end

  @doc "Changeset for setting or clearing deleted_at."
  def soft_delete_changeset(document, attrs) do
    document
    |> cast(attrs, [:deleted_at])
  end
end
</file>

<file path="lib/soft_crud/documents.ex">
defmodule SoftCrud.Documents do
  @moduledoc "Context for managing documents with soft-delete support."

  import Ecto.Query
  alias SoftCrud.Repo
  alias SoftCrud.Documents.Document

  def list_documents(opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    Document
    |> maybe_exclude_deleted(include_deleted)
    |> Repo.all()
  end

  def get_document(id, opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    query =
      Document
      |> where([d], d.id == ^id)
      |> maybe_exclude_deleted(include_deleted)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      document -> {:ok, document}
    end
  end

  def create_document(attrs) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  def update_document(%Document{} = document, attrs) do
    document
    |> Document.changeset(attrs)
    |> Repo.update()
  end

  def soft_delete_document(%Document{deleted_at: deleted_at} = document)
      when not is_nil(deleted_at) do
    {:ok, document}
  end

  def soft_delete_document(%Document{} = document) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    document
    |> Document.soft_delete_changeset(%{deleted_at: now})
    |> Repo.update()
  end

  def restore_document(%Document{deleted_at: nil} = document) do
    {:ok, document}
  end

  def restore_document(%Document{} = document) do
    document
    |> Document.soft_delete_changeset(%{deleted_at: nil})
    |> Repo.update()
  end

  defp maybe_exclude_deleted(query, true), do: query
  defp maybe_exclude_deleted(query, false), do: where(query, [d], is_nil(d.deleted_at))
end
</file>

<file path="lib/soft_crud_web.ex">
defmodule SoftCrudWeb do
  @moduledoc false

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: SoftCrudWeb.Endpoint,
        router: SoftCrudWeb.Router
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
</file>

<file path="lib/soft_crud_web/endpoint.ex">
defmodule SoftCrudWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :soft_crud

  @session_options [
    store: :cookie,
    key: "_soft_crud_key",
    signing_salt: "aBcDeFgH",
    same_site: "Lax"
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SoftCrudWeb.Router
end
</file>

<file path="lib/soft_crud_web/router.ex">
defmodule SoftCrudWeb.Router do
  use SoftCrudWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SoftCrudWeb do
    pipe_through :api

    resources "/documents", DocumentController, only: [:index, :create, :show, :update, :delete]
    post "/documents/:id/restore", DocumentController, :restore
  end
end
</file>

<file path="lib/soft_crud_web/controllers/fallback_controller.ex">
defmodule SoftCrudWeb.FallbackController do
  use SoftCrudWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SoftCrudWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SoftCrudWeb.ErrorJSON)
    |> render(:"422", changeset: changeset)
  end
end
</file>

<file path="lib/soft_crud_web/controllers/error_json.ex">
defmodule SoftCrudWeb.ErrorJSON do
  def render("404.json", _assigns) do
    %{errors: %{detail: "Not found"}}
  end

  def render("422.json", %{changeset: changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    %{errors: errors}
  end

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
</file>

<file path="lib/soft_crud_web/controllers/document_controller.ex">
defmodule SoftCrudWeb.DocumentController do
  use SoftCrudWeb, :controller

  alias SoftCrud.Documents
  alias SoftCrud.Documents.Document

  action_fallback SoftCrudWeb.FallbackController

  def index(conn, params) do
    opts = parse_include_deleted(params)
    documents = Documents.list_documents(opts)
    render(conn, :index, documents: documents)
  end

  def create(conn, %{"document" => document_params}) do
    with {:ok, %Document{} = document} <- Documents.create_document(document_params) do
      conn
      |> put_status(:created)
      |> render(:show, document: document)
    end
  end

  def show(conn, %{"id" => id} = params) do
    opts = parse_include_deleted(params)

    with {:ok, %Document{} = document} <- Documents.get_document(id, opts) do
      render(conn, :show, document: document)
    end
  end

  def update(conn, %{"id" => id, "document" => document_params}) do
    with {:ok, %Document{} = document} <- Documents.get_document(id),
         {:ok, %Document{} = updated} <- Documents.update_document(document, document_params) do
      render(conn, :show, document: updated)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, %Document{} = document} <- Documents.get_document(id),
         {:ok, %Document{} = deleted} <- Documents.soft_delete_document(document) do
      render(conn, :show, document: deleted)
    end
  end

  def restore(conn, %{"id" => id}) do
    with {:ok, %Document{} = document} <- Documents.get_document(id, include_deleted: true) do
      {:ok, restored} = Documents.restore_document(document)
      render(conn, :show, document: restored)
    end
  end

  defp parse_include_deleted(%{"include_deleted" => "true"}), do: [include_deleted: true]
  defp parse_include_deleted(_), do: []
end
</file>

<file path="lib/soft_crud_web/controllers/document_json.ex">
defmodule SoftCrudWeb.DocumentJSON do
  alias SoftCrud.Documents.Document

  def index(%{documents: documents}) do
    %{data: for(document <- documents, do: data(document))}
  end

  def show(%{document: document}) do
    %{data: data(document)}
  end

  defp data(%Document{} = document) do
    %{
      id: document.id,
      title: document.title,
      content: document.content,
      deleted_at: document.deleted_at,
      inserted_at: document.inserted_at,
      updated_at: document.updated_at
    }
  end
end
</file>

<file path="priv/repo/migrations/20240101000000_create_documents.exs">
defmodule SoftCrud.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :title, :string, null: false
      add :content, :text, null: false
      add :deleted_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:documents, [:deleted_at])
  end
end
</file>

<file path="priv/repo/seeds.exs">
# Script for populating the database.
# Run with: mix run priv/repo/seeds.exs
</file>
