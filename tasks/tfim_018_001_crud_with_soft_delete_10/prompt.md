# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SoftCrudWeb.DocumentControllerTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias SoftCrud.Documents

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SoftCrud.Repo)
    %{conn: conn(:get, "/")}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Plug.Test replacements for the Phoenix.ConnTest conveniences this suite
  # used to get from ConnCase: requests are dispatched straight to
  # SoftCrudWeb.Router, so no Endpoint/ConnCase scaffolding is involved.
  defp sigil_p(path, _modifiers), do: path

  defp request(method, path, params) do
    method
    |> conn(path, params)
    |> Plug.Conn.fetch_query_params()
    |> SoftCrudWeb.Router.call(SoftCrudWeb.Router.init([]))
  end

  defp get(_conn, path), do: request(:get, path, %{})
  defp post(_conn, path, params \\ %{}), do: request(:post, path, params)
  defp put(_conn, path, params), do: request(:put, path, params)
  defp delete(_conn, path), do: request(:delete, path, %{})

  defp json_response(conn, status) do
    assert conn.status == status
    Jason.decode!(conn.resp_body)
  end

  defp create_document(attrs \\ %{}) do
    default = %{title: "Test Doc", content: "Some content"}
    {:ok, doc} = Documents.create_document(Map.merge(default, attrs))
    doc
  end

  defp soft_delete!(doc) do
    {:ok, doc} = Documents.soft_delete_document(doc)
    doc
  end

  defp json_data(conn), do: json_response(conn, 200)["data"]
  defp json_errors(conn, status), do: json_response(conn, status)["errors"]

  # -------------------------------------------------------
  # POST /api/documents  (Create)
  # -------------------------------------------------------

  describe "POST /api/documents" do
    test "creates a document with valid attrs", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "My Doc", "content" => "Hello"}
        })

      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["title"] == "My Doc"
      assert data["content"] == "Hello"
      assert data["deleted_at"] == nil
      assert data["inserted_at"]
      assert data["updated_at"]
    end

    test "returns 422 when title is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"content" => "Hello"}
        })

      errors = json_errors(conn, 422)
      assert errors["title"]
    end

    test "returns 422 when title is empty string", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "", "content" => "Hello"}
        })

      errors = json_errors(conn, 422)
      assert errors["title"]
    end

    test "returns 422 when content is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "A Title"}
        })

      errors = json_errors(conn, 422)
      assert errors["content"]
    end
  end

  # -------------------------------------------------------
  # GET /api/documents  (Index)
  # -------------------------------------------------------

  describe "GET /api/documents" do
    test "returns empty list when no documents exist", %{conn: conn} do
      conn = get(conn, ~p"/api/documents")
      assert json_response(conn, 200)["data"] == []
    end

    test "returns only non-deleted documents by default", %{conn: conn} do
      doc1 = create_document(%{title: "Visible"})
      doc2 = create_document(%{title: "Deleted"})
      soft_delete!(doc2)

      conn = get(conn, ~p"/api/documents")
      data = json_response(conn, 200)["data"]

      ids = Enum.map(data, & &1["id"])
      assert doc1.id in ids
      refute doc2.id in ids
    end

    test "returns all documents when include_deleted=true", %{conn: conn} do
      doc1 = create_document(%{title: "Visible"})
      doc2 = create_document(%{title: "Deleted"})
      soft_delete!(doc2)

      conn = get(conn, ~p"/api/documents?include_deleted=true")
      data = json_response(conn, 200)["data"]

      ids = Enum.map(data, & &1["id"])
      assert doc1.id in ids
      assert doc2.id in ids
    end

    test "include_deleted=false behaves like default", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn = get(conn, ~p"/api/documents?include_deleted=false")
      data = json_response(conn, 200)["data"]
      assert data == []
    end
  end

  # -------------------------------------------------------
  # GET /api/documents/:id  (Show)
  # -------------------------------------------------------

  describe "GET /api/documents/:id" do
    test "returns a document by id", %{conn: conn} do
      # TODO
    end

    test "returns 404 for non-existent id", %{conn: conn} do
      conn = get(conn, ~p"/api/documents/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 for soft-deleted document by default", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn = get(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns soft-deleted document when include_deleted=true", %{conn: conn} do
      doc = create_document(%{title: "Ghost"})
      soft_delete!(doc)

      conn = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["title"] == "Ghost"
      assert data["deleted_at"] != nil
    end
  end

  # -------------------------------------------------------
  # PUT /api/documents/:id  (Update)
  # -------------------------------------------------------

  describe "PUT /api/documents/:id" do
    test "updates title and content", %{conn: conn} do
      doc = create_document(%{title: "Old", content: "Old content"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "New", "content" => "New content"}
        })

      data = json_data(conn)
      assert data["title"] == "New"
      assert data["content"] == "New content"
    end

    test "partial update — only title", %{conn: conn} do
      doc = create_document(%{title: "Old", content: "Keep me"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "Updated"}
        })

      data = json_data(conn)
      assert data["title"] == "Updated"
      assert data["content"] == "Keep me"
    end

    test "returns 422 for invalid update (empty title)", %{conn: conn} do
      doc = create_document()

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => ""}
        })

      errors = json_errors(conn, 422)
      assert errors["title"]
    end

    test "returns 404 for non-existent document", %{conn: conn} do
      conn =
        put(conn, ~p"/api/documents/0", %{
          "document" => %{"title" => "Nope"}
        })

      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 for soft-deleted document", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "Can't touch this"}
        })

      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "cannot set deleted_at through update", %{conn: conn} do
      doc = create_document()

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"deleted_at" => DateTime.to_iso8601(DateTime.utc_now())}
        })

      data = json_data(conn)
      assert data["deleted_at"] == nil
    end
  end

  # -------------------------------------------------------
  # DELETE /api/documents/:id  (Soft Delete)
  # -------------------------------------------------------

  describe "DELETE /api/documents/:id" do
    test "soft-deletes a document (sets deleted_at)", %{conn: conn} do
      doc = create_document()

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] != nil
    end

    test "soft-deleted document disappears from default listings", %{conn: conn} do
      doc = create_document()

      delete(conn, ~p"/api/documents/#{doc.id}")

      conn = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      refute doc.id in ids
    end

    test "returns 404 for non-existent document", %{conn: conn} do
      conn = delete(conn, ~p"/api/documents/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 when deleting an already soft-deleted document", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # POST /api/documents/:id/restore  (Restore)
  # -------------------------------------------------------

  describe "POST /api/documents/:id/restore" do
    test "restores a soft-deleted document", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
    end

    test "restored document appears in default listings again", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      post(conn, ~p"/api/documents/#{doc.id}/restore")

      conn = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert doc.id in ids
    end

    test "restoring a non-deleted document is a no-op 200", %{conn: conn} do
      doc = create_document()

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      assert conn.status == 200

      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
    end

    test "returns 404 for non-existent document", %{conn: conn} do
      conn = post(conn, ~p"/api/documents/0/restore")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # Round-trip lifecycle
  # -------------------------------------------------------

  describe "full lifecycle" do
    test "create → read → update → soft delete → invisible → restore → visible", %{conn: conn} do
      # 1. Create
      conn_create =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Lifecycle", "content" => "v1"}
        })

      id = json_response(conn_create, 201)["data"]["id"]
      assert id

      # 2. Read
      conn_show = get(conn, ~p"/api/documents/#{id}")
      assert json_data(conn_show)["title"] == "Lifecycle"

      # 3. Update
      conn_update =
        put(conn, ~p"/api/documents/#{id}", %{
          "document" => %{"content" => "v2"}
        })

      assert json_data(conn_update)["content"] == "v2"

      # 4. Soft delete
      conn_del = delete(conn, ~p"/api/documents/#{id}")
      assert json_data(conn_del)["deleted_at"] != nil

      # 5. Invisible by default
      conn_show2 = get(conn, ~p"/api/documents/#{id}")
      assert conn_show2.status == 404

      # 6. Still visible with flag
      conn_show3 = get(conn, ~p"/api/documents/#{id}?include_deleted=true")
      assert json_data(conn_show3)["id"] == id

      # 7. Restore
      conn_restore = post(conn, ~p"/api/documents/#{id}/restore")
      assert json_data(conn_restore)["deleted_at"] == nil

      # 8. Visible again
      conn_show4 = get(conn, ~p"/api/documents/#{id}")
      assert json_data(conn_show4)["title"] == "Lifecycle"
      assert json_data(conn_show4)["content"] == "v2"
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  describe "edge cases" do
    test "multiple documents — deleting one doesn't affect others", %{conn: conn} do
      _doc1 = create_document(%{title: "Keep"})
      doc2 = create_document(%{title: "Remove"})
      _doc3 = create_document(%{title: "Also Keep"})

      soft_delete!(doc2)

      conn = get(conn, ~p"/api/documents")
      titles = Enum.map(json_response(conn, 200)["data"], & &1["title"])

      assert "Keep" in titles
      assert "Also Keep" in titles
      refute "Remove" in titles
    end

    test "double restore is idempotent", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      post(conn, ~p"/api/documents/#{doc.id}/restore")
      conn2 = post(conn, ~p"/api/documents/#{doc.id}/restore")

      assert conn2.status == 200
      assert json_data(conn2)["deleted_at"] == nil
    end

    test "deleted_at timestamp is a valid ISO8601 datetime", %{conn: conn} do
      doc = create_document()
      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      deleted_at = json_data(conn)["deleted_at"]

      assert {:ok, _dt, _offset} = DateTime.from_iso8601(deleted_at)
    end

    test "update preserves existing content when only title is sent", %{conn: conn} do
      doc = create_document(%{title: "T", content: "Important content"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "T2"}
        })

      data = json_data(conn)
      assert data["title"] == "T2"
      assert data["content"] == "Important content"
    end
  end
end
```
