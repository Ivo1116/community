# Meta
[meta]: #meta
- Name: App Manifests v2
- Start Date: 2024-10-25
- Author(s): @gerg @tcdowney
- Status: Accepted
- RFC Pull Request: [community#1019](https://github.com/cloudfoundry/community/pull/1019)


## Summary

[App
manifests](https://docs.cloudfoundry.org/devguide/deploy-apps/manifest-attributes.html)
empower app developers to bulk-configure their apps and persist that
configuration alongside app code in source control.

This RFC proposes implementing a new major version, v2, of the app manifest
schema. App manifests v2 will add new functionality, ease future Cloud Foundry
feature development, and enable powerful user workflows. Notably, the v2
manifest will be
consistently-[declarative](https://blog.nelhage.com/post/declarative-configuration-management/),
consistent with modern developer expectations and technologies like BOSH,
Terraform, Concourse, and Kubernetes.

## Problem

App manifests currently support much, but not all, of the developer-relevant
configuration available on Cloud Foundry. The existing manifest structure
impedes supporting new features because it is heavily app-centric and laden with
backwards-compatibility-induced complexity.

In addition to issues with the current schema, app manifests are
inconsistently-declarative, which is a constant source of user confusion. In
addition, this makes it difficult to implement more advanced developer
workflows (e.g. [GitOps](https://www.gitops.tech/)), since some resources and
configuration values can not be deleted when applying manifests. For example,
it is currently not possible to unset environment variable or delete service
bindings by applying an app manifest.

### App Manifests vs Space Manifests

Historically, manifests have been called "app manifests", even though they can
contain multiple apps and create/modify non-app resources in a space. Because
of this, the Cloud Controller internally refers to them as [space
manifests](https://github.com/cloudfoundry/cloud_controller_ng/blob/cc0728d112ee98faf20432d6ff962726b73dedd5/app/controllers/v3/space_manifests_controller.rb).
For simplicity and historical continuity, this RFC refers to manifests as "app
manifests", but this is worth re-evaluating for the final implementation.

### Selection of Relevant GitHub Issues:

1. https://github.com/cloudfoundry/cloud_controller_ng/issues/1334
1. https://github.com/cloudfoundry/cloud_controller_ng/issues/1358
1. https://github.com/cloudfoundry/cloud_controller_ng/issues/2996
1. https://github.com/cloudfoundry/capi-release/issues/158
1. https://github.com/cloudfoundry/cli/issues/1710

## Proposal

### Guiding Principles

The low-level details of the v2 app manifest schema may change during
development, but the following should guide those decisions, whenever possible.

#### Mirror v3 API Design

Resources in the manifest should be named and structured similarly to the v3
API. This will reduce conceptual overhead for app developers and API consumers.
This has the additional benefit of reducing design overhead when adding new
features to app manifests, since the API design will serve as a strong
foundation.

#### Top-Level Resources

Space-level resources should have their own top-level configuration blocks,
rather than being nested under apps. For example, routes, service instances,
and service bindings are now top-level nodes, instead of being nested under
apps.

#### Prefer Extensible Data Types

Prefer using maps and sequences instead of scalar values. This makes it easier to
extend values with additional configuration in the future. For example, favor

```yaml
routes:
  - url: foo.example.com
```

over

```yaml
routes:
  - foo.example.com
```

and especially

```yaml
route: foo.example.com
```

#### Keys Use Underscores

Version 1 app manifests use a combination of underscores and hyphens for
multi-word keys. Schema version 2 keys should only use underscores, to match
the v3 API convention.

### Behavior

#### Version Node

Manifests currently support a `version` node, with `1` as the only supported
value:

```yaml
---
version: 1
applications:
  - ...
```

The `version` node enables Cloud Foundry to support different structures and
behaviors for new versions of app manifests, while continuing to support older
manifest schema versions.

Specifying the `version` as `2` will instruct Cloud Foundry to use the v2 app
manifest schema and behavior described by this RFC.

#### Non-Transactional

Like v1 manifests, applying a v2 manifest will NOT be transactional. The
configuration specified in the manifest will be applied in a non-deterministic
order and can fail when partially applied. Changes resulting from applying the
manifest will NOT be rolled-back in the event of a failure.

#### Declarative Configuration

Version 1 app manifests are currently inconsistently-declarative. For instance,
removing a buildpack from the `buildpacks` sequence will delete the buildpack
from the app configuration, however removing a route from the `routes` sequence
will NOT unmap the route from the app NOR will it delete the route.

Version 2 app manifests will declaratively apply configuration to resources. By
default, applying a manifest will update state _for all resources present in
the manifest_ to exactly match the manifest, including destructively updating
configuration (e.g unsetting environment variables). 

However, by default applying a v2 manifest will NOT delete top-level resources
in the space that are not present in the manifest. Deleting resources can be
costly (e.g. a data service instance), so it will require additional user
intent, beyond applying a manifest not including that resource.

##### Declarative Resource Deletion

For some advanced use cases, app developers will also want to delete resources
when applying a manifest. For example, when there is an upstream continuous
deployment system that assembles complete desired state, builds a space-level
manifest, and applies it to CF, ideally without requiring any imperative
commands.

In these cases, developers can opt-in to resource pruning for each top-level
resource. An example implementation of this could look like:

```yaml
---
meta:
  prune:
    routes: true
    apps: true
    service_instances: false # default
routes:
  - url: my.route.biz
apps:
  - name: my-app
```

##### Benefits

Declaratively applying app manifests will have multiple benefits,
including:
1. Internally-consistent behavior between manifest nodes
1. Easier onboarding and reduced confusion for users, since declarative
   configuration is industry-standard (e.g. BOSH, Terraform, Kubernetes)
1. Enables more powerful workflows for Cloud Foundry app developers (e.g. GitOps)

##### Prior Art

Since this is a major behavioral change for app manifests, here a survey of
some prior art for declarative configuration for similar products:
- https://www.meshcloud.io/en/blog/how-to-implement-declarative-deletion/
- https://blog.nelhage.com/post/declarative-configuration-management/
- https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/#automatic-pruning
- https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/#alternative-kubectl-apply-f-directory-prune

### Scope of Work

#### API

1. Add a `GET /v3/space/:guid/manifest` endpoint with a `version` query
   parameter for generating v2 app manifests
1. Update `POST /v3/spaces/:guid/actions/apply_manifest` to accept v2 manifests
1. Update `POST /v3/spaces/:guid/manifest_diff` to accept v2 manifests

#### CLI

1. Update `cf push` and `cf apply-manifest` to accept v2 manifests
1. Add `cf create-space-manifest` (or equivalent) command to generate a v2
   manifest for a space

##### Override Flags

Even though app manifests are parsed server-side, the CLI still has
[significant knowledge of the manifest
schema](https://github.com/cloudfoundry/cli/blob/fb9397c4a5db4a1ea4905ce4496e8b524794b40f/util/manifestparser/application.go#L18).
The CLI uses this knowledge to process nodes that depend on the local
filesystem (e.g. local source code `path`) and for processing push override
flags (e.g. `--memory`).

To simplify v2 manifest implementation, v2 manifests will not be compatible
with override flags. There are numerous options to get similar behavior without
requiring override flags, notably variable interpolation or yaml overlays.
Users who wish to continue using override flags can push apps with no manifests
or with v1 manifests.

This will also make future iteration on manifests easier, since most manifest
parsing logic can be centralized on Cloud Controller, rather than being split
across Cloud Controller and the CLI.

### Example v2 Manifest

_This example is intended to be evocative, rather than a final specification.
Some details of the v2 app manifest schema may change during implementation._

```yaml
---
version: 2
meta:
  prune:
    routes: true
    service_instances: false
    service_bindings: true
    apps: true
routes:
  - url: route.example.com/path
    destinations:
      - app:
          name: app1
          process:
            type: other
        port: 9999
      - app:
          name: app2
        protocol: http2
    metadata:
      annotations:
        potato: route metadata
  - url: tcp-route.example.com:5678
    protocol: tcp
    destinations:
      - app:
          name: app1
service_instances:
  - name: managed-service-instance
    service_offering:
      name: my-service-offering
    service_plan:
      name: my-service-plan
    tags:
      - my-tag
    parameters:
      key1: value1
    metadata:
      annotations:
        carrot: service instance metadata
  - name: user-provided-service-instance
    type: user-provided
    credentials:
      my-cred: secret1234
    syslog_drain:
      url: example.com/syslog
    route_service:
      url: example.com/route
  - name: route-service-instance
    service_offering:
      name: route-service-offering
    service_plan:
      name: route-service-plan
service_bindings:
  - type: app
    service_instance:
      name: managed-service-instance
    app:
      name: app1
    name: my-service-binding-name
    parameters:
      key1: value1
      key2: value2
    metadata:
      annotations:
        yam: service binding metadata
  - type: app
    service_instance:
      name: managed-service-instance
    app:
      name: app2
  - type: key
    service_instance:
      name: managed-service-instance
    name: my-service-key
  - type: route
    service_instance:
      name: route-service-instance
    route:
      url: route.example.com/path
apps:
  - name: app1
    package:
      path: /local/path/to/source/code
      metadata:
        annotations:
          cassava: package metadata
    lifecycle:
      type: buildpack
      buildpacks:
        - name: ruby_buildpack
        - name: java_buildpack
        - url: git.example.com/my_buildpack
      stack:
        name: cflinuxfs4
    environment_variables:
      VAR1: value1
      VAR2: value2
    features:
      ssh: true
    metadata:
      annotations:
        contact: bob@example.com jane@example.com
      labels:
        sensitive: true
    processes:
      - type: web
        command: start-web.sh
        scale:
          disk: 512M
          instances: 3
          memory: 500M
        health_checks:
          liveness:
            http_endpoint: /health_check
            type: http
            invocation_timeout: 10
            timeout: 10
          readiness:
            type: port
        metadata:
          annotations:
            taro: process metadata
      - type: worker
        command: start-worker.sh
        scale:
          disk: 1G
          instances: 2
          memory: 256M
        health_checks:
          liveness:
            type: process
            timeout: 15
  - name: app2
    state: STOPPED
    lifecycle:
      type: docker
    package:
      docker:
        image: docker-image-repository/docker-image-name
        access_credentials:
          - type: basic
            username: docker-user-name
            password: docker-user-password
    processes:
      - type: web
        scale:
          instances: 1
          memory: 256M
    sidecars:
      - name: authenticator
        processes:
          - type: web
          - type: worker
        command: bundle exec run-authenticator
        scale:
          memory: 800M
  - name: app3
    lifecycle:
      type: cnb
      buildpacks:
        - url: docker://example.org/java-buildpack:latest
        - url: docker://second-example.org/logging-buildpack:latest
      access_credentials:
        - type: basic
          url: example.org
          username: my-user
          password: my-pass
        - type: token
          url: second-example.org
          token: ABCD1234
      stack:
        name: cflinuxfs4
    package:
      path: /local/path/to/cnb/code
```

#### Notable Changes

**Meta**
- Add `meta` node to configure manifest behavior
- Add nested `prune` node to configure declarative resource deletion

**Routes**
- Move `routes` to top-level
- Route mappings are now "route-centric". The mappings are nested under routes,
instead of under apps.
- Add support for routing to non-`web` processes
- Add support for routing to custom ports
- Add metadata

**Service Instances**
- Move `service_instances` to top-level
- Add support for provisioning/updating service instances (previously, only
binding to existing service instances was supported)

**Service Bindings**
- Move `service_bindings` to top-level
- Add support for route bindings
- Add support for service keys
- Add metadata

**Apps**
- Add `package`, `lifecycle`, `processes.scale`, and `processes.health_checks` to organize nodes
- Add support for app features
- Add support for app state
- Add metadata to apps and nested app subresources
- Change `docker` (and `cnb`) access credentials to be a list (to enable future credential rotation feature)

### Future Extensions

What follows are some possible extensions for v2 manifests. These demonstrate
some of the future capabilities that could be enabled by v2 manifests. They are
not currently possible with v1 manifests, so they would be new features only
available with v2 manifests. These extensions are less-developed than the core
v2 manifest design, and may change significantly prior to implementation.

#### Droplets

Similar to the `--droplet` flag on `cf push` and the `package.path` node for
app resources proposed above, there could be a way to upload droplets when
pushing with a manifest.

Example manifest:
```yaml
---
apps:
  - name: app1
    droplet:
      path: /local/path/to/droplet.tgz
```

#### Remote Files

In addition to local paths, the manifest could be extended to support remote
files for packages and droplets. Unlike local file paths, these could be
handled server-side, which would further enable GitOps workflows. However,
handling remote files would introduce some of the same access and autentication
issues faced by docker-lifecycle-app's remote image registries.

Example manifest:
```yaml
---
apps:
  - name: app1
    package:
      path: https://example.com/app_source.tgz
      access_credentials:
        - type: basic
          username: new-user
          password: new-pass
        - type: basic
          username: old-user
          password: old-pass
```

#### Buildpack Fallback URL

Buildpacks can currently be specified as either admin-installed buildpack names
or remote urls. Since the set of installed buildpacks can vary between Cloud
Foundry deployments, it is difficult for manifest authors to know whether they
should reference a buildpack by name, or if they need to provide a url.

As requested in [this
issue](https://github.com/cloudfoundry/cloud_controller_ng/issues/1358),
manifests could allow referencing a buildpack by name, while also specifying a
url that will be used if the referenced buildpack is not available.

Example manifest:
```yaml
---
apps:
  - name: app1
    lifecycle:
      type: buildpack
      buildpacks:
        - name: my_buildpack
          url: git.example.com/my_buildpack
```

#### Shared Resources

Some resources can be shared across multiple spaces (currently, routes and
service instances). Sharing resources is not currently possible via app
manifests. Since these resources are no longer fully-contained within a space,
they require configuration split across multiple space-level manifests.

One option could be to add a boolean `shared` node to sharable resources, so
they are not automatically created in the destination space, but can still be
bound/mapped/etc to.

Source manifest:
```yaml
---
routes:
  - url: route.example.com
    destinations:
      - app:
          name: app1
service_instances:
  - name: my-service-instance
    bindings:
      apps:
        - name: app1
    share_to:
      - org: my-org
        space: my-space
```

Destination manifest:
```yaml
---
routes:
  - url: route.example.com
    shared: true
    destinations:
      - app:
          name: app1
service_instances:
  - name: my-service-instance
    shared: true
    bindings:
      apps:
        - name: app1
```

#### Network Policies

Similar to shared resources, container networking policies can span multiple
spaces. Currently, it is not possible to configure network policies via app
manifests.

Notably, network polices are managed by Policy Server, not by Cloud Controller,
so an additional integration will likely need to be built to support network
policies in manifests.

Manifest support for network policies is an [oft-requested
feature](https://github.com/cloudfoundry/cloud_controller_ng/issues/1334) and
will be required for implementing GitOps workflows for apps that use container
networking.

Destination manifest:
```yaml
---
routes:
  - url: destination-app.apps.internal
    destinations:
      - app:
          name: destination-app
network_policies:
  - destination:
      app:
        name: destination-app
        port_range: 1234-9999
    source:
      app:
        name: source-app
        org: source-app-org
        space: source-app-space
    protocol: tcp
```

Network policies will be specified in the destination app's space. No
configuration will be needed in the source app's space.

#### Per-Route Options

The recent [per-route features
RFC](https://github.com/cloudfoundry/community/blob/main/toc/rfc/rfc-0027-generic-per-route-features.md)
included additions to the manifest.

Example manifest:
```yaml
---
routes:
  - url: route.example.com/path
    options:
      loadbalancing: round-robin
      connection_limit: 15
      session_cookie: FOOBAR
      trim_path: true
```

#### Secrets

The recently-proposed [secrets
resource](https://github.com/cloudfoundry/community/pull/994) would also be a
good candidate for adding to manifests, if the corresponding RFC is adopted.

Example manifest:
```yaml
---
apps:
- name: my-app
  secrets:
    - name: my-secret
      mount_path: /etc
secrets:
- name: my-secret
  type: opaque
  value:
    username: AzureDiamond
    password: hunter2
```
