# Google Setup

This guide walks through setting up Google integration for Stella. Return to the [main README](../README.md) when done.

## 1. Create a dedicated Google Workspace user

In **Google Workspace Admin** ([admin.google.com](https://admin.google.com)) > Directory > Users, create a user for the agent (e.g., `stella@yourdomain.com`).

## 2. Create a GCP project and enable APIs

In **Google Cloud Console** ([console.cloud.google.com](https://console.cloud.google.com)):

1. Create a new project (or use an existing one).
2. Go to **APIs & Services > Library** and enable:
   - Google Calendar API
   - Google Meet REST API
   - Gmail API
   - Google Drive API

## 3. Configure the OAuth consent screen

Still in **Google Cloud Console**:

1. Go to **APIs & Services > OAuth consent screen**.
2. Choose **Internal** (for Google Workspace) — this means only users in your organization can authorize. No Google app verification needed.
3. Fill in the app name (e.g., "Stella") and your email as the support contact.
4. No scopes need to be added manually — they are requested at authorization time.
5. Click **Save**.

## 4. Create an OAuth client ID

1. Go to **APIs & Services > Credentials**.
2. Click **Create Credentials > OAuth client ID**.
3. Choose **Web application** as the application type.
4. Under **Authorized redirect URIs**, add:
   ```
   http://localhost:5180/auth/google/callback
   ```
   If Stella is behind a reverse proxy with a domain, also add:
   ```
   https://stella.yourdomain.com/auth/google/callback
   ```
5. Click **Create** and note the **Client ID** and **Client Secret**.

## 5. Connect Stella

1. Open the Stella web panel (default: `http://localhost:5180`).
2. Go to **Settings > Google > Edit**.
3. Enter the **OAuth Client ID** and **OAuth Client Secret**.
4. Enter the Google email of the Stella user (e.g., `stella@yourdomain.com`) and its password for Chrome auto-login.
5. Click **Save**, then click **Connect Google Account**.
6. You will be redirected to Google's consent screen. Log in with the Stella Google account and grant the requested permissions.
7. Once redirected back to Stella, the Google Account status should show **Connected**.

## 6. (Optional) Enable 2FA for Chrome login

If you want to add 2FA security to the Stella Google account:

1. Sign in as the Stella user and enable **2-Step Verification** at [myaccount.google.com/signinoptions/two-step-verification](https://myaccount.google.com/signinoptions/two-step-verification).
2. Choose the **Authenticator app** option and save the TOTP secret.
3. Enter the TOTP secret in Stella's Google settings (Settings > Google > Edit > TOTP Secret).

This is entirely optional. Without 2FA, Stella will log in with just email + password.
