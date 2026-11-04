#!/usr/bin/env bash
set -e

echo "=================================="
echo "       VC MUSIC BOT INSTALLER"
echo "=================================="

read -rp "BOT TOKEN: " BOT_TOKEN
read -rp "OWNER ID: " OWNER_ID

if [[ -z "$BOT_TOKEN" || ! "$OWNER_ID" =~ ^[0-9]+$ ]]; then
    echo "Invalid credentials."
    exit 1
fi

apt-get update -y
apt-get install -y python3 python3-venv ffmpeg

mkdir -p VC-MUSIC-BOT
cd VC-MUSIC-BOT

python3 -m venv venv
source venv/bin/activate

pip install -U discord.py yt-dlp PyNaCl

export BOT_TOKEN OWNER_ID

cat > bot.py <<'PY'
import os
import asyncio
import random
import discord
import yt_dlp

from discord.ext import commands
from discord import app_commands

TOKEN = os.environ["BOT_TOKEN"]
OWNER_ID = int(os.environ["OWNER_ID"])

intents = discord.Intents.default()
intents.voice_states = True
intents.guilds = True

bot = commands.Bot(command_prefix="!", intents=intents)

queues = {}
current = {}
loop_enabled = set()
volume_levels = {}

YDL_OPTIONS = {
    "format": "bestaudio/best",
    "quiet": True,
    "no_warnings": True,
    "noplaylist": True,
    "default_search": "ytsearch",
}

FFMPEG_OPTIONS = {
    "before_options": "-reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5",
    "options": "-vn"
}

async def extract(url):
    loop = asyncio.get_running_loop()

    def get_info():
        with yt_dlp.YoutubeDL(YDL_OPTIONS) as ydl:
            info = ydl.extract_info(url, download=False)
            if "entries" in info:
                info = info["entries"][0]
            return {
                "title": info.get("title", "Unknown"),
                "url": info["url"],
                "webpage": info.get("webpage_url", url),
                "duration": info.get("duration", 0)
            }

    return await loop.run_in_executor(None, get_info)

def get_queue(guild_id):
    return queues.setdefault(guild_id, [])

async def play_next(guild):
    gid = guild.id
    voice = guild.voice_client

    if not voice or not voice.is_connected():
        return

    if gid in loop_enabled and gid in current:
        item = current[gid]
    elif get_queue(gid):
        item = get_queue(gid).pop(0)
        current[gid] = item
    else:
        current.pop(gid, None)
        return

    try:
        audio = discord.FFmpegPCMAudio(item["url"], **FFMPEG_OPTIONS)
        source = discord.PCMVolumeTransformer(
            audio, volume=volume_levels.get(gid, 0.5)
        )

        def after(error):
            if error:
                print("Playback error:", error)
            fut = asyncio.run_coroutine_threadsafe(
                play_next(guild), bot.loop
            )
            try:
                fut.result()
            except Exception as e:
                print(e)

        voice.play(source, after=after)

    except Exception as e:
        print("Play error:", e)
        await play_next(guild)

async def add_song(interaction, url):
    await interaction.response.defer(thinking=True)

    try:
        item = await extract(url)
        gid = interaction.guild_id
        voice = interaction.guild.voice_client

        if not interaction.user.voice:
            return await interaction.followup.send(
                "Join a Voice Channel first."
            )

        channel = interaction.user.voice.channel

        if voice is None:
            voice = await channel.connect()
        elif voice.channel != channel:
            await voice.move_to(channel)

        get_queue(gid).append(item)

        await interaction.followup.send(
            f"Added to queue: **{item['title']}**"
        )

        if not voice.is_playing() and not voice.is_paused():
            await play_next(interaction.guild)

    except Exception as e:
        await interaction.followup.send(f"Error: {e}")

@bot.event
async def on_ready():
    await bot.tree.sync()
    print(f"VC MUSIC BOT ONLINE: {bot.user}")

@bot.tree.command(name="play", description="Play YouTube URL or search")
@app_commands.describe(query="YouTube URL or song name")
async def play(interaction: discord.Interaction, query: str):
    await add_song(interaction, query)

@bot.tree.command(name="pause", description="Pause music")
async def pause(interaction: discord.Interaction):
    v = interaction.guild.voice_client
    if v and v.is_playing():
        v.pause()
        await interaction.response.send_message("Music paused.")
    else:
        await interaction.response.send_message("Nothing is playing.")

@bot.tree.command(name="resume", description="Resume music")
async def resume(interaction: discord.Interaction):
    v = interaction.guild.voice_client
    if v and v.is_paused():
        v.resume()
        await interaction.response.send_message("Music resumed.")
    else:
        await interaction.response.send_message("Music is not paused.")

@bot.tree.command(name="skip", description="Skip current song")
async def skip(interaction: discord.Interaction):
    v = interaction.guild.voice_client
    if v and (v.is_playing() or v.is_paused()):
        v.stop()
        await interaction.response.send_message("Skipped.")
    else:
        await interaction.response.send_message("Nothing to skip.")

@bot.tree.command(name="stop", description="Stop music and clear queue")
async def stop(interaction: discord.Interaction):
    gid = interaction.guild_id
    queues[gid] = []
    loop_enabled.discard(gid)
    v = interaction.guild.voice_client

    if v:
        v.stop()

    current.pop(gid, None)
    await interaction.response.send_message("Music stopped.")

@bot.tree.command(name="leave", description="Leave voice channel")
async def leave(interaction: discord.Interaction):
    v = interaction.guild.voice_client
    if v:
        queues[interaction.guild_id] = []
        await v.disconnect()
        await interaction.response.send_message("Disconnected.")
    else:
        await interaction.response.send_message("Not connected.")

@bot.tree.command(name="join", description="Join your voice channel")
async def join(interaction: discord.Interaction):
    if not interaction.user.voice:
        return await interaction.response.send_message(
            "Join a Voice Channel first."
        )

    channel = interaction.user.voice.channel
    v = interaction.guild.voice_client

    if v:
        await v.move_to(channel)
    else:
        await channel.connect()

    await interaction.response.send_message(
        f"Joined {channel.name}."
    )

@bot.tree.command(name="queue", description="Show music queue")
async def queue(interaction: discord.Interaction):
    q = get_queue(interaction.guild_id)

    if not q:
        return await interaction.response.send_message("Queue is empty.")

    lines = [
        f"{i+1}. {x['title']}"
        for i, x in enumerate(q[:15])
    ]

    await interaction.response.send_message("\n".join(lines))

@bot.tree.command(name="nowplaying", description="Current song")
async def nowplaying(interaction: discord.Interaction):
    item = current.get(interaction.guild_id)

    if item:
        await interaction.response.send_message(
            f"Now Playing: **{item['title']}**\n{item['webpage']}"
        )
    else:
        await interaction.response.send_message("Nothing playing.")

@bot.tree.command(name="volume", description="Set volume 1-100")
async def volume(interaction: discord.Interaction, amount: app_commands.Range[int, 1, 100]):
    gid = interaction.guild_id
    volume_levels[gid] = amount / 100

    v = interaction.guild.voice_client
    if v and isinstance(v.source, discord.PCMVolumeTransformer):
        v.source.volume = amount / 100

    await interaction.response.send_message(
        f"Volume set to {amount}%."
    )

@bot.tree.command(name="loop", description="Toggle song loop")
async def loop(interaction: discord.Interaction):
    gid = interaction.guild_id

    if gid in loop_enabled:
        loop_enabled.remove(gid)
        msg = "Loop disabled."
    else:
        loop_enabled.add(gid)
        msg = "Loop enabled."

    await interaction.response.send_message(msg)

@bot.tree.command(name="shuffle", description="Shuffle queue")
async def shuffle(interaction: discord.Interaction):
    random.shuffle(get_queue(interaction.guild_id))
    await interaction.response.send_message("Queue shuffled.")

@bot.tree.command(name="clear", description="Clear queue")
async def clear(interaction: discord.Interaction):
    queues[interaction.guild_id] = []
    await interaction.response.send_message("Queue cleared.")

@bot.tree.command(name="remove", description="Remove queue item")
async def remove(interaction: discord.Interaction, position: int):
    q = get_queue(interaction.guild_id)

    if position < 1 or position > len(q):
        return await interaction.response.send_message("Invalid position.")

    item = q.pop(position - 1)
    await interaction.response.send_message(
        f"Removed: {item['title']}"
    )

@bot.tree.command(name="skipto", description="Skip to queue position")
async def skipto(interaction: discord.Interaction, position: int):
    q = get_queue(interaction.guild_id)

    if position < 1 or position > len(q):
        return await interaction.response.send_message("Invalid position.")

    del q[:position-1]
    v = interaction.guild.voice_client

    if v:
        v.stop()

    await interaction.response.send_message(
        f"Skipping to position {position}."
    )

@bot.tree.command(name="playnext", description="Add song to front of queue")
async def playnext(interaction: discord.Interaction, query: str):
    await interaction.response.defer(thinking=True)

    try:
        item = await extract(query)
        get_queue(interaction.guild_id).insert(0, item)
        await interaction.followup.send(
            f"Added next: {item['title']}"
        )
    except Exception as e:
        await interaction.followup.send(f"Error: {e}")

@bot.tree.command(name="search", description="Search YouTube")
async def search(interaction: discord.Interaction, query: str):
    await interaction.response.defer()

    try:
        item = await extract(f"ytsearch:{query}")
        await interaction.followup.send(
            f"**{item['title']}**\n{item['webpage']}"
        )
    except Exception as e:
        await interaction.followup.send(f"Search error: {e}")

@bot.tree.command(name="musichelp", description="Show music commands")
async def musichelp(interaction: discord.Interaction):
    await interaction.response.send_message(
        "**VC MUSIC COMMANDS**\n"
        "/play /playnext /search /pause /resume\n"
        "/skip /skipto /stop /leave /join\n"
        "/queue /nowplaying /volume /loop\n"
        "/shuffle /clear /remove /musichelp"
    )

@bot.tree.command(name="botinfo", description="Bot information")
async def botinfo(interaction: discord.Interaction):
    await interaction.response.send_message(
        f"VC Music Bot\nServers: {len(bot.guilds)}"
    )

bot.run(TOKEN)
PY

echo "Starting VC MUSIC BOT..."
exec ./venv/bin/python bot.py
