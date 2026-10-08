# LocalJev

LocalJev is a macOS menu bar app for running a local, Jev-compatible
`POST /v1/systemone` API. The app bundles the Bun server and provides controls
for the server port, upstream inference service, model, API keys, and launch
behavior.

The menu bar app requires macOS 13 or later. The app settings source of truth is
[`tray/Sources/LocalJevTray/ServerSettings.swift`](tray/Sources/LocalJevTray/ServerSettings.swift).

## App settings

The bundled app starts with these values:

| Setting | Default |
|---|---|
| LocalJev port | `8080` |
| Upstream URL | `http://127.0.0.1:8000` |
| Upstream API key | empty |
| Upstream model | `clef-flash` |
| LocalJev API key | empty |
| Start the server when the app launches | enabled |

On the first launch, the app can seed these settings from the following
environment variables:

| Environment variable | Setting |
|---|---|
| `LOCALJEV_PORT` | LocalJev port |
| `LOCALJEV_UPSTREAM` | Upstream URL |
| `LOCALJEV_UPSTREAM_API_KEY` | Upstream API key |
| `LOCALJEV_UPSTREAM_MODEL` | Upstream model |
| `LOCALJEV_API_KEY` | LocalJev API key |

The app saves the settings as encoded data in macOS UserDefaults under the
`serverSettings` key. Once saved settings exist, they take precedence over the
environment variables. The port must be an integer from 1 to 65535, and the
upstream URL cannot be empty.

## Build and run the app

Build the server and the menu bar app with:

```sh
make app
```

The build creates `tray/dist/LocalJev.app`. Open it directly or copy it to
`/Applications`:

```sh
open tray/dist/LocalJev.app
```

The app starts the bundled LocalJev process when the launch setting is enabled.
It checks `/health` and `/ready` on the configured local port. The server log
is stored at `~/Library/Application Support/LocalJev/localjev.log`.

## Run the server without the app

The server can also run directly with Bun. This mode uses the server configuration
from `src/config.ts` and `.env`, not the saved menu bar app settings.

Requires Bun 1.2 or later and a running OpenAI-compatible inference server:

```sh
bun install
cp .env.example .env
$EDITOR .env
bun run start
```

Bun loads `.env` automatically. The direct server listens on
`http://127.0.0.1:8080` by default. Check readiness with:

```sh
curl http://127.0.0.1:8080/ready
```

Make a decision:

```sh
curl http://127.0.0.1:8080/v1/systemone \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "jev-latest",
    "state": "Hi, I have been trying to connect Stripe but keep getting a 403 error.",
    "questions": {
      "department": {
        "type": "choice",
        "instructions": "Which team should handle this?",
        "criteria": {
          "billing": "Payment or subscription issues",
          "technical": "Bugs or integration problems",
          "sales": "Pricing or account questions"
        }
      },
      "frustration": {
        "type": "score",
        "instructions": "How frustrated does the customer appear?",
        "criteria": ["Calm", "Frustrated but civil", "Very angry"]
      },
      "urgent": {
        "type": "noul",
        "instructions": "Does this require an immediate response?"
      }
    }
  }'
```

## Use the TypeSafe SDK

The SDK requires an API key. LocalJev accepts any key unless
`LOCALJEV_API_KEY` is configured. Set the SDK environment for your shell:

```fish
set -gx TYPESAFE_BASE_URL http://127.0.0.1:8080
set -gx TYPESAFE_API_KEY local
```

```sh
export TYPESAFE_BASE_URL=http://127.0.0.1:8080
export TYPESAFE_API_KEY=local
```

```python
from typesafe_sdk import TypeSafeClient

client = TypeSafeClient()
response = client.system_one(
    "I was charged twice this month.",
    {
        "billing": {
            "type": "noul",
            "instructions": "Is this a billing issue?",
        }
    },
)
print(response.nouls["billing"].noul)
```

`jev-latest` and `jev-preview` are accepted aliases so SDK defaults work
unchanged.

## Direct server configuration

These variables apply when running the Bun server without the menu bar app. The
first five variables can also seed the app settings on its first launch.

| Variable | Default | Purpose |
|---|---|---|
| `LOCALJEV_UPSTREAM` | `http://127.0.0.1:8000` | OpenAI-compatible base URL, with or without `/v1` |
| `LOCALJEV_UPSTREAM_API_KEY` | empty | Bearer key sent to the inference server |
| `LOCALJEV_UPSTREAM_MODEL` | `diffusiongemma-26B-A4B-it-4bit` | Upstream model identifier |
| `LOCALJEV_API_KEY` | empty | Optional Bearer key required from LocalJev clients |
| `LOCALJEV_HOST` | `127.0.0.1` | Listen address |
| `LOCALJEV_PORT` | `8080` | Listen port |
| `LOCALJEV_TIMEOUT` | `180` | Upstream timeout in seconds |
| `LOCALJEV_MAX_INFLIGHT` | `2` | Concurrent calls admitted upstream |
| `LOCALJEV_MAX_QUEUE` | `64` | Waiting decisions before HTTP 529 |
| `LOCALJEV_MALFORMED_RETRIES` | `2` | Corrective retries for invalid model JSON |
| `LOCALJEV_MAX_OUTPUT_TOKENS` | `2048` | Per-completion output ceiling |
| `LOCALJEV_QUESTIONS_PER_CALL` | `16` | Chunking limit per model call |
| `LOCALJEV_OUTCOMES_PER_CALL` | `128` | Choice or score outcomes per model call |

## Development

```sh
bun install
bun test
bun run typecheck
bun run smoke
```

## Evaluate different models

The repeatable evaluation runs the LocalJev engine against five installed models
using AG News, BoolQ, and SST-5. It compares quality, calibration, retries, and
full-decision latency at two input lengths.

```sh
# Quick integration check. This is not a meaningful quality sample.
bun run eval --out eval/runs/pilot --limit 3

# 5 models x 120 labeled examples x 2 input lengths.
bun run eval --out eval/runs/my-bakeoff

# Regenerate a report without running inference.
bun run eval:report eval/runs/my-bakeoff
```

The evaluation requires oMLX and the upstream key in `.env`. It does not require
a running LocalJev HTTP server. See [the evaluation guide](docs/evaluation.md) for
data sources, methodology, configuration, resume behavior, and limitations.

The [first completed evaluation](docs/evaluation-results-2026-09-18.md) contains
1,200 requests on an Apple M5 Max. Its results are a small screening sample and
do not establish a production model choice.
