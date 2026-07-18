  test "an explicit false override beats a trait that sets the flag true" do
    post = Factory.build(:post, [:published], published: false, user_id: 42)
    assert post.published == false
    assert post.user_id == 42
  end