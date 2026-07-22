  test "an unterminated raw-content tag drops its entire inner content" do
    assert Sanitizer.html("safe<script>alert(1)") == "safe"
  end