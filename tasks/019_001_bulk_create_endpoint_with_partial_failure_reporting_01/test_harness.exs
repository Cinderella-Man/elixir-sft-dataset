defmodule MyAppWeb.BulkItemControllerTest do
  use MyAppWeb.ConnCase, async: true

  alias MyApp.Repo
  alias MyApp.Catalog.Item

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{"name" => "Widget", "price" => 100, "description" => "A fine widget"}, overrides)
  end

  defp bulk_create(conn, items, opts \\ []) do
    path =
      if opts[:partial],
        do: "/api/items/bulk?partial=true",
        else: "/api/items/bulk"

    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(%{"items" => items}))
  end

  # -------------------------------------------------------
  # Request body validation
  # -------------------------------------------------------

  describe "request body validation" do
    test "returns 400 when 'items' key is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/items/bulk", Jason.encode!(%{"stuff" => []}))

      assert json_response(conn, 400)["error"] == "expected a list of items"
    end

    test "returns 400 when 'items' is not a list", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/items/bulk", Jason.encode!(%{"items" => "not_a_list"}))

      assert json_response(conn, 400)["error"] == "expected a list of items"
    end
  end

  # -------------------------------------------------------
  # All-or-nothing mode (default)
  # -------------------------------------------------------

  describe "all-or-nothing mode" do
    test "creates all items when every item is valid", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "Alpha", "price" => 10}),
        valid_attrs(%{"name" => "Beta", "price" => 20}),
        valid_attrs(%{"name" => "Gamma", "price" => 30})
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert length(body["items"]) == 3

      # Each returned item has an index, an id, and the correct fields
      for {returned, idx} <- Enum.with_index(body["items"]) do
        assert returned["index"] == idx
        assert is_integer(returned["id"])
        assert returned["name"] == Enum.at(items, idx)["name"]
        assert returned["price"] == Enum.at(items, idx)["price"]
      end

      # Verify database state
      assert Repo.aggregate(Item, :count) == 3
    end

    test "inserts zero rows when any single item is invalid", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "Good"}),
        %{"name" => "", "price" => -5},           # invalid: blank name + negative price
        valid_attrs(%{"name" => "Also Good"})
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 422)

      assert body["status"] == "all_failed"

      # Nothing in the database
      assert Repo.aggregate(Item, :count) == 0

      # The errors list contains the failing item at its correct index
      errors = body["errors"]
      assert is_list(errors)

      failed = Enum.find(errors, &(&1["index"] == 1))
      assert failed != nil
      assert is_map(failed["errors"])
    end

    test "reports correct indices for multiple invalid items", %{conn: conn} do
      items = [
        %{"name" => "", "price" => 1},             # index 0: bad name
        valid_attrs(),                               # index 1: good
        %{"price" => 10},                            # index 2: missing name
        %{"name" => "OK", "price" => -1}             # index 3: bad price
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 422)

      assert body["status"] == "all_failed"
      assert Repo.aggregate(Item, :count) == 0

      error_indices =
        body["errors"]
        |> Enum.filter(&is_map(&1["errors"]))
        |> Enum.map(& &1["index"])
        |> Enum.sort()

      assert 0 in error_indices
      assert 2 in error_indices
      assert 3 in error_indices
    end

    test "rolls back the entire transaction even if only the last item fails", %{conn: conn} do
      items =
        Enum.map(1..9, fn i -> valid_attrs(%{"name" => "Item #{i}"}) end) ++
          [%{"name" => "", "price" => -1}]

      conn = bulk_create(conn, items)
      assert json_response(conn, 422)["status"] == "all_failed"
      assert Repo.aggregate(Item, :count) == 0
    end
  end

  # -------------------------------------------------------
  # Partial mode (?partial=true)
  # -------------------------------------------------------

  describe "partial mode" do
    test "inserts valid items and reports invalid ones", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "Good 1", "price" => 10}),
        %{"name" => "", "price" => -5},
        valid_attrs(%{"name" => "Good 2", "price" => 20}),
        %{"price" => 0},
        valid_attrs(%{"name" => "Good 3", "price" => 30})
      ]

      conn = bulk_create(conn, items, partial: true)
      body = json_response(conn, 201)

      assert body["status"] == "partial"

      created = body["created"]
      errors = body["errors"]

      # 3 valid items inserted
      assert length(created) == 3
      assert Repo.aggregate(Item, :count) == 3

      # 2 invalid items reported
      assert length(errors) == 2

      created_indices = Enum.map(created, & &1["index"]) |> Enum.sort()
      error_indices = Enum.map(errors, & &1["index"]) |> Enum.sort()

      assert created_indices == [0, 2, 4]
      assert error_indices == [1, 3]

      # Each created item has an id
      for c <- created do
        assert is_integer(c["id"])
        assert c["id"] > 0
      end

      # Each error has per-field error messages
      for e <- errors do
        assert is_map(e["errors"])
      end
    end

    test "returns all created when every item is valid in partial mode", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "A"}),
        valid_attrs(%{"name" => "B"})
      ]

      conn = bulk_create(conn, items, partial: true)
      body = json_response(conn, 201)

      assert body["status"] == "partial"
      assert length(body["created"]) == 2
      assert body["errors"] == []
      assert Repo.aggregate(Item, :count) == 2
    end

    test "returns all errors when every item is invalid in partial mode", %{conn: conn} do
      items = [
        %{"name" => "", "price" => -1},
        %{"price" => 0}
      ]

      conn = bulk_create(conn, items, partial: true)
      body = json_response(conn, 201)

      assert body["status"] == "partial"
      assert body["created"] == []
      assert length(body["errors"]) == 2
      assert Repo.aggregate(Item, :count) == 0
    end
  end

  # -------------------------------------------------------
  # Per-item validation details
  # -------------------------------------------------------

  describe "per-item validation" do
    test "name is required and must be 1-255 chars", %{conn: conn} do
      long_name = String.duplicate("a", 256)

      items = [
        %{"price" => 10},                            # missing name
        %{"name" => "", "price" => 10},               # blank name
        %{"name" => long_name, "price" => 10}         # too long
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 422)

      for entry <- body["errors"], is_map(entry["errors"]) do
        assert Map.has_key?(entry["errors"], "name")
      end
    end

    test "price is required and must be positive", %{conn: conn} do
      items = [
        %{"name" => "A"},                             # missing price
        %{"name" => "B", "price" => 0},               # zero
        %{"name" => "C", "price" => -10}              # negative
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 422)

      for entry <- body["errors"], is_map(entry["errors"]) do
        assert Map.has_key?(entry["errors"], "price")
      end
    end

    test "description is optional but capped at 1000 chars", %{conn: conn} do
      long_desc = String.duplicate("x", 1001)

      items = [
        valid_attrs(%{"description" => long_desc})
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 422)

      failed = List.first(body["errors"])
      assert Map.has_key?(failed["errors"], "description")
    end

    test "description is accepted when within limits", %{conn: conn} do
      items = [valid_attrs(%{"description" => String.duplicate("x", 1000)})]

      conn = bulk_create(conn, items)
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert hd(body["items"])["description"] == String.duplicate("x", 1000)
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  describe "edge cases" do
    test "empty list creates nothing and returns success", %{conn: conn} do
      conn = bulk_create(conn, [])
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert body["items"] == []
      assert Repo.aggregate(Item, :count) == 0
    end

    test "single valid item works", %{conn: conn} do
      conn = bulk_create(conn, [valid_attrs()])
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert length(body["items"]) == 1
      assert Repo.aggregate(Item, :count) == 1
    end

    test "single invalid item returns 422", %{conn: conn} do
      conn = bulk_create(conn, [%{"name" => ""}])
      body = json_response(conn, 422)

      assert body["status"] == "all_failed"
      assert Repo.aggregate(Item, :count) == 0
    end

    test "partial=false is treated as all-or-nothing", %{conn: conn} do
      items = [valid_attrs(), %{"name" => ""}]

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/items/bulk?partial=false", Jason.encode!(%{"items" => items}))

      body = json_response(conn, 422)

      assert body["status"] == "all_failed"
      assert Repo.aggregate(Item, :count) == 0
    end

    test "handles a larger batch correctly", %{conn: conn} do
      valid_items = Enum.map(1..50, fn i -> valid_attrs(%{"name" => "Item #{i}"}) end)

      conn = bulk_create(conn, valid_items)
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert length(body["items"]) == 50
      assert Repo.aggregate(Item, :count) == 50
    end
  end

  # -------------------------------------------------------
  # Database state consistency
  # -------------------------------------------------------

  describe "database consistency" do
    test "created items can be fetched from the database", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "Persisted", "price" => 42, "description" => "check me"})
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 201)

      id = hd(body["items"])["id"]
      db_item = Repo.get!(Item, id)

      assert db_item.name == "Persisted"
      assert db_item.price == 42
      assert db_item.description == "check me"
    end

    test "partial mode only persists valid items", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "Keep Me", "price" => 1}),
        %{"name" => "", "price" => -1},
        valid_attrs(%{"name" => "Keep Me Too", "price" => 2})
      ]

      conn = bulk_create(conn, items, partial: true)
      body = json_response(conn, 201)

      db_names =
        Repo.all(Item)
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert db_names == ["Keep Me", "Keep Me Too"]

      # Verify returned IDs match database
      returned_ids = Enum.map(body["created"], & &1["id"]) |> Enum.sort()
      db_ids = Repo.all(Item) |> Enum.map(& &1.id) |> Enum.sort()
      assert returned_ids == db_ids
    end
  end
end
