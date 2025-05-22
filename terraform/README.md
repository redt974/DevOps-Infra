# Terraform & Proxmox :

## - cloud-init/user_data :

```
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/vm-access_id_rsa -C "vm-access"
cat ~/.ssh/vm-access_id_rsa.pub
```

Cela crée : ~/.ssh/id_rsa (privée) et ~/.ssh/id_rsa.pub (publique)

Ajoute le contenu de ~/.ssh/id_rsa.pub dans le champ ssh_authorized_keys du fichier user_data :

```
ssh_authorized_keys:
    - $(cat ~/.ssh/vm-access_id_rsa.pub)
```

## - Cle SSH (Admin - Proxmox) :

### 1. Générer une paire de clés SSH (privée + publique)

Dans ton terminal Debian, tape :

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa_terraform -C "terraform key"
```

* Cela crée deux fichiers :

  * `~/.ssh/id_rsa_terraform` (clé privée)
  * `~/.ssh/id_rsa_terraform.pub` (clé publique)

---

### 2. Copier la clé publique sur le serveur Proxmox

Si tu peux te connecter en SSH à Proxmox, fais :

```bash
ssh-copy-id -i ~/.ssh/id_rsa_terraform.pub root@192.168.10.180
```

Sinon, manuellement :

* Ouvre le fichier `~/.ssh/id_rsa_terraform.pub` avec un éditeur ou `cat ~/.ssh/id_rsa_terraform.pub`.
* Connecte-toi sur Proxmox en SSH avec ton user admin (exemple : root).
* Édite le fichier `~/.ssh/authorized_keys` dans le dossier `~/.ssh/` de cet utilisateur, et colle la clé publique (une ligne) à la fin du fichier.
* Assure-toi que les permissions sont correctes :

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

---

### 3. Charger la clé privée dans l'agent SSH local

Pour que Terraform puisse utiliser la clé, charge-la dans ssh-agent :

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa_terraform
```

Pour vérifier que la clé est bien chargée :

```bash
ssh-add -L
```

Tu dois voir la clé publique affichée.

---

### 4. Teste la connexion SSH manuellement

Avant de relancer Terraform, teste que tu peux te connecter sans mot de passe :

```bash
ssh -i ~/.ssh/id_rsa_terraform root@192.168.10.180
```

Tu ne dois pas être invité à entrer de mot de passe.

### 5. Charger les variables d'environnement

```bash
set -a
source .env
set +a
```

---

### 6. Lance Terraform

Maintenant, relance :

```bash
terraform plan
```