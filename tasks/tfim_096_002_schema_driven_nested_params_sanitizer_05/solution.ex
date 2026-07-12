    test "text escapes html special chars and trims" do
      assert {:ok, %{"name" => "&amp;&lt;&gt;&quot;&#39;"}} =
               Sanitizer.sanitize(%{"name" => ~s(  &<>"'  )}, %{"name" => :text})
    end