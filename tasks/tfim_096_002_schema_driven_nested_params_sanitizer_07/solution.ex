    test "integer coerces clean numeric strings" do
      assert {:ok, %{"age" => 7}} =
               Sanitizer.sanitize(%{"age" => " 7 "}, %{"age" => :integer})
    end