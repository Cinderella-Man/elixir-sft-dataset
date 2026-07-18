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