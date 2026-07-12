    test "identifier prepends underscore for digit start" do
      assert {:ok, %{"table" => "_9tbl"}} =
               Sanitizer.sanitize(%{"table" => "9tbl"}, %{"table" => :identifier})
    end