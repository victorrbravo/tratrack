# tratrack

Analyze travel videos and extract the steps of a trip — name, location, date, money spent, description, tags, and media links — then browse them on a macOS canvas.

---

## Prerequisites

- **Go** 1.22+
- **Swift** 6.0+ (Xcode 16+ or swift.org toolchain)
- **PostgreSQL** 14+

---

## 1. PostgreSQL setup

### Install PostgreSQL

**macOS (Homebrew):**
```bash
brew install postgresql@16
brew services start postgresql@16
```

**Ubuntu/Debian:**
```bash
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

### Create the database and user

```bash
psql postgres
```

```sql
CREATE USER stories WITH PASSWORD 'stories';
CREATE DATABASE stories OWNER stories;
\q
```

### Load the schema

```bash
psql -U stories -d stories -f service/data/stories.sql
```

---

## 2. Go service

### Environment variables

Copy the example file and edit it:

```bash
cp service/.env.example service/.env
```

| Variable | Default | Description |
|---|---|---|
| `GRPC_ADDR` | `:50051` | Host and port the gRPC server listens on |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `stories` | PostgreSQL database name |
| `DB_USER` | `stories` | PostgreSQL user |
| `DB_PASS` | `stories` | PostgreSQL password |
| `MODEL_API_KEY` | *(empty)* | Muse API key — leave empty to use the simulated analyzer |
| `ANALYSIS_DURATION` | `5m` | Simulated analysis duration; set to e.g. `10s` for demos |
| `ANALYSIS_LOCATION` | `Paris` | City or country used to geocode places |
| `USER_ID` | `2` | stories-service user ID for storing results |
| `EMAIL` | *(empty)* | Email passed to the stories-service context |
| `CONTENT_TYPE` | `Senda` | Content type for new stories |

Minimal `.env` for local development:

```env
GRPC_ADDR=:50051
DB_HOST=localhost
DB_PORT=5432
DB_NAME=stories
DB_USER=stories
DB_PASS=stories
ANALYSIS_DURATION=10s
```

### Run the service

```bash
cd service
go run ./cmd/server
```

The server prints its address on startup:

```
gRPC server listening on :50051
```

---

## 3. macOS app

### Run

```bash
cd macos-app
swift run
```

You can also open a workflow JSON directly:

```bash
swift run TratrackApp ../examples/bogota.json
```

### Configure server address and API key

Open **Settings** (gear icon in the toolbar) to set:

| Setting | Description |
|---|---|
| **Server Address** | Host of the gRPC service (default: `localhost`) |
| **Server Port** | Port of the gRPC service (default: `50051`) |
| **Muse API Key** | Your Muse API key — required to upload videos for AI analysis |

The app connects to `localhost:50051` by default, which matches the service default.

---

## Workflow

1. **Start the service** (`go run ./cmd/server` from `service/`).
2. **Start the app** (`swift run` from `macos-app/`).
3. Click **Upload Video**, pick an `.mp4` file (≤ 50 MB).
   - Choose **Upload to AI** to send it to the Muse Files API and get a file ID.
   - Choose **Local Only** to skip upload and use the file for video-segment playback only.
4. Click **Analyze** to start the analysis job. Progress is shown in the status bar.
5. When analysis finishes, click **Search** (optionally type a filter) to load the workflow canvas.
6. The canvas shows each step as a sticky note. Right-click a step to:
   - Play its **video section**.
   - **Add a tag** (calls the stories-service and reloads the canvas).
7. Each card also has inline buttons:
   - **Lightbulb** — loads and shows tips for the step.
   - **Map pin** — opens the location in Apple Maps or Google Maps.
   - **Tags** — shows the tag list in a popover.
