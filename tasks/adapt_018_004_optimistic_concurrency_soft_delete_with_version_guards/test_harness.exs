defmodule SoftCrud.DocumentsTest do
  use ExUnit.Case, async: false

  alias SoftCrud.Documents

  setup do
    {:ok, srv} = Documents.start_link()
    {:ok, srv: srv}
  end

  defp create(srv, attrs \\ %{}) do
    {:ok, doc} = Documents.create_document(srv, Map.merge(%{title: "T", content: "C"}, attrs))
    doc
  end

  describe "create_document/2" do
    test "creates with version 0", %{srv: srv} do
      {:ok, doc} = Documents.create_document(srv, %{title: "A", content: "B"})
      assert doc.lock_version == 0
      assert doc.deleted_at == nil
    end

    test "rejects blank fields", %{srv: srv} do
      assert {:error, e} = Documents.create_document(srv, %{title: "", content: "B"})
      assert e[:title]
    end
  end

  describe "get/list visibility" do
    test "hides soft-deleted by default", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)
      assert {:ok, _} = Documents.get_document(srv, doc.id, include_deleted: true)
    end

    test "list excludes deleted by default", %{srv: srv} do
      a = create(srv, %{title: "keep"})
      b = create(srv, %{title: "gone"})
      {:ok, _} = Documents.soft_delete_document(srv, b.id, 0)
      ids = Documents.list_documents(srv) |> Enum.map(& &1.id)
      assert a.id in ids
      refute b.id in ids
    end
  end

  describe "update_document/4 with version guard" do
    test "succeeds with matching version and bumps it", %{srv: srv} do
      doc = create(srv, %{title: "old"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "new"}, 0)
      assert up.title == "new"
      assert up.lock_version == 1
    end

    test "partial update keeps other field", %{srv: srv} do
      doc = create(srv, %{title: "old", content: "keep"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "new"}, 0)
      assert up.content == "keep"
    end

    test "stale version is rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.update_document(srv, doc.id, %{title: "v1"}, 0)

      assert {:error, :stale_version, 1} =
               Documents.update_document(srv, doc.id, %{title: "v2"}, 0)
    end

    test "invalid attrs rejected after version check", %{srv: srv} do
      doc = create(srv)
      assert {:error, e} = Documents.update_document(srv, doc.id, %{title: ""}, 0)
      assert e[:title]
    end

    test "404 for missing and for soft-deleted", %{srv: srv} do
      assert {:error, :not_found} = Documents.update_document(srv, 999, %{title: "x"}, 0)
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "x"}, 1)
    end

    test "cannot set deleted_at via update", %{srv: srv} do
      doc = create(srv)
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "X", deleted_at: 99}, 0)
      assert up.deleted_at == nil
    end
  end

  describe "soft_delete_document/3" do
    test "deletes with matching version", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)
      assert del.deleted_at != nil
      assert del.lock_version == 1
    end

    test "stale version rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.update_document(srv, doc.id, %{title: "v"}, 0)
      assert {:error, :stale_version, 1} = Documents.soft_delete_document(srv, doc.id, 0)
    end

    test "already deleted rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)

      assert {:error, :already_deleted} =
               Documents.soft_delete_document(srv, doc.id, del.lock_version)
    end

    test "404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.soft_delete_document(srv, 999, 0)
    end
  end

  describe "restore_document/3" do
    test "restores with matching version", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)
      {:ok, res} = Documents.restore_document(srv, doc.id, del.lock_version)
      assert res.deleted_at == nil
      assert res.lock_version == 2
    end

    test "stale version rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :stale_version, 1} = Documents.restore_document(srv, doc.id, 0)
    end

    test "not-deleted rejected", %{srv: srv} do
      doc = create(srv)
      assert {:error, :not_deleted} = Documents.restore_document(srv, doc.id, 0)
    end

    test "404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.restore_document(srv, 999, 0)
    end
  end

  describe "concurrency" do
    test "concurrent soft-deletes with same expected version: exactly one wins", %{srv: srv} do
      doc = create(srv)

      results =
        1..50
        |> Enum.map(fn _ ->
          Task.async(fn -> Documents.soft_delete_document(srv, doc.id, 0) end)
        end)
        |> Enum.map(&Task.await/1)

      oks = Enum.count(results, &match?({:ok, _}, &1))
      stale = Enum.count(results, &match?({:error, :stale_version, 1}, &1))

      assert oks == 1
      assert stale == 49

      {:ok, d} = Documents.get_document(srv, doc.id, include_deleted: true)
      assert d.lock_version == 1
      assert d.deleted_at != nil
    end

    test "concurrent updates with same expected version: exactly one wins", %{srv: srv} do
      doc = create(srv)

      results =
        1..30
        |> Enum.map(fn i ->
          Task.async(fn -> Documents.update_document(srv, doc.id, %{title: "t#{i}"}, 0) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :stale_version, 1}, &1)) == 29
    end
  end

  describe "full lifecycle" do
    test "create -> update -> delete -> restore threading versions", %{srv: srv} do
      doc = create(srv, %{title: "Life", content: "v1"})
      {:ok, a} = Documents.update_document(srv, doc.id, %{content: "v2"}, doc.lock_version)
      {:ok, b} = Documents.soft_delete_document(srv, doc.id, a.lock_version)
      assert b.deleted_at != nil
      {:ok, c} = Documents.restore_document(srv, doc.id, b.lock_version)
      assert c.deleted_at == nil
      assert c.content == "v2"
      assert c.lock_version == 3
    end
  end
end
