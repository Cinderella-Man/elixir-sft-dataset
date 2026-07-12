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