defmodule CascadeCrud.Content.Folder do
  @moduledoc """
  Ecto schema for a folder.

  A folder groups documents together and can be soft-deleted. Soft-deleting a
  folder is expected to cascade to the documents it contains (handled in the
  `CascadeCrud.Content` context).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "folders" do
    field(:name, :string)
    field(:deleted_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  @doc """
  Builds a changeset for a folder. Requires a present, non-empty `name`.
  """
  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end

defmodule CascadeCrud.Content.Document do
  @moduledoc """
  Ecto schema for a document living inside a folder.

  A document can be soft-deleted directly, or as a side effect of its parent
  folder being soft-deleted. The `deleted_cascade` flag records which of those
  happened so a folder restore can undo only its own cascade.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "documents" do
    field(:title, :string)
    field(:content, :string)
    field(:folder_id, :integer)
    field(:deleted_at, :utc_datetime)
    field(:deleted_cascade, :boolean, default: false)

    timestamps(type: :utc_datetime)
  end

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  @doc """
  Builds a changeset for creating a document.

  Requires `title` (non-empty), `content`, and `folder_id`, and enforces that
  `folder_id` references an existing folder via a foreign-key constraint.
  """
  def create_changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content, :folder_id])
    |> validate_required([:title, :content, :folder_id])
    |> foreign_key_constraint(:folder_id)
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  @doc """
  Builds a changeset for updating a document. Only `title` and `content` may
  change; all other keys in `attrs` are ignored.
  """
  def update_changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
  end
end

defmodule CascadeCrud.Content do
  @moduledoc """
  The Content context: folders and documents with cascading soft-delete.

  Soft-deleting a folder cascades to its documents (marking them with
  `deleted_cascade: true`), and restoring a folder undoes only that cascade,
  leaving independently-deleted documents untouched.
  """

  import Ecto.Query, only: [from: 2, where: 3]

  alias CascadeCrud.Content.Document
  alias CascadeCrud.Content.Folder
  alias CascadeCrud.Repo

  @spec list_folders(keyword()) :: [Folder.t()]
  @doc """
  Lists folders. Excludes soft-deleted folders unless `include_deleted: true`.
  """
  def list_folders(opts \\ []) do
    Folder
    |> exclude_deleted(opts)
    |> Repo.all()
  end

  @spec get_folder(term(), keyword()) :: {:ok, Folder.t()} | {:error, :not_found}
  @doc """
  Fetches a folder by id. Returns `{:error, :not_found}` for a missing folder,
  and for a soft-deleted folder unless `include_deleted: true` is given.
  """
  def get_folder(id, opts \\ []) do
    Folder
    |> exclude_deleted(opts)
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      folder -> {:ok, folder}
    end
  end

  @spec create_folder(map()) :: {:ok, Folder.t()} | {:error, Ecto.Changeset.t()}
  @doc """
  Creates a folder from `attrs`.
  """
  def create_folder(attrs) do
    %Folder{}
    |> Folder.changeset(attrs)
    |> Repo.insert()
  end

  @spec soft_delete_folder(Folder.t()) :: {:ok, Folder.t()}
  @doc """
  Soft-deletes a folder and cascades to its documents. Documents that are not
  already soft-deleted get `deleted_at` set and `deleted_cascade: true`.
  Already soft-deleted documents are left as-is. No-op if already deleted.
  """
  def soft_delete_folder(%Folder{deleted_at: nil} = folder) do
    now = now_seconds()

    Repo.transaction(fn ->
      {:ok, updated} =
        folder
        |> Ecto.Changeset.change(deleted_at: now)
        |> Repo.update()

      Document
      |> where([d], d.folder_id == ^folder.id and is_nil(d.deleted_at))
      |> Repo.update_all(set: [deleted_at: now, deleted_cascade: true, updated_at: now])

      updated
    end)
  end

  def soft_delete_folder(%Folder{} = folder), do: {:ok, folder}

  @spec restore_folder(Folder.t()) :: {:ok, Folder.t()}
  @doc """
  Restores a soft-deleted folder and undoes its cascade. Documents with
  `deleted_cascade: true` are restored; documents deleted directly are left
  soft-deleted. No-op if the folder is not soft-deleted.
  """
  def restore_folder(%Folder{deleted_at: nil} = folder), do: {:ok, folder}

  def restore_folder(%Folder{} = folder) do
    now = now_seconds()

    Repo.transaction(fn ->
      {:ok, updated} =
        folder
        |> Ecto.Changeset.change(deleted_at: nil)
        |> Repo.update()

      Document
      |> where([d], d.folder_id == ^folder.id and d.deleted_cascade == true)
      |> Repo.update_all(set: [deleted_at: nil, deleted_cascade: false, updated_at: now])

      updated
    end)
  end

  @spec list_documents(keyword()) :: [Document.t()]
  @doc """
  Lists documents. Excludes soft-deleted documents unless `include_deleted:
  true`. When `folder_id: id` is given, only that folder's documents are
  returned (combined with the delete filter).
  """
  def list_documents(opts \\ []) do
    Document
    |> exclude_deleted(opts)
    |> filter_folder(opts)
    |> Repo.all()
  end

  @spec get_document(term(), keyword()) :: {:ok, Document.t()} | {:error, :not_found}
  @doc """
  Fetches a document by id. Returns `{:error, :not_found}` for a missing
  document, and for a soft-deleted document unless `include_deleted: true`.
  """
  def get_document(id, opts \\ []) do
    Document
    |> exclude_deleted(opts)
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      document -> {:ok, document}
    end
  end

  @spec create_document(map()) :: {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  @doc """
  Creates a document from `attrs`. A newly created document has
  `deleted_cascade == false`.
  """
  def create_document(attrs) do
    %Document{}
    |> Document.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec update_document(Document.t(), map()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  @doc """
  Updates a document's `title` and/or `content`. Other keys are ignored.
  """
  def update_document(%Document{} = document, attrs) do
    document
    |> Document.update_changeset(attrs)
    |> Repo.update()
  end

  @spec soft_delete_document(Document.t()) :: {:ok, Document.t()}
  @doc """
  Directly soft-deletes a document, setting `deleted_at` and
  `deleted_cascade: false`. No-op if already soft-deleted.
  """
  def soft_delete_document(%Document{deleted_at: nil} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: now_seconds(), deleted_cascade: false)
    |> Repo.update()
  end

  def soft_delete_document(%Document{} = document), do: {:ok, document}

  @spec restore_document(Document.t()) :: {:ok, Document.t()}
  @doc """
  Restores a document, clearing `deleted_at` and resetting
  `deleted_cascade: false`. No-op if not soft-deleted.
  """
  def restore_document(%Document{deleted_at: nil} = document), do: {:ok, document}

  def restore_document(%Document{} = document) do
    document
    |> Ecto.Changeset.change(deleted_at: nil, deleted_cascade: false)
    |> Repo.update()
  end

  defp exclude_deleted(query, opts) do
    if Keyword.get(opts, :include_deleted, false) do
      query
    else
      from(q in query, where: is_nil(q.deleted_at))
    end
  end

  defp filter_folder(query, opts) do
    case Keyword.get(opts, :folder_id) do
      nil -> query
      folder_id -> from(q in query, where: q.folder_id == ^folder_id)
    end
  end

  defp now_seconds do
    DateTime.truncate(DateTime.utc_now(), :second)
  end
end

defmodule CascadeCrudWeb.ErrorJSON do
  @moduledoc """
  Renders error payloads for the JSON API.
  """

  @spec error(map()) :: map()
  @doc """
  Renders changeset validation errors as `{errors: %{field => [messages]}}`.
  """
  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  @spec not_found() :: map()
  @doc """
  Renders the standard not-found payload.
  """
  def not_found do
    %{errors: %{detail: "Not found"}}
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end

defmodule CascadeCrudWeb.FolderJSON do
  @moduledoc """
  Renders folders as JSON.
  """

  alias CascadeCrud.Content.Folder

  @spec index(map()) :: map()
  @doc """
  Renders a list of folders wrapped in `data`.
  """
  def index(%{folders: folders}) do
    %{data: Enum.map(folders, &data/1)}
  end

  @spec show(map()) :: map()
  @doc """
  Renders a single folder wrapped in `data`.
  """
  def show(%{folder: folder}) do
    %{data: data(folder)}
  end

  @spec data(Folder.t()) :: map()
  @doc """
  Renders a folder's public fields.
  """
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

defmodule CascadeCrudWeb.DocumentJSON do
  @moduledoc """
  Renders documents as JSON.
  """

  alias CascadeCrud.Content.Document

  @spec index(map()) :: map()
  @doc """
  Renders a list of documents wrapped in `data`.
  """
  def index(%{documents: documents}) do
    %{data: Enum.map(documents, &data/1)}
  end

  @spec show(map()) :: map()
  @doc """
  Renders a single document wrapped in `data`.
  """
  def show(%{document: document}) do
    %{data: data(document)}
  end

  @spec data(Document.t()) :: map()
  @doc """
  Renders a document's public fields.
  """
  def data(%Document{} = document) do
    %{
      id: document.id,
      title: document.title,
      content: document.content,
      folder_id: document.folder_id,
      deleted_at: document.deleted_at,
      deleted_cascade: document.deleted_cascade,
      inserted_at: document.inserted_at,
      updated_at: document.updated_at
    }
  end
end

defmodule CascadeCrudWeb.FallbackController do
  @moduledoc """
  Translates context error tuples into JSON error responses.
  """

  use Phoenix.Controller

  alias CascadeCrudWeb.ErrorJSON

  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  @doc """
  Handles `{:error, changeset}` (422) and `{:error, :not_found}` (404).
  """
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ErrorJSON.error(%{changeset: changeset}))
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(ErrorJSON.not_found())
  end
end

defmodule CascadeCrudWeb.FolderController do
  @moduledoc """
  JSON endpoints for folders, including cascading soft-delete and restore.
  """

  use Phoenix.Controller

  alias CascadeCrud.Content
  alias CascadeCrudWeb.FolderJSON

  action_fallback(CascadeCrudWeb.FallbackController)

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  @doc """
  Lists folders. Supports `?include_deleted=true`.
  """
  def index(conn, params) do
    folders = Content.list_folders(list_opts(params))
    json(conn, FolderJSON.index(%{folders: folders}))
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, Ecto.Changeset.t()}
  @doc """
  Creates a folder, responding 201 on success.
  """
  def create(conn, %{"folder" => folder_params}) do
    with {:ok, folder} <- Content.create_folder(folder_params) do
      conn
      |> put_status(:created)
      |> json(FolderJSON.show(%{folder: folder}))
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  @doc """
  Shows a folder. Supports `?include_deleted=true`.
  """
  def show(conn, %{"id" => id} = params) do
    with {:ok, folder} <- Content.get_folder(id, list_opts(params)) do
      json(conn, FolderJSON.show(%{folder: folder}))
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  @doc """
  Soft-deletes a folder (cascading to its documents). 404 if missing or already
  soft-deleted.
  """
  def delete(conn, %{"id" => id}) do
    with {:ok, folder} <- Content.get_folder(id),
         {:ok, folder} <- Content.soft_delete_folder(folder) do
      json(conn, FolderJSON.show(%{folder: folder}))
    end
  end

  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  @doc """
  Restores a soft-deleted folder (undoing its cascade). No-op if not deleted.
  404 if the folder does not exist.
  """
  def restore(conn, %{"id" => id}) do
    with {:ok, folder} <- Content.get_folder(id, include_deleted: true),
         {:ok, folder} <- Content.restore_folder(folder) do
      json(conn, FolderJSON.show(%{folder: folder}))
    end
  end

  defp list_opts(%{"include_deleted" => "true"}), do: [include_deleted: true]
  defp list_opts(_params), do: []
end

defmodule CascadeCrudWeb.DocumentController do
  @moduledoc """
  JSON endpoints for documents, including direct soft-delete and restore.
  """

  use Phoenix.Controller

  alias CascadeCrud.Content
  alias CascadeCrudWeb.DocumentJSON

  action_fallback(CascadeCrudWeb.FallbackController)

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  @doc """
  Lists documents. Supports `?include_deleted=true` and `?folder_id=ID`.
  """
  def index(conn, params) do
    documents = Content.list_documents(list_opts(params))
    json(conn, DocumentJSON.index(%{documents: documents}))
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, Ecto.Changeset.t()}
  @doc """
  Creates a document, responding 201 on success.
  """
  def create(conn, %{"document" => document_params}) do
    with {:ok, document} <- Content.create_document(document_params) do
      conn
      |> put_status(:created)
      |> json(DocumentJSON.show(%{document: document}))
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  @doc """
  Shows a document. Supports `?include_deleted=true`.
  """
  def show(conn, %{"id" => id} = params) do
    with {:ok, document} <- Content.get_document(id, include_opts(params)) do
      json(conn, DocumentJSON.show(%{document: document}))
    end
  end

  @spec update(Plug.Conn.t(), map()) ::
          Plug.Conn.t() | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  @doc """
  Updates a document's `title`/`content`. 404 for a soft-deleted document.
  """
  def update(conn, %{"id" => id, "document" => document_params}) do
    with {:ok, document} <- Content.get_document(id),
         {:ok, document} <- Content.update_document(document, document_params) do
      json(conn, DocumentJSON.show(%{document: document}))
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  @doc """
  Directly soft-deletes a document. 404 if missing or already soft-deleted.
  """
  def delete(conn, %{"id" => id}) do
    with {:ok, document} <- Content.get_document(id),
         {:ok, document} <- Content.soft_delete_document(document) do
      json(conn, DocumentJSON.show(%{document: document}))
    end
  end

  @spec restore(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  @doc """
  Restores a soft-deleted document. No-op if not deleted. 404 if it does not
  exist.
  """
  def restore(conn, %{"id" => id}) do
    with {:ok, document} <- Content.get_document(id, include_deleted: true),
         {:ok, document} <- Content.restore_document(document) do
      json(conn, DocumentJSON.show(%{document: document}))
    end
  end

  defp list_opts(params) do
    []
    |> maybe_include_deleted(params)
    |> maybe_folder_id(params)
  end

  defp include_opts(%{"include_deleted" => "true"}), do: [include_deleted: true]
  defp include_opts(_params), do: []

  defp maybe_include_deleted(opts, %{"include_deleted" => "true"}) do
    Keyword.put(opts, :include_deleted, true)
  end

  defp maybe_include_deleted(opts, _params), do: opts

  defp maybe_folder_id(opts, %{"folder_id" => raw}) when is_binary(raw) do
    case Integer.parse(raw) do
      {id, _rest} -> Keyword.put(opts, :folder_id, id)
      :error -> opts
    end
  end

  defp maybe_folder_id(opts, %{"folder_id" => raw}) when is_integer(raw) do
    Keyword.put(opts, :folder_id, raw)
  end

  defp maybe_folder_id(opts, _params), do: opts
end

defmodule CascadeCrudWeb.Router do
  @moduledoc """
  Routes for the JSON API under `/api`.
  """

  use Phoenix.Router

  import Phoenix.Controller, only: [accepts: 2]

  pipeline :api do
    plug(:accepts, ["json"])
    plug(Plug.Parsers, parsers: [:json], pass: ["*/*"], json_decoder: Jason)
  end

  scope "/api", CascadeCrudWeb do
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

defmodule CascadeCrud.Repo.Migrations.CreateContent do
  @moduledoc """
  Creates the `folders` and `documents` tables with soft-delete columns,
  a foreign key from documents to folders, and supporting indexes.
  """

  use Ecto.Migration

  @spec change() :: :ok
  @doc """
  Creates both tables, the foreign key, and the indexes.
  """
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
      add(:folder_id, references(:folders, on_delete: :nothing), null: false)
      add(:deleted_at, :utc_datetime)
      add(:deleted_cascade, :boolean, null: false, default: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:documents, [:deleted_at]))
    create(index(:documents, [:folder_id]))

    :ok
  end
end
