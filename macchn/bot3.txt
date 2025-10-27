import discord
from discord.ext import commands, tasks
import requests
import json
import os
import asyncio
import time

# ===== BOT 3 CONFIGURATION - CHANGE THESE =====
BOT_TOKEN = "MTQzMjE0MzUwODc5MzQ1ODczOQ.GMaJbi.EDWeuIBp3baZuOqY1AncWASM1hI-1PQAHy5FXY"
BOT_NAME = "Python Script Runner 24/7"
STATE_CHANNEL_ID = 1432329575962120203  # CHANGE THIS
OWNER_USER_ID = 802444845225869342
REFRESH_INTERVAL = 3000  # 50 minutes
# ===============================================

intents = discord.Intents.default()
intents.message_content = True
bot = commands.Bot(command_prefix='!', intents=intents)

active_tasks = {}
run_24_7_tasks = {}
instance_data = {}
run_24_7_data = {}

def can_user_run_script(user_id):
    if user_id == OWNER_USER_ID:
        return True, None
    if user_id in run_24_7_tasks:
        for name, task in run_24_7_tasks[user_id].items():
            if not task.done():
                return False, name
    return True, None

def is_script_already_running(script_link):
    for user_id, scripts in run_24_7_data.items():
        for name, data in scripts.items():
            if data.get('script_link') == script_link:
                if user_id in run_24_7_tasks and name in run_24_7_tasks[user_id]:
                    if not run_24_7_tasks[user_id][name].done():
                        return True, user_id, name
    return False, None, None

def parse_cookie_string(cookie_string):
    cookies = {}
    for cookie in cookie_string.split(';'):
        cookie = cookie.strip()
        if '=' in cookie:
            name, value = cookie.split('=', 1)
            cookies[name] = value
    return cookies

def save_user_cookies(user_id, cookies):
    if not os.path.exists('user_cookies'):
        os.makedirs('user_cookies')
    with open(f'user_cookies/cookies_{user_id}.json', 'w') as f:
        json.dump(cookies, f, indent=2)

def load_user_cookies(user_id):
    filename = f'user_cookies/cookies_{user_id}.json'
    if os.path.exists(filename):
        with open(filename, 'r') as f:
            return json.load(f)
    return None

def get_sandbox_id(session_id, cookies):
    url = "https://build.blackbox.ai/api/create-sandbox-for-session"
    headers = {"accept": "*/*", "content-type": "application/json", "referer": "https://build.blackbox.ai/chat-history"}
    payload = {"sessionId": session_id, "ports": [3000], "runDevServer": True}
    try:
        response = requests.post(url, headers=headers, json=payload, cookies=cookies, timeout=30)
        if response.status_code == 401:
            return {"error": "401 Unauthorized"}
        response.raise_for_status()
        data = response.json()
        if data.get("success"):
            return {"success": True, "sandboxId": data.get("sandboxId"), "sessionId": data.get("sessionId")}
        return {"error": "Request failed"}
    except Exception as e:
        return {"error": str(e)}

def create_terminal(sandbox_id, cookies):
    url = "https://build.blackbox.ai/api/terminals/create"
    headers = {"accept": "*/*", "content-type": "application/json", "referer": f"https://build.blackbox.ai/?sandboxId={sandbox_id}"}
    payload = {"sandboxId": sandbox_id, "name": f"terminal_{int(time.time() * 1000)}"}
    try:
        response = requests.post(url, headers=headers, json=payload, cookies=cookies, timeout=30)
        response.raise_for_status()
        data = response.json()
        if data.get("success"):
            return {"success": True, "terminalId": data["terminal"]["terminalId"]}
        return {"error": "Failed"}
    except Exception as e:
        return {"error": str(e)}

def execute_terminal_command(sandbox_id, terminal_id, command, cookies):
    url = "https://build.blackbox.ai/api/terminals/execute"
    headers = {"accept": "*/*", "content-type": "application/json", "referer": f"https://build.blackbox.ai/?sandboxId={sandbox_id}"}
    payload = {"sandboxId": sandbox_id, "terminalId": terminal_id, "command": command, "workingDirectory": "."}
    try:
        response = requests.post(url, headers=headers, json=payload, cookies=cookies, timeout=30)
        response.raise_for_status()
        return {"success": True}
    except Exception as e:
        return {"error": str(e)}

async def save_state_to_discord():
    try:
        channel = bot.get_channel(STATE_CHANNEL_ID)
        if not channel:
            return
        
        state = {'run_24_7_data': run_24_7_data, 'instance_data': instance_data, 'timestamp': time.time()}
        state_json = json.dumps(state, indent=2)
        
        async for msg in channel.history(limit=5):
            if msg.author == bot.user:
                await msg.delete()
        
        if len(state_json) < 1900:
            await channel.send(f"``````")
        else:
            chunks = [state_json[i:i+1900] for i in range(0, len(state_json), 1900)]
            for chunk in chunks:
                await channel.send(f"``````")
    except Exception as e:
        print(f"State save error: {e}")

async def load_state_from_discord():
    try:
        channel = bot.get_channel(STATE_CHANNEL_ID)
        if not channel:
            return False
        
        state_json = ""
        async for msg in channel.history(limit=5):
            if msg.author == bot.user and msg.content.startswith("```
                content = msg.content.replace("```json\n", "").replace("\n```
                state_json = content + state_json
        
        if state_json:
            global run_24_7_data, instance_data
            state = json.loads(state_json)
            run_24_7_data = state.get('run_24_7_data', {})
            instance_data = state.get('instance_data', {})
            return True
        return False
    except Exception as e:
        print(f"State load error: {e}")
        return False

@tasks.loop(minutes=5)
async def auto_save_state():
    await save_state_to_discord()

async def run_24_7_task(user_id, instance_name, session_id, script_link, pip_packages, cookies, channel):
    if user_id not in run_24_7_data:
        run_24_7_data[user_id] = {}
    cycle = 0
    while True:
        try:
            cycle += 1
            run_24_7_data[user_id][instance_name] = {"session_id": session_id, "script_link": script_link, "pip_packages": pip_packages, "cycle": cycle, "last_refresh": time.time()}
            await save_state_to_discord()
            
            await channel.send(f"🔄 **{instance_name}** Cycle #{cycle}")
            sandbox_result = get_sandbox_id(session_id, cookies)
            if "error" in sandbox_result:
                await channel.send(f"❌ Sandbox failed")
                await asyncio.sleep(300)
                continue
            sandbox_id = sandbox_result['sandboxId']
            
            terminal_result = create_terminal(sandbox_id, cookies)
            if "error" in terminal_result:
                await channel.send(f"❌ Terminal failed")
                await asyncio.sleep(300)
                continue
            terminal_id = terminal_result['terminalId']
            
            commands_list = [f"curl -o script.py {script_link}", "sudo dnf install -y python3 python3-pip"]
            for pkg in pip_packages:
                commands_list.append(f"pip3 install {pkg}")
            
            for cmd in commands_list:
                await asyncio.to_thread(execute_terminal_command, sandbox_id, terminal_id, cmd, cookies)
            
            await asyncio.to_thread(execute_terminal_command, sandbox_id, terminal_id, "python3 script.py &", cookies)
            
            run_24_7_data[user_id][instance_name].update({"sandbox_id": sandbox_id, "terminal_id": terminal_id})
            await save_state_to_discord()
            
            await channel.send(f"✅ **{instance_name}** Cycle #{cycle} running")
            await asyncio.sleep(REFRESH_INTERVAL)
            await asyncio.to_thread(execute_terminal_command, sandbox_id, terminal_id, "pkill -f script.py", cookies)
            
        except asyncio.CancelledError:
            if user_id in run_24_7_data and instance_name in run_24_7_data[user_id]:
                del run_24_7_data[user_id][instance_name]
            await save_state_to_discord()
            break
        except Exception as e:
            await channel.send(f"❌ Error: {str(e)}")
            await asyncio.sleep(300)

@bot.event
async def on_ready():
    print(f'✅ {BOT_NAME} ready!')
    await load_state_from_discord()
    if not auto_save_state.is_running():
        auto_save_state.start()

@bot.command(name='create')
async def create_sandbox(ctx):
    user_id = ctx.author.id
    saved_cookies = load_user_cookies(user_id)
    cookies = None
    if saved_cookies:
        await ctx.send("🍪 Use saved? (1=yes, 2=no)")
        try:
            msg = await bot.wait_for("message", timeout=60, check=lambda m: m.author == ctx.author and m.channel == ctx.channel and m.content in ["1","2"])
            if msg.content == "1":
                cookies = saved_cookies
        except:
            return
    if not cookies:
        await ctx.send("🍪 Paste cookies:")
        try:
            msg = await bot.wait_for("message", timeout=180, check=lambda m: m.author == ctx.author and m.channel == ctx.channel)
            cookies = parse_cookie_string(msg.content.strip())
            try:
                await msg.delete()
            except: pass
            save_user_cookies(user_id, cookies)
            await ctx.send("✅ Saved!")
        except:
            return
    await ctx.send("🔑 Session ID:")
    try:
        msg = await bot.wait_for("message", timeout=60, check=lambda m: m.author == ctx.author and m.channel == ctx.channel)
        session_id = msg.content.strip()
        result = get_sandbox_id(session_id, cookies)
        if "error" in result:
            await ctx.send(f"❌ {result['error']}")
        else:
            await ctx.send(f"✅ `{result['sandboxId']}`")
    except:
        pass

@bot.command(name='run_24/7')
async def run_script_24_7(ctx, script_link: str = None):
    user_id = ctx.author.id
    if not script_link:
        await ctx.send("❌ Usage: `!run_24/7 <link>`")
        return
    
    is_running, _, _ = is_script_already_running(script_link)
    if is_running:
        await ctx.send("⚠️ Script already running!")
        return
    
    can_run, existing = can_user_run_script(user_id)
    if not can_run:
        await ctx.send(f"❌ Already running: {existing}")
        return
    
    cookies = load_user_cookies(user_id)
    if not cookies:
        await ctx.send("❌ Use !create first")
        return
    
    await ctx.send("📝 Instance name:")
    try:
        msg = await bot.wait_for("message", timeout=60, check=lambda m: m.author == ctx.author and m.channel == ctx.channel)
        instance_name = msg.content.strip()
    except:
        return
    
    await ctx.send("🔑 Session ID:")
    try:
        msg = await bot.wait_for("message", timeout=60, check=lambda m: m.author == ctx.author and m.channel == ctx.channel)
        session_id = msg.content.strip()
    except:
        return
    
    await ctx.send("📦 Pip packages (type 'thatsall' when done):")
    pip_packages = []
    while True:
        try:
            msg = await bot.wait_for("message", timeout=120, check=lambda m: m.author == ctx.author and m.channel == ctx.channel)
            pkg = msg.content.strip()
            if pkg.lower() == 'thatsall':
                break
            pip_packages.append(pkg)
        except:
            break
    
    if user_id not in run_24_7_tasks:
        run_24_7_tasks[user_id] = {}
    
    task = asyncio.create_task(run_24_7_task(user_id, instance_name, session_id, script_link, pip_packages, cookies, ctx.channel))
    run_24_7_tasks[user_id][instance_name] = task
    await ctx.send(f"✅ Started {instance_name}")

@bot.command(name='stop_run')
async def stop_run(ctx, name: str = None):
    user_id = ctx.author.id
    if not name:
        await ctx.send("❌ Specify name")
        return
    if user_id in run_24_7_tasks and name in run_24_7_tasks[user_id]:
        run_24_7_tasks[user_id][name].cancel()
        await ctx.send(f"🛑 Stopped {name}")
    elif user_id in run_24_7_data and name in run_24_7_data[user_id]:
        del run_24_7_data[user_id][name]
        await save_state_to_discord()
        await ctx.send(f"🗑️ Cleared {name}")
    else:
        await ctx.send("❌ Not found")

@bot.command(name='list_24/7')
async def list_runs(ctx):
    user_id = ctx.author.id
    if user_id not in run_24_7_data or not run_24_7_data[user_id]:
        await ctx.send("❌ No instances")
        return
    msg = f"📊 **{BOT_NAME} Instances:**\n"
    for name, data in run_24_7_data[user_id].items():
        active = user_id in run_24_7_tasks and name in run_24_7_tasks[user_id] and not run_24_7_tasks[user_id][name].done()
        status = "🟢" if active else "⚠️"
        mins = int((time.time() - data.get('last_refresh', 0)) / 60)
        msg += f"{status} **{name}** - Cycle {data.get('cycle',0)} ({mins}m ago)\n"
    await ctx.send(msg)

@bot.command(name='ping')
async def ping(ctx):
    await ctx.send(f"🟢 {BOT_NAME} alive!")

if __name__ == "__main__":
    bot.run(BOT_TOKEN)
