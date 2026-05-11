"""
templates.py — variable substitution engine for cmdclip
Supports: {var}, {var=default}
"""

import re
from typing import Optional


TEMPLATE_PATTERN = re.compile(r"\{(\w+)(?:=([^}]*))?\}")


def is_template(cmd: str) -> bool:
    """Return True if the command contains template variables."""
    return bool(TEMPLATE_PATTERN.search(cmd))


def get_variables(cmd: str) -> list[dict]:
    """
    Extract all variables from a template command.
    Returns list of {"name": str, "default": str|None}
    """
    seen = set()
    variables = []
    for match in TEMPLATE_PATTERN.finditer(cmd):
        name = match.group(1)
        default = match.group(2)
        if name not in seen:
            seen.add(name)
            variables.append({"name": name, "default": default})
    return variables


def resolve_template(cmd: str, values: Optional[dict] = None) -> str:
    """
    Replace template variables with provided values or prompt interactively.
    
    Args:
        cmd: The template command string
        values: Optional dict of {var_name: value} to use without prompting
    
    Returns:
        Resolved command string
    """
    variables = get_variables(cmd)
    if not variables:
        return cmd

    resolved_values = {}

    for var in variables:
        name = var["name"]
        default = var["default"]

        if values and name in values:
            resolved_values[name] = values[name]
        else:
            # Interactive prompt
            if default is not None:
                prompt = f"  {name} [{default}]: "
            else:
                prompt = f"  {name}: "

            user_input = input(prompt).strip()
            resolved_values[name] = user_input if user_input else (default or "")

    def replacer(match: re.Match) -> str:
        name = match.group(1)
        return resolved_values.get(name, match.group(0))

    return TEMPLATE_PATTERN.sub(replacer, cmd)


def preview_template(cmd: str) -> str:
    """Return a human-readable preview showing variables."""
    variables = get_variables(cmd)
    if not variables:
        return cmd

    lines = [f"Template: {cmd}", "Variables:"]
    for var in variables:
        if var["default"] is not None:
            lines.append(f"  - {var['name']} (default: {var['default']})")
        else:
            lines.append(f"  - {var['name']} (required)")
    return "\n".join(lines)