#!/usr/bin/env bash
set -e

echo "======================================"
echo "       VELOCLOUD DISCORD BOT"
echo "======================================"

read -rp "BOT_TOKEN: " BOT_TOKEN
read -rp "OWNER_ID: " OWNER_ID

if [[ -z "$BOT_TOKEN" || ! "$OWNER_ID" =~ ^[0-9]+$ ]]; then
    echo "Invalid token or owner ID."
    exit 1
fi

mkdir -p VELOCLOUD
cd VELOCLOUD

apt-get update -y
apt-get install -y python3 python3-venv

python3 -m venv venv
source venv/bin/activate
pip install -U discord.py

export BOT_TOKEN OWNER_ID

cat > bot.py <<'PY'
import os, json, time, random, asyncio
from datetime import datetime
import discord
from discord.ext import commands

TOKEN = os.environ["BOT_TOKEN"]
OWNER = int(os.environ["OWNER_ID"])
PREFIX = "!"
DB = "data.json"

def load():
    try:
        with open(DB) as f:
            return json.load(f)
    except:
        return {"warnings": {}, "coins": {}, "levels": {}, "tickets": []}

data = load()

def save():
    with open(DB, "w") as f:
        json.dump(data, f, indent=2)

intents = discord.Intents.all()
bot = commands.Bot(command_prefix=PREFIX, intents=intents, help_command=None)
start_time = time.time()

def owner(ctx):
    return ctx.author.id == OWNER

def staff(ctx):
    return owner(ctx) or ctx.author.guild_permissions.manage_guild

async def say(ctx, message):
    await ctx.send(message)

@bot.event
async def on_ready():
    print(f"VELOCLOUD online: {bot.user}")

@bot.event
async def on_member_join(member):
    channel = discord.utils.get(member.guild.text_channels, name="welcome")
    if channel:
        await channel.send(f"Welcome {member.mention}!")

@bot.event
async def on_member_remove(member):
    channel = discord.utils.get(member.guild.text_channels, name="goodbye")
    if channel:
        await channel.send(f"{member} left the server.")

@bot.event
async def on_message(message):
    if message.author.bot:
        return
    if message.guild:
        key = str(message.author.id)
        data["levels"][key] = data["levels"].get(key, 0) + 1
        save()
    await bot.process_commands(message)

@bot.command()
@commands.is_owner()
async def setup(ctx):
    g = ctx.guild
    names = [
        "welcome", "goodbye", "server-logs", "mod-logs",
        "open-ticket", "announcements"
    ]
    for name in names:
        if not discord.utils.get(g.text_channels, name=name):
            await g.create_text_channel(name)
    await ctx.send("VELOCLOUD channels created.")

@bot.command()
async def ping(ctx):
    await say(ctx, f"Pong: {round(bot.latency*1000)}ms")

@bot.command()
async def uptime(ctx):
    await say(ctx, f"Uptime: {int(time.time()-start_time)} seconds")

@bot.command()
async def serverinfo(ctx):
    g = ctx.guild
    await say(ctx, f"Server: {g.name}\nMembers: {g.member_count}\nRoles: {len(g.roles)}")

@bot.command()
async def userinfo(ctx, member: discord.Member = None):
    m = member or ctx.author
    await say(ctx, f"User: {m}\nID: {m.id}\nJoined: {m.joined_at}")

@bot.command()
async def avatar(ctx, member: discord.Member = None):
    m = member or ctx.author
    await ctx.send(m.display_avatar.url)

@bot.command()
async def help(ctx):
    cmds = sorted(c.name for c in bot.commands)
    await ctx.send("**VELOCLOUD Commands**\n" + ", ".join(cmds))

@bot.command()
@commands.check(staff)
async def ban(ctx, member: discord.Member, *, reason="No reason"):
    await member.ban(reason=reason)
    await say(ctx, f"Banned {member}.")

@bot.command()
@commands.check(staff)
async def kick(ctx, member: discord.Member, *, reason="No reason"):
    await member.kick(reason=reason)
    await say(ctx, f"Kicked {member}.")

@bot.command()
@commands.check(staff)
async def timeout(ctx, member: discord.Member, minutes: int = 10):
    await member.timeout(discord.utils.utcnow() + discord.timedelta(minutes=minutes))
    await say(ctx, f"Timed out {member}.")

@bot.command()
@commands.check(staff)
async def untimeout(ctx, member: discord.Member):
    await member.timeout(None)
    await say(ctx, f"Timeout removed for {member}.")

@bot.command()
@commands.check(staff)
async def warn(ctx, member: discord.Member, *, reason="No reason"):
    key = str(member.id)
    data["warnings"][key] = data["warnings"].get(key, [])
    data["warnings"][key].append(reason)
    save()
    await say(ctx, f"Warned {member}: {reason}")

@bot.command()
async def warnings(ctx, member: discord.Member = None):
    m = member or ctx.author
    await say(ctx, str(data["warnings"].get(str(m.id), [])))

@bot.command()
@commands.check(staff)
async def clearwarns(ctx, member: discord.Member):
    data["warnings"][str(member.id)] = []
    save()
    await say(ctx, "Warnings cleared.")

@bot.command()
@commands.check(staff)
async def purge(ctx, amount: int):
    await ctx.channel.purge(limit=min(amount + 1, 1000))
    await ctx.send("Messages cleared.", delete_after=4)

@bot.command()
async def ticket(ctx):
    role = discord.utils.get(ctx.guild.roles, name="VELOCLOUD Staff")
    if role is None:
        role = await ctx.guild.create_role(name="VELOCLOUD Staff")
    overwrites = {
        ctx.guild.default_role: discord.PermissionOverwrite(view_channel=False),
        ctx.author: discord.PermissionOverwrite(view_channel=True, send_messages=True),
        role: discord.PermissionOverwrite(view_channel=True, send_messages=True),
        ctx.guild.me: discord.PermissionOverwrite(view_channel=True, send_messages=True)
    }
    channel = await ctx.guild.create_text_channel(
        f"ticket-{ctx.author.id}", overwrites=overwrites
    )
    await channel.send(f"{ctx.author.mention} Support ticket opened.")

@bot.command()
@commands.check(staff)
async def close(ctx):
    if ctx.channel.name.startswith("ticket-"):
        await ctx.send("Ticket closing.")
        await asyncio.sleep(2)
        await ctx.channel.delete()

@bot.command()
async def coinflip(ctx):
    await say(ctx, random.choice(["Heads", "Tails"]))

@bot.command()
async def dice(ctx):
    await say(ctx, str(random.randint(1, 6)))

@bot.command()
async def roll(ctx, sides: int = 6):
    await say(ctx, str(random.randint(1, max(2, min(sides, 1000)))))

@bot.command()
async def choose(ctx, *, options):
    items = [x.strip() for x in options.split(",") if x.strip()]
    await say(ctx, random.choice(items) if items else "Give options separated by commas.")

@bot.command()
async def say(ctx, *, message):
    if staff(ctx):
        await ctx.send(message)

@bot.command()
@commands.check(staff)
async def announce(ctx, *, message):
    channel = discord.utils.get(ctx.guild.text_channels, name="announcements")
    if channel:
        await channel.send(message)

@bot.command()
async def balance(ctx):
    await say(ctx, f"Coins: {data['coins'].get(str(ctx.author.id), 0)}")

@bot.command()
async def daily(ctx):
    key = str(ctx.author.id)
    data["coins"][key] = data["coins"].get(key, 0) + 100
    save()
    await say(ctx, "100 coins added.")

@bot.command()
async def work(ctx):
    key = str(ctx.author.id)
    amount = random.randint(10, 80)
    data["coins"][key] = data["coins"].get(key, 0) + amount
    save()
    await say(ctx, f"You earned {amount} coins.")

@bot.command()
async def leaderboard(ctx):
    top = sorted(data["coins"].items(), key=lambda x: x[1], reverse=True)[:10]
    await say(ctx, "\n".join(f"{i+1}. <@{u}>: {v}" for i, (u,v) in enumerate(top)) or "No data.")

# Extra distinct utility commands
def simple_command(name, response):
    async def callback(ctx):
        await ctx.send(response)
    callback.__name__ = name
    bot.command(name=name)(callback)

extras = {
    "hello":"Hello!", "invite":"Ask an admin for the bot invite link.",
    "support":"Contact VELOCLOUD support.", "rules":"Please follow server rules.",
    "website":"VELOCLOUD", "botinfo":"VELOCLOUD Discord Bot",
    "members":"Member count: {members}", "roles":"Role count: {roles}",
    "channels":"Channel count: {channels}", "emoji":"Emoji count: {emoji}",
    "created":"Server created: {created}", "id":"Server ID: {id}",
    "owner":"Server owner: {owner}", "boosts":"Boosts: {boosts}",
    "region":"Discord manages server regions automatically.",
    "random":"Random number: {random}", "time":"Time: {time}",
    "date":"Date: {date}", "quote":"Keep building. Keep learning.",
    "motivate":"You can do it!", "coffee":"Coffee break!",
    "ship":"Friendship level: {random}%", "hug":"Sending good vibes!",
    "rate":"Rating: {random}/10", "8ball":"Maybe. Ask again later.",
    "joke":"Why did the computer get cold? It left Windows open.",
    "fact":"A day on Venus is longer than its year.",
    "cat":"Cats are curious animals.", "dog":"Dogs are loyal companions.",
    "fox":"Foxes are clever animals.", "bird":"Birds have feathers.",
    "ping2":"Use !ping for latency.", "prefix":"Prefix: !",
    "commands":"Use !help to see commands.", "status":"Bot is online.",
    "economy":"Use !balance, !daily and !work.",
    "level":"Messages counted: {level}", "rank":"Your message count: {level}",
    "ticketinfo":"Use !ticket to open a private ticket.",
    "closeinfo":"Staff can use !close inside a ticket.",
    "staff":"Staff permissions are managed in Discord.",
    "security":"Security tools: ban, kick, timeout, warn, purge.",
    "moderation":"Moderation commands require server permissions.",
    "clear":"Use !purge <amount>.",
    "coin":"Use !coinflip.",
    "diceinfo":"Use !dice or !roll.",
    "server":"Use !serverinfo.",
    "user":"Use !userinfo.",
    "pfp":"Use !avatar.",
    "uptimeinfo":"Use !uptime.",
    "latency":"Use !ping.",
    "dailyinfo":"Use !daily once per day.",
    "workinfo":"Use !work to earn coins.",
    "balanceinfo":"Use !balance to check coins.",
    "leaderboardinfo":"Use !leaderboard.",
    "giveaway":"Giveaway management can be added in a later version.",
    "poll":"Poll: react to the message with your choice.",
    "suggest":"Send your suggestion to the staff team.",
    "report":"Contact staff to report an issue.",
    "feedback":"Thanks for your feedback!",
    "version":"VELOCLOUD Basic 1.0",
    "developer":"VELOCLOUD",
    "helpdesk":"Open a ticket with !ticket.",
    "rulesinfo":"Read the server rules channel.",
    "welcomeinfo":"Welcome channel is managed by !setup.",
    "goodbyeinfo":"Goodbye channel is managed by !setup.",
    "logs":"Server logs channel is created by !setup.",
    "announceinfo":"Staff can use !announce.",
    "setupinfo":"Owner can use !setup.",
    "online":"Online",
    "offline":"Check VPS host status.",
    "vps":"VELOCLOUD VPS support.",
    "linux":"Linux is an open-source operating system family.",
    "ubuntu":"Ubuntu is a Linux distribution.",
    "debian":"Debian is a Linux distribution.",
    "ssh":"SSH is a secure remote login protocol.",
    "cpu":"CPU means Central Processing Unit.",
    "ram":"RAM is temporary working memory.",
    "storage":"Storage keeps files and data.",
    "network":"Network connects devices.",
    "cloud":"Cloud services run on remote infrastructure.",
    "hosting":"Hosting makes services available online.",
    "domain":"A domain is a website address.",
    "dns":"DNS maps domain names to IP addresses.",
    "http":"HTTP is a web communication protocol.",
    "https":"HTTPS secures web communication.",
    "python":"Python is a programming language.",
    "bash":"Bash is a command-line shell.",
    "git":"Git tracks code changes.",
    "github":"GitHub hosts Git repositories.",
    "discord":"Discord is a communication platform.",
    "bot":"A bot automates tasks in Discord.",
    "helpme":"Use !help for command names.",
    "thanks":"You're welcome!",
    "bye":"Goodbye!",
    "goodnight":"Good night!",
    "goodmorning":"Good morning!",
    "goodluck":"Good luck!",
    "welcome":"Welcome!",
    "hey":"Hey!",
    "hi":"Hi!",
    "hello2":"Hello there!",
    "nice":"Nice!",
    "cool":"Cool!",
    "wow":"Wow!",
    "gg":"Good game!",
    "brb":"Be right back.",
    "afk":"Away from keyboard.",
    "back":"Welcome back!",
    "meme":"Memes make communities fun.",
    "fun":"Have fun in VELOCLOUD!",
    "music":"Music commands are not configured.",
    "play":"Music playback is not configured.",
    "stop":"Music playback is not configured.",
    "skip":"Music playback is not configured.",
    "queue":"Music playback is not configured.",
    "volume":"Music playback is not configured.",
    "weather":"Weather service is not configured.",
    "translate":"Translation service is not configured.",
    "remind":"Reminder service is not configured.",
    "timer":"Timer service is not configured.",
    "pollinfo":"Use Discord polls or reactions.",
    "inviteinfo":"Ask the server owner for an invite.",
    "profile":"Use !userinfo.",
    "rankinfo":"Use !rank.",
    "coins":"Use !balance.",
    "shop":"Shop system is not configured.",
    "buy":"Shop system is not configured.",
    "pay":"Coin transfers are not configured.",
    "deposit":"Bank system is not configured.",
    "withdraw":"Bank system is not configured.",
    "inventory":"Inventory system is not configured.",
    "dailybonus":"Use !daily.",
    "workbonus":"Use !work.",
    "claim":"No claims available.",
    "redeem":"No codes available.",
    "code":"No redeem codes available.",
    "feedbackinfo":"Send feedback to staff.",
    "reportinfo":"Report issues to staff.",
    "suggestinfo":"Send suggestions to staff.",
    "tickethelp":"Use !ticket.",
    "ticketclose":"Use !close inside a ticket.",
    "servericon":"Server icon: {icon}",
    "banner":"Server banner: {banner}",
    "emojis":"Use !emoji.",
    "membersinfo":"Use !members.",
    "rolesinfo":"Use !roles.",
    "channelsinfo":"Use !channels.",
    "boostinfo":"Use !boosts.",
    "createdinfo":"Use !created.",
    "ownerinfo":"Use !owner.",
    "idinfo":"Use !id.",
    "botstatus":"VELOCLOUD is online.",
    "credits":"VELOCLOUD Bot."
}

for name, response in extras.items():
    if name not in bot.all_commands:
        simple_command(name, response)

@bot.command()
async def members(ctx):
    await ctx.send(f"Members: {ctx.guild.member_count}")

@bot.command()
async def roles(ctx):
    await ctx.send(f"Roles: {len(ctx.guild.roles)}")

@bot.command()
async def channels(ctx):
    await ctx.send(f"Channels: {len(ctx.guild.channels)}")

@bot.command()
async def emoji(ctx):
    await ctx.send(f"Emojis: {len(ctx.guild.emojis)}")

@bot.command()
async def created(ctx):
    await ctx.send(str(ctx.guild.created_at))

@bot.command()
async def id(ctx):
    await ctx.send(str(ctx.guild.id))

@bot.command()
async def ownerinfo(ctx):
    await ctx.send(str(ctx.guild.owner))

@bot.command()
async def boosts(ctx):
    await ctx.send(str(ctx.guild.premium_subscription_count))

bot.run(TOKEN)
PY

python bot.py
