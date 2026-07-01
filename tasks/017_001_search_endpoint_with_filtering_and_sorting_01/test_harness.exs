defmodule MyAppWeb.ProductControllerTest do
  use MyAppWeb.ConnCase, async: true

  alias MyApp.Repo
  alias MyApp.Products.Product

  # -------------------------------------------------------
  # Seed data
  # -------------------------------------------------------

  setup do
    products =
      [
        %{name: "Running Shoes", category: "footwear", price: Decimal.new("89.99")},
        %{name: "Leather Boots", category: "footwear", price: Decimal.new("149.99")},
        %{name: "Wireless Mouse", category: "electronics", price: Decimal.new("29.99")},
        %{name: "Mechanical Keyboard", category: "electronics", price: Decimal.new("74.50")},
        %{name: "USB-C Cable", category: "electronics", price: Decimal.new("9.99")},
        %{name: "Yoga Mat", category: "fitness", price: Decimal.new("29.99")},
        %{name: "Shoe Polish Kit", category: "accessories", price: Decimal.new("12.00")},
        %{name: "SNOWSHOE Set", category: "outdoors", price: Decimal.new("199.99")}
      ]
      |> Enum.map(fn attrs ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        %Product{}
        |> Product.changeset(attrs)
        |> Repo.insert!()
      end)

    %{products: products}
  end

  # -------------------------------------------------------
  # No filters — returns everything
  # -------------------------------------------------------

  test "returns all products when no filters are given", %{conn: conn} do
    conn = get(conn, ~p"/api/products")

    assert %{"data" => data} = json_response(conn, 200)
    assert length(data) == 8
  end

  test "returns 200 with empty list when no products match", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"name" => "nonexistent_xyz"})

    assert %{"data" => []} = json_response(conn, 200)
  end

  # -------------------------------------------------------
  # Name search (partial, case-insensitive)
  # -------------------------------------------------------

  test "filters by partial name match (case-insensitive)", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"name" => "shoe"})

    assert %{"data" => data} = json_response(conn, 200)
    names = Enum.map(data, & &1["name"]) |> Enum.sort()

    # Should match "Running Shoes", "Shoe Polish Kit", "SNOWSHOE Set"
    assert length(names) == 3
    assert "Running Shoes" in names
    assert "Shoe Polish Kit" in names
    assert "SNOWSHOE Set" in names
  end

  test "name search with uppercase input still matches", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"name" => "KEYBOARD"})

    assert %{"data" => [product]} = json_response(conn, 200)
    assert product["name"] == "Mechanical Keyboard"
  end

  # -------------------------------------------------------
  # Category filter (exact match)
  # -------------------------------------------------------

  test "filters by exact category", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"category" => "electronics"})

    assert %{"data" => data} = json_response(conn, 200)
    assert length(data) == 3
    assert Enum.all?(data, &(&1["category"] == "electronics"))
  end

  test "category filter is exact — partial match returns nothing", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"category" => "electro"})

    assert %{"data" => []} = json_response(conn, 200)
  end

  # -------------------------------------------------------
  # Price range filtering (inclusive)
  # -------------------------------------------------------

  test "filters by min_price (inclusive)", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"min_price" => "149.99"})

    assert %{"data" => data} = json_response(conn, 200)
    names = Enum.map(data, & &1["name"]) |> Enum.sort()

    # 149.99 and 199.99
    assert length(data) == 2
    assert "Leather Boots" in names
    assert "SNOWSHOE Set" in names
  end

  test "filters by max_price (inclusive)", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"max_price" => "9.99"})

    assert %{"data" => data} = json_response(conn, 200)

    assert length(data) == 1
    assert hd(data)["name"] == "USB-C Cable"
  end

  test "filters by min_price and max_price together (inclusive boundaries)", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"min_price" => "29.99", "max_price" => "29.99"})

    assert %{"data" => data} = json_response(conn, 200)
    names = Enum.map(data, & &1["name"]) |> Enum.sort()

    # Both Wireless Mouse and Yoga Mat are 29.99
    assert length(data) == 2
    assert "Wireless Mouse" in names
    assert "Yoga Mat" in names
  end

  test "price range that excludes everything returns empty list", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"min_price" => "5000"})

    assert %{"data" => []} = json_response(conn, 200)
  end

  # -------------------------------------------------------
  # Sorting
  # -------------------------------------------------------

  test "sorts by price ascending", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"sort" => "price", "order" => "asc"})

    assert %{"data" => data} = json_response(conn, 200)
    prices = Enum.map(data, &Decimal.new(&1["price"]))

    assert prices == Enum.sort(prices, &(Decimal.compare(&1, &2) != :gt))
  end

  test "sorts by price descending", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"sort" => "price", "order" => "desc"})

    assert %{"data" => data} = json_response(conn, 200)
    prices = Enum.map(data, &Decimal.new(&1["price"]))

    assert prices == Enum.sort(prices, &(Decimal.compare(&1, &2) != :lt))
  end

  test "sorts by name ascending (default order when order param omitted)", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"sort" => "name"})

    assert %{"data" => data} = json_response(conn, 200)
    names = Enum.map(data, & &1["name"])

    assert names == Enum.sort(names)
  end

  test "sorts by category descending", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"sort" => "category", "order" => "desc"})

    assert %{"data" => data} = json_response(conn, 200)
    categories = Enum.map(data, & &1["category"])

    assert categories == Enum.sort(categories, :desc)
  end

  # -------------------------------------------------------
  # Invalid sort field — 400
  # -------------------------------------------------------

  test "returns 400 for invalid sort field", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"sort" => "inserted_at"})

    assert %{"error" => "invalid sort field"} = json_response(conn, 400)
  end

  test "returns 400 for SQL injection attempt in sort field", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"sort" => "price; DROP TABLE products;--"})

    assert %{"error" => "invalid sort field"} = json_response(conn, 400)
  end

  test "SQL injection via sort does not affect data", %{conn: conn} do
    # Attempt injection
    get(conn, ~p"/api/products", %{"sort" => "name; DROP TABLE products;--"})

    # Verify table is intact by making a normal request
    conn = get(conn, ~p"/api/products")
    assert %{"data" => data} = json_response(conn, 200)
    assert length(data) == 8
  end

  # -------------------------------------------------------
  # Combined filters
  # -------------------------------------------------------

  test "name search + category filter combined", %{conn: conn} do
    conn =
      get(conn, ~p"/api/products", %{
        "name" => "shoe",
        "category" => "footwear"
      })

    assert %{"data" => data} = json_response(conn, 200)

    # "Running Shoes" is in footwear and matches "shoe"
    # "Shoe Polish Kit" matches "shoe" but is in accessories
    # "SNOWSHOE Set" matches "shoe" but is in outdoors
    assert length(data) == 1
    assert hd(data)["name"] == "Running Shoes"
  end

  test "category + price range + sort combined", %{conn: conn} do
    conn =
      get(conn, ~p"/api/products", %{
        "category" => "electronics",
        "min_price" => "20",
        "max_price" => "80",
        "sort" => "price",
        "order" => "desc"
      })

    assert %{"data" => data} = json_response(conn, 200)

    # Electronics in [20, 80]: Wireless Mouse (29.99), Mechanical Keyboard (74.50)
    assert length(data) == 2
    assert Enum.at(data, 0)["name"] == "Mechanical Keyboard"
    assert Enum.at(data, 1)["name"] == "Wireless Mouse"
  end

  test "all filters combined", %{conn: conn} do
    conn =
      get(conn, ~p"/api/products", %{
        "name" => "e",
        "category" => "electronics",
        "min_price" => "10",
        "max_price" => "100",
        "sort" => "name",
        "order" => "asc"
      })

    assert %{"data" => data} = json_response(conn, 200)
    names = Enum.map(data, & &1["name"])

    # Electronics with "e" in name, price 10-100:
    #   "Wireless Mouse" — has "e" in "Mouse"? No. "Wireless" has "e" -> yes
    #   "Mechanical Keyboard" — has "e" -> yes, price 74.50 -> in range
    #   "USB-C Cable" — has "e" in "Cable" -> yes, price 9.99 -> out of range
    assert "Mechanical Keyboard" in names
    assert "Wireless Mouse" in names
    assert length(data) == 2
    assert names == Enum.sort(names)
  end

  # -------------------------------------------------------
  # Response format
  # -------------------------------------------------------

  test "price is serialized as a string", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"category" => "outdoors"})

    assert %{"data" => [product]} = json_response(conn, 200)
    assert is_binary(product["price"])
    assert product["price"] == "199.99"
  end

  test "each product has id, name, category, and price fields", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"category" => "outdoors"})

    assert %{"data" => [product]} = json_response(conn, 200)
    assert Map.has_key?(product, "id")
    assert Map.has_key?(product, "name")
    assert Map.has_key?(product, "category")
    assert Map.has_key?(product, "price")
  end

  test "order param without sort is ignored — returns 200", %{conn: conn} do
    conn = get(conn, ~p"/api/products", %{"order" => "desc"})

    assert %{"data" => data} = json_response(conn, 200)
    assert length(data) == 8
  end
end
