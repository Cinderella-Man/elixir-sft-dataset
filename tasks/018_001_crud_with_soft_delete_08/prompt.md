# Implement the missing file

Below is the complete specification of a task, followed by its working,
fully tested multi-file solution — except that the entire content of
`lib/soft_crud_web/controllers/document_controller.ex` has been blanked to `# TODO`. Write that file so the whole
bundle passes the task's full test suite again. Change nothing else —
every other file must stay exactly as shown.

## The task

Build me an Elixir Phoenix JSON API for a `Document` resource with soft-delete support. The project should be a standard Mix project using Phoenix and Ecto with PostgreSQL.

## Schema

Create a `Document` schema in a context module called `SoftCrud.Documents` with the following fields:

- `title` — string, required, non-empty
- `content` — string, required
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `inserted_at` / `updated_at` — standard Phoenix timestamps

The Ecto migration should create a `documents` table with these columns. Add an index on `deleted_at` to support efficient filtering.

## Context: `SoftCrud.Documents`

This module should expose the following functions:

- `list_documents(opts \\ [])` — Returns all documents. By default, excludes documents where `deleted_at` is not nil. If `opts` contains `include_deleted: true`, return all documents regardless of `deleted_at`.
- `get_document(id, opts \\ [])` — Fetches a single document by ID. Returns `{:ok, document}` or `{:error, :not_found}`. By default, a soft-deleted document should return `{:error, :not_found}`. If `opts` contains `include_deleted: true`, return it even if soft-deleted.
- `create_document(attrs)` — Creates a new document. Returns `{:ok, document}` or `{:error, changeset}`. Validate that `title` is present and non-empty, and `content` is present.
- `update_document(document, attrs)` — Updates an existing document's `title` and/or `content`. Returns `{:ok, document}` or `{:error, changeset}`. Do not allow updating `deleted_at` through this function.
- `soft_delete_document(document)` — Sets `deleted_at` to the current UTC time. Returns `{:ok, document}`. If already soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).
- `restore_document(document)` — Sets `deleted_at` back to nil. Returns `{:ok, document}`. If the document is not soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).

## Router & Controller

Set up a JSON API under the `/api` scope with these endpoints:

- `GET    /api/documents`              — Lists documents. Supports `?include_deleted=true` query param.
- `POST   /api/documents`              — Creates a document. Expects JSON body `{"document": {"title": "...", "content": "..."}}`.
- `GET    /api/documents/:id`          — Shows a single document. Supports `?include_deleted=true` query param.
- `PUT    /api/documents/:id`          — Updates a document. Expects JSON body `{"document": {"title": "...", "content": "..."}}`. Should return 404 for soft-deleted documents (no `include_deleted` support on write endpoints).
- `DELETE /api/documents/:id`          — Soft-deletes a document (sets `deleted_at`). Should return 200 with the updated document JSON. Should return 404 if already soft-deleted.
- `POST   /api/documents/:id/restore`  — Restores a soft-deleted document. Returns 200 with the restored document JSON. If the document is not soft-deleted, return 200 as a no-op with the document as-is.

All success responses should render the document as JSON with this shape:

```json
{
  "data": {
    "id": 1,
    "title": "...",
    "content": "...",
    "deleted_at": null,
    "inserted_at": "...",
    "updated_at": "..."
  }
}
```

For list endpoints, wrap in `{"data": [...]}`.

Validation errors should return 422 with `{"errors": {...}}` containing field-level error details.

Not-found responses should return 404 with `{"errors": {"detail": "Not found"}}`.

## Project structure

Use the app name `soft_crud` with module prefix `SoftCrud`. Organize the code as:

- `lib/soft_crud/documents.ex` — context module
- `lib/soft_crud/documents/document.ex` — Ecto schema + changeset
- `lib/soft_crud_web/router.ex` — routes
- `lib/soft_crud_web/controllers/document_controller.ex` — controller
- `lib/soft_crud_web/controllers/document_json.ex` — JSON view/rendering
- `lib/soft_crud_web/controllers/fallback_controller.ex` — handles `{:error, ...}` tuples from the controller with proper HTTP status codes
- `priv/repo/migrations/..._create_documents.exs` — migration

Use only standard Phoenix/Ecto dependencies. Give me all the files needed for a working application.
## Additional interface contract

- Use exactly these module names: router `SoftCrudWeb.Router`, context `SoftCrud.Documents` (with `create_document/1` and `soft_delete_document/1` returning `{:ok, doc}`), repo `SoftCrud.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The tests dispatch requests straight to `SoftCrudWeb.Router` with `Plug.Test` (no endpoint in front), so every route must be servable by the router pipeline alone.
- Successful creation returns **201** with the document JSON.

## The bundle with `lib/soft_crud_web/controllers/document_controller.ex` missing

```elixir
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

# TODO

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
```

Give me only the complete content of `lib/soft_crud_web/controllers/document_controller.ex` — that one file, nothing
else.
