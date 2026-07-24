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
- Updated conversion from stock FreeBSD 14.3 to OPNsense 26.1, followed by the
  supported OPNsense major upgrade to 26.7 (FreeBSD 15.1), with WALinuxAgent
  2.15.0.1.
- Preserved fail-fast bootstrap behavior so Azure reports installation errors.
- Deferred reboot until Azure integration and upgrade hooks are fully installed.
- Retained separate configuration files for single-VM and HA deployments.
- Added compatibility with the legacy Azure Custom Script extension on
  FreeBSD.
