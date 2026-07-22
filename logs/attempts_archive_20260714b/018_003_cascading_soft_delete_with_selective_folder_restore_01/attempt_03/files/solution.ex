defmodule SoftCrud.Repo do
  @moduledoc """
  The Ecto repository for the SoftCrud application, backed by PostgreSQL.

  The connection is configured (and the process started) by the host
  test environment; this module only wires `Ecto.Repo` to the app so the
  generated repository functions (`all/2`, `get/3`, `insert/2`, …) are
  available to the context module.
  """

  use Ecto.Repo,
    otp_app: :soft_crud,
    adapter: Ecto.Adapters.Postgres
end

defmodule SoftCrud.Library.Folder do
  @moduledoc """
  Ecto schema and changeset for a `Folder`, the top level of the
  `Folder` -> `Document` hierarchy. Supports soft-deletion through a
  nullable `deleted_at` timestamp.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @timestamps_opts [type: :utc_datetime]

  schema "folders" do
    field(:name, :string)
    field(:deleted_at, :utc_datetime)

    has_many(:documents, SoftCrud.Library.Document)

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a folder. Requires a
  non-empty `name`.
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
  Ecto schema and changeset for a `Document`, the leaf level of the
  hierarchy. Each document belongs to a `Folder` and can be soft-deleted.

  The `cascade_deleted` field remembers whether the document's current
  soft-deletion happened as part of a folder cascade. It is internal and
  never rendered in JSON responses.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @timestamps_opts [type: :utc_datetime]

  schema "documents" do
    field(:title, :string)
    field(:content, :string)
    field(:deleted_at, :utc_datetime)
    field(:cascade_deleted, :boolean, default: false)

    belongs_to(:folder, SoftCrud.Library.Folder)

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a document. Requires a
  non-empty `title` and a present `content`. Does not allow changing
  `deleted_at` or `cascade_deleted`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
    |> validate_length(:title, min: 1)
  end
end

defmodule SoftCrud.Library do
  @moduledoc """
  The Library context: CRUD and soft-delete operations for `Folder` and
  `Document` records.

  Soft-deleting a folder cascades to its currently-visible documents,
  marking each as cascade-deleted. Restoring the folder brings back only
  those cascade-deleted documents; documents soft-deleted independently
  stay deleted.
  """

  import Ecto.Query, warn: false

  alias SoftCrud.Repo
  alias SoftCrud.Library.Folder
  alias SoftCrud.Library.Document

  @doc """
  Lists folders. Excludes soft-deleted folders unless `include_deleted:
  true` is given in `opts`.
  """
  @spec list_folders(keyword()) :: [Folder.t()]
  def list_folders(opts \\ []) do
    Folder
    |> maybe_exclude_deleted(opts)
    |> Repo.all()
  end

  @doc """
  Fetches a single folder by id. Returns `{:ok, folder}` or
  `{:error, :not_found}`. Soft-deleted folders are hidden unless
  `include_deleted: true` is given.
  """
  @spec get_folder(integer() | String.t(), keyword()) ::
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
  Creates a folder. Returns `{:ok, folder}` or `{:error, changeset}`.
  """
  @spec create_folder(map()) :: {:ok, Folder.t()} | {:error, Ecto.Changeset.t()}
  def create_folder(attrs) do
    %Folder{}
    |> Folder.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Soft-deletes a folder, cascading to every document in it that is not
  already soft-deleted. Cascaded documents are flagged so they can be
  restored later. A no-op if the folder is already soft-deleted.
  """
  @spec soft_delete_folder(Folder.t()) :: {:ok, Folder.t()}
  def soft_delete_folder(%Folder{deleted_at: nil} = folder) do
    stamp = now()

    {:ok, updated} =
      Repo.transaction(fn ->
        {:ok, updated} =
          folder
          |> Ecto.Changeset.change(deleted_at: stamp)
          |> Repo.update()

        from(d in Document,
          where: d.folder_id == ^folder.id and is_nil(d.deleted_at)
        )
        |> Repo.update_all(set: [deleted_at: stamp, cascade_deleted: true, updated_at: stamp])

        updated
      end)

    {:ok, updated}
  end

  def soft_delete_folder(%Folder{} = folder), do: {:ok, folder}

  @doc """
  Restores a soft-deleted folder along with only the documents that were
  soft-deleted as part of its cascade. A no-op if the folder is not
  soft-deleted.
  """
  @spec restore_folder(Folder.t()) :: {:ok, Folder.t()}
  def restore_folder(%Folder{deleted_at: deleted_at} = folder)
      when not is_nil(deleted_at) do
    stamp = now()

    {:ok, updated} =
      Repo.transaction(fn ->
        {:ok, updated} =
          folder
          |> Ecto.Changeset.change(deleted_at: nil)
          |> Repo.update()

        from(d in Document,
          where: d.folder_id == ^folder.id and d.cascade_deleted == true
        )
        |> Repo.update_all(set: [deleted_at: nil, cascade_deleted: false, updated_at: stamp])

        updated
      end)

    {:ok, updated}
  end

  def restore_folder(%Folder{} = folder), do: {:ok, folder}

  @doc """
  Lists the documents belonging to `folder_id`. Excludes soft-deleted
  documents unless `include_deleted: true` is given in `opts`.
  """
  @spec list_documents(integer() | String.t(), keyword()) :: [Document.t()]
  def list_documents(folder_id, opts \\ []) do
    from(d in Document, where: d.folder_id == ^folder_id)
    |> maybe_exclude_deleted(opts)
    |> Repo.all()
  end

  @doc """
  Fetches a single document by id. Returns `{:ok, document}` or
  `{:error, :not_found}`. Soft-deleted documents are hidden unless
  `include_deleted: true` is given.
  """
  @spec get_document(integer() | String.t(), keyword()) ::
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
  Creates a document inside `folder`. Returns `{:ok, document}` or
  `{:error, changeset}`.
  """
  @spec create_document(Folder.t(), map()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def create_document(%Folder{} = folder, attrs) do
    %Document{}
    |> Document.changeset(attrs)
    |> Ecto.Changeset.put_change(:folder_id, folder.id)
    |> Repo.insert()
  end

  @doc """
  Updates a document's `title` and/or `content`. Cannot change
  `deleted_at`. Returns `{:ok, document}` or `{:error, changeset}`.
  """
  @spec update_document(Document.t(), map()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def update_document(%Document{} = document, attrs) do
    document
    |> Document.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a single document independently (not as a cascade). A
  no-op if the document is already soft-deleted.
  """
  @spec soft_delete_document(Document.t()) :: {:ok, Document.t()}
  def soft_delete_document(%Document{deleted_at: nil} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: now(), cascade_deleted: false)
    |> Repo.update()
  end

  def soft_delete_document(%Document{} = document), do: {:ok, document}

  @doc """
  Restores a soft-deleted document. A no-op if the document is not
  soft-deleted.
  """
  @spec restore_document(Document.t()) :: {:ok, Document.t()}
  def restore_document(%Document{deleted_at: deleted_at} = document)
      when not is_nil(deleted_at) do
    document
    |> Ecto.Changeset.change(deleted_at: nil, cascade_deleted: false)
    |> Repo.update()
  end

  def restore_document(%Document{} = document), do: {:ok, document}

  @spec maybe_exclude_deleted(Ecto.Queryable.t(), keyword()) ::
          Ecto.Query.t()
  defp maybe_exclude_deleted(query, opts) do
    if Keyword.get(opts, :include_deleted, false) do
      from(q in query)
    else
      from(q in query, where: is_nil(q.deleted_at))
    end
  end

  @spec now() :: DateTime.t()
  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end

defmodule SoftCrudWeb.FallbackController do
  @moduledoc """
  Translates `{:error, ...}` tuples returned by context functions into
  proper JSON error responses with the correct HTTP status codes.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  @doc """
  Handles error tuples: changeset errors become 422 responses and
  `:not_found` becomes a 404 response.
  """
  @spec call(Plug.Conn.t(), {:error, Ecto.Changeset.t() | :not_found}) ::
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

defmodule SoftCrudWeb.FolderJSON do
  @moduledoc """
  Renders folders as JSON. Wraps single folders in `{"data": {...}}` and
  lists in `{"data": [...]}`.
  """

  alias SoftCrud.Library.Folder

  @doc "Renders a list of folders."
  @spec index(map()) :: map()
  def index(%{folders: folders}) do
    %{data: for(folder <- folders, do: data(folder))}
  end

  @doc "Renders a single folder."
  @spec show(map()) :: map()
  def show(%{folder: folder}) do
    %{data: data(folder)}
  end

  @doc "Builds the JSON-serializable map for one folder."
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
  Renders documents as JSON. Wraps single documents in `{"data": {...}}`
  and lists in `{"data": [...]}`. The internal cascade flag is omitted.
  """

  alias SoftCrud.Library.Document

  @doc "Renders a list of documents."
  @spec index(map()) :: map()
  def index(%{documents: documents}) do
    %{data: for(document <- documents, do: data(document))}
  end

  @doc "Renders a single document."
  @spec show(map()) :: map()
  def show(%{document: document}) do
    %{data: data(document)}
  end

  @doc "Builds the JSON-serializable map for one document."
  @spec data(Document.t()) :: map()
  def data(%Document{} = document) do
    %{
      id: document.id,
      folder_id: document.folder_id,
      title: document.title,
      content: document.content,
      deleted_at: document.deleted_at,
      inserted_at: document.inserted_at,
      updated_at: document.updated_at
    }
  end
end

defmodule SoftCrudWeb.FolderController do
  @moduledoc """
  JSON API controller for folders, including cascading soft-delete and
  restore endpoints.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias SoftCrud.Library
  alias SoftCrud.Library.Folder

  action_fallback(SoftCrudWeb.FallbackController)

  plug(:put_view, json: SoftCrudWeb.FolderJSON)

  @doc "Lists folders, optionally including soft-deleted ones."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    folders = Library.list_folders(opts_from_params(params))
    render(conn, :index, folders: folders)
  end

  @doc "Creates a folder and returns it with status 201."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"folder" => folder_params}) do
    with {:ok, %Folder{} = folder} <- Library.create_folder(folder_params) do
      conn
      |> put_status(:created)
      |> render(:show, folder: folder)
    end
  end

  @doc "Shows a single folder, optionally including soft-deleted ones."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id} = params) do
    with {:ok, folder} <- Library.get_folder(id, opts_from_params(params)) do
      render(conn, :show, folder: folder)
    end
  end

  @doc "Soft-deletes a folder, cascading to its documents."
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with {:ok, folder} <- Library.get_folder(id),
         {:ok, folder} <- Library.soft_delete_folder(folder) do
      render(conn, :show, folder: folder)
    end
  end

  @doc "Restores a soft-deleted folder and its cascaded documents."
  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def restore(conn, %{"id" => id}) do
    with {:ok, folder} <- Library.get_folder(id, include_deleted: true),
         {:ok, folder} <- Library.restore_folder(folder) do
      render(conn, :show, folder: folder)
    end
  end

  @spec opts_from_params(map()) :: keyword()
  defp opts_from_params(params) do
    if params["include_deleted"] == "true" do
      [include_deleted: true]
    else
      []
    end
  end
end

defmodule SoftCrudWeb.DocumentController do
  @moduledoc """
  JSON API controller for documents, including nested listing/creation
  under a folder and independent soft-delete/restore endpoints.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias SoftCrud.Library
  alias SoftCrud.Library.Document

  action_fallback(SoftCrudWeb.FallbackController)

  plug(:put_view, json: SoftCrudWeb.DocumentJSON)

  @doc "Lists the documents in a folder; 404 if the folder is hidden."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"folder_id" => folder_id} = params) do
    with {:ok, folder} <- Library.get_folder(folder_id) do
      documents = Library.list_documents(folder.id, opts_from_params(params))
      render(conn, :index, documents: documents)
    end
  end

  @doc "Creates a document in a folder; 404 if the folder is hidden."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"folder_id" => folder_id, "document" => doc_params}) do
    with {:ok, folder} <- Library.get_folder(folder_id),
         {:ok, %Document{} = document} <-
           Library.create_document(folder, doc_params) do
      conn
      |> put_status(:created)
      |> render(:show, document: document)
    end
  end

  @doc "Shows a single document, optionally including soft-deleted ones."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id} = params) do
    with {:ok, document} <-
           Library.get_document(id, opts_from_params(params)) do
      render(conn, :show, document: document)
    end
  end

  @doc "Updates a document's title/content; 404 if soft-deleted."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id, "document" => doc_params}) do
    with {:ok, document} <- Library.get_document(id),
         {:ok, document} <- Library.update_document(document, doc_params) do
      render(conn, :show, document: document)
    end
  end

  @doc "Soft-deletes a single document independently."
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with {:ok, document} <- Library.get_document(id),
         {:ok, document} <- Library.soft_delete_document(document) do
      render(conn, :show, document: document)
    end
  end

  @doc "Restores a soft-deleted document."
  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def restore(conn, %{"id" => id}) do
    with {:ok, document} <- Library.get_document(id, include_deleted: true),
         {:ok, document} <- Library.restore_document(document) do
      render(conn, :show, document: document)
    end
  end

  @spec opts_from_params(map()) :: keyword()
  defp opts_from_params(params) do
    if params["include_deleted"] == "true" do
      [include_deleted: true]
    else
      []
    end
  end
end

defmodule SoftCrudWeb.Router do
  @moduledoc """
  Routes for the JSON API under `/api`. The pipeline parses JSON bodies
  so requests can be dispatched directly to this router without an
  endpoint in front of it.
  """

  use Phoenix.Router

  pipeline :api do
    plug(Plug.Parsers,
      parsers: [:json],
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

    get("/folders/:folder_id/documents", DocumentController, :index)
    post("/folders/:folder_id/documents", DocumentController, :create)

    get("/documents/:id", DocumentController, :show)
    put("/documents/:id", DocumentController, :update)
    delete("/documents/:id", DocumentController, :delete)
    post("/documents/:id/restore", DocumentController, :restore)
  end
end

defmodule SoftCrud.Repo.Migrations.CreateLibrary do
  @moduledoc """
  Creates the `folders` and `documents` tables with soft-delete columns,
  a foreign key from documents to folders, and indexes on `deleted_at`.
  """

  use Ecto.Migration

  @doc "Creates the library schema tables and indexes."
  @spec change() :: any()
  def change do
    create table(:folders) do
      add(:name, :string, null: false)
      add(:deleted_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:folders, [:deleted_at]))

    create table(:documents) do
      add(:title, :string, null: false)
      add(:content, :text, null: false)
      add(:deleted_at, :utc_datetime)
      add(:cascade_deleted, :boolean, default: false, null: false)
      add(:folder_id, references(:folders, on_delete: :nothing), null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:documents, [:folder_id]))
    create(index(:documents, [:deleted_at]))
  end
end
