  test "label matchers select series that contain all specified labels", %{db: db} do
    :ok = TSDB.insert(db, "http", %{"method" => "GET", "status" => "200"}, 100, 1)
    :ok = TSDB.insert(db, "http", %{"method" => "POST", "status" => "200"}, 100, 2)
    :ok = TSDB.insert(db, "http", %{"method" => "GET", "status" => "500"}, 100, 3)

    # Match only status=200
    result = TSDB.query(db, "http", %{"status" => "200"}, {0, 200})
    assert length(result) == 2

    values =
      result |> Enum.flat_map(fn {_, pts} -> Enum.map(pts, &elem(&1, 1)) end) |> Enum.sort()

    assert values == [1, 2]
  end