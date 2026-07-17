# Sealed secrets

SealedSecret manifests, synced into the cluster by the `secrets` Argo CD
Application (`gitops/applications/secrets/`). Each file is encrypted with the
public key of the in-cluster sealed-secrets controller — only that controller
can decrypt it, so these files are safe to keep in a public repository.

## Sealing a secret

The controller (installed by `gitops/applications/secrets/controller.yaml`)
must be running. With `kubeseal` pointed at the cluster:

```bash
export KUBECONFIG=../../infra/ansible/.artifacts/kubeconfig

# Adopt an existing kubectl-created Secret (skip for brand-new secrets):
kubectl -n chatwoot annotate secret chatwoot-secrets \
  sealedsecrets.bitnami.com/managed="true"

# Encrypt it into this directory:
kubectl -n chatwoot get secret chatwoot-secrets -o yaml \
  | kubeseal --format yaml > chatwoot-secrets.sealed.yaml
```

Commit the sealed file; Argo CD syncs it and the controller unseals it into
the namespace. The `managed` annotation lets the controller take ownership of
a pre-existing Secret without deleting or recreating it.

## Notes

- SealedSecrets are scoped to their name and namespace; a manifest cannot be
  unsealed under a different name.
- The sealing key pair lives only in the cluster. After a cluster rebuild the
  new controller cannot decrypt old manifests — re-create the plaintext Secret
  (see `helm/chatwoot/README.md`) and re-seal.
- Plaintext secret values never enter Git, in any form, in any commit.
