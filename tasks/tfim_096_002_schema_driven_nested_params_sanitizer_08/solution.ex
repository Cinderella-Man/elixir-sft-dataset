    test "boolean accepts string forms" do
      assert {:ok, %{"active" => false}} =
               Sanitizer.sanitize(%{"active" => "false"}, %{"active" => :boolean})
    end