    test "fetches a live node", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, fetched} = Archive.fetch_node(s, root.id)
      assert fetched.id == root.id
      assert fetched.name == "root"
    end