defmodule CascadeCrudWeb.CascadeControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias CascadeCrud.Content

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(CascadeCrud.Repo)
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
    |> CascadeCrudWeb.Router.call(CascadeCrudWeb.Router.init([]))
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

  defp create_folder!(attrs \\ %{}) do
    {:ok, folder} = Content.create_folder(Map.merge(%{name: "Folder"}, attrs))
    folder
  end

  defp create_document!(folder, attrs \\ %{}) do
    default = %{title: "Doc", content: "Body", folder_id: folder.id}
    {:ok, doc} = Content.create_document(Map.merge(default, attrs))
    doc
  end

  defp direct_delete!(doc) do
    {:ok, doc} = Content.soft_delete_document(doc)
    doc
  end

  # -------------------------------------------------------
  # Folders — Create
  # -------------------------------------------------------

  describe "POST /api/folders" do
    test "creates a folder with a valid name", %{conn: conn} do
      conn = post(conn, ~p"/api/folders", %{"folder" => %{"name" => "Inbox"}})
      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["name"] == "Inbox"
      assert data["deleted_at"] == nil
      assert data["inserted_at"]
      assert data["updated_at"]
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

  # -------------------------------------------------------
  # Folders — Index / Show
  # -------------------------------------------------------

  describe "GET /api/folders" do
    test "returns only non-deleted folders by default", %{conn: conn} do
      keep = create_folder!(%{name: "Keep"})
      gone = create_folder!(%{name: "Gone"})
      {:ok, _} = Content.soft_delete_folder(gone)

      conn = get(conn, ~p"/api/folders")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert keep.id in ids
      refute gone.id in ids
    end

    test "returns all folders when include_deleted=true", %{conn: conn} do
      keep = create_folder!(%{name: "Keep"})
      gone = create_folder!(%{name: "Gone"})
      {:ok, _} = Content.soft_delete_folder(gone)

      conn = get(conn, ~p"/api/folders?include_deleted=true")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert keep.id in ids
      assert gone.id in ids
    end
  end

  describe "GET /api/folders/:id" do
    test "shows a folder by id", %{conn: conn} do
      folder = create_folder!(%{name: "Shown"})
      conn = get(conn, ~p"/api/folders/#{folder.id}")
      assert json_data(conn)["name"] == "Shown"
    end

    test "returns 404 for a missing folder", %{conn: conn} do
      conn = get(conn, ~p"/api/folders/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 for a soft-deleted folder by default", %{conn: conn} do
      folder = create_folder!()
      {:ok, _} = Content.soft_delete_folder(folder)
      conn = get(conn, ~p"/api/folders/#{folder.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns a soft-deleted folder with include_deleted=true", %{conn: conn} do
      folder = create_folder!()
      {:ok, _} = Content.soft_delete_folder(folder)
      conn = get(conn, ~p"/api/folders/#{folder.id}?include_deleted=true")
      data = json_data(conn)
      assert data["id"] == folder.id
      assert data["deleted_at"] != nil
    end
  end

  # -------------------------------------------------------
  # Folders — Delete / Restore basics
  # -------------------------------------------------------

  describe "DELETE /api/folders/:id" do
    test "soft-deletes a folder", %{conn: conn} do
      folder = create_folder!()
      conn = delete(conn, ~p"/api/folders/#{folder.id}")
      data = json_data(conn)
      assert data["id"] == folder.id
      assert data["deleted_at"] != nil
    end

    test "returns 404 for a missing folder", %{conn: conn} do
      conn = delete(conn, ~p"/api/folders/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 when deleting an already soft-deleted folder", %{conn: conn} do
      folder = create_folder!()
      {:ok, _} = Content.soft_delete_folder(folder)
      conn = delete(conn, ~p"/api/folders/#{folder.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  describe "POST /api/folders/:id/restore" do
    test "restores a soft-deleted folder", %{conn: conn} do
      folder = create_folder!()
      {:ok, _} = Content.soft_delete_folder(folder)
      conn = post(conn, ~p"/api/folders/#{folder.id}/restore")
      assert json_data(conn)["deleted_at"] == nil
    end

    test "restoring a non-deleted folder is a no-op 200", %{conn: conn} do
      folder = create_folder!()
      conn = post(conn, ~p"/api/folders/#{folder.id}/restore")
      assert conn.status == 200
      assert json_data(conn)["deleted_at"] == nil
    end

    test "returns 404 for a missing folder", %{conn: conn} do
      conn = post(conn, ~p"/api/folders/0/restore")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # Documents — Create
  # -------------------------------------------------------

  describe "POST /api/documents" do
    test "creates a document inside a folder", %{conn: conn} do
      folder = create_folder!()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Notes", "content" => "Hi", "folder_id" => folder.id}
        })

      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["title"] == "Notes"
      assert data["content"] == "Hi"
      assert data["folder_id"] == folder.id
      assert data["deleted_at"] == nil
      assert data["deleted_cascade"] == false
    end

    test "returns 422 when title is missing", %{conn: conn} do
      folder = create_folder!()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"content" => "Hi", "folder_id" => folder.id}
        })

      assert json_errors(conn, 422)["title"]
    end

    test "returns 422 when content is missing", %{conn: conn} do
      folder = create_folder!()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Notes", "folder_id" => folder.id}
        })

      assert json_errors(conn, 422)["content"]
    end

    test "returns 422 when folder_id is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Notes", "content" => "Hi"}
        })

      assert json_errors(conn, 422)["folder_id"]
    end

    test "returns 422 when folder_id references a non-existent folder", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Notes", "content" => "Hi", "folder_id" => 999_999}
        })

      assert json_errors(conn, 422)["folder_id"]
    end
  end

  # -------------------------------------------------------
  # Documents — Index / Show / Update
  # -------------------------------------------------------

  describe "GET /api/documents" do
    test "returns only non-deleted documents by default", %{conn: conn} do
      folder = create_folder!()
      keep = create_document!(folder, %{title: "Keep"})
      gone = create_document!(folder, %{title: "Gone"})
      direct_delete!(gone)

      conn = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert keep.id in ids
      refute gone.id in ids
    end

    test "returns all documents when include_deleted=true", %{conn: conn} do
      folder = create_folder!()
      gone = create_document!(folder)
      direct_delete!(gone)

      conn = get(conn, ~p"/api/documents?include_deleted=true")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert gone.id in ids
    end

    test "filters by folder_id", %{conn: conn} do
      folder_a = create_folder!(%{name: "A"})
      folder_b = create_folder!(%{name: "B"})
      doc_a = create_document!(folder_a)
      doc_b = create_document!(folder_b)

      conn = get(conn, ~p"/api/documents?folder_id=#{folder_a.id}")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert doc_a.id in ids
      refute doc_b.id in ids
    end
  end

  describe "GET /api/documents/:id" do
    test "returns 404 for a soft-deleted document by default", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      direct_delete!(doc)
      conn = get(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns a soft-deleted document with include_deleted=true", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      direct_delete!(doc)
      conn = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] != nil
    end
  end

  describe "PUT /api/documents/:id" do
    test "updates title and content", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder, %{title: "Old", content: "Old"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "New", "content" => "New body"}
        })

      data = json_data(conn)
      assert data["title"] == "New"
      assert data["content"] == "New body"
    end

    test "ignores deleted_at supplied through update", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{
            "title" => "T",
            "content" => "C",
            "deleted_at" => DateTime.to_iso8601(DateTime.utc_now())
          }
        })

      assert json_data(conn)["deleted_at"] == nil
    end

    test "ignores folder_id supplied through update", %{conn: conn} do
      folder_a = create_folder!(%{name: "A"})
      folder_b = create_folder!(%{name: "B"})
      doc = create_document!(folder_a)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "T", "content" => "C", "folder_id" => folder_b.id}
        })

      assert json_data(conn)["folder_id"] == folder_a.id
    end

    test "returns 404 for a soft-deleted document", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      direct_delete!(doc)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "X", "content" => "Y"}
        })

      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # Documents — direct delete / restore
  # -------------------------------------------------------

  describe "DELETE /api/documents/:id" do
    test "directly soft-deletes with deleted_cascade false", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["deleted_at"] != nil
      assert data["deleted_cascade"] == false
    end

    test "returns 404 when already soft-deleted", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      direct_delete!(doc)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  describe "POST /api/documents/:id/restore" do
    test "restores a soft-deleted document", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      direct_delete!(doc)

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      data = json_data(conn)
      assert data["deleted_at"] == nil
      assert data["deleted_cascade"] == false
    end

    test "restoring a non-deleted document is a no-op 200", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      assert conn.status == 200
      assert json_data(conn)["deleted_at"] == nil
    end
  end

  # -------------------------------------------------------
  # Cascade semantics
  # -------------------------------------------------------

  describe "cascading folder delete" do
    test "deleting a folder soft-deletes its documents with deleted_cascade true", %{conn: conn} do
      folder = create_folder!()
      doc1 = create_document!(folder, %{title: "One"})
      doc2 = create_document!(folder, %{title: "Two"})

      delete(conn, ~p"/api/folders/#{folder.id}")

      # both documents disappear from the default listing
      list = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(list, 200)["data"], & &1["id"])
      refute doc1.id in ids
      refute doc2.id in ids

      # each is now soft-deleted and marked as a cascade deletion
      for doc <- [doc1, doc2] do
        shown = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
        data = json_data(shown)
        assert data["deleted_at"] != nil
        assert data["deleted_cascade"] == true
      end
    end

    test "cascade does not touch documents in other folders", %{conn: conn} do
      folder_a = create_folder!(%{name: "A"})
      folder_b = create_folder!(%{name: "B"})
      doc_a = create_document!(folder_a)
      doc_b = create_document!(folder_b)

      delete(conn, ~p"/api/folders/#{folder_a.id}")

      shown_a = get(conn, ~p"/api/documents/#{doc_a.id}?include_deleted=true")
      assert json_data(shown_a)["deleted_at"] != nil

      shown_b = get(conn, ~p"/api/documents/#{doc_b.id}")
      assert json_data(shown_b)["deleted_at"] == nil
    end
  end

  describe "cascading folder restore" do
    test "restoring a folder restores its cascade-deleted documents", %{conn: conn} do
      folder = create_folder!()
      doc1 = create_document!(folder, %{title: "One"})
      doc2 = create_document!(folder, %{title: "Two"})

      delete(conn, ~p"/api/folders/#{folder.id}")
      post(conn, ~p"/api/folders/#{folder.id}/restore")

      list = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(list, 200)["data"], & &1["id"])
      assert doc1.id in ids
      assert doc2.id in ids

      for doc <- [doc1, doc2] do
        shown = get(conn, ~p"/api/documents/#{doc.id}")
        data = json_data(shown)
        assert data["deleted_at"] == nil
        assert data["deleted_cascade"] == false
      end
    end

    test "a directly-deleted document is NOT revived by restoring its folder", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)

      # delete the document directly first (deleted_cascade stays false)
      direct_delete!(doc)

      # then delete and restore the folder
      delete(conn, ~p"/api/folders/#{folder.id}")
      post(conn, ~p"/api/folders/#{folder.id}/restore")

      # the document is still soft-deleted, still not a cascade deletion
      shown = get(conn, ~p"/api/documents/#{doc.id}")
      assert shown.status == 404

      with_flag = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
      data = json_data(with_flag)
      assert data["deleted_at"] != nil
      assert data["deleted_cascade"] == false
    end

    test "cascade delete leaves an already-deleted document's cascade flag false", %{conn: conn} do
      folder = create_folder!()
      already = create_document!(folder, %{title: "Already"})
      fresh = create_document!(folder, %{title: "Fresh"})

      direct_delete!(already)
      delete(conn, ~p"/api/folders/#{folder.id}")

      already_shown = get(conn, ~p"/api/documents/#{already.id}?include_deleted=true")
      assert json_data(already_shown)["deleted_cascade"] == false

      fresh_shown = get(conn, ~p"/api/documents/#{fresh.id}?include_deleted=true")
      assert json_data(fresh_shown)["deleted_cascade"] == true
    end
  end

  # -------------------------------------------------------
  # Full lifecycle
  # -------------------------------------------------------

  describe "full lifecycle" do
    test "folder + doc: cascade delete → invisible → cascade restore → visible", %{conn: conn} do
      folder = create_folder!(%{name: "Project"})
      doc = create_document!(folder, %{title: "Spec", content: "v1"})

      # cascade delete
      conn_del = delete(conn, ~p"/api/folders/#{folder.id}")
      assert json_data(conn_del)["deleted_at"] != nil

      # document is invisible by default
      assert get(conn, ~p"/api/documents/#{doc.id}").status == 404

      # visible with flag and marked as a cascade deletion
      with_flag = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
      assert json_data(with_flag)["deleted_cascade"] == true

      # restore folder → document comes back
      post(conn, ~p"/api/folders/#{folder.id}/restore")
      restored = get(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(restored)
      assert data["title"] == "Spec"
      assert data["deleted_cascade"] == false
    end
  end
end
