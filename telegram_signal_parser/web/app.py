import asyncio
import os
from typing import Optional
from fastapi import FastAPI, Request, Form, BackgroundTasks
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from loguru import logger

from config.settings import settings
from database.connection import DatabaseManager
from telegram.client import TelegramSignalClient

app = FastAPI(title="Telegram Signal Parser Dashboard")

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

@app.on_event("startup")
async def startup_event():
    """Initialize database and load settings on startup."""
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
            "EXPORT_PATH": settings.export_path,
            "MAX_SL_DISTANCE": str(settings.max_sl_distance),
            "LOG_LEVEL": settings.log_level,
            "LOG_FILE": settings.log_file
        }
        db_manager.bulk_update_settings(defaults)
        db_settings = defaults

    # Update global settings object
    settings.update_from_db(db_settings)
    logger.info("Dashboard web server started on http://127.0.0.1:7000")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup background tasks on shutdown."""
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

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    """Render the main dashboard page."""
    db_settings = db_manager.get_all_settings()
    return templates.TemplateResponse("index.html", {
        "request": request,
        "settings": db_settings,
        "is_running": parser_state.is_running
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

@app.post("/settings/apply")
async def apply_settings(
    request: Request,
    telegram_api_id: str = Form(...),
    telegram_api_hash: str = Form(...),
    telegram_phone: str = Form(...),
    telegram_channels: str = Form(...),
    filter_symbols: str = Form(...),
    max_sl_distance: str = Form(...),
    database_path: str = Form(...),
    export_path: str = Form(...),
    log_level: str = Form(...)
):
    """Save settings to database and update global configuration."""
    new_settings = {
        "TELEGRAM_API_ID": telegram_api_id,
        "TELEGRAM_API_HASH": telegram_api_hash,
        "TELEGRAM_PHONE": telegram_phone,
        "TELEGRAM_CHANNELS": telegram_channels,
        "FILTER_SYMBOLS": filter_symbols,
        "MAX_SL_DISTANCE": max_sl_distance,
        "DATABASE_PATH": database_path,
        "EXPORT_PATH": export_path,
        "LOG_LEVEL": log_level
    }

    db_manager.bulk_update_settings(new_settings)
    settings.update_from_db(new_settings)

    # Return HTMX partial or redirect
    if request.headers.get("HX-Request"):
        return HTMLResponse('<div class="bg-green-500 text-white p-2 rounded mb-4" id="flash-message">Settings applied successfully!</div>')
    return RedirectResponse(url="/", status_code=303)

@app.post("/parser/start")
async def start_parser():
    """Start the parser background task."""
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
        with open(log_file, "r") as f:
            # Efficiently read last lines
            lines = f.readlines()
            last_lines = lines[-50:]
            formatted_logs = "".join(last_lines)
            return HTMLResponse(f'<pre class="whitespace-pre-wrap font-mono text-[10px] leading-tight text-slate-300">{formatted_logs}</pre>')
    except Exception as e:
        return HTMLResponse(f'<div class="text-red-400">Error reading logs: {e}</div>')
