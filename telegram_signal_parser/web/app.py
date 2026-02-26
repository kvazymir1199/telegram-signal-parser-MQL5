import asyncio
import os
import html
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, Request, Form, BackgroundTasks
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger

from config.settings import settings, BASE_DIR
from database.connection import DatabaseManager
from telegram.client import TelegramSignalClient

app = FastAPI(title="Telegram Signal Parser Service")

# Add CORS middleware to allow HTMX requests from any local origin
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Setup templates
templates = Jinja2Templates(directory="web/templates")

# Global state for parser
class ParserState:
    def __init__(self):
        self.is_running = False
        self.task: Optional[asyncio.Task] = None
        self.client: Optional[TelegramSignalClient] = None

parser_state = ParserState()
db_manager = DatabaseManager(settings.database_path)


def get_db_manager() -> DatabaseManager:
    """Return the current db_manager (always up-to-date with settings)."""
    return db_manager


def reinit_db_manager() -> None:
    """Recreate db_manager when DATABASE_PATH setting changes."""
    global db_manager
    new_path = settings.database_path
    if str(db_manager.db_path) != str(new_path):
        logger.info(f"DATABASE_PATH changed → reinitializing db_manager: {new_path}")
        db_manager = DatabaseManager(new_path)
        db_manager.init_tables()

# Global task for signal expiry checker
expiry_checker_task: Optional[asyncio.Task] = None

@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log every incoming request for debugging (at DEBUG level to avoid noise)."""
    logger.debug(f"Incoming request: {request.method} {request.url.path}")
    response = await call_next(request)
    logger.debug(f"Response status: {response.status_code}")
    return response

@app.on_event("startup")
async def startup_event():
    """Initialize database, start background tasks, and load settings on startup."""
    global expiry_checker_task

    # Add a session separator to logs
    logger.info("\n" + "="*50 + f"\nNEW SESSION STARTED AT {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n" + "="*50)

    db_manager.init_tables()

    # Seed default settings from .env if DB is empty
    db_settings = db_manager.get_all_settings()
    if not db_settings:
        logger.info("Initializing database with default settings from environment...")
        defaults = {
            "TELEGRAM_API_ID": str(settings.telegram_api_id),
            "TELEGRAM_API_HASH": settings.telegram_api_hash,
            "TELEGRAM_PHONE": settings.telegram_phone,
            "TELEGRAM_CHANNELS": ",".join(map(str, settings.telegram_channels)),
            "FILTER_SYMBOLS": ",".join(settings.filter_symbols),
            "DATABASE_PATH": settings.database_path,
            "MAX_SL_DISTANCE": str(settings.max_sl_distance),
            "LOG_LEVEL": settings.log_level,
            "LOG_FILE": settings.log_file
        }
        db_manager.bulk_update_settings(defaults)
        db_settings = defaults

    # Update global settings object
    settings.update_from_db(db_settings)

    # Reinitialize db_manager if DATABASE_PATH changed from defaults
    reinit_db_manager()

    # Start signal expiry checker background task
    expiry_checker_task = asyncio.create_task(signal_expiry_checker())

    logger.info(f"Signal Parser Service started on http://127.0.0.1:{settings.web_port}")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup background tasks on shutdown."""
    global expiry_checker_task

    # Stop signal expiry checker
    if expiry_checker_task:
        expiry_checker_task.cancel()
        try:
            await expiry_checker_task
        except asyncio.CancelledError:
            pass
        logger.info("Signal expiry checker stopped")

    # Stop parser task
    if parser_state.is_running and parser_state.task:
        logger.info("Shutting down parser task...")
        parser_state.task.cancel()
        try:
            await parser_state.task
        except asyncio.CancelledError:
            pass

    logger.info("Web server shutdown complete")

async def run_parser():
    """Background task to run the parser."""
    try:
        parser_state.is_running = True
        parser_state.client = TelegramSignalClient()
        await parser_state.client.start()
    except asyncio.CancelledError:
        logger.info("Parser task cancelled")
    except Exception as e:
        logger.error(f"Parser encountered an error: {e}")
    finally:
        if parser_state.client and parser_state.client.client.is_connected():
            await parser_state.client.client.disconnect()
        parser_state.is_running = False
        parser_state.task = None


async def signal_expiry_checker():
    """Background task to check and expire old signals every second."""
    logger.info("Signal expiry checker started (60-minute validity window)")
    while True:
        try:
            db_manager.expire_old_signals(max_age_seconds=3600)
        except Exception as e:
            logger.error(f"Error in signal expiry checker: {e}")
        await asyncio.sleep(1)


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    """Render the main dashboard page."""
    db_settings = db_manager.get_all_settings()

    # Calculate simple stats
    with db_manager.get_session() as session:
        from sqlalchemy import select, func
        from database.models import Signal
        from datetime import date

        total_signals = session.execute(select(func.count(Signal.id))).scalar()

        # Signals for today
        today_start = datetime.combine(date.today(), datetime.min.time())
        today_signals = session.execute(
            select(func.count(Signal.id)).where(Signal.created_at >= today_start)
        ).scalar()

    return templates.TemplateResponse("index.html", {
        "request": request,
        "settings": db_settings,
        "is_running": parser_state.is_running,
        "stats": {
            "total": total_signals or 0,
            "today": today_signals or 0
        }
    })

@app.get("/signals", response_class=HTMLResponse)
async def signals_page(request: Request):
    """Render the signals history page."""
    with db_manager.get_session() as session:
        from sqlalchemy import select, desc
        from database.models import Signal
        stmt = select(Signal).order_by(desc(Signal.created_at))
        result = session.execute(stmt)
        signals = result.scalars().all()

    return templates.TemplateResponse("signals.html", {
        "request": request,
        "signals": signals,
        "is_running": parser_state.is_running
    })

@app.get("/signals/list", response_class=HTMLResponse)
async def signals_list(request: Request):
    """Render only the signals list for HTMX polling."""
    with db_manager.get_session() as session:
        from sqlalchemy import select, desc
        from database.models import Signal
        stmt = select(Signal).order_by(desc(Signal.created_at))
        result = session.execute(stmt)
        signals = result.scalars().all()

    return templates.TemplateResponse("signals_list_partial.html", {
        "request": request,
        "signals": signals
    })

@app.get("/debug/settings")
async def debug_settings():
    """Endpoint to check current settings state."""
    db_values = db_manager.get_all_settings()
    return {
        "memory": {
            "api_id": settings.telegram_api_id,
            "api_hash": "***" if settings.telegram_api_hash else None,
            "phone": settings.telegram_phone,
            "is_configured": settings.is_fully_configured()
        },
        "database": db_values
    }

@app.post("/settings/apply")
async def apply_settings(
    request: Request
):
    """Save settings to database and update global configuration."""
    form_data_raw = await request.form()
    logger.info(f"Incoming form request. Fields: {list(form_data_raw.keys())}")

    new_settings = {}
    mapping = {
        "telegram_api_id": "TELEGRAM_API_ID",
        "telegram_api_hash": "TELEGRAM_API_HASH",
        "telegram_phone": "TELEGRAM_PHONE",
        "telegram_channels": "TELEGRAM_CHANNELS",
        "filter_symbols": "FILTER_SYMBOLS",
        "max_sl_distance": "MAX_SL_DISTANCE",
        "database_path": "DATABASE_PATH",
        "log_level": "LOG_LEVEL",
        "web_port": "WEB_PORT"
    }

    # Numeric fields that must not be saved as empty string
    numeric_fields = {"max_sl_distance", "telegram_api_id", "web_port"}

    for form_key, db_key in mapping.items():
        val = form_data_raw.get(form_key)
        if val is not None:
            val_str = str(val).strip()
            # Skip saving empty value for numeric fields — keep existing DB value
            if form_key in numeric_fields and val_str == "":
                logger.warning(f"Skipping empty value for numeric field: {form_key}")
                continue
            new_settings[db_key] = val_str
            logger.debug(f"Form data: {form_key} -> {db_key} = {val_str if 'hash' not in form_key else '***'}")

    if not new_settings:
        logger.warning("No settings fields found in POST request")
        return HTMLResponse('<div class="bg-yellow-500 text-white p-2 rounded mb-4" id="flash-message">No settings provided to update.</div>')

    try:
        db_manager.bulk_update_settings(new_settings)

        # Reload and sync
        updated_db_settings = db_manager.get_all_settings()
        settings.update_from_db(updated_db_settings)

        # Reinitialize db_manager if DATABASE_PATH was changed
        reinit_db_manager()

        is_ok = settings.is_fully_configured()
        logger.success(f"Settings applied. System ready: {is_ok}")

        msg = f"Settings applied successfully! (Configuration: {'READY' if is_ok else 'INCOMPLETE'})"
        color = "bg-green-500" if is_ok else "bg-blue-500"

        return HTMLResponse(f'<div class="{color} text-white p-2 rounded mb-4" id="flash-message">{msg}</div>')
    except Exception as e:
        logger.error(f"Error applying settings: {e}")
        return HTMLResponse(f'<div class="bg-red-500 text-white p-2 rounded mb-4" id="flash-message">Error: {str(e)}</div>')

@app.post("/parser/start")
async def start_parser():
    """Start the parser background task."""
    # Force reload from DB before starting to be 100% sure
    db_settings = db_manager.get_all_settings()
    settings.update_from_db(db_settings)

    if not settings.is_fully_configured():
        # Return Stopped status + Out-of-band error notification
        return HTMLResponse(
            status_code=200,
            content='<span class="h-3 w-3 rounded-full bg-red-500 inline-block"></span><span class="ml-2 text-red-500 font-bold uppercase tracking-wider text-xs">Stopped</span>'
                    '<div hx-swap-oob="afterbegin:#flash-container">'
                    '<div class="bg-red-600 text-white p-4 rounded-xl shadow-lg mb-4 flex justify-between items-center animate-pulse" id="error-popup">'
                    '<div><i class="fa-solid fa-triangle-exclamation mr-2"></i> <strong>Configuration Required:</strong> Please enter your Telegram API ID, Hash, and Phone in Settings below.</div>'
                    '<button onclick="this.parentElement.remove()" class="ml-4 opacity-70 hover:opacity-100"><i class="fa-solid fa-xmark"></i></button></div></div>'
        )

    if not parser_state.is_running:
        parser_state.task = asyncio.create_task(run_parser())
        return HTMLResponse(status_code=200, content='<span class="flex h-3 w-3"><span class="animate-ping absolute inline-flex h-3 w-3 rounded-full bg-green-400 opacity-75"></span><span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span></span><span class="ml-2 text-green-500 font-bold">RUNNING</span>')
    return HTMLResponse(status_code=200)

@app.post("/parser/stop")
async def stop_parser():
    """Stop the parser background task."""
    if parser_state.is_running and parser_state.task:
        parser_state.task.cancel()
        return HTMLResponse(status_code=200, content='<span class="h-3 w-3 rounded-full bg-red-500 inline-block"></span><span class="ml-2 text-red-500 font-bold">STOPPED</span>')
    return HTMLResponse(status_code=200)

@app.post("/parser/test-signal")
async def test_signal():
    """Generate a fake signal for demonstration purposes."""
    from database.models import SignalStatus
    import random

    # 1. Create a dummy signal
    entry_min = 2350.0 + random.uniform(-10, 10)
    test_data = {
        "telegram_message_id": random.randint(1000, 9999),
        "telegram_channel_id": -123456789,
        "symbol": "XAUUSD",
        "direction": "BUY",
        "entry_min": round(entry_min, 2),
        "entry_max": round(entry_min + 2.0, 2),
        "stop_loss": round(entry_min - 10.0, 2),
        "take_profit_1": round(entry_min + 5.0, 2),
        "take_profit_2": round(entry_min + 15.0, 2),
        "take_profit_3": None,
        "raw_message": f"TEST SIGNAL: XAUUSD BUY @ {round(entry_min, 2)}",
        "content_hash": f"test_{datetime.now().timestamp()}",
        "status": SignalStatus.PROCESS.value
    }

    try:
        # 2. Save to DB
        db_manager.save_signal(test_data)

        logger.success("Test signal generated.")
        return HTMLResponse(
            status_code=200,
            content='<div hx-swap-oob="afterbegin:#flash-container">'
                    '<div class="bg-green-600 text-white p-4 rounded-xl shadow-lg mb-4 flex justify-between items-center" id="test-popup">'
                    '<div><i class="fa-solid fa-vial mr-2"></i> <strong>Test Success:</strong> Dummy signal generated!</div>'
                    '<button onclick="this.parentElement.remove()" class="ml-4 opacity-70 hover:opacity-100"><i class="fa-solid fa-xmark"></i></button></div></div>'
        )
    except Exception as e:
        logger.error(f"Failed to generate test signal: {e}")
        return HTMLResponse(content=f'<div class="bg-red-500 text-white p-2 rounded">Error: {e}</div>')

@app.get("/parser/status")
async def get_status():
    """Get current status of the parser for HTMX polling."""
    if parser_state.is_running:
        return HTMLResponse('<span class="flex h-3 w-3"><span class="animate-ping absolute inline-flex h-3 w-3 rounded-full bg-green-400 opacity-75"></span><span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span></span><span class="ml-2 text-green-500 font-bold">RUNNING</span>')
    else:
        return HTMLResponse('<span class="h-3 w-3 rounded-full bg-red-500 inline-block"></span><span class="ml-2 text-red-500 font-bold">STOPPED</span>')

@app.get("/parser/logs")
async def get_logs():
    """Return the last 50 lines of the log file."""
    log_file = settings.log_file
    if not os.path.exists(log_file):
        return HTMLResponse('<div class="text-slate-500 italic">No log file found yet...</div>')

    try:
        with open(log_file, "r", encoding="utf-8") as f:
            # Read last 100 lines
            lines = f.readlines()
            last_lines = lines[-100:]
            # Escape HTML to prevent XSS
            formatted_logs = html.escape("".join(last_lines))
            return HTMLResponse(f'<pre class="whitespace-pre-wrap font-mono text-[10px] leading-tight text-slate-300">{formatted_logs}</pre>')
    except Exception as e:
        return HTMLResponse(f'<div class="text-red-400">Error reading logs: {e}</div>')

@app.get("/settings/browse", response_class=HTMLResponse)
async def browse_directory(
    request: Request,
    current_path: str = None,
    target_input: str = "database_path"
):
    """List directories for the picker and return a partial HTML."""
    from pathlib import Path

    # Start at current path, settings path, or BASE_DIR
    if not current_path or not os.path.exists(current_path):
        current_path = str(BASE_DIR)

    # Ensure current_path is a directory
    if os.path.isfile(current_path):
        current_path = os.path.dirname(current_path)

    path_obj = Path(current_path).resolve()

    # List only directories
    items = []
    try:
        for item in path_obj.iterdir():
            if item.is_dir() and not item.name.startswith('.'):
                items.append({
                    "name": item.name,
                    "path": str(item.absolute()),
                })
        items.sort(key=lambda x: x["name"].lower())
    except PermissionError:
        logger.warning(f"Permission denied accessing directory: {current_path}")

    parent_path = str(path_obj.parent.absolute()) if path_obj != path_obj.parent else None

    return templates.TemplateResponse("directory_picker_partial.html", {
        "request": request,
        "current_path": str(path_obj),
        "parent_path": parent_path,
        "items": items,
        "target_input": target_input,
        "base_dir": str(BASE_DIR)
    })
