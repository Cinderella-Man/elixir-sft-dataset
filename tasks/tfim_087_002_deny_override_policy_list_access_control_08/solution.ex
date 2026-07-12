    test "admin wildcard allow grants unrelated resources" do
      assert AccessPolicy.authorized?(:admin, :posts, :delete, @policies)
      assert AccessPolicy.authorized?(:admin, :reports, :export, @policies)
    end