#!/usr/bin/env python3
"""Dynamic Ansible inventory sourced from Terraform outputs.

The single source of truth for the k3s node's IP address is the Terraform
state under ../../ (infra/). The address is DHCP-assigned and must never be
hardcoded, so this script resolves it at run time via `terraform output`.

Produces one host, `k3s-node`, in group `k3s`.
"""
import json
import os
import subprocess
import sys

INFRA_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def tf_output(name):
    try:
        raw = subprocess.check_output(
            ["terraform", f"-chdir={INFRA_DIR}", "output", "-raw", name],
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        sys.stderr.write(f"terraform output {name} failed: {exc}\n")
        sys.exit(1)
    return raw.decode().strip()


def inventory():
    ip = tf_output("k3s_node_ip")
    return {
        "k3s": {"hosts": ["k3s-node"]},
        "_meta": {"hostvars": {"k3s-node": {"ansible_host": ip}}},
    }


def main():
    if "--host" in sys.argv:
        print(json.dumps({}))
    else:
        print(json.dumps(inventory(), indent=2))


if __name__ == "__main__":
    main()
