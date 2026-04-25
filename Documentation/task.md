# **Enclaive Lead Infrastructure Engineer – Home Challenge**

**Important Notes**:

1. We do not expect from you any prior experience with confidential computing (CC). Think of anything that works now, works identically with CC.  
2. Please use LLMs as you would use in daily work. However, document (either in the code, or in a code of LLM conduct, when you used the LLM).

## **Delivery**

Please provide a link to a github repository containing  the solution(s).

1. Add code  
2. Add Readme   
3. Add Time table with required time per relevant sub-task  
4. Add leadership answers

## **Context**

At Enclaive we deploy **secure confidential cloud environments** across:

* Bare metal servers in datacenters  
* Private clouds  
* Public clouds

Installations must be:

* **Fully automated**  
* **GitOps-driven**  
* **Reproducible**  
* **Secure by default**

Infrastructure team deploy environments using:

* Terraform  
* Ansible  
* Docker  
* Helm  
* Kubernetes operators

You will lead a team of **3 DevOps engineers** responsible for deploying and operating these environments.

# **Challenge Overview**

Design and partially implement a **GitOps-based infrastructure platform** capable of deploying a **Kubernetes environment with an operator-managed stateful service**.

The goal is to demonstrate:

* Infrastructure architecture  
* Automation quality  
* Kubernetes operations maturity  
* GitOps practices  
* Operational thinking

# **Scenario**

A customer wants to deploy a **secure Kubernetes platform** capable of hosting applications with **stateful services**. Your team must build a **GitOps-driven deployment repository** that:

1. Provisions infrastructure  
2. Installs Kubernetes  
3. Deploys an operator  
4. Uses the operator to manage a production-ready stateful service  
5. Demonstrates lifecycle management (monitoring, backup, upgrades)

# **Requirements**

## 1\. Infrastructure Provisioning (Terraform)

Provision infrastructure using Terraform.

You may choose one environment:

* Public cloud (e.g AWS)  
* Bare Metal (e.g. Hetzner)  
* Local VMs

Minimum infrastructure:

* 3 Kubernetes nodes  
* networking  
* SSH access  
* firewall configuration

Terraform requirements:

* modular design  
* environment separation (dev / prod)  
* reusable modules

Example structure:

terraform/  
  modules/  
  environments/  
    dev/  
    prod/

## 2\. Node Configuration (Ansible)

Use **Ansible** to configure nodes and bootstrap Kubernetes.

Tasks include:

* install container runtime  
* install Kubernetes (e.g., k3s, talos or kubeadm)  
* configure networking  
* prepare cluster for GitOps

Structure example:

ansible/  
  roles/  
    base  
    kubernetes  
    security  
  playbooks/  
    bootstrap.yml

Playbooks should be:

* idempotent  
* modular  
* reusable

## 3\. GitOps Deployment

Deploy cluster applications via **GitOps**.

You may use:

* **Argo CD (preferred)**  
* **Flux**

GitOps responsibilities:

* install operators  
* manage application manifests  
* separate environments

Example structure:

gitops/  
  clusters/  
    dev  
    prod  
  infrastructure/  
  applications/

## 4\. Operator-Based Stateful Service

Instead of deploying a database via Helm, install and configure a **Kubernetes operator** that manages the lifecycle of a stateful service.

Recommended option:

* **CloudNativePG**

Alternative acceptable operators or an operator you used to work in the past:

* **Crunchy PostgreSQL for Kubernetes**

### Operator Requirements

The operator should manage:

#### Database cluster

Example:

* 3 PostgreSQL instances  
* persistent volumes  
* failover configuration

#### Backups

Configure automated backups:

* object storage  
* scheduled backups  
* restore procedure

Example targets:

* S3  
* MinIO

#### Monitoring

Expose metrics compatible with:

* Prometheus

Monitoring setup may include:

* ServiceMonitor  
* exporter

#### Upgrades

Demonstrate how upgrades would work:

* PostgreSQL minor upgrades  
* rolling restart  
* GitOps change management

## 5\. Example Application

Deploy a simple application that connects to the operator-managed database.

Example:

* containerized REST API  
* reads/writes data to Postgres

Application deployment should also be managed via GitOps.

### Example Repository Structure

enclaive-platform-challenge/

README.md

terraform/  
ansible/

gitops/  
  clusters/  
  operators/  
    postgres/  
  applications/  
    demo-app/

docs/  
  architecture.md

# 

# 

# 

# 

# 

# **Documentation**

Provide documentation describing:

### **Architecture**

* infrastructure layout  
* cluster architecture  
* GitOps workflow

### **Operational lifecycle**

Explain how the platform supports:

* database backup  
* database restore  
* upgrades  
* monitoring  
* scaling

### **Security considerations**

Discuss:

* secret management  
* access control  
* network policies

# 

# 

# 

# 

# **Leadership Component**

Provide short written answers (e.g. bullet points).

## **1\. Team Organization**

How would you organize a **team of 3 DevOps engineers** deploying this platform?

Topics:

* roles  
* review process  
* release management

## **2\. Multi-Environment Deployments**

How would you manage:

* customer-specific configurations  
* infrastructure variations  
* upgrades across customers?

## **3\. Reliability**

How would you ensure:

* repeatable deployments  
* automated testing  
* safe infrastructure changes?

## **4\. Security**

How would you ensure:

* Network security  
* Data security  
* Runtime security (i.e. while app runs)  
* Secrets Management  
* Access Management  
* Supply Chain Security

# **Evaluation Criteria**

You will be evaluated on:

### **Infrastructure Engineering**

* Terraform quality  
* Ansible automation  
* repository structure

### **Kubernetes Maturity**

* operator usage  
* stateful workloads  
* lifecycle management

### **GitOps Thinking**

* declarative infrastructure  
* reproducibility  
* environment separation

### **Operational Thinking**

* backup  
* monitoring  
* upgrades

### **Leadership Thinking**

* team organization  
* operational strategy

