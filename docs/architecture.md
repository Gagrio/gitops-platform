# 🏛️ Architecture Overview

## 🗺️ Platform Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            GIT REPOSITORY (GitHub)                              │
│                                                                                 │
│   terraform/           ansible/           gitops/            docs/              │
│   ├── modules/         ├── roles/         ├── clusters/       ├── architecture  │
│   │   ├── network      │   ├── base       │   ├── dev/        └── runbooks/     │
│   │   ├── node         │   ├── k8s        │   └── prod/                         │
│   │   └── firewall     │   └── security   ├── operators/                        │
│   └── environments/    └── playbooks/     │   └── postgres/                     │
│       ├── dev/             bootstrap.yml  └── applications/                     │
│       └── prod/                               └── demo-app/                     │
└───────────────┬──────────────────────┬──────────────────────────────────────────┘
                │                      │
        terraform apply        ansible-playbook bootstrap.yml
                │                      │
                │              ┌───────┴────────────────────┐
                │              │ roles/base                 │
                │              │ roles/kubernetes  (k3s)    │
                │              │ roles/security             │
                │              │ roles/flux   (bootstrap)   │
                │              └───────┬────────────────────┘
                ▼                      ▼
┌──────────────────────────────────────────────────────────┐
│                      GOOGLE CLOUD (GCE)                  │
│                                                          │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   │
│   │   node-01   │   │   node-02   │   │   node-03   │   │
│   │  (control)  │   │  (worker)   │   │  (worker)   │   │
│   │             │   │             │   │             │   │
│   │  k3s server │   │  k3s agent  │   │  k3s agent  │   │
│   │  flux-system│   │             │   │             │   │
│   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   │
│          └─────────────────┴─────────────────┘          │
│                        Flannel CNI                       │
│                   NetworkPolicies enforced               │
│                                                          │
│   VPC Firewall: 22 (SSH)  6443 (API)  80/443 (ingress)   │
└───────────────────────────┬──────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                             KUBERNETES CLUSTER                                  │
│                                                                                 │
│   ┌───────────────────────────────────────────────────────────────────────┐     │
│   │   namespace: flux-system                                              │     │
│   │                                                                       │     │
│   │   Flux  ──── git pull (reconcile loop, 60s) ◄──── GitHub repo         │     │
│   │   ├── GitRepository CR                                                │     │
│   │   └── Kustomization CR                                                │     │
│   │     │                                                                 │     │
│   └─────┼─────────────────────────────────────────────────────────────────┘     │
│         │ deploys / reconciles                                                  │
│         ├─────────────────────────────────────────────────────┐                 │
│         │                                                     │                 │
│         ▼                                                     ▼                 │
│   ┌──────────────────────────────────┐   ┌───────────────────────────────┐      │
│   │   namespace: postgres            │   │   namespace: demo-app         │      │
│   │                                  │   │                               │      │
│   │   CloudNativePG Operator         │   │   Adminer (Deployment)        │      │
│   │                                  │   │   ├── 1 replica               │      │
│   │   Cluster CR                     │   │   ├── envFrom: secret         │      │
│   │   ├── pg-1  (primary)  ──────────────────► connects to Postgres      │      │
│   │   ├── pg-2  (replica)            │   │   └── Ingress / Service       │      │
│   │   └── pg-3  (replica)            │   └───────────────────────────────┘      │
│   │          │                       │                                          │
│   │   ScheduledBackup CR             │   ┌───────────────────────────────┐      │
│   │   └──► GCS bucket (barman)       │   │   namespace: monitoring       │      │
│   │                                  │   │                               │      │
│   │   PodMonitor CR                  │   │   Prometheus                  │      │
│   │   └──► Prometheus scrape         │   │   Grafana                     │      │
│   │                                  │   │   Alertmanager                │      │
│   │   Secrets via External Secrets   │   └───────────────────────────────┘      │
│   │   └──► Google Secret Manager     │                                          │
│   └──────────────────────────────────┘                                          │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

   GCS Bucket  ◄── CloudNativePG barman-cloud-backup (WAL + base backups)
```

---

## 🔄 GitOps Change Flow

Every change to the cluster goes through Git — no one runs `kubectl apply` by hand. Here's what happens from the moment you push code to the moment the cluster reflects it:

```
  Engineer              GitHub             flux-system            Cluster
     │                     │                    │                    │
     ├── git push ─────────►                    │                    │
     │                     ├── PR / review       │                    │
     │◄── merge approved ──┤                    │                    │
     │                     │◄── poll (60s) ─────┤                    │
     │                     ├── diff detected ───►                    │
     │                     │                    ├── reconcile ───────►
     │                     │                    │◄── ready ──────────
     │                     │                    │                    │
```

---

## ⬆️ PostgreSQL Minor Upgrade Flow

Upgrading Postgres is a Git operation. The operator handles the rolling restart with zero downtime — replicas restart first, then the primary fails over to a healthy replica before restarting itself:

```
  1. Engineer bumps imageName in Cluster CR and opens PR
  2. PR reviewed and merged to main
  3. Flux detects diff, reconciles Cluster CR to cluster
  4. CloudNativePG operator detects image change
  5. Rolling restart begins:
        replica pg-3  →  restart  →  healthy
        replica pg-2  →  restart  →  healthy
        primary pg-1  →  failover to pg-2  →  restart  →  rejoin as replica
  6. Zero downtime — replicas serve reads throughout
```

---

## 💾 Backup and Restore

Two mechanisms run in parallel to protect your data. WAL archiving gives you continuous coverage; base backups give you a faster restore starting point:

```
  BACKUP
  ──────
  ScheduledBackup CR  (e.g. daily 02:00 UTC)
  ├── WAL streaming  ─────────────────────────► GCS bucket
  └── base backup (barman-cloud-backup) ───────► GCS bucket

  RESTORE
  ───────
  1. Create new Cluster CR with:
         bootstrap:
           recovery:
             source: cluster-backup
             recoveryTarget:
               targetTime: "2026-03-15T03:00:00Z"
  2. CloudNativePG pulls base backup from GCS
  3. CloudNativePG replays WAL up to target time
  4. Cluster comes online at point-in-time
```
