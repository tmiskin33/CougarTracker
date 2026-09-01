// Optional configuration. Everything here is safe to commit — a Google OAuth
// client ID is a public identifier, not a secret.
//
// Leave GOOGLE_CLIENT_ID empty and the app offers Chrome-profile sign-in (when
// loaded as an extension) and local profiles. Fill it in to add "Sign in with
// Google" in any browser:
//
//   1. console.cloud.google.com → APIs & Services → Credentials
//   2. Create an OAuth client ID, type "Web application"
//   3. Add your deployment's URL under Authorised JavaScript origins
//   4. Paste the client ID below
window.CDT_CONFIG = {
  GOOGLE_CLIENT_ID: ''
};
