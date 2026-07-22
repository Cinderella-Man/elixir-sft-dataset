defmodule SoftCrud.Repo do
  @moduledoc """
  The Ecto repository for the SoftCrud application, backed by PostgreSQL.

  The surrounding test environment is responsible for configuring, starting,
  and migrating this repository before the tests run.
  """

  use Ecto.Repo,
    otp_app: :soft_crud,
    adapter: Ecto.Adapters.Postgres
end

defmodule SoftCrud.Library.Folder do
  @moduledoc """
  Ecto schema and changeset for a `folders` row.

  A folder owns many documents and supports soft deletion via `deleted_at`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "folders" do
    field(:name, :string)
    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a folder.

  Validates that `name` is present and non-empty.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1)
  end
end

defmodule SoftCrud.Library.Document do
  @moduledoc """
  Ecto schema and changesets for a `documents` row.

  A document always belongs to exactly one folder (`folder_id`) and supports
  soft deletion. The `deleted_via_cascade` flag records whether a soft delete
  came from its folder being soft-deleted (`true`) or was independent (`false`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "documents" do
    field(:title, :string)
    field(:content, :string)
    field(:folder_id, :integer)
    field(:deleted_at, :utc_datetime)
    field(:deleted_via_cascade, :boolean, default: false)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a document.

  Validates that `title` is present and non-empty, and that `content` and
  `folder_id` are present. A newly created document has `deleted_via_cascade`
  equal to `false`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content, :folder_id])
    |> validate_required([:title, :content, :folder_id])
    |> validate_length(:title, min: 1)
  end

  @doc """
  Builds a changeset that only updates `title` and/or `content`.

  It deliberately never casts `folder_id`, `deleted_at`, or
  `deleted_via_cascade`, so those fields cannot be changed through it.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
    |> validate_length(:title, min: 1)
  end
end

defmodule SoftCrud.Library do
  @moduledoc """
  The Library context.

  Manages a two-level `Folder`/`Document` hierarchy with cascading soft delete.
  Soft-deleting a folder cascades the soft delete to its live documents,
  flagging them with `deleted_via_cascade: true`. Restoring the folder brings
  back exactly those cascade-deleted documents, leaving independently deleted
  documents untouched.
  """

  import Ecto.Query

  alias SoftCrud.Repo
  alias SoftCrud.Library.{Document, Folder}

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
  Fetches a folder by id.

  Returns `{:ok, folder}` or `{:error, :not_found}`. Soft-deleted folders are
  hidden unless `include_deleted: true` is given.
  """
  @spec get_folder(integer() | binary(), keyword()) ::
          {:ok, Folder.t()} | {:error, :not_found}
  def get_folder(id, opts \\ []) do
    Folder
    |> maybe_exclude_deleted(opts)
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      folder -> {:ok, folder}
    end
  end

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
  Cascading soft delete of a folder.

  Sets the folder's `deleted_at`, then soft-deletes every currently live
  document in the folder with `deleted_via_cascade: true`. Documents that were
  already soft-deleted are left untouched. A no-op returning `{:ok, folder}`
  when the folder is already soft-deleted.
  """
  @spec soft_delete_folder(Folder.t()) :: {:ok, Folder.t()}
  def soft_delete_folder(%Folder{deleted_at: nil} = folder) do
    timestamp = now()

    {:ok, updated} =
      Repo.transaction(fn ->
        result =
          folder
          |> Ecto.Changeset.change(deleted_at: timestamp)
          |> Repo.update!()

        from(d in Document,
          where: d.folder_id == ^folder.id and is_nil(d.deleted_at)
        )
        |> Repo.update_all(set: [deleted_at: timestamp, deleted_via_cascade: true])

        result
      end)

    {:ok, updated}
  end

  def soft_delete_folder(%Folder{} = folder), do: {:ok, folder}

  @doc """
  Cascading restore of a folder.

  Clears the folder's `deleted_at`, then restores every document in the folder
  whose `deleted_via_cascade` is `true` (clearing both `deleted_at` and the
  flag). Independently deleted documents stay soft-deleted. A no-op returning
  `{:ok, folder}` when the folder is not soft-deleted.
  """
  @spec restore_folder(Folder.t()) :: {:ok, Folder.t()}
  def restore_folder(%Folder{deleted_at: nil} = folder), do: {:ok, folder}

  def restore_folder(%Folder{} = folder) do
    {:ok, updated} =
      Repo.transaction(fn ->
        result =
          folder
          |> Ecto.Changeset.change(deleted_at: nil)
          |> Repo.update!()

        from(d in Document,
          where: d.folder_id == ^folder.id and d.deleted_via_cascade == true
        )
        |> Repo.update_all(set: [deleted_at: nil, deleted_via_cascade: false])

        result
      end)

    {:ok, updated}
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
  Fetches a document by id.

  Returns `{:ok, document}` or `{:error, :not_found}`. Soft-deleted documents
  are hidden unless `include_deleted: true` is given.
  """
  @spec get_document(integer() | binary(), keyword()) ::
          {:ok, Document.t()} | {:error, :not_found}
  def get_document(id, opts \\ []) do
    Document
    |> maybe_exclude_deleted(opts)
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      document -> {:ok, document}
    end
  end

  @doc """
  Creates a document from `attrs`.

  Returns `{:ok, document}` or `{:error, changeset}`.
  """
  @spec create_document(map()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def create_document(attrs) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a document's `title` and/or `content`.

  Never changes `folder_id`, `deleted_at`, or `deleted_via_cascade`. Returns
  `{:ok, document}` or `{:error, changeset}`.
  """
  @spec update_document(Document.t(), map()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def update_document(document, attrs) do
    document
    |> Document.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Independent soft delete of a document.

  Sets `deleted_at` to now and keeps `deleted_via_cascade` as `false`. A no-op
  returning `{:ok, document}` when the document is already soft-deleted.
  """
  @spec soft_delete_document(Document.t()) :: {:ok, Document.t()}
  def soft_delete_document(%Document{deleted_at: nil} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: now(), deleted_via_cascade: false)
    |> Repo.update()
  end

  def soft_delete_document(%Document{} = document), do: {:ok, document}

  @doc """
  Restores a soft-deleted document.

  Clears `deleted_at` and sets `deleted_via_cascade` to `false`. A no-op
  returning `{:ok, document}` when the document is not soft-deleted.
  """
  @spec restore_document(Document.t()) :: {:ok, Document.t()}
  def restore_document(%Document{deleted_at: nil} = document), do: {:ok, document}

  def restore_document(%Document{} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: nil, deleted_via_cascade: false)
    |> Repo.update()
  end

  @spec maybe_exclude_deleted(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
  defp maybe_exclude_deleted(queryable, opts) do
    if Keyword.get(opts, :include_deleted, false) do
      from(q in queryable)
    else
      from(q in queryable, where: is_nil(q.deleted_at))
    end
  end

  @spec now() :: DateTime.t()
  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end

defmodule SoftCrudWeb.ErrorJSON do
  @moduledoc """
  Renders error responses for the JSON API.

  Handles changeset validation errors (`422`) and not-found errors (`404`).
  """

  @doc """
  Renders field-level validation errors from a changeset.
  """
  @spec error(map()) :: map()
  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  @doc """
  Renders a generic not-found error for any other template.
  """
  @spec render(String.t(), map()) :: map()
  def render(_template, _assigns) do
    %{errors: %{detail: "Not found"}}
  end

  @spec translate_error({String.t(), keyword()}) :: String.t()
  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end

defmodule SoftCrudWeb.FallbackController do
  @moduledoc """
  Translates context error tuples into JSON HTTP responses.
  """

  use Phoenix.Controller

  import Plug.Conn

  @doc """
  Handles `{:error, changeset}` and `{:error, :not_found}` return values.
  """
  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SoftCrudWeb.ErrorJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SoftCrudWeb.ErrorJSON)
    |> render(:"404")
  end
end

defmodule SoftCrudWeb.FolderJSON do
  @moduledoc """
  JSON rendering for folders.
  """

  alias SoftCrud.Library.Folder

  @doc """
  Renders a list of folders.
  """
  @spec index(map()) :: map()
  def index(%{folders: folders}) do
    %{data: Enum.map(folders, &data/1)}
  end

  @doc """
  Renders a single folder.
  """
  @spec show(map()) :: map()
  def show(%{folder: folder}) do
    %{data: data(folder)}
  end

  @spec data(Folder.t()) :: map()
  defp data(%Folder{} = folder) do
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
  JSON rendering for documents.
  """

  alias SoftCrud.Library.Document

  @doc """
  Renders a list of documents.
  """
  @spec index(map()) :: map()
  def index(%{documents: documents}) do
    %{data: Enum.map(documents, &data/1)}
  end

  @doc """
  Renders a single document.
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
      folder_id: document.folder_id,
      deleted_at: document.deleted_at,
      deleted_via_cascade: document.deleted_via_cascade,
      inserted_at: document.inserted_at,
      updated_at: document.updated_at
    }
  end
end

defmodule SoftCrudWeb.FolderController do
  @moduledoc """
  JSON API endpoints for folders, including cascading soft delete and restore.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias SoftCrud.Library

  action_fallback(SoftCrudWeb.FallbackController)

  @doc """
  Lists folders, optionally including soft-deleted ones.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    folders = Library.list_folders(opts_from_params(params))
    render(conn, :index, folders: folders)
  end

  @doc """
  Shows a folder, optionally including a soft-deleted one.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id} = params) do
    with {:ok, folder} <- Library.get_folder(id, opts_from_params(params)) do
      render(conn, :show, folder: folder)
    end
  end

  @doc """
  Creates a folder and returns `201` on success.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"folder" => folder_params}) do
    with {:ok, folder} <- Library.create_folder(folder_params) do
      conn
      |> put_status(:created)
      |> render(:show, folder: folder)
    end
  end

  @doc """
  Cascading soft delete of a folder; `404` if missing or already deleted.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with {:ok, folder} <- Library.get_folder(id),
         {:ok, folder} <- Library.soft_delete_folder(folder) do
      render(conn, :show, folder: folder)
    end
  end

  @doc """
  Cascading restore of a folder; a no-op if not soft-deleted.
  """
  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def restore(conn, %{"id" => id}) do
    with {:ok, folder} <- Library.get_folder(id, include_deleted: true),
         {:ok, folder} <- Library.restore_folder(folder) do
      render(conn, :show, folder: folder)
    end
  end

  @spec opts_from_params(map()) :: keyword()
  defp opts_from_params(params) do
    if params["include_deleted"] in ["true", true] do
      [include_deleted: true]
    else
      []
    end
  end
end

defmodule SoftCrudWeb.DocumentController do
  @moduledoc """
  JSON API endpoints for documents, including independent soft delete/restore.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias SoftCrud.Library

  action_fallback(SoftCrudWeb.FallbackController)

  @doc """
  Lists documents, optionally including soft-deleted ones.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    documents = Library.list_documents(opts_from_params(params))
    render(conn, :index, documents: documents)
  end

  @doc """
  Shows a document, optionally including a soft-deleted one.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id} = params) do
    with {:ok, document} <- Library.get_document(id, opts_from_params(params)) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Creates a document and returns `201` on success.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"document" => document_params}) do
    with {:ok, document} <- Library.create_document(document_params) do
      conn
      |> put_status(:created)
      |> render(:show, document: document)
    end
  end

  @doc """
  Updates a document's `title` and/or `content`; `404` if soft-deleted.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id, "document" => document_params}) do
    with {:ok, document} <- Library.get_document(id),
         {:ok, document} <- Library.update_document(document, document_params) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Independent soft delete of a document; `404` if missing or already deleted.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with {:ok, document} <- Library.get_document(id),
         {:ok, document} <- Library.soft_delete_document(document) do
      render(conn, :show, document: document)
    end
  end

  @doc """
  Restores a soft-deleted document; a no-op if not soft-deleted.
  """
  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def restore(conn, %{"id" => id}) do
    with {:ok, document} <- Library.get_document(id, include_deleted: true),
         {:ok, document} <- Library.restore_document(document) do
      render(conn, :show, document: document)
    end
  end

  @spec opts_from_params(map()) :: keyword()
  defp opts_from_params(params) do
    if params["include_deleted"] in ["true", true] do
      [include_deleted: true]
    else
      []
    end
  end
end

defmodule SoftCrudWeb.Router do
  @moduledoc """
  Routes for the JSON API under the `/api` scope.

  The pipeline parses JSON bodies and fetches query params so the router can be
  served directly (without a Phoenix endpoint) in tests.
  """

  use Phoenix.Router

  import Phoenix.Controller
  import Plug.Conn

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_query_params)

    plug(Plug.Parsers,
      parsers: [:json, :urlencoded, :multipart],
      pass: ["*/*"],
      json_decoder: Jason
    )
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
    put("/documents/:id", DocumentController, :update)
    delete("/documents/:id", DocumentController, :delete)
    post("/documents/:id/restore", DocumentController, :restore)
  end
end

defmodule SoftCrud.Repo.Migrations.CreateLibrary do
  @moduledoc """
  Creates the `folders` and `documents` tables with soft-delete columns and
  supporting indexes.
  """

  use Ecto.Migration

  @doc """
  Creates both tables and their indexes.
  """
  @spec change() :: term()
  def change do
    create table(:folders) do
      add(:name, :string, null: false)
      add(:deleted_at, :utc_datetime)

      timestamps()
    end

    create(index(:folders, [:deleted_at]))

    create table(:documents) do
      add(:title, :string, null: false)
      add(:content, :text, null: false)
      add(:folder_id, references(:folders, on_delete: :nothing), null: false)
      add(:deleted_at, :utc_datetime)
      add(:deleted_via_cascade, :boolean, null: false, default: false)

      timestamps()
    end

    create(index(:documents, [:deleted_at]))
    create(index(:documents, [:folder_id]))
  end
end
