# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

Build me a self-contained Elixir in-memory context module for a `Document` resource with **trash-and-purge soft delete** governed by a retention window. This is a pure Elixir/OTP task — no Phoenix, no Ecto, no database. State lives in a `GenServer` and time is injectable so retention can be tested deterministically.

## Overview

Unlike a plain `deleted_at` flag, a soft-deleted ("trashed") document has a *bounded* second life: it can be restored only while it is inside its retention window. Once `retention_ms` has elapsed since it was trashed, the document becomes **expired** — no longer restorable — and is eligible to be permanently **purged**. This gives three derived states from a single `deleted_at` field plus the clock:

- `:active`  — `deleted_at == nil`
- `:trashed` — `deleted_at` set and `now - deleted_at < retention_ms`
- `:expired` — `deleted_at` set and `now - deleted_at >= retention_ms`

## Module: `SoftCrud.Documents`

A `GenServer`. `start_link(opts)` accepts:

- `:clock` — a zero-arity function returning the current time in integer milliseconds (default `fn -> System.system_time(:millisecond) end`).
- `:retention_ms` — how long a trashed document stays restorable (default 30 days).

A document is a map: `%{id, title, content, deleted_at, inserted_at, updated_at}` where timestamps come from the injected clock.

Functions (all take the server pid/ref first):

- `create_document(server, attrs)` — validates `title` (non-empty string) and `content` (non-empty string). Returns `{:ok, document}` or `{:error, errors}` where `errors` is a map like `%{title: ["can't be blank"]}`. `attrs` may use atom or string keys.
- `list_documents(server, opts \\ [])` — returns documents sorted by id. By default only `:active`. With `include_deleted: true`, returns active, trashed, and expired (anything still stored).
- `get_document(server, id, opts \\ [])` — `{:ok, document}` or `{:error, :not_found}`. By default a trashed or expired document returns `{:error, :not_found}`; with `include_deleted: true` it is returned.
- `update_document(server, id, attrs)` — updates `title` and/or `content` (partial updates allowed) of an `:active` document. Returns `{:ok, document}`, `{:error, errors}`, or `{:error, :not_found}` if the document is missing, trashed, or expired. `deleted_at` can never be set through this function.
- `soft_delete_document(server, id)` — sets `deleted_at` to `clock.()` for an active document → `{:ok, document}`. If already trashed/expired, no-op returning `{:ok, document}`. `{:error, :not_found}` if missing.
- `restore_document(server, id)` — clears `deleted_at` of a `:trashed` document → `{:ok, document}`. No-op `{:ok, document}` for an already-active document. Returns `{:error, :expired}` for an expired document (retention lapsed). `{:error, :not_found}` if missing.
- `purge_document(server, id)` — hard-deletes a trashed or expired document, returning `{:ok, document}`. Returns `{:error, :not_deleted}` for an active document and `{:error, :not_found}` if missing.
- `purge_expired(server)` — permanently removes every currently `:expired` document. Returns `{:ok, purged_count}`.

## Project structure

Use module prefix `SoftCrud`. Put everything in `lib/soft_crud/documents.ex`. Use only the standard library and OTP.
