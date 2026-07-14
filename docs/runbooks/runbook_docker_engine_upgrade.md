# Docker Engine upgrade runbook

## Scope

Controlled Docker Engine patch/minor upgrades on the two-node Swarm cluster.

## Preconditions

- Execute deployments and cluster validation from `master1`.
- Confirm all desired services are converged.
- Record package versions and `/etc/docker/daemon.json`.
- Validate NVIDIA driver and NVIDIA Container Toolkit before upgrading
  `master2`.
- Do not prune images, containers, networks or volumes during this procedure.

## Upgrade order

1. Keep `master1` operational as Swarm manager.
2. Upgrade `master2` first.
3. Validate Swarm, local containers, GPU runtime and Ollama inference.
4. Validate the full cluster from `master1`.
5. Update this documentation through a pull request.

## Validation

```bash
# master1
docker node ls
docker service ls

# master2
docker version
docker info --format '{{.Swarm.LocalNodeState}}'
docker info --format '{{.DefaultRuntime}}'
nvidia-smi
```

Required outcomes:

- both nodes report the intended Docker Engine version;
- `master2` is `Ready` and `Active`;
- Docker default runtime on `master2` is `nvidia`;
- all desired Swarm services converge;
- Ollama `/api/ps` reports `size_vram > 0`;
- Prometheus reports `up{job="nvidia_gpu"} = 1`.

## Rollback

Use the exact package versions recorded before the change:

```bash
sudo apt-get install -y   docker-ce=<previous-version>   docker-ce-cli=<previous-version>
sudo systemctl restart docker
```

After rollback, repeat all Swarm and GPU validations.
