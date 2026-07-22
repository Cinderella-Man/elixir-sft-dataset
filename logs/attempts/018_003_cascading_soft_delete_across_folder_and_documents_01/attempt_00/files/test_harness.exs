defmodule SoftCrudWeb.CascadeSoftDeleteTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias SoftCrud.Documents

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SoftCrud.Repo)
    %{conn: conn(:get, "/")}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp sigil_p(path, _modifiers), do: path

  defp request(method, path, params) do
    method
    |> conn(path, params)
    |> Plug.Conn.fetch_query_params()
    |> SoftCrudWeb.Router.call(SoftCrudWeb.Router.init([]))
  end

  defp get(_conn, path), do: request(:get, path, %{})
  defp post(_conn, path, params \\ %{}), do: request(:post, path, params)
  defp delete(_conn, path), do: request(:delete, path, %{})

  defp json_response(conn, status) do
    assert conn.status == status
    Jason.decode!(conn.resp_body)
  end

  defp json_data(conn), do: json_response(conn, 200)["data"]
  defp json_errors(conn, status), do: json_response(conn, status)["errors"]

  defp create_folder(attrs \\ %{}) do
    default = %{name: "Folder"}
    {:ok, folder} = Documents.create_folder(Map.merge(default, attrs))
    folder
  end

  defp create_document(folder, attrs \\ %{}) do
    default = %{title: "Doc", content: "content", folder_id: folder.id}
    {:ok, doc} = Documents.create_document(Map.merge(default, attrs))
    doc
  end

  defp soft_delete_folder!(folder) do
    {:ok, folder} = Documents.soft_delete_folder(folder)
    folder
  end

  defp soft_delete_document!(doc) do
    {:ok, doc} = Documents.soft_delete_document(doc)
    doc
  end

  # -------------------------------------------------------
  # Folders — create
  # -------------------------------------------------------

  describe "POST /api/folders" do
    test "creates a folder with valid attrs", %{conn: conn} do
      conn = post(conn, ~p"/api/folders", %{"folder" => %{"name" => "Inbox"}})
      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["name"] == "Inbox"
      assert data["deleted_at"] == nil
    end

    test "returns 422 when name is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/folders", %{"folder" => %{}})
      assert json_errors(conn, 422)["name"]
    end

    test "returns 422 when name is empty", %{conn: conn} do
      conn = post(conn, ~p"/api/folders", %{"folder" => %{"name" => ""}})
      assert json_errors(conn, 422)["name"]
    end
  end

  describe "GET /api/folders" do
    test "excludes soft-deleted folders by default", %{conn: conn} do
      keep = create_folder(%{name: "Keep"})
      gone = create_folder(%{name: "Gone"})
      soft_delete_folder!(gone)

      conn = get(conn, ~p"/api/folders")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert keep.id in ids
      refute gone.id in ids
    end
  end

  describe "GET /api/folders/:id" do
    test "returns 404 for a soft-deleted folder by default", %{conn: conn} do
      folder = create_folder()
      soft_delete_folder!(folder)
      conn = get(conn, ~p"/api/folders/#{folder.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns a soft-deleted folder when include_deleted=true", %{conn: conn} do
      folder = create_folder(%{name: "Ghost"})
      soft_delete_folder!(folder)
      conn = get(conn, ~p"/api/folders/#{folder.id}?include_deleted=true")
      data = json_data(conn)
      assert data["id"] == folder.id
      assert data["deleted_at"] != nil
    end
  end

  # -------------------------------------------------------
  # Documents — create
  # -------------------------------------------------------

  describe "POST /api/documents" do
    test "creates a document with valid attrs", %{conn: conn} do
      folder = create_folder()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "My Doc", "content" => "Hello", "folder_id" => folder.id}
        })

      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["title"] == "My Doc"
      assert data["content"] == "Hello"
      assert data["folder_id"] == folder.id
      assert data["deleted_at"] == nil
      assert data["cascaded"] == false
    end

    test "returns 422 when title is missing", %{conn: conn} do
      folder = create_folder()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"content" => "Hello", "folder_id" => folder.id}
        })

      assert json_errors(conn, 422)["title"]
    end

    test "returns 422 when content is missing", %{conn: conn} do
      folder = create_folder()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "T", "folder_id" => folder.id}
        })

      assert json_errors(conn, 422)["content"]
    end

    test "returns 422 when folder_id is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "T", "content" => "C"}
        })

      assert json_errors(conn, 422)["folder_id"]
    end
  end

  # -------------------------------------------------------
  # Documents — list & show
  # -------------------------------------------------------

  describe "GET /api/documents" do
    test "excludes soft-deleted documents by default", %{conn: conn} do
      folder = create_folder()
      keep = create_document(folder, %{title: "Keep"})
      gone = create_document(folder, %{title: "Gone"})
      soft_delete_document!(gone)

      conn = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert keep.id in ids
      refute gone.id in ids
    end

    test "returns all documents when include_deleted=true", %{conn: conn} do
      folder = create_folder()
      keep = create_document(folder, %{title: "Keep"})
      gone = create_document(folder, %{title: "Gone"})
      soft_delete_document!(gone)

      conn = get(conn, ~p"/api/documents?include_deleted=true")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert keep.id in ids
      assert gone.id in ids
    end
  end

  describe "GET /api/documents/:id" do
    test "returns 404 for a soft-deleted document by default", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      soft_delete_document!(doc)
      conn = get(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns a soft-deleted document when include_deleted=true", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      soft_delete_document!(doc)
      conn = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
      assert json_data(conn)["id"] == doc.id
      assert json_data(conn)["deleted_at"] != nil
    end
  end

  # -------------------------------------------------------
  # Documents — direct delete / restore
  # -------------------------------------------------------

  describe "DELETE /api/documents/:id (direct)" do
    test "soft-deletes and marks cascaded=false", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] != nil
      assert data["cascaded"] == false
    end

    test "returns 404 for a non-existent document", %{conn: conn} do
      conn = delete(conn, ~p"/api/documents/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 when already soft-deleted", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      soft_delete_document!(doc)
      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  describe "POST /api/documents/:id/restore (direct)" do
    test "restores a soft-deleted document", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      soft_delete_document!(doc)

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
      assert data["cascaded"] == false
    end

    test "restoring a non-deleted document is a no-op 200", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      assert conn.status == 200
      assert json_data(conn)["deleted_at"] == nil
    end

    test "returns 404 for a non-existent document", %{conn: conn} do
      conn = post(conn, ~p"/api/documents/0/restore")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # Cascading delete
  # -------------------------------------------------------

  describe "DELETE /api/folders/:id (cascade)" do
    test "soft-deletes the folder and returns it with deleted_at set", %{conn: conn} do
      folder = create_folder()
      conn = delete(conn, ~p"/api/folders/#{folder.id}")
      data = json_data(conn)
      assert data["id"] == folder.id
      assert data["deleted_at"] != nil
    end

    test "cascade soft-deletes the folder's documents with cascaded=true", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder, %{title: "Child"})

      delete(conn, ~p"/api/folders/#{folder.id}")

      # Disappears from the default document listing
      list = get(conn, ~p"/api/documents")
      refute doc.id in Enum.map(json_response(list, 200)["data"], & &1["id"])

      # But is retrievable with include_deleted and flagged as cascaded
      shown = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
      data = json_data(shown)
      assert data["deleted_at"] != nil
      assert data["cascaded"] == true
    end

    test "does not affect documents in other folders", %{conn: conn} do
      f1 = create_folder(%{name: "F1"})
      f2 = create_folder(%{name: "F2"})
      doc_in_f1 = create_document(f1, %{title: "X"})
      doc_in_f2 = create_document(f2, %{title: "Y"})

      delete(conn, ~p"/api/folders/#{f1.id}")

      list = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(list, 200)["data"], & &1["id"])
      refute doc_in_f1.id in ids
      assert doc_in_f2.id in ids
    end

    test "returns 404 when the folder is already soft-deleted", %{conn: conn} do
      folder = create_folder()
      soft_delete_folder!(folder)
      conn = delete(conn, ~p"/api/folders/#{folder.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # Cascading restore
  # -------------------------------------------------------

  describe "POST /api/folders/:id/restore (cascade)" do
    test "restores the folder and its cascade-deleted documents", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder, %{title: "Child"})

      delete(conn, ~p"/api/folders/#{folder.id}")
      restore = post(conn, ~p"/api/folders/#{folder.id}/restore")
      assert json_data(restore)["deleted_at"] == nil

      # The document is visible again with cascaded reset to false
      shown = get(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(shown)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
      assert data["cascaded"] == false
    end

    test "does not restore documents that were deleted on their own before the cascade", %{
      conn: conn
    } do
      folder = create_folder()
      own = create_document(folder, %{title: "OwnDelete"})
      cascaded = create_document(folder, %{title: "CascadeDelete"})

      # 'own' is deleted directly (cascaded = false)
      soft_delete_document!(own)
      # Then the folder is deleted, cascading to 'cascaded' only
      delete(conn, ~p"/api/folders/#{folder.id}")
      # Restoring the folder brings back only the cascade-deleted document
      post(conn, ~p"/api/folders/#{folder.id}/restore")

      shown_cascaded = get(conn, ~p"/api/documents/#{cascaded.id}?include_deleted=true")
      assert json_data(shown_cascaded)["deleted_at"] == nil

      shown_own = get(conn, ~p"/api/documents/#{own.id}?include_deleted=true")
      assert json_data(shown_own)["deleted_at"] != nil
    end

    test "restoring a non-deleted folder is a no-op 200", %{conn: conn} do
      folder = create_folder()
      conn = post(conn, ~p"/api/folders/#{folder.id}/restore")
      assert conn.status == 200
      assert json_data(conn)["deleted_at"] == nil
    end

    test "returns 404 for a non-existent folder", %{conn: conn} do
      conn = post(conn, ~p"/api/folders/0/restore")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # Full lifecycle
  # -------------------------------------------------------

  describe "full cascade lifecycle" do
    test "create folder+doc → cascade delete → invisible → cascade restore → visible", %{
      conn: conn
    } do
      fconn = post(conn, ~p"/api/folders", %{"folder" => %{"name" => "Life"}})
      folder_id = json_response(fconn, 201)["data"]["id"]

      dconn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Doc", "content" => "v1", "folder_id" => folder_id}
        })

      doc_id = json_response(dconn, 201)["data"]["id"]

      # Cascade delete
      del = delete(conn, ~p"/api/folders/#{folder_id}")
      assert json_data(del)["deleted_at"] != nil

      # Document invisible by default
      hidden = get(conn, ~p"/api/documents/#{doc_id}")
      assert hidden.status == 404

      # Cascade restore
      post(conn, ~p"/api/folders/#{folder_id}/restore")

      shown = get(conn, ~p"/api/documents/#{doc_id}")
      data = json_data(shown)
      assert data["id"] == doc_id
      assert data["deleted_at"] == nil
      assert data["cascaded"] == false
    end
  end
end
