  test "post :published trait flips the published flag" do
    post = Factory.build(:post, [:published])
    assert post.published == true
    assert is_integer(post.user_id)
  end