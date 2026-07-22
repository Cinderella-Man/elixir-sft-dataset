defmodule CascadeCrudWeb.DocumentControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias CascadeCrud.Documents

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

  defp create_document(attrs \\ %{}) do
    default = %{title: "Test Doc", content: "Some content"}
    {:ok, doc} = Documents.create_document(Map.merge(default, attrs))
    doc
  end

  defp create_child(parent, attrs \\ %{}) do
    create_document(Map.merge(%{title: "Child", parent_id: parent.id}, attrs))
  end

  defp soft_delete!(doc) do
    {:ok, doc} = Documents.soft_delete_document(doc)
    doc
  end

  # -------------------------------------------------------
  # POST /api/documents  (Create)
  # -------------------------------------------------------

  describe "POST /api/documents" do
    test "creates a root document with valid attrs", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "My Doc", "content" => "Hello"}
        })

      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["title"] == "My Doc"
      assert data["content"] == "Hello"
      assert data["parent_id"] == nil
      assert data["deleted_at"] == nil
      assert data["deleted_via_cascade"] == false
      assert data["inserted_at"]
      assert data["updated_at"]
    end

    test "creates a child document referencing a parent", %{conn: conn} do
      parent = create_document(%{title: "Parent"})

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Kid", "content" => "c", "parent_id" => parent.id}
        })

      data = json_response(conn, 201)["data"]
      assert data["parent_id"] == parent.id
      assert data["deleted_via_cascade"] == false
    end

    test "returns 422 when title is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{"document" => %{"content" => "Hello"}})

      assert json_errors(conn, 422)["title"]
    end

    test "returns 422 when title is empty string", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{"document" => %{"title" => "", "content" => "Hi"}})

      assert json_errors(conn, 422)["title"]
    end

    test "returns 422 when content is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{"document" => %{"title" => "A Title"}})

      assert json_errors(conn, 422)["content"]
    end

    test "returns 422 when parent_id references a non-existent document", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Orphan", "content" => "c", "parent_id" => 999_999}
        })

      assert json_errors(conn, 422)["parent_id"]
    end

    test "returns 422 when parent_id references a soft-deleted document", %{conn: conn} do
      parent = create_document(%{title: "Doomed"})
      soft_delete!(parent)

      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Kid", "content" => "c", "parent_id" => parent.id}
        })

      assert json_errors(conn, 422)["parent_id"]
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
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert doc1.id in ids
      refute doc2.id in ids
    end

    test "returns all documents when include_deleted=true", %{conn: conn} do
      doc1 = create_document(%{title: "Visible"})
      doc2 = create_document(%{title: "Deleted"})
      soft_delete!(doc2)

      conn = get(conn, ~p"/api/documents?include_deleted=true")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert doc1.id in ids
      assert doc2.id in ids
    end
  end

  # -------------------------------------------------------
  # GET /api/documents/:id  (Show)
  # -------------------------------------------------------

  describe "GET /api/documents/:id" do
    test "returns a document by id", %{conn: conn} do
      doc = create_document(%{title: "Fetchable"})
      conn = get(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["title"] == "Fetchable"
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

    test "partial update — only title keeps content", %{conn: conn} do
      doc = create_document(%{title: "Old", content: "Keep me"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => "Updated"}})

      data = json_data(conn)
      assert data["title"] == "Updated"
      assert data["content"] == "Keep me"
    end

    test "returns 422 for invalid update (empty title)", %{conn: conn} do
      doc = create_document()

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => ""}})

      assert json_errors(conn, 422)["title"]
    end

    test "returns 404 for non-existent document", %{conn: conn} do
      conn =
        put(conn, ~p"/api/documents/0", %{"document" => %{"title" => "Nope"}})

      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "returns 404 for soft-deleted document", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{"document" => %{"title" => "Nope"}})

      assert json_errors(conn, 404)["detail"] == "Not found"
    end

    test "cannot change parent_id through update", %{conn: conn} do
      other = create_document(%{title: "Other"})
      doc = create_document(%{title: "Root"})

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "Root2", "parent_id" => other.id}
        })

      data = json_data(conn)
      assert data["parent_id"] == nil
    end

    test "cannot set deleted_at through update", %{conn: conn} do
      doc = create_document()

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{
            "title" => "Still here",
            "deleted_at" => DateTime.to_iso8601(DateTime.utc_now())
          }
        })

      data = json_data(conn)
      assert data["deleted_at"] == nil
    end
  end

  # -------------------------------------------------------
  # DELETE /api/documents/:id  (Cascading Soft Delete)
  # -------------------------------------------------------

  describe "DELETE /api/documents/:id" do
    test "soft-deletes the target with deleted_via_cascade=false", %{conn: conn} do
      doc = create_document()

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] != nil
      assert data["deleted_via_cascade"] == false
    end

    test "cascades to children, flagging them deleted_via_cascade=true", %{conn: conn} do
      root = create_document(%{title: "Root"})
      child = create_child(root)

      delete(conn, ~p"/api/documents/#{root.id}")

      conn = get(conn, ~p"/api/documents/#{child.id}?include_deleted=true")
      data = json_data(conn)
      assert data["deleted_at"] != nil
      assert data["deleted_via_cascade"] == true
    end

    test "cascades through multiple levels", %{conn: conn} do
      root = create_document(%{title: "Root"})
      child = create_child(root)
      grandchild = create_child(child, %{title: "Grand"})

      delete(conn, ~p"/api/documents/#{root.id}")

      conn_g = get(conn, ~p"/api/documents/#{grandchild.id}?include_deleted=true")
      assert json_data(conn_g)["deleted_via_cascade"] == true
    end

    test "cascade-deleted subtree disappears from default listings", %{conn: conn} do
      root = create_document(%{title: "Root"})
      child = create_child(root)

      delete(conn, ~p"/api/documents/#{root.id}")

      conn = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      refute root.id in ids
      refute child.id in ids
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
  # POST /api/documents/:id/restore  (Scoped Cascade Restore)
  # -------------------------------------------------------

  describe "POST /api/documents/:id/restore" do
    test "restores a directly soft-deleted document", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
      assert data["deleted_via_cascade"] == false
    end

    test "restoring a root brings back cascade-deleted descendants", %{conn: conn} do
      root = create_document(%{title: "Root"})
      child = create_child(root)
      grandchild = create_child(child, %{title: "Grand"})

      soft_delete!(root)
      post(conn, ~p"/api/documents/#{root.id}/restore")

      conn_c = get(conn, ~p"/api/documents/#{child.id}")
      assert json_data(conn_c)["deleted_at"] == nil
      assert json_data(conn_c)["deleted_via_cascade"] == false

      conn_g = get(conn, ~p"/api/documents/#{grandchild.id}")
      assert json_data(conn_g)["deleted_at"] == nil
      assert json_data(conn_g)["deleted_via_cascade"] == false
    end

    test "restoring a root does NOT bring back an independently-deleted branch", %{conn: conn} do
      root = create_document(%{title: "Root"})
      child = create_child(root)
      grandchild = create_child(child, %{title: "Grand"})

      # child (and its grandchild) deleted directly first
      soft_delete!(child)
      # then the root is deleted
      soft_delete!(root)

      post(conn, ~p"/api/documents/#{root.id}/restore")

      # root is back
      conn_r = get(conn, ~p"/api/documents/#{root.id}")
      assert json_data(conn_r)["deleted_at"] == nil

      # the independently-deleted child stays deleted...
      conn_c = get(conn, ~p"/api/documents/#{child.id}")
      assert json_errors(conn_c, 404)["detail"] == "Not found"

      # ...and its subtree stays deleted too
      conn_g = get(conn, ~p"/api/documents/#{grandchild.id}")
      assert json_errors(conn_g, 404)["detail"] == "Not found"
    end

    test "restoring a non-deleted document is a no-op 200", %{conn: conn} do
      doc = create_document()

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      assert conn.status == 200
      assert json_data(conn)["deleted_at"] == nil
    end

    test "returns 409 when the parent is currently soft-deleted", %{conn: conn} do
      root = create_document(%{title: "Root"})
      child = create_child(root)

      soft_delete!(root)

      conn = post(conn, ~p"/api/documents/#{child.id}/restore")
      assert json_errors(conn, 409)["detail"] == "Parent is deleted"
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
    test "create tree → cascade delete → invisible → restore → visible", %{conn: conn} do
      root = create_document(%{title: "Root", content: "v1"})
      child = create_child(root, %{title: "Child", content: "cv1"})

      # cascade delete
      conn_del = delete(conn, ~p"/api/documents/#{root.id}")
      assert json_data(conn_del)["deleted_at"] != nil

      # both invisible by default
      assert get(conn, ~p"/api/documents/#{root.id}").status == 404
      assert get(conn, ~p"/api/documents/#{child.id}").status == 404

      # child visible with flag and marked cascade
      conn_show = get(conn, ~p"/api/documents/#{child.id}?include_deleted=true")
      assert json_data(conn_show)["deleted_via_cascade"] == true

      # restore root -> child comes back too
      conn_restore = post(conn, ~p"/api/documents/#{root.id}/restore")
      assert json_data(conn_restore)["deleted_at"] == nil

      conn_child = get(conn, ~p"/api/documents/#{child.id}")
      assert json_data(conn_child)["title"] == "Child"
      assert json_data(conn_child)["deleted_via_cascade"] == false
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  describe "edge cases" do
    test "deleting one subtree doesn't affect a sibling subtree", %{conn: conn} do
      a = create_document(%{title: "A"})
      _a_child = create_child(a, %{title: "A-child"})
      b = create_document(%{title: "B"})
      b_child = create_child(b, %{title: "B-child"})

      delete(conn, ~p"/api/documents/#{a.id}")

      conn = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert b.id in ids
      assert b_child.id in ids
      refute a.id in ids
    end

    test "deleted_at timestamp is a valid ISO8601 datetime", %{conn: conn} do
      doc = create_document()
      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      deleted_at = json_data(conn)["deleted_at"]
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(deleted_at)
    end
  end
end
