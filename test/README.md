# Testing

When running tests, you must start the environment with the development override configuration. This is necessary because the development override maps ports for each individual container to the host machine, which allows the tests to communicate with the services directly.
And in production, the mapping should only happen to the API Gateway.

To start the environment for testing, run:

```bash
docker compose -f deployment_manifest/local-docker-compose/docker-compose.yml -f deployment_manifest/local-docker-compose/docker-compose.dev.yml up -d
```
