# GOSservice Lab

```bash
cp .env.example .env
# edit .env if needed
make up
```

or

```bash
cp .env.example .env
# edit .env if needed
docker compose --env-file .env -f docker-compose.yml -f docker-compose.local.yml up -d --build
```

Ubuntu VM:

```bash
make up-vm
```
