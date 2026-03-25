# Stella — AI Meeting Agent

Stella is an AI meeting agent that joins Google Meet calls as a voice participant. She listens, speaks, and answers questions using a knowledge base — replacing passive notetakers with an active team member.

## 1. Prerequisites

To make Stella work you'll need the next ingredients:

- An **OpenAI API key** with Realtime API access
- A **Google Workspace** account dedicated to the agent (basic Gmail won't work)
- A **Google Cloud project** with some APIs enabled and an OAuth Client

Not too complicated, but we know that GCP is not the friendliest of platforms so we prepared a step-by-step guide to help you get everything in place. Head over to the [Setup Guide](doc/google-workspace-setup.md) and follow along.

**-- Stop here (until you have all the elements from this step) --**

## 2. First Time Run

Now that you have all the ingredients, let's start Stella so you can fill in all that information and finish the setup in a friendly interface.

```bash
git clone https://github.com/Agent-Stella/agent-stella.git
cd agent-stella

# Create an admin user for the web interface
docker compose run --rm stella stella web setup

# Start the Stella daemon
docker compose up --build -d
```

Stella takes around 20-30 seconds to start up. Be patient. You can check the logs to see the progress:

```bash
docker compose logs -f
```

You know that Stella is running when you see the first `heartbeat`.

Then, access the web interface:

```
http://<stella-server-ip>:5180
```

Enter your admin details (the ones you just created) and you'll be guided through the onboarding process, which consists of 2 steps:

1. Fill in the data collected in [Prerequisites](#1-prerequisites)
2. Authorize your bot with OAuth

> **Heads up:** Authorize the **bot** account, not your own Google user. Otherwise you'll give Stella access to *your* calendar and email. It's an option and may not be that bad, but we sincerely recommend giving the bot its own space to live its life (and not mix its stuff with yours).

Done! You can now start using your bot to power up your meetings!

## 3. How to Use Stella

Stella does a few nice things. Here's an overview of what she can do:

- **Instant meetings** — You can make her create a meeting on the spot, which you and others can join on the go. She will auto-admit everyone and enable the note taker to take transcripts.

- **Join existing meetings** — You can make her join a meeting that already exists. You'll have to enable the note taker and accept others yourself, but she will join with all her knowledge to help and assist you.

- **Calendar invitations** — You (or others) can invite her into a future meeting by adding her to a calendar event. She will take the description of the event and prepare herself a good briefing before joining. She will be there at the given time, briefed and ready.

- **Post-meeting intelligence** — After any meeting she will monitor the email and calendar events looking for transcriptions and notes. She will take any related documents and ingest them to enrich her memory.

- **Known peers** — Her memory contains a list of known peers. Keep that list updated so she will auto-accept any events coming from those peers. If she's invited to an event by an unknown peer she will notify you and let you accept or decline the meeting for her.

- **Document knowledge** — Her memory can be fed with documents you consider of interest. She will ingest and analyse them, and all that knowledge will be available for her when she joins a meeting.

## 4. Is That All?

NO! Are you a skilled devops? Then you can make the most of her powerful command line. Everything that can be done through the web panel can also be done (and thus, automated) through her CLI.

Feel free to build an API and integrate her with your CRM or any software. Or what we love the most: give her to your [Openclaw](https://openclaw.com) assistant and let it manage her for you!

Check out the [full command line usage](doc/usage.md) for the complete reference and detailed examples.

## 5. Enjoy!

Enjoy Stella. Give us a star if you like what she does, recommend it to others, and of course don't hesitate asking questions or giving feedback. She will ingest it for our next meetings 😜
