<file path="lib/soft_crud/documents.ex">
defmodule SoftCrud.Documents do
  @moduledoc """
  The Documents context.

  Provides CRUD operations for `SoftCrud.Documents.Document` records along with
  soft-delete support. By default, read operations exclude soft-deleted
  documents; pass `include_deleted: true` to include them.
  """

  import Ecto.Query, warn: false

  alias SoftCrud.Documents.Document
  alias SoftCrud.Repo

  @doc """
  Returns the list of documents.

  Soft-deleted documents (those with a non-nil `deleted_at`) are excluded
  unless `opts` contains `include_deleted: true`.
  """
  @spec list_documents(keyword()) :: [Document.t()]
  def list_documents(opts \\ []) do
    opts
    |> base_query()
    |> Repo.all()
  end

  @doc """
  Fetches a single document by `id`.

  Returns `{:ok, document}` when found, or `{:error, :not_found}` otherwise. A
  soft-deleted document is treated as not found unless `opts` contains
  `include_deleted: true`.
  """
  @spec get_document(integer() | String.t(), keyword()) ::
          {:ok, Document.t()} | {:error, :not_found}
  def get_document(id, opts \\ []) do
    case Repo.get(base_query(opts), id) do
      nil -> {:error, :not_found}
      %Document{} = document -> {:ok, document}
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

  The `deleted_at` field cannot be modified through this function. Returns
  `{:ok, document}` on success or `{:error, changeset}` on failure.
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

  If the document is already soft-deleted, this is a no-op and returns the
  document unchanged. Always returns `{:ok, document}`.
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

  If the document is not soft-deleted, this is a no-op and returns the document
  unchanged. Always returns `{:ok, document}`.
  """
  @spec restore_document(Document.t()) :: {:ok, Document.t()}
  def restore_document(%Document{deleted_at: nil} = document), do: {:ok, document}

  def restore_document(%Document{} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
  end

  @spec base_query(keyword()) :: Ecto.Queryable.t()
  defp base_query(opts) do
    if Keyword.get(opts, :include_deleted, false) do
      Document
    else
      from d in Document, where: is_nil(d.deleted_at)
    end
  end
end
</file>
<file path="lib/soft_crud/documents/document.ex">
defmodule SoftCrud.Documents.Document do
  @moduledoc """
  Ecto schema and changeset for a `Document` resource.

  Documents support soft deletion via the nullable `deleted_at` field. The
  changeset only accepts `title` and `content`, ensuring `deleted_at` can never
  be modified through user-supplied attributes.
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
    field :deleted_at, :utc_datetime

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a document.

  Casts and validates `title` (required, non-empty) and `content` (required).
  The `deleted_at` field is intentionally excluded so it cannot be set here.
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
  JSON controller for the `Document` resource.

  Delegates business logic to `SoftCrud.Documents` and relies on
  `SoftCrudWeb.FallbackController` to translate `{:error, _}` tuples into the
  appropriate HTTP responses.
  """

  use Phoenix.Controller, formats: [:json]

  alias SoftCrud.Documents
  alias SoftCrud.Documents.Document

  action_fallback SoftCrudWeb.FallbackController

  @type params :: map()

  @doc """
  Lists documents, optionally including soft-deleted ones via
  `?include_deleted=true`.
  """
  @spec index(Plug.Conn.t(), params()) :: Plug.Conn.t()
  def index(conn, params) do
    documents = Documents.list_documents(opts_from_params(params))
    render(conn, :index, documents: documents)
  end

  @doc """
  Creates a document and responds with `201 Created` on success.
  """
  @spec create(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, Ecto.Changeset.t()}
  def create(conn, %{"document" => document_params}) do
    with {:ok, %Document{} = document} <- Documents.create_document(document_params) do
      conn
      |> put_status(:created)
      |> render(:show, document: document)
    end
  end

  @doc """
  Shows a single document, optionally including soft-deleted ones via
  `?include_deleted=true`.
  """
  @spec show(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, :not_found}
  def show(conn, %{"id" => id} = params) do
    with {:ok, document} <- Documents.get_document(id, opts_from_params(params)) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Updates a document. Soft-deleted documents respond with `404 Not Found`.
  """
  @spec update(Plug.Conn.t(), params()) ::
          Plug.Conn.t() | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update(conn, %{"id" => id, "document" => document_params}) do
    with {:ok, document} <- Documents.get_document(id),
         {:ok, %Document{} = document} <- Documents.update_document(document, document_params) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Soft-deletes a document. Returns `404 Not Found` if already soft-deleted.
  """
  @spec delete(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, :not_found}
  def delete(conn, %{"id" => id}) do
    with {:ok, document} <- Documents.get_document(id),
         {:ok, %Document{} = document} <- Documents.soft_delete_document(document) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Restores a soft-deleted document. Acts as a no-op for active documents.
  """
  @spec restore(Plug.Conn.t(), params()) :: Plug.Conn.t() | {:error, :not_found}
  def restore(conn, %{"id" => id}) do
    with {:ok, document} <- Documents.get_document(id, include_deleted: true),
         {:ok, %Document{} = document} <- Documents.restore_document(document) do
      render(conn, :show, document: document)
    end
  end

  @spec opts_from_params(params()) :: keyword()
  defp opts_from_params(%{"include_deleted" => "true"}), do: [include_deleted: true]
  defp opts_from_params(_params), do: []
end
</file>
<file path="lib/soft_crud_web/controllers/document_json.ex">
defmodule SoftCrudWeb.DocumentJSON do
  @moduledoc """
  JSON rendering for `Document` resources.

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
  Translates the `{:error, _}` tuples returned by controller actions into HTTP
  responses.

  Handles Ecto changeset validation errors (`422 Unprocessable Entity`) and
  missing resources (`404 Not Found`).
  """

  use Phoenix.Controller

  @doc """
  Handles error tuples returned from controller actions.
  """
  @spec call(Plug.Conn.t(), {:error, Ecto.Changeset.t() | :not_found}) :: Plug.Conn.t()
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

  Because requests are dispatched directly to this router (without a Phoenix
  endpoint in front), the `:api` pipeline is responsible for parsing JSON
  request bodies and negotiating the response format.
  """

  use Phoenix.Router

  import Phoenix.Controller, only: [accepts: 2]

  pipeline :api do
    plug Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason

    plug :accepts, ["json"]
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

  Includes an index on `deleted_at` to keep filtering of active/deleted
  documents efficient.
  """

  use Ecto.Migration

  @doc """
  Creates the `documents` table and its supporting index.
  """
  @spec change() :: :ok
  def change do
    create table(:documents) do
      add :title, :string, null: false
      add :content, :text, null: false
      add :deleted_at, :utc_datetime

      timestamps()
    end

    create index(:documents, [:deleted_at])

    :ok
  end
end
</file>