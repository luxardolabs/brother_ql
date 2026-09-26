# brother_ql documentation

*Last grounded: 2026-09-26 — brother_ql 2.0.0.*

| Page                                  | What's in it                                                                                                         |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| [Usage](usage.md)                     | Creating images, label sizes, conversion options, red/black, full-bleed, sending bytes to a printer, worked examples |
| [Configuration](configuration.md)     | Where label and printer definitions come from, adding your own, how merging works                                    |
| [Command line](cli.md)                | The `brother-ql` command, and the per-machine config discovery it owns                                               |
| [API reference](api.md)               | `convert()`, `BrotherQLRaster`, lookups, the extension API                                                           |
| [Troubleshooting](troubleshooting.md) | Off-center labels, print quality, red not printing, debug logging                                                    |
| [Advanced](advanced.md)               | Thermal printing findings, the raster buffer, protocol details, performance                                          |
| [Development](development.md)         | Running the tests, repository layout, the quality gate, contributing, releases                                       |

The [changelog](../CHANGELOG.md) records what changed in each version.

## About "last grounded"

Every page carries the date it was last checked against the running code, and the version it was checked against. A page whose marker is older than the current `VERSION` has not been re-verified — treat it as a claim, not a fact, and confirm against the code. When you edit a page, bump its marker.
