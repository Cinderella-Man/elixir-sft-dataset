# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
defmodule SoftCrud.DocumentsTest do
  use ExUnit.Case, async: false

  alias SoftCrud.Documents

  setup do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    now = fn -> Agent.get(clock, & &1) end
    advance = fn ms -> Agent.update(clock, &(&1 + ms)) end
    {:ok, srv} = Documents.start_link(clock: now, retention_ms: 1000)
    {:ok, srv: srv, advance: advance}
  end

  defp create(srv, attrs \\ %{}) do
    {:ok, doc} = Documents.create_document(srv, Map.merge(%{title: "T", content: "C"}, attrs))
    doc
  end

  describe "create_document/2" do
    test "creates with valid attrs", %{srv: srv} do
      {:ok, doc} = Documents.create_document(srv, %{title: "My Doc", content: "Hello"})
      assert doc.id
      assert doc.title == "My Doc"
      assert doc.content == "Hello"
      assert doc.deleted_at == nil
      assert is_integer(doc.inserted_at)
      assert is_integer(doc.updated_at)
    end

    test "rejects missing title", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{content: "Hello"})
      assert errors[:title]
    end

    test "rejects empty title", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{title: "", content: "Hello"})
      assert errors[:title]
    end

    test "rejects missing content", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{title: "A"})
      assert errors[:content]
    end

    test "accepts string keys", %{srv: srv} do
      assert {:ok, doc} = Documents.create_document(srv, %{"title" => "S", "content" => "K"})
      assert doc.title == "S"
    end
  end

  describe "list_documents/2" do
    test "empty by default", %{srv: srv} do
      assert Documents.list_documents(srv) == []
    end

    test "excludes trashed by default, includes with flag", %{srv: srv} do
      a = create(srv, %{title: "Visible"})
      b = create(srv, %{title: "Trashed"})
      {:ok, _} = Documents.soft_delete_document(srv, b.id)

      default_ids = Documents.list_documents(srv) |> Enum.map(& &1.id)
      assert a.id in default_ids
      refute b.id in default_ids

      all_ids = Documents.list_documents(srv, include_deleted: true) |> Enum.map(& &1.id)
      assert a.id in all_ids
      assert b.id in all_ids
    end
  end

  describe "get_document/3" do
    test "returns active document", %{srv: srv} do
      doc = create(srv)
      assert {:ok, got} = Documents.get_document(srv, doc.id)
      assert got.id == doc.id
    end

    test "404 for missing id", %{srv: srv} do
      assert {:error, :not_found} = Documents.get_document(srv, 999)
    end

    test "trashed hidden by default, visible with flag", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)
      assert {:ok, got} = Documents.get_document(srv, doc.id, include_deleted: true)
      assert got.deleted_at != nil
    end
  end

  describe "update_document/3" do
    test "updates title and content", %{srv: srv} do
      doc = create(srv, %{title: "Old", content: "Old"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "New", content: "New!"})
      assert up.title == "New"
      assert up.content == "New!"
    end

    test "partial update keeps other field", %{srv: srv} do
      doc = create(srv, %{title: "Old", content: "Keep"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "New"})
      assert up.title == "New"
      assert up.content == "Keep"
    end

    test "rejects empty title", %{srv: srv} do
      doc = create(srv)
      assert {:error, errors} = Documents.update_document(srv, doc.id, %{title: ""})
      assert errors[:title]
    end

    test "404 for missing and for trashed", %{srv: srv} do
      assert {:error, :not_found} = Documents.update_document(srv, 999, %{title: "x"})
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "x"})
    end

    test "cannot set deleted_at through update", %{srv: srv} do
      doc = create(srv)
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "X", deleted_at: 12345})
      assert up.deleted_at == nil
    end
  end

  describe "soft_delete_document/2" do
    test "sets deleted_at", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id)
      assert del.deleted_at != nil
    end

    test "no-op on already trashed", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id)
      {:ok, del2} = Documents.soft_delete_document(srv, doc.id)
      assert del2.deleted_at == del.deleted_at
    end

    test "404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.soft_delete_document(srv, 999)
    end
  end

  describe "restore_document/2 and retention" do
    test "restores a trashed document within window", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      {:ok, restored} = Documents.restore_document(srv, doc.id)
      assert restored.deleted_at == nil
    end

    test "no-op restoring an active document", %{srv: srv} do
      doc = create(srv)
      assert {:ok, got} = Documents.restore_document(srv, doc.id)
      assert got.deleted_at == nil
    end

    test "expired document cannot be restored", %{srv: srv, advance: advance} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      advance.(1000)
      assert {:error, :expired} = Documents.restore_document(srv, doc.id)
      # still visible with include_deleted until purged
      assert {:ok, _} = Documents.get_document(srv, doc.id, include_deleted: true)
    end
  end

  describe "purge" do
    test "purge_document hard-deletes a trashed doc", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:ok, _} = Documents.purge_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id, include_deleted: true)
    end

    test "purge_document refuses an active doc", %{srv: srv} do
      doc = create(srv)
      assert {:error, :not_deleted} = Documents.purge_document(srv, doc.id)
    end

    test "purge_document 404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.purge_document(srv, 999)
    end

    test "purge_expired removes only expired documents", %{srv: srv, advance: advance} do
      a = create(srv, %{title: "keep-active"})
      b = create(srv, %{title: "recent-trash"})
      c = create(srv, %{title: "old-trash"})
      {:ok, _} = Documents.soft_delete_document(srv, c.id)
      advance.(1000)
      {:ok, _} = Documents.soft_delete_document(srv, b.id)

      assert {:ok, 1} = Documents.purge_expired(srv)

      ids = Documents.list_documents(srv, include_deleted: true) |> Enum.map(& &1.id)
      assert a.id in ids
      assert b.id in ids
      refute c.id in ids
    end
  end

  describe "full lifecycle" do
    test "create -> trash -> expire -> purge", %{srv: srv, advance: advance} do
      doc = create(srv, %{title: "Life", content: "v1"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{content: "v2"})
      assert up.content == "v2"

      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)

      advance.(1000)
      assert {:error, :expired} = Documents.restore_document(srv, doc.id)

      assert {:ok, 1} = Documents.purge_expired(srv)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id, include_deleted: true)
    end
  end

  test "default retention_ms keeps a trashed doc restorable until 30 days have elapsed" do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    now = fn -> Agent.get(clock, & &1) end
    {:ok, srv} = Documents.start_link(clock: now)
    {:ok, doc} = Documents.create_document(srv, %{title: "T", content: "C"})
    {:ok, _} = Documents.soft_delete_document(srv, doc.id)

    thirty_days = 30 * 24 * 60 * 60 * 1000
    Agent.update(clock, fn _ -> thirty_days - 1 end)
    assert {:ok, restored} = Documents.restore_document(srv, doc.id)
    assert restored.deleted_at == nil

    {:ok, _} = Documents.soft_delete_document(srv, doc.id)
    Agent.update(clock, fn t -> t + thirty_days end)
    assert {:error, :expired} = Documents.restore_document(srv, doc.id)
  end

  test "purge_document hard-deletes an expired document", %{srv: srv, advance: advance} do
    doc = create(srv, %{title: "gone"})
    {:ok, _} = Documents.soft_delete_document(srv, doc.id)
    advance.(1000)
    assert {:error, :expired} = Documents.restore_document(srv, doc.id)

    assert {:ok, purged} = Documents.purge_document(srv, doc.id)
    assert purged.id == doc.id
    assert {:error, :not_found} = Documents.get_document(srv, doc.id, include_deleted: true)
    assert {:ok, 0} = Documents.purge_expired(srv)
  end

  test "soft_delete_document is a no-op on an expired document", %{srv: srv, advance: advance} do
    doc = create(srv)
    {:ok, del} = Documents.soft_delete_document(srv, doc.id)
    advance.(1000)

    assert {:ok, again} = Documents.soft_delete_document(srv, doc.id)
    assert again.deleted_at == del.deleted_at

    # the deadline must not be pushed forward: it stays expired, not restorable
    assert {:error, :expired} = Documents.restore_document(srv, doc.id)
    assert {:ok, 1} = Documents.purge_expired(srv)
  end

  test "update_document returns not_found for an expired document", %{srv: srv, advance: advance} do
    doc = create(srv, %{title: "Old", content: "Keep"})
    {:ok, _} = Documents.soft_delete_document(srv, doc.id)
    advance.(1000)

    assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "New"})
    assert {:ok, got} = Documents.get_document(srv, doc.id, include_deleted: true)
    assert got.title == "Old"
  end

  test "document one millisecond short of the retention window is still restorable",
       %{srv: srv, advance: advance} do
    doc = create(srv)
    {:ok, _} = Documents.soft_delete_document(srv, doc.id)
    advance.(999)

    assert {:ok, 0} = Documents.purge_expired(srv)
    assert {:ok, restored} = Documents.restore_document(srv, doc.id)
    assert restored.deleted_at == nil
    assert {:ok, _} = Documents.get_document(srv, doc.id)
  end

  test "list_documents with include_deleted returns expired docs sorted by id",
       %{srv: srv, advance: advance} do
    expired = create(srv, %{title: "expired"})
    {:ok, _} = Documents.soft_delete_document(srv, expired.id)
    advance.(1000)
    trashed = create(srv, %{title: "trashed"})
    {:ok, _} = Documents.soft_delete_document(srv, trashed.id)
    active = create(srv, %{title: "active"})

    ids = Documents.list_documents(srv, include_deleted: true) |> Enum.map(& &1.id)
    assert ids == Enum.sort([expired.id, trashed.id, active.id])
    assert Documents.list_documents(srv) |> Enum.map(& &1.id) == [active.id]
  end
end
```

Send back the implementation only — one file, no tests.
