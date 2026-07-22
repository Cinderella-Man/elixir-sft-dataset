defmodule SoftCrudWeb.CascadeSoftDeleteTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias SoftCrud.Library

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
  defp put(_conn, path, params), do: request(:put, path, params)
  defp delete(_conn, path), do: request(:delete, path, %{})

  defp json_response(conn, status) do
    assert conn.status == status
    Jason.decode!(conn.resp_body)
  end

  defp json_data(conn), do: json_response(conn, 200)["data"]
  defp json_errors(conn, status), do: json_response(conn, status)["errors"]

  defp create_folder(attrs \\ %{}) do
    default = %{name: "Folder"}
    {:ok, folder} = Library.create_folder(Map.merge(default, attrs))
    folder
  end

  defp create_document(folder, attrs \\ %{}) do
    default = %{title: "Doc", content: "Content"}
    {:ok, doc} = Library.create_document(folder, Map.merge(default, attrs))
    doc
  end

  defp soft_delete_folder!(folder) do
    {:ok, folder} = Library.soft_delete_folder(folder)
    folder
  end

  defp soft_delete_document!(doc) do
    {:ok, doc} = Library.soft_delete_document(doc)
    doc
  end

  # -------------------------------------------------------
  # POST /api/folders
  # -------------------------------------------------------

  describe "POST /api/folders" do
    test "creates a folder with valid attrs", %{conn: conn} do
      conn = post(conn, ~p"/api/folders", %{"folder" => %{"name" => "Reports"}})

      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["name"] == "Reports"
      assert data["deleted_at"] == nil
      assert data["inserted_at"]
      assert data["updated_at"]
    end

    test "returns 422 when name is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/folders", %{"folder" => %{}})
      assert json_errors(conn, 422)["name"]
    end

    test "returns 422 when name is empty string", %{conn: conn} do
      conn = post(conn, ~p"/api/folders", %{"folder" => %{"name" => ""}})
      assert json_errors(conn, 422)["name"]
    end
  end

  # -------------------------------------------------------
  # GET /api/folders
  # -------------------------------------------------------

  describe "GET /api/folders" do
    test "returns empty list when no folders exist", %{conn: conn} do
      conn = get(conn, ~p"/api/folders")
      assert json_response(conn, 200)["data"] == []
    end

    test "returns only non-deleted folders by default", %{conn: conn} do
      keep = create_folder(%{name: "Keep"})
      gone = create_folder(%{name: "Gone"})
      soft_delete_folder!(gone)

      conn = get(conn, ~p"/api/folders")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert keep.id in ids
      refute gone.id in ids
    end

    test "returns all folders when include_deleted=true", %{conn: conn} do
      keep = create_folder(%{name: "Keep"})
      gone = create_folder(%{name: "Gone"})
      soft_delete_folder!(gone)

      conn = get(conn, ~p"/api/folders?include_deleted=true")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert keep.id in ids
      assert gone.id in ids
    end
  end

  # -------------------------------------------------------
  # GET /api/folders/:id
  # -------------------------------------------------------

  describe "GET /api/folders/:id" do
    test "returns a folder by id", %{conn: conn} do
      folder = create_folder(%{name: "Fetchable"})
      conn = get(conn, ~p"/api/folders/#{folder.id}")
      data = json_data(conn)
      assert data["id"] == folder.id
      assert data["name"] == "Fetchable"
    end

    test "returns 404 for non-existent id", %{conn: conn} do
      conn = get(conn, ~p"/api/folders/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

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
  # DELETE /api/folders/:id
  # -------------------------------------------------------

  describe "DELETE /api/folders/:id" do
    test "soft-deletes a folder (sets deleted_at)", %{conn: conn} do
      folder = create_folder()

      conn = delete(conn, ~p"/api/folders/#{folder.id}")
      data = json_data(conn)
      assert data["id"] == folder.id
      assert data["deleted_at"] != nil
    end

    test "deleted_at is a valid ISO8601 datetime", %{conn: conn} do
      folder = create_folder()
      conn = delete(conn, ~p"/api/folders/#{folder.id}")
      assert {:ok, _dt, _off} = DateTime.from_iso8601(json_data(conn)["deleted_at"])
    end

    test "returns 404 for a non-existent folder", %{conn: conn} do
      conn = delete(conn, ~p"/api/folders/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 when deleting an already soft-deleted folder", %{conn: conn} do
      folder = create_folder()
      soft_delete_folder!(folder)

      conn = delete(conn, ~p"/api/folders/#{folder.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # POST /api/folders/:id/restore
  # -------------------------------------------------------

  describe "POST /api/folders/:id/restore" do
    test "restores a soft-deleted folder", %{conn: conn} do
      folder = create_folder()
      soft_delete_folder!(folder)

      conn = post(conn, ~p"/api/folders/#{folder.id}/restore")
      data = json_data(conn)
      assert data["id"] == folder.id
      assert data["deleted_at"] == nil
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
  # POST /api/folders/:folder_id/documents
  # -------------------------------------------------------

  describe "POST /api/folders/:folder_id/documents" do
    test "creates a document inside a folder", %{conn: conn} do
      folder = create_folder()

      conn =
        post(conn, ~p"/api/folders/#{folder.id}/documents", %{
          "document" => %{"title" => "My Doc", "content" => "Hello"}
        })

      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["folder_id"] == folder.id
      assert data["title"] == "My Doc"
      assert data["content"] == "Hello"
      assert data["deleted_at"] == nil
      assert data["inserted_at"]
      assert data["updated_at"]
    end

    test "returns 422 when title is missing", %{conn: conn} do
      folder = create_folder()

      conn =
        post(conn, ~p"/api/folders/#{folder.id}/documents", %{
          "document" => %{"content" => "Hello"}
        })

      assert json_errors(conn, 422)["title"]
    end

    test "returns 422 when title is empty string", %{conn: conn} do
      folder = create_folder()

      conn =
        post(conn, ~p"/api/folders/#{folder.id}/documents", %{
          "document" => %{"title" => "", "content" => "Hello"}
        })

      assert json_errors(conn, 422)["title"]
    end

    test "returns 422 when content is missing", %{conn: conn} do
      folder = create_folder()

      conn =
        post(conn, ~p"/api/folders/#{folder.id}/documents", %{
          "document" => %{"title" => "A Title"}
        })

      assert json_errors(conn, 422)["content"]
    end

    test "returns 404 when the folder does not exist", %{conn: conn} do
      conn =
        post(conn, ~p"/api/folders/0/documents", %{
          "document" => %{"title" => "X", "content" => "Y"}
        })

      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 when the folder is soft-deleted", %{conn: conn} do
      folder = create_folder()
      soft_delete_folder!(folder)

      conn =
        post(conn, ~p"/api/folders/#{folder.id}/documents", %{
          "document" => %{"title" => "X", "content" => "Y"}
        })

      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # GET /api/folders/:folder_id/documents
  # -------------------------------------------------------

  describe "GET /api/folders/:folder_id/documents" do
    test "lists non-deleted documents in the folder by default", %{conn: conn} do
      folder = create_folder()
      a = create_document(folder, %{title: "A"})
      b = create_document(folder, %{title: "B"})
      soft_delete_document!(b)

      conn = get(conn, ~p"/api/folders/#{folder.id}/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert a.id in ids
      refute b.id in ids
    end

    test "lists all documents when include_deleted=true", %{conn: conn} do
      folder = create_folder()
      a = create_document(folder, %{title: "A"})
      b = create_document(folder, %{title: "B"})
      soft_delete_document!(b)

      conn = get(conn, ~p"/api/folders/#{folder.id}/documents?include_deleted=true")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert a.id in ids
      assert b.id in ids
    end

    test "returns 404 when the folder does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/folders/0/documents")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 when the folder is soft-deleted", %{conn: conn} do
      folder = create_folder()
      soft_delete_folder!(folder)

      conn = get(conn, ~p"/api/folders/#{folder.id}/documents")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # GET /api/documents/:id
  # -------------------------------------------------------

  describe "GET /api/documents/:id" do
    test "returns a document by id", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder, %{title: "Fetchable"})

      conn = get(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["title"] == "Fetchable"
      assert data["folder_id"] == folder.id
    end

    test "returns 404 for a non-existent id", %{conn: conn} do
      conn = get(conn, ~p"/api/documents/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 for a soft-deleted document by default", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      soft_delete_document!(doc)

      conn = get(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns a soft-deleted document when include_deleted=true", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder, %{title: "Ghost"})
      soft_delete_document!(doc)

      conn = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] != nil
    end
  end

  # -------------------------------------------------------
  # PUT /api/documents/:id
  # -------------------------------------------------------

  describe "PUT /api/documents/:id" do
    test "updates title and content", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder, %{title: "Old", content: "Old content"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "New", "content" => "New content"}
        })

      data = json_data(conn)
      assert data["title"] == "New"
      assert data["content"] == "New content"
    end

    test "partial update — only title", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder, %{title: "Old", content: "Keep me"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => "Updated"}})

      data = json_data(conn)
      assert data["title"] == "Updated"
      assert data["content"] == "Keep me"
    end

    test "returns 422 for an empty title", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)

      conn = put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => ""}})
      assert json_errors(conn, 422)["title"]
    end

    test "returns 404 for a non-existent document", %{conn: conn} do
      conn = put(conn, ~p"/api/documents/0", %{"document" => %{"title" => "Nope"}})
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 for a soft-deleted document", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      soft_delete_document!(doc)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => "No"}})

      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "cannot set deleted_at through update", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"deleted_at" => DateTime.to_iso8601(DateTime.utc_now())}
        })

      assert json_data(conn)["deleted_at"] == nil
    end
  end

  # -------------------------------------------------------
  # DELETE /api/documents/:id  (independent single delete)
  # -------------------------------------------------------

  describe "DELETE /api/documents/:id" do
    test "soft-deletes a single document", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] != nil
    end

    test "soft-deleted document disappears from default listings", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)

      delete(conn, ~p"/api/documents/#{doc.id}")

      conn = get(conn, ~p"/api/folders/#{folder.id}/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      refute doc.id in ids
    end

    test "returns 404 for a non-existent document", %{conn: conn} do
      conn = delete(conn, ~p"/api/documents/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 when deleting an already soft-deleted document", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      soft_delete_document!(doc)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # POST /api/documents/:id/restore
  # -------------------------------------------------------

  describe "POST /api/documents/:id/restore" do
    test "restores a soft-deleted document", %{conn: conn} do
      folder = create_folder()
      doc = create_document(folder)
      soft_delete_document!(doc)

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
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
  # Cascade delete / selective restore
  # -------------------------------------------------------

  describe "cascade delete" do
    test "soft-deleting a folder soft-deletes its documents", %{conn: conn} do
      folder = create_folder()
      a = create_document(folder, %{title: "A"})
      b = create_document(folder, %{title: "B"})

      del = delete(conn, ~p"/api/folders/#{folder.id}")
      assert json_data(del)["deleted_at"] != nil

      # Both documents are now hidden by default.
      assert get(conn, ~p"/api/documents/#{a.id}").status == 404
      assert get(conn, ~p"/api/documents/#{b.id}").status == 404

      # But visible (with a deleted_at) via include_deleted.
      da = json_data(get(conn, ~p"/api/documents/#{a.id}?include_deleted=true"))
      db = json_data(get(conn, ~p"/api/documents/#{b.id}?include_deleted=true"))
      assert da["deleted_at"] != nil
      assert db["deleted_at"] != nil
    end
  end

  describe "selective restore" do
    test "restoring a folder restores its cascade-deleted documents", %{conn: conn} do
      folder = create_folder()
      a = create_document(folder, %{title: "A"})
      b = create_document(folder, %{title: "B"})

      delete(conn, ~p"/api/folders/#{folder.id}")
      post(conn, ~p"/api/folders/#{folder.id}/restore")

      da = json_data(get(conn, ~p"/api/documents/#{a.id}"))
      db = json_data(get(conn, ~p"/api/documents/#{b.id}"))
      assert da["id"] == a.id
      assert da["deleted_at"] == nil
      assert db["id"] == b.id
      assert db["deleted_at"] == nil

      # Nested listing shows both again.
      ids =
        conn
        |> get(~p"/api/folders/#{folder.id}/documents")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert a.id in ids
      assert b.id in ids
    end

    test "independently deleted document stays deleted after folder restore", %{conn: conn} do
      folder = create_folder()
      a = create_document(folder, %{title: "Independent"})
      b = create_document(folder, %{title: "Cascaded"})

      # Delete A on its own, before the folder cascade.
      delete(conn, ~p"/api/documents/#{a.id}")

      # Now cascade-delete the folder (touches B, leaves A as-is).
      delete(conn, ~p"/api/folders/#{folder.id}")

      # Restore the folder.
      post(conn, ~p"/api/folders/#{folder.id}/restore")

      # B was restored by the cascade.
      assert get(conn, ~p"/api/documents/#{b.id}").status == 200
      assert json_data(get(conn, ~p"/api/documents/#{b.id}"))["deleted_at"] == nil

      # A was NOT resurrected — it stays soft-deleted.
      assert get(conn, ~p"/api/documents/#{a.id}").status == 404
      da = json_data(get(conn, ~p"/api/documents/#{a.id}?include_deleted=true"))
      assert da["deleted_at"] != nil
    end
  end

  # -------------------------------------------------------
  # Round-trip lifecycle
  # -------------------------------------------------------

  describe "full lifecycle" do
    test "create folder → add doc → cascade delete → invisible → restore → visible", %{conn: conn} do
      folder =
        conn
        |> post(~p"/api/folders", %{"folder" => %{"name" => "Lifecycle"}})
        |> json_response(201)
        |> Map.fetch!("data")

      fid = folder["id"]
      assert fid

      doc =
        conn
        |> post(~p"/api/folders/#{fid}/documents", %{
          "document" => %{"title" => "Item", "content" => "v1"}
        })
        |> json_response(201)
        |> Map.fetch!("data")

      did = doc["id"]

      # Cascade delete
      assert json_data(delete(conn, ~p"/api/folders/#{fid}"))["deleted_at"] != nil

      # Document invisible by default
      assert get(conn, ~p"/api/documents/#{did}").status == 404

      # Restore folder → document visible again
      assert json_data(post(conn, ~p"/api/folders/#{fid}/restore"))["deleted_at"] == nil
      shown = json_data(get(conn, ~p"/api/documents/#{did}"))
      assert shown["id"] == did
      assert shown["deleted_at"] == nil
      assert shown["content"] == "v1"
    end
  end
end
