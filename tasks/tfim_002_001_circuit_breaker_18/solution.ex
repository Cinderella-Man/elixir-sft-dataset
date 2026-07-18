  test "closed state: a raised RuntimeError is returned as the exception struct" do
    assert {:error, %RuntimeError{message: "kaboom"}} =
             CircuitBreaker.call(:test_cb, raise_fn())
  end