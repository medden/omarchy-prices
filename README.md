# Prices for Omarchy

An [Omarchy](https://omarchy.org) bar widget that shows FX rates and crypto prices.

![Prices widget in the Omarchy bar](preview.png)

- **Crypto** prices from [CoinGecko](https://www.coingecko.com), with the 24h change in the tooltip.
- **FX** rates from [Frankfurter](https://frankfurter.dev), which serves European Central Bank reference rates. Any currency pair works.

Neither source needs an API key.

## Install

```bash
omarchy plugin add https://github.com/medden/omarchy-prices.git --enable
```

## Usage

| Action | Result |
|---|---|
| Left click | Refresh now |
| Hover | Full prices, 24h change, and the date of the FX rates |
| Scroll | Step through tickers (when rotation is on) |

If a refresh fails, the last prices stay up and the tooltip says so.

## Settings

Add settings to the widget's entry in `~/.config/omarchy/shell.json`. The bar picks up changes when you save.

```json
{
  "id": "io.github.medden.prices",
  "crypto": "bitcoin,ethereum,solana",
  "vsCurrency": "usd",
  "fxPairs": "EUR/USD,USD/JPY",
  "refreshMinutes": 5,
  "rotateSeconds": 0
}
```

| Key | Default | Meaning |
|---|---|---|
| `crypto` | `bitcoin,ethereum` | CoinGecko coin ids, comma-separated (the last part of the coin's coingecko.com URL). `""` hides crypto. |
| `vsCurrency` | `usd` | Currency crypto prices are quoted in. |
| `fxPairs` | `EUR/USD,GBP/USD` | `BASE/QUOTE` pairs, comma-separated. `""` hides FX. |
| `refreshMinutes` | `5` | How often to fetch prices. |
| `rotateSeconds` | `0` | `0` shows every ticker at once; any other value shows one ticker at a time, switching every that many seconds. |

On a vertical bar the widget shows `$`; prices are in the tooltip.

## Notes

- **FX rates update once per business day** (around 16:00 CET), not live, and don't change at weekends.
- CoinGecko's free endpoint is rate limited. Keep `refreshMinutes` at 1 or more, especially with several widget instances.
- Refresh from a script: `omarchy-shell io.github.medden.prices refresh`

## License

MIT
