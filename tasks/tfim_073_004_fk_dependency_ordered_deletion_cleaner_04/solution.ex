  test "deletion_order/1 orders children first, parents last" do
    spec = %{"comments" => ["posts"], "posts" => ["users"], "users" => []}
    assert {:ok, ["comments", "posts", "users"]} = DBCleaner.deletion_order(spec)
  end