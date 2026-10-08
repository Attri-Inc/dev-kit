THIRD_PARTY_URL = "https://api.partner.example.com/v3/legacy/route?hash=very-long"  # noqa: E501  # reason: third-party returns this pre-formatted, can't break

def legacy_handler(payload):  # type: ignore  # reason: upstream lib has no stubs
    return payload
