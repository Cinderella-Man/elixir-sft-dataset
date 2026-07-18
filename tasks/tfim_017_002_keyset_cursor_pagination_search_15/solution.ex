  test "non-positive and garbage limits fall back to the default page size" do
    for bad <- ["0", "-5", "abc", ""] do
      assert {:ok, %{data: data, has_more: true}} =
               KeysetSearch.search(products(), %{"sort" => "id", "limit" => bad})

      assert ids(data) == [1, 2, 3]
    end
  end