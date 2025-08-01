## About deployments

The contents of this directory have been migrated to the [mip-deployments](https://github.com/NeuroTech-Platform/mip-deployments) repository. Our deployments are private, therefore we do not commit them to this repo but we upkeep a public deployable sample here. The `shared-apps` is still in use but our `local` and `hybrid` federations reside in the other repository and might contain overridings of the `shared-apps` default configurations.

### For Private Users (MIP Team)

If you are a member of the MIP team, you do not have to change anything to your configs if you use the latest files of this repo.

### For Public Users

This repository still contains a working configuration that can be used for public local deployments.
However, you must run the following commands from the root directory of this repo.
```
sed -i 's|git@github.com:NeuroTech-Platform/mip-deployments.git|https://github.com/NeuroTech-Platform/mip-infra.git|g' mip-infra/base/mip-infrastructure/mip-infrastructure.yaml
sed -i 's|git@github.com:NeuroTech-Platform/mip-deployments.git|https://github.com/NeuroTech-Platform/mip-infra.git|g' mip-infra/base/argo-projects.yaml
sed -i '/git@github.com:NeuroTech-Platform\/mip-deployments.git/d' mip-infra/projects/static/mip-federations/mip-federations.yaml
sed -i '/git@github.com:NeuroTech-Platform\/mip-deployments.git/d' mip-infra/projects/templates/federation/values.yaml
```

