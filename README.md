# 🛠️ DevOps Infrastructure - Projet Proxmox / Terraform / Ansible / Bash

Ce dépôt regroupe l’ensemble des outils et configurations utilisés pour automatiser le déploiement, l’installation et le durcissement de machines virtuelles Linux dans un environnement basé sur **Proxmox**, **Terraform**, **Ansible** et des **scripts shell**.

---

## 📁 Structure du projet

```bash
devops-infra/
├── ansible/            # Playbooks et rôles Ansible
├── proxmox/            # Configs spécifiques à Proxmox (réseau, cloud-init, etc.)
├── docker/             # Fichier de configuration de conteneur Docker
├── kubernetes/         # Fichier de configuration de Kubernetes (minikube)
├── terraform/          # Fichiers Terraform pour provisionnement VM
├── scripts-bash/       # Scripts shell de configuration et de hardening
└── README.md
```

---

## 📦 Contenu du projet

### 1. 🧩 `ansible-playbooks/` – Déploiement & durcissement sous Arch Linux

Ce dossier contient :

* Des **playbooks Ansible** pour installer et configurer **Arch Linux**.
* Des rôles pour automatiser le **durcissement de sécurité** (SSH, firewall, sudo, etc.).
* L’automatisation de certaines étapes post-installation (utilisateurs, paquets, journaux, etc.).

📌 Objectif : Déployer rapidement une Arch Linux durcie et prête à l’emploi.

---

### 2. 🖥️ `proxmox/` – Configuration initiale de l’hyperviseur

Ce dossier contient :

* Des **scripts et notes** pour :

  * Configurer le **réseau Proxmox** (`/etc/network/interfaces`)
  * Créer une **template Cloud-Init Ubuntu/Debian**
  * Ajouter les fichiers **cloud-init snippets** (`user-data` / `meta-data`)
* Aide à la **préparation de l’environnement** avant d’utiliser Terraform

📌 Objectif : Préparer Proxmox pour être utilisé en tant que backend de provisionnement automatique.

---

### 3. ☁️ `terraform/` – Provisionnement de VM Cloud-Init

Ce dossier contient :

* Des fichiers Terraform (`main.tf`, `variables.tf`, `outputs.tf`) pour :

  * Créer une VM basée sur une **template cloud-init Ubuntu**
  * Utiliser un **provider Proxmox API**
  * Intégrer les fichiers `user_data` et `meta_data`
  * Gérer le réseau, les disques, le nom d’hôte, les tags, etc.

📌 Objectif : Automatiser la création de machines virtuelles sur Proxmox à partir d’une **infrastructure as code**.

---

### 4. ⚙️ `scripts-bash/` – Scripts Shell de configuration et de sécurité

Ce dossier contient :

* Des **scripts bash** utiles à l’installation et configuration de systèmes Linux
* Des scripts de **hardening** (sécurité SSH, désactivation root, fail2ban, auditd, etc.)
* Possibilité de les utiliser standalone ou dans une VM cloud-init post-installation

📌 Objectif : Offrir des scripts simples et portables pour les environnements non automatisés par Ansible.

---

## ✅ Prérequis

* Proxmox VE (7.x ou 8.x)
* Terraform >= 1.5
* Ansible >= 2.14
* Accès SSH/API à Proxmox
* Une template cloud-init prête dans Proxmox

---

## 🚀 À venir

* Ajout de templates cloud-init pour **Debian** et **Arch Linux**
* Déploiement multi-VM avec Terraform
* Intégration CI/CD pour tests automatiques
* Support de configuration réseau VLAN/VXLAN

---

## 📄 Licence

Ce projet est open-source, sous licence MIT. Utilisation libre pour vos labs ou environnements de production avec attribution.

---

## 🙋 Contact

Tu peux me contacter via \[GitHub Issues] ou directement depuis ce dépôt pour toute amélioration, question ou bug.

```