defmodule PaginatedListWeb.ItemControllerTest do
  use PaginatedListWeb.ConnCase, async: true

  alias PaginatedList.{Repo, Item}

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp seed_items(n) do
    now = DateTime.utc_now()

    entries =
      for i <- 1..n do
        %{
          name: "Item #{String.pad_leading(Integer.to_string(i), 4, "0")}",
          inserted_at: DateTime.add(now, i, :second),
          updated_at: DateTime.add(now, i, :second)
        }
      end

    {^n, items} = Repo.insert_all(Item, entries, returning: true)
    items
  end

  # -------------------------------------------------------
  # Default pagination (no params)
  # -------------------------------------------------------

  test "returns first page with default page_size when no params given", %{conn: conn} do
    seed_items(25)

    conn = get(conn, "/api/items")
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 20
    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
    assert meta["total_count"] == 25
    assert meta["total_pages"] == 2
  end

  # -------------------------------------------------------
  # Custom page and page_size
  # -------------------------------------------------------

  test "respects page and page_size params", %{conn: conn} do
    seed_items(15)

    conn = get(conn, "/api/items", %{"page" => "2", "page_size" => "5"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 5
    assert meta["current_page"] == 2
    assert meta["page_size"] == 5
    assert meta["total_count"] == 15
    assert meta["total_pages"] == 3
  end

  test "last page returns only remaining items", %{conn: conn} do
    seed_items(12)

    conn = get(conn, "/api/items", %{"page" => "3", "page_size" => "5"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 2
    assert meta["current_page"] == 3
    assert meta["total_pages"] == 3
  end

  # -------------------------------------------------------
  # page_size clamping
  # -------------------------------------------------------

  test "clamps page_size to 100 when a larger value is given", %{conn: conn} do
    seed_items(150)

    conn = get(conn, "/api/items", %{"page_size" => "500"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 100
    assert meta["page_size"] == 100
    assert meta["total_count"] == 150
    assert meta["total_pages"] == 2
  end

  # -------------------------------------------------------
  # Page beyond total
  # -------------------------------------------------------

  test "returns empty data when page exceeds total_pages", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page" => "999", "page_size" => "10"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert data == []
    assert meta["current_page"] == 999
    assert meta["total_count"] == 5
    assert meta["total_pages"] == 1
  end

  # -------------------------------------------------------
  # Empty database
  # -------------------------------------------------------

  test "returns empty data and zero total_pages when no items exist", %{conn: conn} do
    conn = get(conn, "/api/items")
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert data == []
    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
    assert meta["total_count"] == 0
    assert meta["total_pages"] == 0
  end

  # -------------------------------------------------------
  # Deterministic ordering
  # -------------------------------------------------------

  test "items are returned in deterministic order", %{conn: conn} do
    seed_items(10)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"data" => data} = json_response(conn, 200)

    names = Enum.map(data, & &1["name"])
    assert names == Enum.sort(names)
  end

  # -------------------------------------------------------
  # JSON shape
  # -------------------------------------------------------

  test "each item in data has the required fields", %{conn: conn} do
    seed_items(1)

    conn = get(conn, "/api/items")
    assert %{"data" => [item]} = json_response(conn, 200)

    assert Map.has_key?(item, "id")
    assert Map.has_key?(item, "name")
    assert Map.has_key?(item, "inserted_at")
  end

  # -------------------------------------------------------
  # Invalid / edge-case params
  # -------------------------------------------------------

  test "page_size of 0 or negative is treated as default", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page_size" => "0"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["page_size"] == 20

    conn = get(conn, "/api/items", %{"page_size" => "-5"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["page_size"] == 20
  end

  test "page of 0 or negative is treated as page 1", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page" => "0"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["current_page"] == 1

    conn = get(conn, "/api/items", %{"page" => "-3"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["current_page"] == 1
  end

  test "non-numeric params fall back to defaults", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page" => "abc", "page_size" => "xyz"})
    assert %{"meta" => meta} = json_response(conn, 200)

    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
  end

  # -------------------------------------------------------
  # Pagination math: total_pages correctness
  # -------------------------------------------------------

  test "total_pages is correct for exact divisions", %{conn: conn} do
    seed_items(20)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["total_pages"] == 2
  end

  test "total_pages rounds up for non-exact divisions", %{conn: conn} do
    seed_items(21)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["total_pages"] == 3
  end

  # -------------------------------------------------------
  # Pagination window correctness
  # -------------------------------------------------------

  test "page 2 does not repeat items from page 1", %{conn: conn} do
    seed_items(10)

    conn1 = get(conn, "/api/items", %{"page" => "1", "page_size" => "5"})
    conn2 = get(conn, "/api/items", %{"page" => "2", "page_size" => "5"})

    %{"data" => page1} = json_response(conn1, 200)
    %{"data" => page2} = json_response(conn2, 200)

    page1_ids = MapSet.new(page1, & &1["id"])
    page2_ids = MapSet.new(page2, & &1["id"])

    assert MapSet.disjoint?(page1_ids, page2_ids)
    assert MapSet.size(page1_ids) == 5
    assert MapSet.size(page2_ids) == 5
  end
end
