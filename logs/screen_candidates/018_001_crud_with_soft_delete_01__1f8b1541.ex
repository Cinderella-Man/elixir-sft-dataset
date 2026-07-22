<file path="lib/soft_crud/documents.ex">
defmodule SoftCrud.Documents do
  @moduledoc """
  The Documents context.

  Provides CRUD operations for `SoftCrud.Documents.Document` with support for
  soft deletion. Soft-deleted documents (those with a non-nil `deleted_at`) are
  excluded from queries by default but can be included via the
  `include_deleted: true` option.
  """

  import Ecto.Query, warn: false

  alias SoftCrud.Documents.Document
  alias SoftCrud.Repo

  @doc """
  Returns the list of documents.

  By default excludes soft-deleted documents. Pass `include_deleted: true` in
  `opts` to include documents regardless of their `deleted_at` value.
  """
  @spec list_documents(keyword()) :: [Document.t()]
  def list_documents(opts \\ []) do
    query =
      if Keyword.get(opts, :include_deleted, false) do
        from(d in Document)
      else
        from(d in Document, where: is_nil(d.deleted_at))
      end

    Repo.all(query)
  end

  @doc """
  Fetches a single document by `id`.

  Returns `{:ok, document}` or `{:error, :not_found}`. By default a
  soft-deleted document yields `{:error, :not_found}`; pass
  `include_deleted: true` in `opts` to return it even when soft-deleted.
  """
  @spec get_document(term(), keyword()) :: {:ok, Document.t()} | {:error, :not_found}
  def get_document(id, opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    case Repo.get(Document, id) do
      nil ->
        {:error, :not_found}

      %Document{deleted_at: nil} = document ->
        {:ok, document}

      %Document{} = document ->
        if include_deleted, do: {:ok, document}, else: {:error, :not_found}
    end
  end

  @doc """
  Creates a document from the given attributes.

  Returns `{:ok, document}` on success or `{:error, changeset}` on validation
  failure.
  """
  @spec create_document(map()) :: {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def create_document(attrs) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates the `title` and/or `content` of an existing document.

  `deleted_at` cannot be modified through this function. Returns
  `{:ok, document}` or `{:error, changeset}`.
  """
  @spec update_document(Document.t(), map()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def update_document(%Document{} = document, attrs) do
    document
    |> Document.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a document by setting `deleted_at` to the current UTC time.

  If the document is already soft-deleted this is a no-op and the document is
  returned unchanged. Always returns `{:ok, document}`.
  """
  @spec soft_delete_document(Document.t()) :: {:ok, Document.t()}
  def soft_delete_document(%Document{deleted_at: nil} = document) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    document
    |> Ecto.Changeset.change(deleted_at: now)
    |> Repo.update()
  end

  def soft_delete_document(%Document{} = document), do: {:ok, document}

  @doc """
  Restores a soft-deleted document by setting `deleted_at` back to `nil`.

  If the document is not soft-deleted this is a no-op and the document is
  returned unchanged. Always returns `{:ok, document}`.
  """
  @spec restore_document(Document.t()) :: {:ok, Document.t()}
  def restore_document(%Document{deleted_at: nil} = document), do: {:ok, document}

  def restore_document(%Document{} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
  end
end
</file>
<file path="lib/soft_crud/documents/document.ex">
defmodule SoftCrud.Documents.Document do
  @moduledoc """
  Ecto schema and changeset for the `Document` resource.

  A document has a `title` and `content` and supports soft deletion via the
  nullable `deleted_at` timestamp. When `deleted_at` is `nil` the document is
  considered active; when it holds a datetime the document is soft-deleted.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          title: String.t() | nil,
          content: String.t() | nil,
          deleted_at: DateTime.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "documents" do
    field :title, :string
    field :content, :string
    field :deleted_at, :utc_datetime, default: nil

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a document.

  Casts and validates only `title` and `content`. `title` must be present and
  non-empty and `content` must be present. `deleted_at` is intentionally not
  castable here so it can only be changed through the dedicated context
  functions.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
    |> validate_length(:title, min: 1)
  end
end
</file>
<file path="lib/soft_crud_web/controllers/document_controller.ex">
defmodule SoftCrudWeb.DocumentController do
  @moduledoc """
  JSON API controller for the `Document` resource.

  Delegates all business logic to `SoftCrud.Documents` and relies on
  `SoftCrudWeb.FallbackController` to translate `{:error, ...}` tuples into the
  appropriate HTTP responses.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias SoftCrud.Documents

  action_fallback SoftCrudWeb.FallbackController

  plug :put_view, json: SoftCrudWeb.DocumentJSON

  @type params :: map()

  @doc """
  Lists documents. Supports the `include_deleted=true` query parameter.
  """
  @spec index(Plug.Conn.t(), params()) :: Plug.Conn.t()
  def index(conn, params) do
    documents = Documents.list_documents(include_deleted_opts(params))
    render(conn, :index, documents: documents)
  end

  @doc """
  Creates a document from the `"document"` body parameters.
  """
  @spec create(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, %{"document" => document_params}) do
    with {:ok, document} <- Documents.create_document(document_params) do
      conn
      |> put_status(:created)
      |> render(:show, document: document)
    end
  end

  @doc """
  Shows a single document. Supports the `include_deleted=true` query parameter.
  """
  @spec show(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, %{"id" => id} = params) do
    with {:ok, document} <- Documents.get_document(id, include_deleted_opts(params)) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Updates a document. Soft-deleted documents are treated as not found.
  """
  @spec update(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"id" => id, "document" => document_params}) do
    with {:ok, document} <- Documents.get_document(id),
         {:ok, document} <- Documents.update_document(document, document_params) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Soft-deletes a document. Returns 404 if the document is already soft-deleted.
  """
  @spec delete(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, %{"id" => id}) do
    with {:ok, document} <- Documents.get_document(id),
         {:ok, document} <- Documents.soft_delete_document(document) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Restores a soft-deleted document. A no-op returns the document as-is.
  """
  @spec restore(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, term()}
  def restore(conn, %{"id" => id}) do
    with {:ok, document} <- Documents.get_document(id, include_deleted: true),
         {:ok, document} <- Documents.restore_document(document) do
      render(conn, :show, document: document)
    end
  end

  @spec include_deleted_opts(params()) :: keyword()
  defp include_deleted_opts(params) do
    [include_deleted: params["include_deleted"] == "true"]
  end
end
</file>
<file path="lib/soft_crud_web/controllers/document_json.ex">
defmodule SoftCrudWeb.DocumentJSON do
  @moduledoc """
  JSON rendering for the `Document` resource.

  Produces the `{"data": ...}` envelope expected by the API, wrapping either a
  single document or a list of documents.
  """

  alias SoftCrud.Documents.Document

  @doc """
  Renders a list of documents as `%{data: [...]}`.
  """
  @spec index(%{documents: [Document.t()]}) :: map()
  def index(%{documents: documents}) do
    %{data: Enum.map(documents, &data/1)}
  end

  @doc """
  Renders a single document as `%{data: ...}`.
  """
  @spec show(%{document: Document.t()}) :: map()
  def show(%{document: document}) do
    %{data: data(document)}
  end

  @spec data(Document.t()) :: map()
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
<file path="lib/soft_crud_web/controllers/fallback_controller.ex">
defmodule SoftCrudWeb.FallbackController do
  @moduledoc """
  Translates `{:error, ...}` tuples returned from controller actions into JSON
  HTTP responses.

  Handles validation failures (`Ecto.Changeset`) as 422 responses and
  `:not_found` as 404 responses, both using the `{"errors": {...}}` envelope.
  """

  use Phoenix.Controller

  import Plug.Conn

  @doc """
  Handles error tuples produced by controller actions.
  """
  @spec call(Plug.Conn.t(), {:error, Ecto.Changeset.t()} | {:error, :not_found}) ::
          Plug.Conn.t()
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: translate_errors(changeset)})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "Not found"}})
  end

  @spec translate_errors(Ecto.Changeset.t()) :: map()
  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
</file>
<file path="lib/soft_crud_web/router.ex">
defmodule SoftCrudWeb.Router do
  @moduledoc """
  Router for the SoftCrud JSON API.

  Exposes the `Document` resource under the `/api` scope. The `:api` pipeline
  parses JSON request bodies so the router is fully servable on its own, without
  a Phoenix endpoint in front of it.
  """

  use Phoenix.Router

  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]

    plug Plug.Parsers,
      parsers: [:json],
      pass: ["*/*"],
      json_decoder: Jason
  end

  scope "/api", SoftCrudWeb do
    pipe_through :api

    get "/documents", DocumentController, :index
    post "/documents", DocumentController, :create
    get "/documents/:id", DocumentController, :show
    put "/documents/:id", DocumentController, :update
    delete "/documents/:id", DocumentController, :delete
    post "/documents/:id/restore", DocumentController, :restore
  end
end
</file>
<file path="priv/repo/migrations/20260708000000_create_documents.exs">
defmodule SoftCrud.Repo.Migrations.CreateDocuments do
  @moduledoc """
  Creates the `documents` table with soft-delete support.
  """

  use Ecto.Migration

  @doc """
  Creates the `documents` table and an index on `deleted_at`.
  """
  @spec change() :: any()
  def change do
    create table(:documents) do
      add :title, :string, null: false
      add :content, :text, null: false
      add :deleted_at, :utc_datetime, default: nil

      timestamps()
    end

    create index(:documents, [:deleted_at])
  end
end
</file>