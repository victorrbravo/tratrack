# show-flow-data example

A standalone Go program that imports the `stories-service` library and runs
the `show_flow_data` workflow action (the same call as
`TestProcessShowFlowDataCtgFunction` in `pkg/workflow/input/input_test.go`).
It prints the JSON response: amounts grouped by day or by category for a ticket.

This folder is its **own Go module**, exactly like a program in another
repository would be.

## Run it

Start PostgreSQL (see the root README), then:

```bash
cd examples/show-flow-data

# Amounts by day for ticket 243
go run . -ticket 243 -by-day

# Amounts by category after Apr 30, only bill/coffee/cash
go run . -ticket 239 -filter ">apr30 and ctg- bill,coffee,cash" -by-day=false -page-size 20
```

| Flag | Default | Meaning |
|---|---|---|
| `-ticket` | `243` | Ticket (story) id |
| `-filter` | empty | Filter expression |
| `-by-day` | `true` | Group by day instead of by category |
| `-page`, `-page-size` | `1`, `12` | Pagination |
| `-email` | empty | User email passed in the context |

Database settings are read from `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`,
`DB_PASS` (or a `.env` file in this folder) and default to the Docker Compose
credentials.

## Use the same code in your own program

```bash
mkdir my-app && cd my-app
go mod init example.com/my-app
go get github.com/victorrbravo/stories-service@latest
```

Copy `main.go` and run `go mod tidy`.

The core of the program is just:

```go
var pg database.PostgresQuery
pg.Initialize(&database.DatabaseConfig{Host: "localhost", Port: 5432,
    Name: "stories", User: "stories", Password: "stories"})
if err := pg.Connect(); err != nil {
    log.Fatal(err)
}
query := pg.NewQuery()

order := []byte(`
action: show_flow_data
ticket: 243
filter:
by_day: true
page_number: 1
page_size: 12
`)
response, err := input.ProcessInput(context.Background(), order, &query)
```

> Inside this repository, `go.mod` uses
> `replace github.com/victorrbravo/stories-service => ../..` so the example
> builds against your local checkout. Programs outside the repo don't need it.
