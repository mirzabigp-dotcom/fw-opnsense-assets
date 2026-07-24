# Source and license

This repository contains provisioning assets adapted from
[`dmauser/opnazure`](https://github.com/dmauser/opnazure).

- Upstream commit:
  [`7a16066dd410d4add19f70c44136bdddda051a2f`](https://github.com/dmauser/opnazure/commit/7a16066dd410d4add19f70c44136bdddda051a2f)
- Upstream commit date: 2026-04-20
- License: MIT

The original MIT license is included in [LICENSE](LICENSE).

Local changes include:

- Improved input validation, quoting, logging, and Python discovery in the
  provisioning script.
- Updated support for FreeBSD 15.1, OPNsense 26.7, and WALinuxAgent 2.15.0.1.
- Retained separate configuration files for single-VM and HA deployments.
- Added compatibility with the legacy Azure Custom Script extension on
  FreeBSD.

