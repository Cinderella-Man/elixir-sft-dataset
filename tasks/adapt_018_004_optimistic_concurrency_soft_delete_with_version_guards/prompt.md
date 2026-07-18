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

Build me a self-contained Elixir in-memory context module for a `Document` resource with soft delete guarded by **optimistic concurrency** (version-checked writes). This is a pure Elixir/OTP task — no Phoenix, no Ecto, no database. State lives in a `GenServer`, which serializes writes so lost updates are provably impossible.

## Overview

Every document carries a monotonically increasing `lock_version` (starting at `0`). Each mutating operation — update, soft delete, restore — must be given the `expected_version` the caller last observed. If it does not match the document's current `lock_version`, the write is rejected with `{:error, :stale_version, current_version}` and no state changes. A successful mutation bumps `lock_version` by one. This lets many concurrent writers race safely: exactly one wins, the rest are told they hold a stale view.

## Module: `SoftCrud.Documents`

A `GenServer`. `start_link(opts \\ [])` takes no required options. `attrs` may use atom or string keys.

A document is a map: `%{id, title, content, deleted_at, lock_version, inserted_at, updated_at}` (`deleted_at` is `nil` when active, a stamp when soft-deleted).

Validation errors are returned as `{:error, errors}`, where `errors` is a map keyed by the offending field name (`:title` and/or `:content`) with a non-empty value (e.g. a list of messages); an absent field means it passed. A `title` or `content` is blank when it is not a binary or trims to `""`.

Functions (server pid/ref first):

- `create_document(server, attrs)` — validates non-empty `title` and `content`. Returns `{:ok, document}` (with `lock_version: 0`) or `{:error, errors}`. On error nothing is stored.
- `list_documents(server, opts \\ [])` — active only by default; `include_deleted: true` for all. Sorted by id ascending.
- `get_document(server, id, opts \\ [])` — `{:ok, document}` or `{:error, :not_found}`; soft-deleted hidden unless `include_deleted: true`.
- `update_document(server, id, attrs, expected_version)` — updates `title`/`content` (partial allowed) of an active document; unrecognized keys (e.g. `deleted_at`) are ignored. Precedence: `{:error, :not_found}` if missing **or** soft-deleted; then `{:error, :stale_version, current}` on version mismatch; then `{:error, errors}` on invalid attrs; else `{:ok, document}` with `lock_version + 1`. Never sets `deleted_at`.
- `soft_delete_document(server, id, expected_version)` — precedence: `{:error, :not_found}` if missing; then `{:error, :stale_version, current}` on mismatch; then `{:error, :already_deleted}` if already soft-deleted; else soft-deletes → `{:ok, document}` with `lock_version + 1` and a non-nil `deleted_at`.
- `restore_document(server, id, expected_version)` — precedence: `{:error, :not_found}` if missing; then `{:error, :stale_version, current}` on mismatch; then `{:error, :not_deleted}` if already active; else restores → `{:ok, document}` with `lock_version + 1` and `deleted_at` back to `nil`.

Because the GenServer processes calls one at a time, a burst of concurrent `soft_delete_document(id, 0)` requests must yield exactly one `{:ok, _}` and the rest `{:error, :stale_version, 1}`.

## Project structure

Use module prefix `SoftCrud`. Put everything in `lib/soft_crud/documents.ex`. Use only the standard library and OTP.
