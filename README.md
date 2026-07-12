# GOSservice Lab

```bash
cp .env.example .env
# edit non-Wazuh passwords and ports if needed
make up
```

macOS:

```bash
cp .env.example .env
# edit non-Wazuh passwords and ports if needed
make up-local
```

The three Wazuh passwords in `.env.example` satisfy the Wazuh complexity rules.
The indexer and dashboard values match the bcrypt hashes in
`services/gos_siem/config/wazuh_indexer/internal_users.yml`; the API value also
matches `services/gos_siem/config/wazuh_dashboard/wazuh.yml`. When rotating
these credentials, update the matching hash/config before recreating Wazuh.

Direct Compose startup remains available:

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.vm.yml up -d --build
```
