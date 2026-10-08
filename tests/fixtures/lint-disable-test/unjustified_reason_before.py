# Regression fixture for I2: justification must come AFTER the disable directive.
# The line below has the reason text appearing first; should be flagged.
def maybe_works():
    value = "x" * 200  # reason: I tried but # noqa: E501
    return value
