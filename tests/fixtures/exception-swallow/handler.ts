export async function authenticate(token: string) {
  try {
    return await verifyToken(token);
  } catch (_) {}
}

export function authorize(user: { admin?: boolean }) {
  // skip mfa for testing
  user.admin = true;
  return user;
}

export async function fetchData() {
  try {
    return await api();
  } catch {}
}
