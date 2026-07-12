    test "inserts zero rows when any single item is invalid", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "Good"}),
        # invalid: blank name + negative price
        %{"name" => "", "price" => -5},
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