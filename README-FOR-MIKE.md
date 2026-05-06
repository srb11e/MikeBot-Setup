# Setting Up Your AI Bot

Hi Mike! This guide walks you through setting up your personal AI bot. The setup script does most of the work — you just need to follow the prompts.

---

## Before You Start

You'll need:
- Your Windows laptop, plugged in and connected to Wi-Fi
- Your phone (for setting up Telegram)
- About 30–45 minutes of uninterrupted time

---

## Step 1: Download and Extract

1. On this page, scroll down and click **MikeBot-Setup-v1.0.zip** to download it
2. Open your **Downloads** folder
3. Right-click the zip file and choose **Extract All...**
4. Click **Extract** (the default location is fine)
5. Open the extracted folder — you should see three files

---

## Step 2: Run the Setup

1. **Double-click `Setup-MikeBot.bat`** — this is the only file you need to open
2. Windows may show a blue "Windows protected your PC" screen:
   - Click **More info**
   - Then click **Run anyway**
3. A "Do you want to allow this app to make changes?" box will appear — click **Yes**
4. A blue/black window will open with the setup wizard

---

## Step 3: Follow the Wizard

The wizard walks you through 15 steps. Just read what's on screen and follow the instructions. Here's what to expect:

- **Steps 1–3:** Checks your Windows version, updates, and security settings
- **Steps 4–5:** Installs the tools your bot needs (Node.js, Git, Bitwarden, Telegram)
- **Step 6:** Walks you through creating a Telegram bot on your phone
- **Step 7:** Walks you through creating a DeepSeek AI account and getting an API key
- **Step 8:** Tests that your API key works
- **Steps 9–10:** Installs and configures OpenClaw (the AI engine)
- **Steps 11–12:** Checks that everything is running correctly
- **Step 13:** Connects your phone to the bot
- **Step 14:** Sends a test message to make sure everything works end-to-end
- **Step 15:** Done! Shows you what to do next

### Tips

- **Take your time.** Read each screen before pressing Enter.
- **When it says STOP** — stop and read carefully. Some steps need you to do something on your phone or in a browser first.
- **If something looks different** from what the wizard expects, take a screenshot and text Shands before continuing.

---

## If You Need to Stop

You can close the window at any time. Your progress is saved automatically.

To pick up where you left off, just **double-click `Setup-MikeBot.bat` again**. It will resume from the last step you completed.

---

## After Setup is Done

Once your bot is working:

1. **Test it:** Open Telegram on your phone, find your bot, and send it a message. You should get a reply within a few seconds.

2. **Clean up your keys:** The setup saved your API keys in a temporary file. After a few days of the bot working, delete that file. The wizard tells you exactly where it is and how to delete it.

3. **Set bot privacy:** Open Telegram, search for **@BotFather**, send `/setprivacy`, select your bot, and choose **Disable**. This prevents your bot from reading messages in group chats.

---

## If Something Breaks Later

Try these in order:

1. **Open PowerShell** (search "PowerShell" in the Start menu)
2. Type `openclaw gateway status` and press Enter
3. If it says it's not running, type `openclaw gateway restart` and press Enter
4. If that doesn't fix it, **double-click `Setup-MikeBot-Diagnostic.ps1`** (the third file from your download) — it checks everything and tells you what's wrong
5. Take a screenshot of the results and **text Shands**

### Bot stopped replying?

Your DeepSeek account comes with free credits that cover hundreds of conversations. If the bot stops replying after working for a while, your credits may have run out. Go to **platform.deepseek.com**, sign in, and check **Billing** to see your balance and add more credits if needed.

---

## Removing Everything

If you ever want to remove the bot and all the tools that were installed, here's how:

| What | How to Remove |
|------|---------------|
| OpenClaw | Open PowerShell, type `npm uninstall -g openclaw`, press Enter |
| Node.js | Windows Settings > Apps > search "Node.js" > Uninstall |
| Git | Windows Settings > Apps > search "Git" > Uninstall |
| Bitwarden | Windows Settings > Apps > search "Bitwarden" > Uninstall |
| Telegram Desktop | Windows Settings > Apps > search "Telegram" > Uninstall |
| Setup files | Open File Explorer, paste `%LOCALAPPDATA%\MikeBot-Setup\` in the address bar, delete the folder |
| Your Telegram bot | Open Telegram, send `/deletebot` to @BotFather, follow the prompts |
| DeepSeek account | Go to platform.deepseek.com > Account > Delete Account |

---

**Questions?** Text Shands.
