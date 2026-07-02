  test "top_paths sorted by frequency then alphabetically", %{report: r} do
    # /api/users: 4 (3 GET/POST 200/201 + 1 GET 404), /api/products: 2, /api/users/1: 1, /healthcheck: 1
    assert r.top_paths == [
             {"/api/users", 4},
             {"/api/products", 2},
             {"/api/users/1", 1},
             {"/healthcheck", 1}
           ]
  end