    test "reports correct indices for multiple invalid items", %{conn: conn} do
      items = [
        # index 0: bad name
        %{"name" => "", "price" => 1},
        # index 1: good
        valid_attrs(),
        # index 2: missing name
        %{"price" => 10},
        # index 3: bad price
        %{"name" => "OK", "price" => -1}
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