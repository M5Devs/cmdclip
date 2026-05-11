"""
ai.py — Groq AI integration for cmdclip
Provides: explain_command(), suggest_tags()
"""

import os
import json
from typing import Optional


def _get_key() -> Optional[str]:
    """Resolve Groq API key: env var first, then config file."""
    if key := os.environ.get("GROQ_API_KEY"):
        return key
    from cmdclip.storage import get_config
    return get_config().get("groq_api_key")


def _get_client():
    try:
        from groq import Groq
    except ImportError:
        raise ImportError(
            "groq package not installed. Run: pip install groq"
        )
    key = _get_key()
    if not key:
        return None
    return Groq(api_key=key)


def explain_command(cmd: str) -> str:
    """Return a plain-English explanation of a shell command."""
    client = _get_client()
    if not client:
        return "[!] No Groq API key found. Run: cmdclip config set-key <KEY>"

    try:
        response = client.chat.completions.create(
            model="llama3-8b-8192",
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are a shell command explainer. "
                        "Given a shell command, explain what it does clearly and concisely "
                        "in 2-4 sentences. Mention any risks if relevant. "
                        "Reply in plain text, no markdown."
                    ),
                },
                {
                    "role": "user",
                    "content": f"Explain this command:\n\n{cmd}",
                },
            ],
            max_tokens=200,
            temperature=0.3,
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        return f"[!] AI error: {e}"


def suggest_tags(cmd: str) -> list[str]:
    """
    Use AI to suggest relevant tags for a command.
    Returns a list of lowercase tag strings.
    Falls back to simple keyword matching if no API key.
    """
    client = _get_client()

    if not client:
        return _fallback_tags(cmd)

    try:
        response = client.chat.completions.create(
            model="llama3-8b-8192",
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are a shell command tagger. "
                        "Given a shell command, respond ONLY with a JSON array of 2-4 lowercase tag strings. "
                        "Tags should be tool names or categories like: docker, git, network, files, ops, python, ssh, etc. "
                        "Example output: [\"docker\", \"containers\", \"ops\"] "
                        "No explanation, no markdown, just the JSON array."
                    ),
                },
                {
                    "role": "user",
                    "content": f"Suggest tags for:\n\n{cmd}",
                },
            ],
            max_tokens=60,
            temperature=0.2,
        )
        raw = response.choices[0].message.content.strip()
        tags = json.loads(raw)
        if isinstance(tags, list):
            return [str(t).lower().strip() for t in tags if t][:4]
    except Exception:
        pass

    return _fallback_tags(cmd)


def _fallback_tags(cmd: str) -> list[str]:
    """Simple keyword-based tag fallback when AI is unavailable."""
    cmd_lower = cmd.lower()
    keyword_map = {
        "docker": ["docker", "containers"],
        "git": ["git", "vcs"],
        "ssh": ["ssh", "remote"],
        "python": ["python"],
        "pip": ["python", "pip"],
        "apt": ["apt", "linux", "packages"],
        "brew": ["brew", "macos", "packages"],
        "npm": ["npm", "node", "js"],
        "curl": ["curl", "network", "http"],
        "wget": ["wget", "network", "download"],
        "ffmpeg": ["ffmpeg", "media"],
        "grep": ["grep", "search", "text"],
        "find": ["find", "files"],
        "rm": ["files", "cleanup"],
        "chmod": ["files", "permissions"],
        "systemctl": ["systemd", "services", "linux"],
        "kubectl": ["kubernetes", "k8s", "ops"],
        "tar": ["archive", "files"],
        "rsync": ["rsync", "files", "sync"],
    }
    tags = []
    for keyword, t in keyword_map.items():
        if keyword in cmd_lower:
            tags.extend(t)
    return list(dict.fromkeys(tags))[:4] or ["general"]