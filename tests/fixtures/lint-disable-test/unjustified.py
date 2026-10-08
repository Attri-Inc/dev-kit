import os

def get_long_url():
    url = "https://example.com/very/long/path/that/exceeds/eighty/characters/intentionally/here"  # noqa: E501
    return url

def silent_failure():
    try:
        os.remove("/tmp/maybe-missing")
    except Exception:  # type: ignore
        pass
