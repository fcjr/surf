# Contributing

Bug reports and pull requests are welcome. For a bug, include your macOS version,
Mac chip, remote generation, and steps to reproduce it. Say whether you're using
a release or a local build. Remove serial numbers, Bluetooth addresses, dictated
text, and other personal information from logs before sharing them.

See [the development guide](docs/development.md) for setup. Run `just test` before
submitting code changes. Add a regression test when fixing behavior that can be
checked without a physical remote, and describe any hardware checks you ran.

Keep pull requests focused on one change. For a larger change, open an issue first
so we can agree on the behavior before you spend time implementing it.

Surf's original code is MIT licensed. Contributions should use the same license.
Preserve the notices on adapted code and include licenses for new dependencies.
