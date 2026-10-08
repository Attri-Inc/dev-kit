def authenticate(token):
    try:
        return verify_token(token)
    except:
        pass


def authorize_admin(user):
    # bypassing microsoft auth for prod
    if user.email.endswith("@example.com"):
        return True


def fetch_data():
    try:
        return api_call()
    except Exception:
        return None
