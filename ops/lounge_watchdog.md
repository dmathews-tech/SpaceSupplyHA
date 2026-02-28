# lounge_watchdog.sh

Runs projector idle recovery for Lounge screens.

## Security

Do not hardcode Home Assistant long-lived access tokens in the script.

Provide token with one of:

1. Env var (systemd/launchd):

```bash
export TOKEN="<ha_long_lived_token>"
```

2. Token file (default):

```bash
mkdir -p /home/pi/.config/lounge_watchdog
printf '%s\n' '<ha_long_lived_token>' > /home/pi/.config/lounge_watchdog/token
chmod 600 /home/pi/.config/lounge_watchdog/token
```

## Run

```bash
bash /home/pi/lounge_watchdog.sh
```

Optional overrides:

- `API_BASE`
- `A_IP`, `B_IP`
- `A_ENTITY`, `B_ENTITY`
- `FOCUS_REGEX`
- `QUIET_START_H`, `QUIET_END_H`, `TZ_EASTERN`
