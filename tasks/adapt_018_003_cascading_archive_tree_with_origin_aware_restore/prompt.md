# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
<file path="lib/soft_crud/documents/document.ex">
defmodule SoftCrud.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field(:title, :string)
    field(:content, :string)
    field(:deleted_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating and updating title/content."
  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
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

<file path="lib/soft_crud_web/router.ex">
defmodule SoftCrudWeb.Router do
  use SoftCrudWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", SoftCrudWeb do
    pipe_through(:api)

    resources("/documents", DocumentController, only: [:index, :create, :show, :update, :delete])
    post("/documents/:id/restore", DocumentController, :restore)
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

<file path="lib/soft_crud_web/controllers/document_controller.ex">
defmodule SoftCrudWeb.DocumentController do
  use SoftCrudWeb, :controller

  alias SoftCrud.Documents
  alias SoftCrud.Documents.Document

  action_fallback(SoftCrudWeb.FallbackController)

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

<file path="priv/repo/migrations/20240101000000_create_documents.exs">
defmodule SoftCrud.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add(:title, :string, null: false)
      add(:content, :text, null: false)
      add(:deleted_at, :utc_datetime, null: true)

      timestamps(type: :utc_datetime)
    end

    create(index(:documents, [:deleted_at]))
  end
end
</file>
```

## New specification

Build me an in-memory **hierarchical archive store** as a single Elixir GenServer module named `CascadeCrud.Archive`. There is no database, no Phoenix, and no supervision tree to build — just this one module. It stores a tree of *nodes* (folders and files) and supports **cascading archive** (soft delete that propagates down a subtree) and **origin-aware restore** (an un-archive only brings back what *that* archive operation took down).

## Node shape

Every node is a plain map with exactly these keys:

```elixir
%{
  id: 1,                   # positive integer, assigned by the server
  type: :folder,           # :folder or :file
  name: "reports",         # non-empty string
  parent_id: nil,          # id of the containing folder, or nil for a root folder
  content: nil,            # string for files, nil for folders
  archived_at: nil,        # nil when live, a DateTime when archived
  archive_origin: nil      # nil when live, :direct or :cascade when archived
}
```

- IDs are assigned sequentially starting at `1`, in creation order, and are never reused.
- `archived_at` is a `DateTime` in UTC truncated to the second.
- `archive_origin` is `:direct` when the node was the explicit target of an archive call, and `:cascade` when it was archived only because an ancestor was archived.

Attribute maps passed into the API use **atom keys**.

## Public API

### `start_link(opts)`

Starts the server. `opts` is a keyword list; if it contains `:name`, the server is registered under that name, otherwise it is started unnamed. Returns `{:ok, pid}`. The module must also be usable as a supervised child (i.e. `start_supervised!({CascadeCrud.Archive, []})` must work).

Every other function takes the server (pid or registered name) as its first argument.

### `create_folder(server, attrs)`

`attrs` may contain `:name` (required) and `:parent_id` (optional, defaults to `nil` meaning a root folder).

- `{:ok, folder}` on success (a node map with `type: :folder`, `content: nil`, `archived_at: nil`, `archive_origin: nil`).
- `{:error, :invalid_name}` if `:name` is missing, is not a string, or is empty / whitespace-only.
- `{:error, :parent_not_found}` if `:parent_id` is given but no node with that id exists, or that node is a file.
- `{:error, :parent_archived}` if the parent folder exists but is archived.

### `create_file(server, attrs)`

`attrs` may contain `:name` (required), `:parent_id` (**required** — files always live inside a folder) and `:content` (optional string, defaults to `""`).

- `{:ok, file}` on success (`type: :file`, `content` set).
- `{:error, :invalid_name}` — same name rules as above.
- `{:error, :parent_not_found}` if `:parent_id` is `nil`/missing, refers to no node, or refers to a file.
- `{:error, :parent_archived}` if the parent folder is archived.

Validation order: the name is validated before the parent.

### `fetch_node(server, id, opts \\ [])`

- `{:ok, node}` if a node with that id exists and is live.
- If the node is archived: `{:error, :not_found}` by default, but `{:ok, node}` when `opts` contains `include_archived: true`.
- `{:error, :not_found}` if no node has that id.

### `list_children(server, folder_id, opts \\ [])`

Direct children of the given folder (not the whole subtree), **sorted by id ascending**.

- `{:ok, children}` — archived children are excluded unless `opts` contains `include_archived: true`.
- The folder itself is subject to the same visibility rule: if it is archived and `include_archived: true` is not given, return `{:error, :not_found}`.
- `{:error, :not_found}` if no node has that id, or the id refers to a file.
- An empty folder yields `{:ok, []}`.

### `rename_node(server, id, new_name)`

Renames a **live** node (folder or file).

- `{:ok, node}` with the updated name.
- `{:error, :invalid_name}` if `new_name` is not a non-empty (non-whitespace-only) string.
- `{:error, :not_found}` if no node has that id **or the node is archived** (archived nodes cannot be renamed).

Validation order: the name is validated before the node lookup.

### `archive_node(server, id)`

Archives a live node. If it is a folder, its entire subtree is archived too.

- `{:ok, %{node: node, cascaded: cascaded_ids}}` where:
  - `node` is the target with `archive_origin: :direct` and `archived_at` set,
  - `cascaded_ids` is the list of ids of the descendants that this call archived, **sorted ascending**. Those descendants get `archive_origin: :cascade` and **the same `archived_at` value as the target**.
  - Descendants that were *already* archived before this call are left completely untouched (their `archived_at` and `archive_origin` do not change) and their ids do **not** appear in `cascaded_ids`.
- `{:error, :already_archived}` if the node exists but is already archived.
- `{:error, :not_found}` if no node has that id.

Archiving a file archives just that file (`cascaded: []`).

### `unarchive_node(server, id)`

Restores a node that was archived **directly**, together with the descendants that were taken down by that same cascade.

- `{:ok, %{node: node, restored: restored_ids}}` where `node` is the target back to `archived_at: nil, archive_origin: nil`, and `restored_ids` are the ids of descendants restored by this call, sorted ascending.
- Restoration walks down from the target: a child with `archive_origin: :cascade` is restored and the walk continues through it; a child with `archive_origin: :direct` is **left archived and its whole subtree is skipped** (it was archived on its own terms, so it stays in the archive).
- `{:error, :not_found}` if no node has that id.
- `{:error, :not_archived}` if the node exists and is live.
- `{:error, :cascade_archived}` if the node's `archive_origin` is `:cascade` — a cascade-archived node can only come back by restoring the ancestor that took it down.
- `{:error, :parent_archived}` if the node's parent folder is still archived (this can happen when a child was archived directly and then its parent was archived directly afterwards).

### `list_archived(server)`

Returns `{:ok, nodes}` — every archived node (both `:direct` and `:cascade` origins), sorted by id ascending.

## Notes

- All state lives in the GenServer; no persistence, no ETS.
- All operations are serialized through the server, so concurrent callers see a consistent tree.
- Compile with zero warnings.
