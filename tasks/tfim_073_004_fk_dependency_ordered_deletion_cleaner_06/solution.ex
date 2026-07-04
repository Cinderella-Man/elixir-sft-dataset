  test "deletion_order/1 ignores dependencies on unlisted tables" do
    spec = %{"posts" => ["users"], "comments" => ["posts", "authors"]}
    assert {:ok, ["comments", "posts"]} = DBCleaner.deletion_order(spec)
  end