# Google Workspace Setup

This guide walks through setting up Google Workspace for Stella. Return to the [main README](../README.md) when done.

## 1. Create a dedicated Workspace user

In **Google Workspace Admin** (`admin.google.com`) → Directory → Users, create a user for the agent (e.g., `stella@yourdomain.com`).

## 2. Configure the user account

Sign in as the new user and complete these steps:

1. Enable **2-Step Verification** at https://myaccount.google.com/signinoptions/two-step-verification — choose the **Authenticator app** option and save the TOTP secret (the text code shown during setup). Stella uses it for automated Chrome login.
2. Generate an **App Password** at https://myaccount.google.com/apppasswords — Stella uses it for IMAP access to scan transcription emails.

## 3. Create a GCP project and enable APIs

In **Google Cloud Console** (`console.cloud.google.com`):

1. Create a new project (or use an existing one).
2. Go to **APIs & Services → Library** and enable:
   - Google Calendar API
   - Google Meet REST API
   - Google Drive API

## 4. Create a service account

Still in **Google Cloud Console**:

1. Go to **IAM & Admin → Service Accounts** and create a new service account.
2. On the service account details page, go to the **Keys** tab → **Add Key → Create new key** → JSON. Save the downloaded file — you'll upload it through the Stella web interface.

## 5. Set up domain-wide delegation

This step connects the GCP service account to your Workspace domain so it can act on behalf of the agent user.

1. In **Google Cloud Console**, go to the service account details page and note the **Client ID** (a numeric ID, not the email).
2. In **Google Workspace Admin** (`admin.google.com`), go to **Security → Access and data control → API controls → Domain-wide delegation → Manage Domain Wide Delegation**.
3. Click **Add new** and enter:
   - **Client ID**: the numeric ID from step 1
   - **OAuth scopes** (comma-separated):
     ```
     https://www.googleapis.com/auth/calendar.events,https://www.googleapis.com/auth/meetings.space.created,https://www.googleapis.com/auth/drive.readonly
     ```
4. Click **Authorize**.
