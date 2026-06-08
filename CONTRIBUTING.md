# Contributing

Thanks for considering a contribution to 3xui Geo Updater.

## Good first contributions

- Fix unclear documentation or translations
- Report install issues with OS and shell details
- Add support notes for a Linux distribution you tested
- Improve logging, validation, or safety checks

## Before opening a pull request

1. Keep the change focused.
2. Test on a disposable server or container when possible.
3. Include the OS, 3x-ui version, and scheduler backend used for testing.
4. Avoid changing update sources without explaining the upstream license and maintenance status.

## Reporting issues

Please include:

- Linux distribution and version
- Memory size if Supercronic fallback is involved
- The command you ran
- Relevant log output from `/var/log/3xui-geo-updater.log`
- Whether `x-ui` was restarted unexpectedly or not restarted when expected

Security-sensitive reports should avoid publishing tokens, server IPs, or private configuration.