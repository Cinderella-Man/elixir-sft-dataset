defmodule SoftCrud.Repo do
  @moduledoc """
  The Ecto repository for the `SoftCrud` application.

  Backed by PostgreSQL. The repository is defined here so the test environment
  can start it, run the migration against it, and check out sandbox connections
  keyed on `SoftCrud.Repo`.
  """

  use Ecto.Repo,
    otp_app: :soft_crud,
    adapter: Ecto.Adapters.Postgres
end

defmodule SoftCrud.Documents.Folder do
  @moduledoc """
  Ecto schema and changeset for a `folders` record.

  A folder groups documents and can be soft-deleted. Soft deletion is recorded
  by setting `deleted_at` to a UTC timestamp; a `nil` value means the folder is
  live.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SoftCrud.Documents.Document

  @type t :: %__MODULE__{}

  schema "folders" do
    field(:name, :string)
    field(:deleted_at, :utc_datetime)

    has_many(:documents, Document)

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a folder.

  Requires a present, non-empty `name`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :deleted_at])
    |> validate_required([:name])
    |> validate_length(:name, min: 1)
  end
end

defmodule SoftCrud.Documents.Document do
  @moduledoc """
  Ecto schema and changeset for a `documents` record.

  Every document belongs to exactly one folder. The `cascaded` flag records how
  a document came to be soft-deleted: `true` means it was removed as a side
  effect of its folder being soft-deleted, `false` means it was never deleted or
  was deleted directly on its own.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SoftCrud.Documents.Folder

  @type t :: %__MODULE__{}

  schema "documents" do
    field(:title, :string)
    field(:content, :string)
    field(:deleted_at, :utc_datetime)
    field(:cascaded, :boolean, default: false)

    belongs_to(:folder, Folder)

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a document.

  Requires a present, non-empty `title`, a present `content`, and a present
  `folder_id`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content, :folder_id, :deleted_at, :cascaded])
    |> validate_required([:title, :content, :folder_id])
    |> validate_length(:title, min: 1)
    |> foreign_key_constraint(:folder_id)
  end
end

defmodule SoftCrud.Documents do
  @moduledoc """
  The Documents context: a two-level `Folder` -> `Document` hierarchy with
  cascading soft delete.

  Soft-deleting a folder cascades to the documents it contains, marking each
  cascade-deleted document with `cascaded: true`. Restoring the folder brings
  back exactly the documents that were removed by that cascade (those with
  `cascaded: true`) and nothing more.
  """

  import Ecto.Query, warn: false

  alias SoftCrud.Repo
  alias SoftCrud.Documents.{Folder, Document}

  @doc """
  Creates a folder from `attrs`.

  Returns `{:ok, folder}` or `{:error, changeset}`.
  """
  @spec create_folder(map()) :: {:ok, Folder.t()} | {:error, Ecto.Changeset.t()}
  def create_folder(attrs) do
    %Folder{}
    |> Folder.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists folders.

  By default excludes soft-deleted folders. Pass `include_deleted: true` to
  include them.
  """
  @spec list_folders(keyword()) :: [Folder.t()]
  def list_folders(opts \\ []) do
    Folder
    |> maybe_exclude_deleted(opts)
    |> Repo.all()
  end

  @doc """
  Fetches a folder by `id`.

  Returns `{:ok, folder}` or `{:error, :not_found}`. By default a soft-deleted
  folder is treated as not found; pass `include_deleted: true` to return it.
  """
  @spec get_folder(term(), keyword()) :: {:ok, Folder.t()} | {:error, :not_found}
  def get_folder(id, opts \\ []) do
    Folder
    |> maybe_exclude_deleted(opts)
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      %Folder{} = folder -> {:ok, folder}
    end
  end

  @doc """
  Soft-deletes `folder` and cascades to its live documents.

  Sets the folder's `deleted_at` to the current UTC time and soft-deletes every
  document in the folder that is not already soft-deleted, marking each with
  `cascaded: true`. The operation is atomic. A no-op if already soft-deleted.
  """
  @spec soft_delete_folder(Folder.t()) :: {:ok, Folder.t()}
  def soft_delete_folder(%Folder{deleted_at: nil} = folder) do
    now = current_time()

    Repo.transaction(fn ->
      {:ok, updated} =
        folder
        |> Ecto.Changeset.change(deleted_at: now)
        |> Repo.update()

      from(d in Document,
        where: d.folder_id == ^folder.id and is_nil(d.deleted_at)
      )
      |> Repo.update_all(set: [deleted_at: now, cascaded: true, updated_at: now])

      updated
    end)
  end

  def soft_delete_folder(%Folder{} = folder), do: {:ok, folder}

  @doc """
  Restores `folder` and cascade-restores its cascade-deleted documents.

  Sets the folder's `deleted_at` back to nil and restores every document in the
  folder whose `cascaded` flag is `true`, resetting that flag to `false`.
  Documents deleted on their own are left untouched. Atomic. No-op if the folder
  is not soft-deleted.
  """
  @spec restore_folder(Folder.t()) :: {:ok, Folder.t()}
  def restore_folder(%Folder{deleted_at: nil} = folder), do: {:ok, folder}

  def restore_folder(%Folder{} = folder) do
    now = current_time()

    Repo.transaction(fn ->
      {:ok, updated} =
        folder
        |> Ecto.Changeset.change(deleted_at: nil)
        |> Repo.update()

      from(d in Document,
        where: d.folder_id == ^folder.id and d.cascaded == true
      )
      |> Repo.update_all(set: [deleted_at: nil, cascaded: false, updated_at: now])

      updated
    end)
  end

  @doc """
  Creates a document from `attrs`.

  Returns `{:ok, document}` or `{:error, changeset}`. New documents start with
  `deleted_at: nil` and `cascaded: false`.
  """
  @spec create_document(map()) :: {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def create_document(attrs) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists documents.

  By default excludes soft-deleted documents. Pass `include_deleted: true` to
  include them.
  """
  @spec list_documents(keyword()) :: [Document.t()]
  def list_documents(opts \\ []) do
    Document
    |> maybe_exclude_deleted(opts)
    |> Repo.all()
  end

  @doc """
  Fetches a document by `id`.

  Returns `{:ok, document}` or `{:error, :not_found}`. By default a soft-deleted
  document is treated as not found; pass `include_deleted: true` to return it.
  """
  @spec get_document(term(), keyword()) ::
          {:ok, Document.t()} | {:error, :not_found}
  def get_document(id, opts \\ []) do
    Document
    |> maybe_exclude_deleted(opts)
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      %Document{} = document -> {:ok, document}
    end
  end

  @doc """
  Directly soft-deletes a single `document`.

  Sets `deleted_at` to the current UTC time and `cascaded` to `false` (a direct
  deletion, not a cascade). No-op if already soft-deleted.
  """
  @spec soft_delete_document(Document.t()) :: {:ok, Document.t()}
  def soft_delete_document(%Document{deleted_at: nil} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: current_time(), cascaded: false)
    |> Repo.update()
  end

  def soft_delete_document(%Document{} = document), do: {:ok, document}

  @doc """
  Directly restores a single `document`.

  Sets `deleted_at` back to nil and `cascaded` to `false`. No-op if the document
  is not soft-deleted.
  """
  @spec restore_document(Document.t()) :: {:ok, Document.t()}
  def restore_document(%Document{deleted_at: nil} = document), do: {:ok, document}

  def restore_document(%Document{} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: nil, cascaded: false)
    |> Repo.update()
  end

  @spec maybe_exclude_deleted(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
  defp maybe_exclude_deleted(query, opts) do
    if Keyword.get(opts, :include_deleted, false) do
      from(q in query)
    else
      from(q in query, where: is_nil(q.deleted_at))
    end
  end

  @spec current_time() :: DateTime.t()
  defp current_time do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end

defmodule SoftCrudWeb.FolderJSON do
  @moduledoc """
  Renders folders as JSON-serializable maps for the API.
  """

  alias SoftCrud.Documents.Folder

  @doc """
  Renders a list of folders wrapped in a `:data` key.
  """
  @spec index(map()) :: map()
  def index(%{folders: folders}) do
    %{data: for(folder <- folders, do: data(folder))}
  end

  @doc """
  Renders a single folder wrapped in a `:data` key.
  """
  @spec show(map()) :: map()
  def show(%{folder: folder}) do
    %{data: data(folder)}
  end

  @doc """
  Renders a single folder into a plain map.
  """
  @spec data(Folder.t()) :: map()
  def data(%Folder{} = folder) do
    %{
      id: folder.id,
      name: folder.name,
      deleted_at: folder.deleted_at,
      inserted_at: folder.inserted_at,
      updated_at: folder.updated_at
    }
  end
end

defmodule SoftCrudWeb.DocumentJSON do
  @moduledoc """
  Renders documents as JSON-serializable maps for the API.
  """

  alias SoftCrud.Documents.Document

  @doc """
  Renders a list of documents wrapped in a `:data` key.
  """
  @spec index(map()) :: map()
  def index(%{documents: documents}) do
    %{data: for(document <- documents, do: data(document))}
  end

  @doc """
  Renders a single document wrapped in a `:data` key.
  """
  @spec show(map()) :: map()
  def show(%{document: document}) do
    %{data: data(document)}
  end

  @doc """
  Renders a single document into a plain map.
  """
  @spec data(Document.t()) :: map()
  def data(%Document{} = document) do
    %{
      id: document.id,
      title: document.title,
      content: document.content,
      folder_id: document.folder_id,
      deleted_at: document.deleted_at,
      cascaded: document.cascaded,
      inserted_at: document.inserted_at,
      updated_at: document.updated_at
    }
  end
end

defmodule SoftCrudWeb.FallbackController do
  @moduledoc """
  Translates `{:error, ...}` tuples returned by controller actions into JSON
  responses with the appropriate HTTP status.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  @doc """
  Handles error tuples produced by controller actions.
  """
  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "Not found"}})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: translate_errors(changeset)})
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

defmodule SoftCrudWeb.FolderController do
  @moduledoc """
  JSON API controller for folders, including cascading soft delete and restore.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias SoftCrud.Documents
  alias SoftCrudWeb.FolderJSON

  action_fallback(SoftCrudWeb.FallbackController)

  @doc """
  Lists folders. Supports `?include_deleted=true`.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    folders = Documents.list_folders(parse_opts(params))
    json(conn, FolderJSON.index(%{folders: folders}))
  end

  @doc """
  Creates a folder, responding with 201 on success.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"folder" => folder_params}) do
    with {:ok, folder} <- Documents.create_folder(folder_params) do
      conn
      |> put_status(:created)
      |> json(FolderJSON.show(%{folder: folder}))
    end
  end

  @doc """
  Shows a single folder. Supports `?include_deleted=true`.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id} = params) do
    with {:ok, folder} <- Documents.get_folder(id, parse_opts(params)) do
      json(conn, FolderJSON.show(%{folder: folder}))
    end
  end

  @doc """
  Soft-deletes a folder, cascading to its documents. 404 if missing or already
  soft-deleted.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with {:ok, folder} <- Documents.get_folder(id),
         {:ok, folder} <- Documents.soft_delete_folder(folder) do
      json(conn, FolderJSON.show(%{folder: folder}))
    end
  end

  @doc """
  Restores a soft-deleted folder, cascade-restoring its documents. No-op (200)
  if not soft-deleted; 404 if missing.
  """
  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def restore(conn, %{"id" => id}) do
    with {:ok, folder} <- Documents.get_folder(id, include_deleted: true),
         {:ok, folder} <- Documents.restore_folder(folder) do
      json(conn, FolderJSON.show(%{folder: folder}))
    end
  end

  @spec parse_opts(map()) :: keyword()
  defp parse_opts(%{"include_deleted" => "true"}), do: [include_deleted: true]
  defp parse_opts(_params), do: []
end

defmodule SoftCrudWeb.DocumentController do
  @moduledoc """
  JSON API controller for documents, including direct soft delete and restore.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias SoftCrud.Documents
  alias SoftCrudWeb.DocumentJSON

  action_fallback(SoftCrudWeb.FallbackController)

  @doc """
  Lists documents. Supports `?include_deleted=true`.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    documents = Documents.list_documents(parse_opts(params))
    json(conn, DocumentJSON.index(%{documents: documents}))
  end

  @doc """
  Creates a document, responding with 201 on success.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"document" => document_params}) do
    with {:ok, document} <- Documents.create_document(document_params) do
      conn
      |> put_status(:created)
      |> json(DocumentJSON.show(%{document: document}))
    end
  end

  @doc """
  Shows a single document. Supports `?include_deleted=true`.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id} = params) do
    with {:ok, document} <- Documents.get_document(id, parse_opts(params)) do
      json(conn, DocumentJSON.show(%{document: document}))
    end
  end

  @doc """
  Directly soft-deletes a document. 404 if missing or already soft-deleted.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with {:ok, document} <- Documents.get_document(id),
         {:ok, document} <- Documents.soft_delete_document(document) do
      json(conn, DocumentJSON.show(%{document: document}))
    end
  end

  @doc """
  Directly restores a soft-deleted document. No-op (200) if not soft-deleted;
  404 if missing.
  """
  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def restore(conn, %{"id" => id}) do
    with {:ok, document} <- Documents.get_document(id, include_deleted: true),
         {:ok, document} <- Documents.restore_document(document) do
      json(conn, DocumentJSON.show(%{document: document}))
    end
  end

  @spec parse_opts(map()) :: keyword()
  defp parse_opts(%{"include_deleted" => "true"}), do: [include_deleted: true]
  defp parse_opts(_params), do: []
end

defmodule SoftCrudWeb.Router do
  @moduledoc """
  Routes for the JSON API under the `/api` scope.

  The `:api` pipeline parses request bodies and negotiates the JSON format so
  the router is fully servable on its own, without a Phoenix endpoint in front.
  """

  use Phoenix.Router

  import Phoenix.Controller, only: [accepts: 2]

  pipeline :api do
    plug(Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Jason
    )

    plug(:accepts, ["json"])
  end

  scope "/api", SoftCrudWeb do
    pipe_through(:api)

    get("/folders", FolderController, :index)
    post("/folders", FolderController, :create)
    get("/folders/:id", FolderController, :show)
    delete("/folders/:id", FolderController, :delete)
    post("/folders/:id/restore", FolderController, :restore)

    get("/documents", DocumentController, :index)
    post("/documents", DocumentController, :create)
    get("/documents/:id", DocumentController, :show)
    delete("/documents/:id", DocumentController, :delete)
    post("/documents/:id/restore", DocumentController, :restore)
  end
end

defmodule SoftCrud.Repo.Migrations.CreateDocuments do
  @moduledoc """
  Creates the `folders` and `documents` tables with soft-delete columns and
  supporting indexes.
  """

  use Ecto.Migration

  @doc """
  Creates both tables and their indexes.
  """
  @spec change() :: :ok
  def change do
    create table(:folders) do
      add(:name, :string, null: false)
      add(:deleted_at, :utc_datetime)

      timestamps()
    end

    create(index(:folders, [:deleted_at]))

    create table(:documents) do
      add(:title, :string, null: false)
      add(:content, :string, null: false)
      add(:folder_id, references(:folders, on_delete: :nothing), null: false)
      add(:deleted_at, :utc_datetime)
      add(:cascaded, :boolean, default: false, null: false)

      timestamps()
    end

    create(index(:documents, [:deleted_at]))
    create(index(:documents, [:folder_id]))

    :ok
  end
end
