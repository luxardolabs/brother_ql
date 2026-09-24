"""Command-line interface for brother_ql.

The library never goes looking for configuration; this CLI is the layer that does.
It discovers the conventional per-machine files, lowest precedence first::

    /etc/brother_ql/{labels,models}.json
    $XDG_CONFIG_HOME/brother_ql/{labels,models}.json   (default: ~/.config)
    ~/.brother_ql/{labels,models}.json                 (legacy location)

and hands each to the library through its explicit loaders, followed by anything
named with ``--labels`` / ``--models``. ``--no-user-config`` ignores the discovered
files entirely, which is what a reproducible run wants.

``brother-ql config`` prints what was found and what was loaded — the first thing
to run when a custom label "isn't there".

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import os
from pathlib import Path
from typing import IO, Any

import click

from brother_ql.conversion import convert
from brother_ql.exceptions import BrotherQLError
from brother_ql.labels import (
    LABELS_ENV_VAR,
    all_labels,
    get_labels_for_model,
    load_labels_from,
)
from brother_ql.models import MODELS_ENV_VAR, all_models, load_models_from
from brother_ql.raster import BrotherQLRaster


def _home() -> Path | None:
    """The user's home directory, or None where the environment has no home."""
    try:
        return Path.home()
    except RuntimeError:
        return None


def config_dirs() -> list[Path]:
    """Conventional configuration directories, lowest precedence first."""
    dirs = [Path("/etc/brother_ql")]
    home = _home()
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        dirs.append(Path(xdg) / "brother_ql")
    elif home is not None:
        dirs.append(home / ".config" / "brother_ql")
    if home is not None:
        dirs.append(home / ".brother_ql")
    return dirs


def discover_config(kind: str) -> list[Path]:
    """Existing `<kind>.json` files in the conventional directories, lowest first."""
    return [d / f"{kind}.json" for d in config_dirs() if (d / f"{kind}.json").is_file()]


def _load_config(
    label_files: tuple[Path, ...], model_files: tuple[Path, ...], user_config: bool
) -> list[Path]:
    """Merge discovered and explicitly named files into the library, lowest first."""
    loaded: list[Path] = []
    for path in (discover_config("labels") if user_config else []) + list(label_files):
        load_labels_from(path)
        loaded.append(path)
    for path in (discover_config("models") if user_config else []) + list(model_files):
        load_models_from(path)
        loaded.append(path)
    return loaded


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
@click.option(
    "--labels",
    "label_files",
    multiple=True,
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    help="Extra label JSON file, merged over the rest (repeatable).",
)
@click.option(
    "--models",
    "model_files",
    multiple=True,
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    help="Extra model JSON file, merged over the rest (repeatable).",
)
@click.option(
    "--user-config/--no-user-config",
    default=True,
    help="Read the conventional per-machine config files.",
)
@click.pass_context
def main(
    ctx: click.Context,
    label_files: tuple[Path, ...],
    model_files: tuple[Path, ...],
    user_config: bool,
) -> None:
    """Brother QL label printer tools."""
    try:
        loaded = _load_config(label_files, model_files, user_config)
    except (OSError, ValueError) as exc:
        # A broken config file is the user's to fix: report it as a CLI error with
        # the file and entry named, not as a traceback.
        raise click.ClickException(str(exc)) from exc
    ctx.obj = {"loaded": loaded}


@main.command("config")
@click.pass_context
def config_cmd(ctx: click.Context) -> None:
    """Show which configuration files were searched for and loaded."""
    obj: dict[str, Any] = ctx.obj
    loaded: list[Path] = obj["loaded"]

    if loaded:
        click.echo("Loaded, lowest precedence first:")
        for path in loaded:
            click.echo(f"  {path}")
    else:
        click.echo("Loaded: bundled definitions only.")

    click.echo("\nSearched:")
    for directory in config_dirs():
        click.echo(f"  {directory}/labels.json, {directory}/models.json")

    for var in (LABELS_ENV_VAR, MODELS_ENV_VAR):
        value = os.environ.get(var)
        click.echo(f"  {var}={value}" if value else f"  {var} unset")

    click.echo(f"\n{len(all_labels())} label(s), {len(all_models())} model(s).")


@main.command("labels")
@click.option("--model", help="Only labels usable on this printer model.")
def labels_cmd(model: str | None) -> None:
    """List the available label definitions."""
    specs = get_labels_for_model(model) if model else list(all_labels().values())
    for spec in sorted(specs, key=lambda s: s.identifier):
        size = (
            f"{spec.width_mm:g}x{spec.height_mm:g}mm"
            if spec.height_mm
            else f"{spec.width_mm:g}mm endless"
        )
        click.echo(
            f"{spec.identifier:<20} {size:<18} {spec.kind.value:<15} "
            f"{spec.printable_width}px"
        )


@main.command("models")
def models_cmd() -> None:
    """List the available printer models."""
    for spec in sorted(all_models().values(), key=lambda m: m.name):
        features = ", ".join(
            name
            for name, enabled in (
                ("two-color", spec.has_two_color),
                ("600dpi", spec.has_600_dpi),
                ("cutting", spec.has_cutting),
                ("compression", spec.has_compression),
            )
            if enabled
        )
        click.echo(f"{spec.name:<15} {spec.pixel_width:>5}px  {features}")


@main.command("convert")
@click.argument(
    "images",
    nargs=-1,
    required=True,
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
)
@click.option("--model", required=True, help="Printer model, e.g. QL-810W.")
@click.option("--label", "label_id", required=True, help="Label id, e.g. 62x29.")
@click.option(
    "-o",
    "--output",
    required=True,
    type=click.File("wb"),
    help="Write the raster instructions here ('-' for stdout).",
)
@click.option("--red/--no-red", default=False, help="Red/black printing (QL-8xx).")
@click.option("--dither/--no-dither", default=False, help="Dithering, for photos.")
@click.option("--cut/--no-cut", default=True, help="Cut after printing.")
@click.option("--compress/--no-compress", default=False, help="Compress if supported.")
@click.option("--600dpi", "dpi_600", is_flag=True, help="600 DPI mode if supported.")
@click.option("--threshold", default=70.0, show_default=True, help="B/W threshold %.")
@click.option("--rotate", default="auto", show_default=True, help="'auto' or degrees.")
@click.option("--offset-x", default=0, show_default=True, help="Horizontal offset, px.")
def convert_cmd(
    images: tuple[Path, ...],
    model: str,
    label_id: str,
    output: IO[Any],
    red: bool,
    dither: bool,
    cut: bool,
    compress: bool,
    dpi_600: bool,
    threshold: float,
    rotate: str,
    offset_x: int,
) -> None:
    """Convert image(s) to Brother QL raster instructions.

    The instructions are written as bytes; sending them to a printer is the
    caller's job (see the README for USB and network examples).
    """
    angle: str | int = int(rotate) if rotate.lstrip("-").isdigit() else rotate
    try:
        qlr = BrotherQLRaster(model)
        data = convert(
            qlr,
            list(images),
            label_id,
            red=red,
            dither=dither,
            cut=cut,
            compress=compress,
            dpi_600=dpi_600,
            threshold=threshold,
            rotate=angle,
            offset_x=offset_x,
        )
    except (BrotherQLError, OSError, ValueError) as exc:
        raise click.ClickException(str(exc)) from exc

    # click.File handles '-' (stdout) and opens a real path lazily, so a failed
    # conversion above leaves no empty file behind.
    output.write(data)
    name = getattr(output, "name", "-")
    if name != "-":
        click.echo(f"wrote {len(data)} bytes to {name}", err=True)
