defmodule SoftCrudWeb.CascadeSoftDeleteTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias SoftCrud.Library

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SoftCrud.Repo)
    %{conn: conn(:get, "/")}
  end

  # -------------------------------------------------------
  # Helpers (Plug.Test replacements for Phoenix.ConnTest)
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

  defp create_folder!(attrs \\ %{}) do
    {:ok, folder} = Library.create_folder(Map.merge(%{name: "Folder"}, attrs))
    folder
  end

  defp create_document!(folder, attrs \\ %{}) do
    default = %{title: "Doc", content: "Body", folder_id: folder.id}
    {:ok, doc} = Library.create_document(Map.merge(default, attrs))
    doc
  end

  defp soft_delete_doc!(doc) do
    {:ok, doc} = Library.soft_delete_document(doc)
    doc
  end

  defp doc_ids(conn) do
    conn
    |> json_response(200)
    |> Map.fetch!("data")
    |> Enum.map(& &1["id"])
  end

  # -------------------------------------------------------
  # POST /api/folders
  # -------------------------------------------------------

  describe "POST /api/folders" do
    test "creates a folder with valid attrs", %{conn: conn} do
      conn = post(conn, ~p"/api/folders", %{"folder" => %{"name" => "Work"}})
      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["name"] == "Work"
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
  # GET /api/folders and /api/folders/:id
  # -------------------------------------------------------

  describe "reading folders" do
    test "lists only non-deleted folders by default", %{conn: conn} do
      keep = create_folder!(%{name: "Keep"})
      gone = create_folder!(%{name: "Gone"})
      {:ok, _} = Library.soft_delete_folder(gone)

      ids = doc_ids(get(conn, ~p"/api/folders"))
      assert keep.id in ids
      refute gone.id in ids
    end

    test "lists all folders with include_deleted=true", %{conn: conn} do
      keep = create_folder!(%{name: "Keep"})
      gone = create_folder!(%{name: "Gone"})
      {:ok, _} = Library.soft_delete_folder(gone)

      ids = doc_ids(get(conn, ~p"/api/folders?include_deleted=true"))
      assert keep.id in ids
      assert gone.id in ids
    end

    test "shows a folder by id", %{conn: conn} do
      folder = create_folder!(%{name: "Findable"})
      data = json_data(get(conn, ~p"/api/folders/#{folder.id}"))
      assert data["id"] == folder.id
      assert data["name"] == "Findable"
    end

    test "returns 404 for a non-existent folder", %{conn: conn} do
      assert json_errors(get(conn, ~p"/api/folders/0"), 404)["detail"] == "Not found"
    end

    test "returns 404 for a soft-deleted folder by default", %{conn: conn} do
      folder = create_folder!()
      {:ok, _} = Library.soft_delete_folder(folder)
      assert json_errors(get(conn, ~p"/api/folders/#{folder.id}"), 404)["detail"] == "Not found"
    end

    test "shows a soft-deleted folder with include_deleted=true", %{conn: conn} do
      folder = create_folder!()
      {:ok, _} = Library.soft_delete_folder(folder)
      data = json_data(get(conn, ~p"/api/folders/#{folder.id}?include_deleted=true"))
      assert data["id"] == folder.id
      assert data["deleted_at"] != nil
    end
  end

  # -------------------------------------------------------
  # POST /api/documents
  # -------------------------------------------------------

  describe "POST /api/documents" do
    test "creates a document with valid attrs", %{conn: conn} do
      folder = create_folder!()

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
      assert data["deleted_via_cascade"] == false
      assert data["inserted_at"]
      assert data["updated_at"]
    end

    test "returns 422 when title is missing", %{conn: conn} do
      folder = create_folder!()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"content" => "Hello", "folder_id" => folder.id}
        })

      assert json_errors(conn, 422)["title"]
    end

    test "returns 422 when title is empty", %{conn: conn} do
      folder = create_folder!()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "", "content" => "Hello", "folder_id" => folder.id}
        })

      assert json_errors(conn, 422)["title"]
    end

    test "returns 422 when content is missing", %{conn: conn} do
      folder = create_folder!()

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "T", "folder_id" => folder.id}
        })

      assert json_errors(conn, 422)["content"]
    end

    test "returns 422 when folder_id is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "T", "content" => "Hello"}
        })

      assert json_errors(conn, 422)["folder_id"]
    end
  end

  # -------------------------------------------------------
  # GET /api/documents and /api/documents/:id
  # -------------------------------------------------------

  describe "reading documents" do
    test "lists only non-deleted documents by default", %{conn: conn} do
      folder = create_folder!()
      keep = create_document!(folder, %{title: "Keep"})
      gone = create_document!(folder, %{title: "Gone"})
      soft_delete_doc!(gone)

      ids = doc_ids(get(conn, ~p"/api/documents"))
      assert keep.id in ids
      refute gone.id in ids
    end

    test "lists all documents with include_deleted=true", %{conn: conn} do
      folder = create_folder!()
      keep = create_document!(folder, %{title: "Keep"})
      gone = create_document!(folder, %{title: "Gone"})
      soft_delete_doc!(gone)

      ids = doc_ids(get(conn, ~p"/api/documents?include_deleted=true"))
      assert keep.id in ids
      assert gone.id in ids
    end

    test "returns 404 for a soft-deleted document by default", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      soft_delete_doc!(doc)
      assert json_errors(get(conn, ~p"/api/documents/#{doc.id}"), 404)["detail"] == "Not found"
    end

    test "shows a soft-deleted document with include_deleted=true", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder, %{title: "Ghost"})
      soft_delete_doc!(doc)

      data = json_data(get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true"))
      assert data["id"] == doc.id
      assert data["title"] == "Ghost"
      assert data["deleted_at"] != nil
    end
  end

  # -------------------------------------------------------
  # PUT /api/documents/:id
  # -------------------------------------------------------

  describe "PUT /api/documents/:id" do
    test "updates title and content", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder, %{title: "Old", content: "Old body"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "New", "content" => "New body"}
        })

      data = json_data(conn)
      assert data["title"] == "New"
      assert data["content"] == "New body"
    end

    test "partial update keeps existing content when only title is sent", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder, %{title: "Old", content: "Keep me"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => "Updated"}})

      data = json_data(conn)
      assert data["title"] == "Updated"
      assert data["content"] == "Keep me"
    end

    test "returns 422 for empty title", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)

      conn = put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => ""}})
      assert json_errors(conn, 422)["title"]
    end

    test "returns 404 for a soft-deleted document", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      soft_delete_doc!(doc)

      conn = put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => "Nope"}})
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "cannot change folder_id or deleted_via_cascade through update", %{conn: conn} do
      folder = create_folder!(%{name: "Home"})
      other = create_folder!(%{name: "Other"})
      doc = create_document!(folder)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{
            "title" => "Renamed",
            "folder_id" => other.id,
            "deleted_via_cascade" => true
          }
        })

      data = json_data(conn)
      assert data["title"] == "Renamed"
      assert data["folder_id"] == folder.id
      assert data["deleted_via_cascade"] == false
    end
  end

  # -------------------------------------------------------
  # DELETE /api/documents/:id  (independent soft delete)
  # -------------------------------------------------------

  describe "DELETE /api/documents/:id" do
    test "independent delete sets deleted_at and leaves deleted_via_cascade false", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] != nil
      assert data["deleted_via_cascade"] == false
    end

    test "returns 404 when deleting an already soft-deleted document", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      soft_delete_doc!(doc)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # DELETE /api/folders/:id  (cascading soft delete)
  # -------------------------------------------------------

  describe "DELETE /api/folders/:id (cascade)" do
    test "cascades the soft delete to all live documents", %{conn: conn} do
      folder = create_folder!()
      d1 = create_document!(folder, %{title: "A"})
      d2 = create_document!(folder, %{title: "B"})

      del = delete(conn, ~p"/api/folders/#{folder.id}")
      assert json_data(del)["deleted_at"] != nil

      # both documents disappear from default listing
      ids = doc_ids(get(conn, ~p"/api/documents"))
      refute d1.id in ids
      refute d2.id in ids

      # both are flagged as cascade-deleted
      for id <- [d1.id, d2.id] do
        data = json_data(get(conn, ~p"/api/documents/#{id}?include_deleted=true"))
        assert data["deleted_at"] != nil
        assert data["deleted_via_cascade"] == true
      end
    end

    test "does not touch documents that were already soft-deleted", %{conn: conn} do
      folder = create_folder!()
      indep = create_document!(folder, %{title: "Indep"})
      soft_delete_doc!(indep)

      delete(conn, ~p"/api/folders/#{folder.id}")

      data = json_data(get(conn, ~p"/api/documents/#{indep.id}?include_deleted=true"))
      assert data["deleted_at"] != nil
      assert data["deleted_via_cascade"] == false
    end

    test "returns 404 when the folder is already soft-deleted", %{conn: conn} do
      folder = create_folder!()
      {:ok, _} = Library.soft_delete_folder(folder)

      conn = delete(conn, ~p"/api/folders/#{folder.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 for a non-existent folder", %{conn: conn} do
      assert json_errors(delete(conn, ~p"/api/folders/0"), 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # POST /api/folders/:id/restore  (cascading restore)
  # -------------------------------------------------------

  describe "POST /api/folders/:id/restore (cascade)" do
    test "restores the folder and its cascade-deleted documents", %{conn: conn} do
      folder = create_folder!()
      d1 = create_document!(folder, %{title: "A"})
      d2 = create_document!(folder, %{title: "B"})

      delete(conn, ~p"/api/folders/#{folder.id}")
      restore = post(conn, ~p"/api/folders/#{folder.id}/restore")
      assert json_data(restore)["deleted_at"] == nil

      ids = doc_ids(get(conn, ~p"/api/documents"))
      assert d1.id in ids
      assert d2.id in ids

      data = json_data(get(conn, ~p"/api/documents/#{d1.id}"))
      assert data["deleted_at"] == nil
      assert data["deleted_via_cascade"] == false
    end

    test "restores only cascade-deleted documents, not independently deleted ones", %{conn: conn} do
      folder = create_folder!()
      indep = create_document!(folder, %{title: "Indep"})
      live = create_document!(folder, %{title: "Live"})

      # delete one on its own, then cascade-delete the folder
      soft_delete_doc!(indep)
      delete(conn, ~p"/api/folders/#{folder.id}")

      # restoring the folder brings back only the cascade-deleted doc
      post(conn, ~p"/api/folders/#{folder.id}/restore")

      ids = doc_ids(get(conn, ~p"/api/documents"))
      assert live.id in ids
      refute indep.id in ids

      indep_data = json_data(get(conn, ~p"/api/documents/#{indep.id}?include_deleted=true"))
      assert indep_data["deleted_at"] != nil
      assert indep_data["deleted_via_cascade"] == false
    end

    test "restoring a non-deleted folder is a no-op 200", %{conn: conn} do
      folder = create_folder!()
      conn = post(conn, ~p"/api/folders/#{folder.id}/restore")
      assert conn.status == 200
      assert json_data(conn)["deleted_at"] == nil
    end

    test "returns 404 for a non-existent folder", %{conn: conn} do
      assert json_errors(post(conn, ~p"/api/folders/0/restore"), 404)["detail"] == "Not found"
    end
  end

  # -------------------------------------------------------
  # POST /api/documents/:id/restore
  # -------------------------------------------------------

  describe "POST /api/documents/:id/restore" do
    test "restores a soft-deleted document", %{conn: conn} do
      folder = create_folder!()
      doc = create_document!(folder)
      soft_delete_doc!(doc)

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
      assert data["deleted_via_cascade"] == false
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
  # Full lifecycle
  # -------------------------------------------------------

  describe "full lifecycle" do
    test "folder + documents: cascade delete → invisible → cascade restore → visible", %{
      conn: conn
    } do
      folder = create_folder!(%{name: "Project"})
      d1 = create_document!(folder, %{title: "One", content: "v1"})
      d2 = create_document!(folder, %{title: "Two", content: "v1"})

      # cascade delete
      del = delete(conn, ~p"/api/folders/#{folder.id}")
      assert json_data(del)["deleted_at"] != nil

      # folder and documents invisible by default
      assert get(conn, ~p"/api/folders/#{folder.id}").status == 404
      assert get(conn, ~p"/api/documents/#{d1.id}").status == 404
      assert get(conn, ~p"/api/documents/#{d2.id}").status == 404

      # documents flagged cascade
      ghost = json_data(get(conn, ~p"/api/documents/#{d1.id}?include_deleted=true"))
      assert ghost["deleted_via_cascade"] == true

      # cascade restore
      restore = post(conn, ~p"/api/folders/#{folder.id}/restore")
      assert json_data(restore)["deleted_at"] == nil

      # everything visible again
      assert json_data(get(conn, ~p"/api/folders/#{folder.id}"))["name"] == "Project"
      ids = doc_ids(get(conn, ~p"/api/documents"))
      assert d1.id in ids
      assert d2.id in ids
    end
  end
end
