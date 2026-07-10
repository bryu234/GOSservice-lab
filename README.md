# GOSservice Lab

```bash
cp .env.example .env
# edit .env if needed
make up
# or
docker compose --env-file .env -f docker-compose.yml -f docker-compose.vm.yml up -d --build
```

macOS:

```bash
cp .env.example .env
# edit .env if needed
make up-local
# or
docker compose --env-file .env -f docker-compose.yml -f docker-compose.local.yml up -d --build
```
