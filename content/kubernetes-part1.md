+++
title = "Kubernetes Workshop Part 1"
description = ""
date = 2019-09-18
weight = 0
draft = false
slug = "k8s-workshop-p1"
[taxonomies]
tags = ["kubernetes", "kubectl"]
categories = ["ops"]
+++

# Intro
First of all, I want to thank [Bastian Hofmann][1] for his time to share his knowledge with us. He is one of the major contributors to the [MetaKube Kubernetes as a Service product at SysEleven][2]. We shared an intensive 3 hours hands on workshop time on Kubernetes and a basic use-case of getting a simple PHP application running and adding the whole Kubernetes sugar. <!-- more -->

We used two major sources of knowledge / code:

- Slides as introduction to K8s on [speaker deck][3]
- K8s step-by-step guide for an example application in this [github repository][4].

On top of all of that, we had a whole K8s cluster up & running at SysEleven for the whole demo project. This made it very easy to get to speed easily.
# Prerequesites
## Required tools
This section describes, which tools you need to run through this tutorial.
### kubectl
`kubectl` is the most basic tool for managing your K8s cluster. It is written in `golang` and actually is a a client application which acts as an interface to the kubernetes HTTP API of the server.

On OSx, just use homebrew to install it:

```bash
brew install kubernetes-cli
```

You can find more information for the setup on different systems / OSes [here][5].

### helm
[Helm][6] is a package manager for running applications on k8s clusters.
You can install `helm` on OSx as follows:

```bash
brew install kubernetes-helm
```

For setting up `helm` on other OSes, please follow the [install guide][7]

### linkerd
[Linkerd][8] is a so-called service mesh for kubernetes. It provides tools for runtime debugging, observability, reliability, and security in your service cluster.

You can install `linkerd` cli tool on OSx as follows:

```bash
brew install linkerd
```

For installing up `linkerd` on other OSes, please follow the [linkerd install guide][9]

[1]: https://twitter.com/bastianhofmann
[2]: https://www.syseleven.de/produkte-services/kubernetes/
[3]: https://speakerdeck.com/bastianhofmann/deploying-your-first-micro-service-application-to-kubernetes-ddda6008-5d8f-4b26-903c-2da2a544c8b5
[4]: https://github.com/syseleven/golem-workshop
[5]: https://kubernetes.io/docs/tasks/tools/install-kubectl/
[6]: https://helm.sh/
[7]: https://helm.sh/docs/using_helm/#installing-helm
[8]: https://linkerd.io/
[9]: https://linkerd.io/2/getting-started/#step-1-install-the-cli

## Configuring kubectl
Before you can start to work on your kubernetes cluster, you have to configure `kubectl` to point to the right cluster and use the respective credentials. The default configuration file is located in your home directory in `~/.kube/config`.

**For this tutorial I recommend the K8s cluster on [Digital Ocean][10], because e.g. getting public IPs for LoadBalancer services just works without extra configuration hazzle.** The cheapest cluster costs $30 per month which comes down to roundabout $1 per day.

Alternatively, you can use [Minikube][11] as a local environment at no cost. However I did not test all of the tutorial steps on Minikube. 

### Kubectl config in detail
After setting up your Digital Ocean K8s cluster, your `~/.kubectl/config` file contents look like this:

```yml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ...
    server: https://***.k8s.ondigitalocean.com
  name: do-fra1-n2d
contexts:
- context:
    cluster: do-fra1-n2d
    user: do-fra1-n2d-admin
  name: do-fra1-n2d
current-context: do-fra1-n2d
kind: Config
preferences: {}
users:
- name: do-fra1-n2d-admin
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - kubernetes
      - cluster
      - kubeconfig
      - exec-credential
      - --version=v1beta1
      - --context=default
      - ***
      command: doctl
      env: null
```

There are three main entities:

* Clusters,
* Users,
* Contexts.

`clusters` are a list of K8s cluster definitions. Each cluster just has a `name` and a http url (`server`) pointing to the K8s API of the cluster plus some tls certificate data. If you are using many different clusters, this list can get long.

`users` is a list of credentials, each relevant for accessing one or multiple clusters. In case of digital ocean, the credentials are created ad-hoc by running the `doctl` command. For minikube, a user definition can use client certificate credentials:

```yml
users:
- name: minikube
  user:
    client-certificate: /Users/tim/.minikube/client.crt
    client-key: /Users/tim/.minikube/client.key
```

`contexts` defines a list of individual pairs of the `cluster` and `user` entities. A context links, which Cluster should be accessed by which User. 

When running kubectl, you can specify the context via the `--context` option, but you can also set it in the kubectl yaml config via the `current-context` option, so that you don't have to pass it along everytime.

You can get all existing contexts of the current kube config with:

```bash
$> kubectl config get-contexts
CURRENT   NAME          CLUSTER       AUTHINFO            NAMESPACE
*         do-fra1-n2d   do-fra1-n2d   do-fra1-n2d-admin
```

[10]: https://cloud.digitalocean.com/kubernetes/
[11]: https://kubernetes.io/docs/tasks/tools/install-minikube/

## Preparing the Repository
Before we can finally start, we have to clone and enter the golem workshop repository:

```bash
git clone git@github.com:syseleven/golem-workshop.git
cd golem-workshop
```

# Hands-On
## Resources
Your K8s cluster generally consists of `Resources`. Resources are things like

* Pods,
* ReplicaSets,
* Services,
* Deployments,
* Namespaces,
* etc ...

The list of existing `Resources` in your K8s cluster can be fetched by:
```bash
kubectl api-resources
```

You can list all existing instances of a resource by calling `kubectl get <resource-name>`.

Get existing `pods` or `namespaces`:

```bash
$> kubectl get pods
...

$> kubectl get namespaces
NAME              STATUS   AGE
default           Active   3h
kube-node-lease   Active   3h
kube-public       Active   3h
kube-system       Active   3h
```

Geting details for a specific resource works by adding it's identifier.
Here we fetch details of the namespace `default`.
```bash
$> kubectl get namespace default
NAME      STATUS   AGE
default   Active   3h9m
```

The power of K8s comes from the possibility to provide your own so-called `CustomResourceDefinitions` (CRDs), which can do whatever you like.

## Namespaces
`Namespaces` divide your `Resources` within a K8s cluster logically. There is no physical differentiation attached. Usually you can divide your cluster into namespaces like

* `monitoring` for all monitoring resources,
* `application` for all application relevant resources,
* ...

On Digital Ocean, the K8s cluster brings some basic namespaces and when you fetch resources with the `kubectl` command, it uses the current set `Namespaces` from the kube config. If not explicitly set, the fallback namespace is `default`.

For this tutorial, we want to create all resources for our web application in a namespace called `web-application`:

```bash
$> kubectl create namespace web-application
namespace/web-application created
```

We then set this namespace as the default for our context name `do-fra1-n2d`:

```bash
kubectl config set-context do-fra1-n2d --namespace=web-application 
```

Note, that our `~/.kube/config` changed the context value:
```yml
...
- context:
    cluster: do-fra1-n2d
    namespace: web-application
    user: do-fra1-n2d-admin
  name: do-fra1-n2d
...
```

Querying and creating resources subsequently will always happen in the namespace `web-application` unless we change it in the kube configuration or manually overwrite it with the `-namespace` option.