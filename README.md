# fw-opnsense-assets

Public provisioning assets used by
[`mirzabigp-dotcom/fw-opnsense`](https://github.com/mirzabigp-dotcom/fw-opnsense)
to deploy OPNsense on Azure.

The infrastructure repository is private, so Azure virtual machines download
these files from this public repository during provisioning. Deployments should
use a commit-pinned raw URL:

```text
https://raw.githubusercontent.com/mirzabigp-dotcom/fw-opnsense/<commit>/scripts/
```

## Files

- `configureopnsense.sh` installs and configures OPNsense.
- `config.xml` configures the single-VM deployment.
- `config-active-active-primary.xml` and
  `config-active-active-secondary.xml` configure the HA deployment.
- `get_nic_gw.py` determines the Azure gateway address.
- `actions_waagent.conf` integrates the Azure Linux Agent with OPNsense.

## Security

The configuration XML files retain upstream default OPNsense credentials for
initial provisioning. Change all default administrative and synchronization
credentials immediately after deployment.

## Source

These files are adapted from
[`dmauser/opnazure`](https://github.com/dmauser/opnazure) at commit
[`7a16066dd410d4add19f70c44136bdddda051a2f`](https://github.com/dmauser/opnazure/commit/7a16066dd410d4add19f70c44136bdddda051a2f).
See [SOURCE.md](SOURCE.md) for details.

