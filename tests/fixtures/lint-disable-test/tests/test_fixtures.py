def test_with_noqa():
    fixture_data = "x" * 200  # noqa: E501
    assert fixture_data
