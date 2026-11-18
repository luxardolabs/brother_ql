"""The suite runs against the installed wheel, never the source tree.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

from pathlib import Path

import brother_ql


def test_the_package_under_test_is_the_installed_wheel():
    location = Path(brother_ql.__file__).resolve()
    assert "site-packages" in location.parts, location
    assert "src" not in location.parts, location
