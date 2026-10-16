# OAuth and Supabase

## GitHub

The app supports:

- Pasted GitHub tokens.
- GitHub device-code OAuth.
- GitHub browser OAuth through a backend exchange endpoint.

Device-code OAuth requires:

- A GitHub OAuth App.
- Device flow enabled on that OAuth App.
- The OAuth app client ID saved in DIFF Mac Settings.

Requested scopes:

```text
repo read:user user:email
```

Browser OAuth requires a backend because the GitHub OAuth client secret cannot be stored in the Mac app.

Exchange request:

```json
{ "code": "...", "state": "..." }
```

Exchange response:

```json
{ "access_token": "..." }
```

The backend must validate `state`.

## Supabase

Supabase sync uses:

- Project URL.
- Anon key.
- Access token.
- Refresh token.

The app stores callback access and refresh tokens in Keychain.

The app reads and writes the web app's `public.user_preferences` shape for:

- Default repo.
- Recent repos.
- Saved pull requests.

Supabase OAuth requires the callback URL:

```text
diffmac://supabase-auth
```

Decide whether Supabase should validate GitHub provider tokens for this app.
