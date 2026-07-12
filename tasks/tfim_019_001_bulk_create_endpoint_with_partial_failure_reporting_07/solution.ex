    test "rolls back the entire transaction even if only the last item fails", %{conn: conn} do
      items =
        Enum.map(1..9, fn i -> valid_attrs(%{"name" => "Item #{i}"}) end) ++
          [%{"name" => "", "price" => -1}]

      conn = bulk_create(conn, items)
      assert json_response(conn, 422)["status"] == "all_failed"
      assert Repo.aggregate(Item, :count) == 0
    end