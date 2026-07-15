# Ansible — node configuration and k3s

Configures the Terraform-provisioned VM and installs single-node k3s.

## Layout

```text
ansible.cfg              connection defaults (user abdo, key auth)
inventory/terraform.py   dynamic inventory: resolves the VM IP from terraform output
group_vars/all.yml       pinned k3s version, local kubeconfig path
site.yml                 top-level playbook (base -> k3s)
roles/base              base packages
roles/k3s               pinned k3s install, kubeconfig fetch
```

The inventory reads the node IP from `terraform output k3s_node_ip`, so the
DHCP-assigned address is never hardcoded. The VM must be provisioned (`infra/`
applied) before running the playbook.

## Usage

```bash
cd infra/ansible
ansible-inventory --list          # sanity-check the resolved IP
ansible all -m ping               # connectivity
ansible-playbook site.yml         # install k3s (idempotent; re-runs are no-ops)
```

After a successful run the cluster kubeconfig is written to
`.artifacts/kubeconfig` (gitignored — it holds cluster credentials) with the
server URL rewritten to the VM's address:

```bash
export KUBECONFIG=$PWD/.artifacts/kubeconfig
kubectl get nodes
```

## Notes

- `host_key_checking` is disabled: the VM is recreatable, so its host key
  changes on rebuild. Acceptable for a local libvirt VM; revisit if the target
  ever becomes long-lived or remote.
- Bundled k3s add-ons (Traefik, local-path, servicelb, metrics-server) are kept
  on purpose — Traefik provides ingress and local-path provides PVCs.
- The k3s version is pinned in `group_vars/all.yml`; bump it deliberately.
