# Setup Guide

Stella lives in the Google ecosystem. Like it or not, that's how she does. So if you want Stella in your meetings then you need to prepare her a few things.

Not too complicated, just do these steps and you should be done in a few minutes.

Return to the [main README](../README.md) when done.

---

## 1. The Voice Backend API Key

Stella supports two voice backends: **OpenAI Realtime** and **Google Gemini Live**. You only need one — pick whichever you prefer.

### Option A: OpenAI

1. Log in to [platform.openai.com](https://platform.openai.com)
2. Go to your settings, find the **Billing** section (usually [here](https://platform.openai.com/settings/organization/billing/overview))
3. Add a payment method
4. Go to your default project, find the **API keys** section
5. Create an API key. Note it for later.

### Option B: Gemini

1. Go to [Google AI Studio](https://aistudio.google.com/apikey)
2. Create an API key (or use an existing one)
3. Note it for later.

Done!

---

## 2. The Google Workspace User

Yes, Stella needs a Google Workspace user. Basic Gmail access won't work because it lacks important functionalities that Stella needs (like managing transcripts), and also the OAuth Client that we'll prepare in the next section needs to be in the same domain as the Stella user. This is so we don't have to make the OAuth gateway public, which involves Google reviewing it and takes long to approve.

> **Note:** The bot's email address needs to be in the same domain as the OAuth client. Otherwise you'll have to publish the OAuth client as open and go through Google review and acceptance, which may take hours or days.

So let's create a Google Workspace user for Stella:

1. Go to [admin.google.com](https://admin.google.com)
2. Go into **Directory > Users**
3. Create a user for Stella (e.g., `stella@yourdomain.com`)
4. Note the email and the password for later

Done! (one less step...)

---

## 3. Google Cloud, the Ugly Monster

Google Cloud is a beast. Don't worry if you are not familiar with it. Just follow these steps and you'll be done in 3 minutes.

### Enable the APIs

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project (**IAM & Admin > Create a project**), or use an existing one
3. Go to **APIs & Services > Library** and enable:
   - Google Calendar API
   - Google Meet REST API
   - Gmail API
   - Google Drive API

### Create the OAuth Consent Screen

1. Go to **APIs & Services > OAuth consent screen**
2. Choose **Internal** (for Google Workspace) — this means only users in your organization can authorize. No Google app verification needed.
3. Fill in the app name (e.g., "Stella") and your email as the support contact
4. No scopes need to be added
5. Click **Save**

### Create the OAuth Client ID

1. Go to **APIs & Services > Credentials**
2. Click **Create Credentials > OAuth client ID**
3. Choose **Web application** as the application type
4. Under **Authorized redirect URIs**, add:
   ```
   http://localhost:5180/auth/google/callback
   ```
   Or, if Stella is hosted on a public IP or the server has a name:
   ```
   http://<server-ip-or-name>:5180/auth/google/callback
   ```
5. Click **Create** and note the **Client ID** and **Client Secret** for later

---

## ALL DONE!!

Yes, no jokes, all done. Pain is over.

### Recap

If you did everything right you should now have:

- An **OpenAI API key** or a **Gemini API key** (one of the two)
- A **Google user** (email + password)
- An **OAuth Client ID** + **Client Secret**

If you have all of these then head back to the [README](../README.md#2-first-time-run) to start Stella and finish the setup from her web interface (easy and painless).

If you are missing any of these then don't worry, just breathe and start over :sweat_smile:
