# Security

Please do not report vulnerabilities publicly. Contact the maintainers through
the private security channel configured for the repository, including a
minimal reproduction and impact. Never send API keys or access tokens.

WakaBoard stores credentials in Keychain and keeps them out of cache, App Group
snapshots, widgets, logs, and previews. OAuth requires an operator-controlled
HTTPS relay; until configured, use only the advanced personal API-key flow.
