# tratrack service

Go HTTP service built with [Echo](https://echo.labstack.com/).

```bash
go run .
```

Listens on `:8080` (override with `PORT`). Endpoints:

- `GET /health` → `{"status":"ok"}`
