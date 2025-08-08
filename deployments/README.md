## About deployments

The contents of this directory have been migrated to the [mip-deployments](https://github.com/NeuroTech-Platform/mip-deployments) repository. Our deployments are private, therefore we do not commit them to this repo but we upkeep a public deployable sample here. The `shared-apps` is still in use but our `local` and `hybrid` federations reside in the other repository and might contain overridings of the `shared-apps` default configurations.

### For Private Users (MIP Team)

If you are a member of the MIP team, you do not have to change anything to your configs if you use the latest files of this repo.

### For Public Users

This repository still contains a working configuration that can be used for public local deployments.
However, you must run the following commands from the root directory of this repo.
```
cd mip-infra

# Switch any private git URLs to the public repo
sed -i 's|git@github.com:NeuroTech-Platform/mip-deployments.git|https://github.com/NeuroTech-Platform/mip-infra.git|g' base/mip-infrastructure/mip-infrastructure.yaml
sed -i 's|git@github.com:NeuroTech-Platform/mip-deployments.git|https://github.com/NeuroTech-Platform/mip-infra.git|g' base/argo-projects.yaml
sed -i 's|git@github.com:NeuroTech-Platform/mip-deployments.git|https://github.com/NeuroTech-Platform/mip-infra.git|g' deployments/shared-apps/mip-stack/mip-stack.yaml
sed -i 's|git@github.com:NeuroTech-Platform/mip-deployments.git|https://github.com/NeuroTech-Platform/mip-infra.git|g' deployments/shared-apps/exareme2/exareme2.yaml
sed -i '/git@github.com:NeuroTech-Platform\/mip-deployments.git/d' projects/static/mip-federations/mip-federations.yaml
sed -i '/git@github.com:NeuroTech-Platform\/mip-deployments.git/d' projects/templates/federation/values.yaml

# Remove MetalLB-specific lines from the public ingress Service (so it works generically)
sed -i '/metallb\.io\/address-pool: pool-no-auto/d' common/nginx-ingress/manifests/nginx-public-service.yaml
sed -i '/^\s*loadBalancerIP:\s*148\.187\.143\.44\s*$/d' common/nginx-ingress/manifests/nginx-public-service.yaml

```
