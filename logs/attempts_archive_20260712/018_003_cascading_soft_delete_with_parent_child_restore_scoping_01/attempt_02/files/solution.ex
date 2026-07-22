defmodule CascadeCrud.Documents.Document do
  @moduledoc """
  Ecto schema and changesets for the `Document` resource.

  Documents form a parent/child tree via `parent_id`. Soft deletion is tracked
  with `deleted_at` (nil when live) and `deleted_via_cascade`, which records
  whether the document was deleted directly (`false`) or only because an
  ancestor was deleted (`true`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "documents" do
    field(:title, :string)
    field(:content, :string)
    field(:parent_id, :integer)
    field(:deleted_at, :utc_datetime)
    field(:deleted_via_cascade, :boolean, default: false)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a document.

  Casts `title`, `content` and `parent_id`, and validates that `title` is
  present and non-empty and that `content` is present.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content, :parent_id])
    |> validate_required([:title, :content])
    |> validate_length(:title, min: 1)
  end

  @doc """
  Builds a changeset for updating a document.

  Only `title` and `content` may be changed; all other attributes are ignored.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
    |> validate_length(:title, min: 1)
  end
end

defmodule CascadeCrud.Documents do
  @moduledoc """
  The Documents context.

  Provides listing, fetching, creation and updates for documents, plus
  cascading soft delete and scoped cascade restore across the parent/child
  hierarchy.
  """

  import Ecto.Query, warn: false

  alias CascadeCrud.Repo
  alias CascadeCrud.Documents.Document

  @doc """
  Lists documents.

  Excludes soft-deleted documents by default. Pass `include_deleted: true` to
  return every document regardless of `deleted_at`.
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

  Returns `{:ok, document}` or `{:error, :not_found}`. Soft-deleted documents
  are hidden unless `include_deleted: true` is passed.
  """
  @spec get_document(integer() | binary(), keyword()) ::
          {:ok, Document.t()} | {:error, :not_found}
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
  Creates a document.

  Validates required fields and, when `parent_id` is supplied, that it points at
  an existing, non-soft-deleted document. Returns `{:ok, document}` or
  `{:error, changeset}`.
  """
  @spec create_document(map()) :: {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def create_document(attrs) do
    %Document{}
    |> Document.create_changeset(attrs)
    |> validate_parent()
    |> Repo.insert()
  end

  @doc """
  Updates a document's `title` and/or `content`.

  `parent_id`, `deleted_at` and `deleted_via_cascade` are never changed here.
  Returns `{:ok, document}` or `{:error, changeset}`.
  """
  @spec update_document(Document.t(), map()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def update_document(document, attrs) do
    document
    |> Document.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a document and cascades to its whole subtree.

  The given document is flagged as a direct deletion; every descendant that is
  not already soft-deleted is flagged as a cascade deletion. Already-deleted
  descendants are left untouched. A no-op when the document is already deleted.
  """
  @spec soft_delete_document(Document.t()) :: {:ok, Document.t()}
  def soft_delete_document(%Document{deleted_at: nil} = document) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    descendant_ids = collect_descendant_ids([document.id])

    Repo.transaction(fn ->
      Repo.update_all(
        from(d in Document, where: d.id == ^document.id),
        set: [deleted_at: now, deleted_via_cascade: false, updated_at: now]
      )

      if descendant_ids != [] do
        Repo.update_all(
          from(d in Document,
            where: d.id in ^descendant_ids and is_nil(d.deleted_at)
          ),
          set: [deleted_at: now, deleted_via_cascade: true, updated_at: now]
        )
      end
    end)

    {:ok, updated} = get_document(document.id, include_deleted: true)
    {:ok, updated}
  end

  def soft_delete_document(%Document{} = document), do: {:ok, document}

  @doc """
  Restores a soft-deleted document with a scoped cascade restore.

  A no-op when the document is not soft-deleted. Returns
  `{:error, :parent_deleted}` when the document's parent is currently
  soft-deleted. Otherwise the document is restored and the restore cascades
  downward only to descendants that were removed by the cascade
  (`deleted_via_cascade == true`) and whose own parent was just restored.
  """
  @spec restore_document(Document.t()) ::
          {:ok, Document.t()} | {:error, :parent_deleted}
  def restore_document(%Document{deleted_at: nil} = document), do: {:ok, document}

  def restore_document(%Document{} = document) do
    if parent_deleted?(document) do
      {:error, :parent_deleted}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        restore_ids = collect_restore_ids([document.id])

        Repo.update_all(
          from(d in Document, where: d.id in ^restore_ids),
          set: [deleted_at: nil, deleted_via_cascade: false, updated_at: now]
        )
      end)

      {:ok, updated} = get_document(document.id, include_deleted: true)
      {:ok, updated}
    end
  end

  @spec validate_parent(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_parent(changeset) do
    case Ecto.Changeset.fetch_change(changeset, :parent_id) do
      {:ok, nil} ->
        changeset

      {:ok, parent_id} ->
        case Repo.get(Document, parent_id) do
          %Document{deleted_at: nil} ->
            changeset

          _ ->
            Ecto.Changeset.add_error(
              changeset,
              :parent_id,
              "does not reference an existing, non-deleted document"
            )
        end

      :error ->
        changeset
    end
  end

  @spec parent_deleted?(Document.t()) :: boolean()
  defp parent_deleted?(%Document{parent_id: nil}), do: false

  defp parent_deleted?(%Document{parent_id: parent_id}) do
    case Repo.get(Document, parent_id) do
      nil -> false
      %Document{deleted_at: nil} -> false
      _ -> true
    end
  end

  @spec collect_descendant_ids([integer()]) :: [integer()]
  defp collect_descendant_ids(parent_ids) do
    children =
      Repo.all(from(d in Document, where: d.parent_id in ^parent_ids, select: d.id))

    case children do
      [] -> []
      _ -> children ++ collect_descendant_ids(children)
    end
  end

  @spec collect_restore_ids([integer()]) :: [integer()]
  defp collect_restore_ids(frontier_ids) do
    children =
      Repo.all(
        from(d in Document,
          where:
            d.parent_id in ^frontier_ids and not is_nil(d.deleted_at) and
              d.deleted_via_cascade == true,
          select: d.id
        )
      )

    case children do
      [] -> frontier_ids
      _ -> frontier_ids ++ collect_restore_ids(children)
    end
  end
end

defmodule CascadeCrudWeb.DocumentJSON do
  @moduledoc """
  Renders documents as JSON payloads for the API.
  """

  alias CascadeCrud.Documents.Document

  @doc """
  Renders a list of documents wrapped in a `data` list.
  """
  @spec index(map()) :: map()
  def index(%{documents: documents}) do
    %{data: Enum.map(documents, &data/1)}
  end

  @doc """
  Renders a single document wrapped in a `data` object.
  """
  @spec show(map()) :: map()
  def show(%{document: document}) do
    %{data: data(document)}
  end

  @spec data(Document.t()) :: map()
  defp data(%Document{} = document) do
    %{
      id: document.id,
      title: document.title,
      content: document.content,
      parent_id: document.parent_id,
      deleted_at: iso(document.deleted_at),
      deleted_via_cascade: document.deleted_via_cascade,
      inserted_at: iso(document.inserted_at),
      updated_at: iso(document.updated_at)
    }
  end

  @spec iso(nil | DateTime.t() | NaiveDateTime.t()) :: nil | binary()
  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
end

defmodule CascadeCrudWeb.FallbackController do
  @moduledoc """
  Translates `{:error, ...}` tuples returned from controller actions into
  appropriate JSON error responses with the correct HTTP status codes.
  """

  use Phoenix.Controller, formats: [:json]

  @doc """
  Handles error tuples from controller actions and renders a JSON error body.
  """
  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: changeset_errors(changeset)})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "Not found"}})
  end

  def call(conn, {:error, :parent_deleted}) do
    conn
    |> put_status(:conflict)
    |> json(%{errors: %{detail: "Parent is deleted"}})
  end

  @spec changeset_errors(Ecto.Changeset.t()) :: map()
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end

defmodule CascadeCrudWeb.DocumentController do
  @moduledoc """
  JSON API controller for the `Document` resource, including cascading soft
  delete and scoped cascade restore.
  """

  use Phoenix.Controller, formats: [:json]

  alias CascadeCrud.Documents
  alias CascadeCrud.Documents.Document
  alias CascadeCrudWeb.DocumentJSON

  action_fallback(CascadeCrudWeb.FallbackController)

  @doc """
  Lists documents. Supports the `include_deleted=true` query parameter.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    documents = Documents.list_documents(include_opts(params))

    conn
    |> put_status(:ok)
    |> json(DocumentJSON.index(%{documents: documents}))
  end

  @doc """
  Creates a document from the `document` params. Returns 201 on success.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"document" => document_params}) do
    with {:ok, %Document{} = document} <- Documents.create_document(document_params) do
      conn
      |> put_status(:created)
      |> json(DocumentJSON.show(%{document: document}))
    end
  end

  @doc """
  Shows a single document. Supports the `include_deleted=true` query parameter.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id} = params) do
    with {:ok, %Document{} = document} <- Documents.get_document(id, include_opts(params)) do
      conn
      |> put_status(:ok)
      |> json(DocumentJSON.show(%{document: document}))
    end
  end

  @doc """
  Updates a document's `title` and/or `content`. Returns 404 when soft-deleted.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id, "document" => document_params}) do
    with {:ok, %Document{} = document} <- Documents.get_document(id),
         {:ok, %Document{} = updated} <-
           Documents.update_document(document, document_params) do
      conn
      |> put_status(:ok)
      |> json(DocumentJSON.show(%{document: updated}))
    end
  end

  @doc """
  Soft-deletes a document and cascades to its subtree. Returns 404 when the
  document does not exist or is already soft-deleted.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with {:ok, %Document{} = document} <- Documents.get_document(id),
         {:ok, %Document{} = deleted} <- Documents.soft_delete_document(document) do
      conn
      |> put_status(:ok)
      |> json(DocumentJSON.show(%{document: deleted}))
    end
  end

  @doc """
  Restores a soft-deleted document with a scoped cascade restore. Returns 409
  when the document's parent is currently soft-deleted.
  """
  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def restore(conn, %{"id" => id}) do
    with {:ok, %Document{} = document} <-
           Documents.get_document(id, include_deleted: true),
         {:ok, %Document{} = restored} <- Documents.restore_document(document) do
      conn
      |> put_status(:ok)
      |> json(DocumentJSON.show(%{document: restored}))
    end
  end

  @spec include_opts(map()) :: keyword()
  defp include_opts(%{"include_deleted" => value}) when value in ["true", true] do
    [include_deleted: true]
  end

  defp include_opts(_params), do: []
end

defmodule CascadeCrudWeb.Router do
  @moduledoc """
  Router for the Documents JSON API. All routes live under the `/api` scope and
  are servable by the router pipeline alone (JSON body parsing is included).
  """

  use Phoenix.Router
  import Phoenix.Controller

  pipeline :api do
    plug(Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason
    )

    plug(:accepts, ["json"])
  end

  scope "/api", CascadeCrudWeb do
    pipe_through(:api)

    get("/documents", DocumentController, :index)
    post("/documents", DocumentController, :create)
    get("/documents/:id", DocumentController, :show)
    put("/documents/:id", DocumentController, :update)
    delete("/documents/:id", DocumentController, :delete)
    post("/documents/:id/restore", DocumentController, :restore)
  end
end

defmodule CascadeCrud.Repo.Migrations.CreateDocuments do
  @moduledoc """
  Creates the `documents` table with soft-delete columns and supporting indexes.
  """

  use Ecto.Migration

  @doc """
  Creates the `documents` table and its `deleted_at` / `parent_id` indexes.
  """
  @spec change() :: term()
  def change do
    create table(:documents) do
      add(:title, :string, null: false)
      add(:content, :string, null: false)
      add(:parent_id, :integer)
      add(:deleted_at, :utc_datetime)
      add(:deleted_via_cascade, :boolean, default: false, null: false)

      timestamps()
    end

    create(index(:documents, [:deleted_at]))
    create(index(:documents, [:parent_id]))
  end
end
