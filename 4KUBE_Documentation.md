# **SUPINFO 4KUBE - Benjamin MAURY**  

## **Sommaire**  
1. [Introduction](#1-introduction) 
2. [Prérequis](#2-prérequis)
3. [Création des manifests Kubernetes](#3-création-des-manifests-kubernetes)  
4. [Configuration du cluster Kubernetes](#4-configuration-du-cluster-kubernetes)  
5. [Vérification des déploiements](#5-vérification-des-déploiements)
6. [Accès à l'application](#6-accès-à-lapplication)
7. [Conclusion](#7-conclusion)
8. [Sources](#8-sources)

---

## **1. Introduction** 

Pour ce mini-projet, on vous donne une application distribuée permettant de suivre en temps réel une flotte de véhicules effectuant des livraisons.

Cette application distribuée est composée des éléments suivants :

- fleetman-position-simulator : une application Spring Boot émettant en continu des positions fictives de véhicules.
- fleetman-queue : une queue Apache ActiveMQ qui reçoit puis transmet ces positions.
- fleetman-position-tracker : une application Spring Boot qui consomme ces positions reçues pour les stocker dans une base de données MongoDB. Elles sont ensuite disponibles via une API RESTful.
- fleetman-mongo : instance de la base de données MongoDB.
- fleetman-api-gateway : une API Gateway servant de point d'entrée pour l'application web
- fleetman-web-app : l'application web présentée précédemment.

---

## **2. Prérequis**  

- **Déployer l'application en local**
  - **Système d'exploitation** : Windows ou autres
  - **Outils nécessaires** :  
    - `docker`  

- **Cluster Kubernetes**
  - **Système d'exploitation** : Debian ou autre distribution Linux compatible  
  - **Cluster Kubernetes** : Créé avec `kubeadm` et `containerd`  
  - **Accès** : Utilisateur avec permissions administratives  
  - **Outils nécessaires** :  
    - `kubectl`  
    - `kubeadm`  

---

## **3. Création des manifests Kubernetes**

Création des fichiers YAML pour déployer tous les éléments de l'application (API, MongoDB ...). 

- fleetman-api-gateway.yaml
- fleetman-mongodb.yaml
- fleetman-position-simulator.yaml
- fleetman-position-tracker.yaml
- fleetman-queue.yaml
- fleetman-webapp.yaml

Chacun de ces manifests contiennent les deployments, les services et autres (pv, pvc) nécessaires au bon fonctionnement de l'application.

Et en plus présent, un script bash pour exécuter rapidement tous les manifests.
(!! Une modification des permissions du script est peut-être nécessaire sur votre machine !!).

---

## **4. Configuration du cluster Kubernetes**  

### **4.1. Création du cluster Kubernetes**  

Commandes à faire sur chaque nœuds du cluster (Master et Workers).

#### **4.1.1 Configurer DNS**  

Chaque machines virtuelles ont deux cartes réseaux (NAT & Host-only).
Voici la configuration des Host-only :

```bash
$ sudo nano /etc/hosts
```

```plaintext
    192.168.56.101 k8s-master
    192.168.56.102 k8s-worker1
    192.168.56.103 k8s-worker2
```

#### **4.1.2 Désactivation du Swap**

Pour que kubelet fonctionne correctement, il est recommandé de désactiver le swap :

```bash
$ sudo swapoff -a
$ sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

#### **4.1.3 Emulation de l'architecture ARM64**

```bash
apt-get install qemu-system qemu-user  qemu-user-static
```

#### **4.1.4 Installation de containerd**

Avant d'installer containerd, nous définissons les paramètres de noyau suivants :

```bash
$ cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

$ sudo modprobe overlay
$ sudo modprobe br_netfilter

$ cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

$ sudo sysctl --system
```

Installation de containerd :

```bash
$ sudo apt update
$ sudo apt -y install containerd
```

Pour configurer containerd pour qu'il fonctionne avec Kubernetes :

```bash
$ containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1

$ sudo systemctl restart containerd
$ sudo systemctl enable containerd
```

#### **4.1.4 Installation de Kubelet, Kubectl et Kubeadm**

Installer les paquets nécessaires à l'ajout du dépôt :

```bash
$ sudo apt install -y apt-transport-https ca-certificates curl gnupg
```

Téléchargez la clé de signature :

```bash
$ curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Ajoutez le dépôt APT Kubernetes :

```bash
$ echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Installation de Kubelet, Kubectl et Kubeadm :

```bash
$ sudo apt update
$ sudo apt install -y kubelet kubeadm kubectl
$ sudo apt-mark hold kubelet kubeadm kubectl
```

### **4.2 Configuration du Master**

Commandes à faire uniquement sur le nœud Master.

Maintenant, tout est prêts pour créer un cluster Kubernetes :

```bash
$ sudo kubeadm init --control-plane-endpoint=k8s-master
```

La sortie de cette commande confirme que le cluster a été initialisé avec succès.  
Dans la sortie, nous avons des commandes utilisateur pour interagir avec le cluster et également la commande pour joindre n'importe quel nœud de travail à ce cluster.

Pour commencer à interagir avec le cluster, il faut suivre ces commandes :

```bash
$ mkdir -p $HOME/.kube
$ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
$ sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

```bash
$ kubectl get nodes
$ kubectl cluster-info
```

### **4.3 Ajouter les nœuds de travail au cluster**

Sur chacun des nœuds de travail (k8s-worker1 et k8s-worker2), utiliser la commande récupérée précédemment suite à l'initialisation du cluster :

```bash
$ sudo kubeadm join k8s-master:6443 --token <votre-token> --discovery-token-ca-cert-hash sha256:<votre-hash>
```

### **4.4 Installer le moteur de politique réseau Calico**

A la fin de l'étape précédente, le statut des noeuds est NotReady.  
Afin de corriger cela, il faut installer un moteur de politique réseau, dans notre cas, nous allons installer Calico.

Sur le nœud maître, lancez la commande :

```bash
$ kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
```

---

## **5. Vérification des Déploiements**

Suite à la création et la configuration du cluster Kubernetes.  
Nous pouvons lancer nos manifests à l'intérieur de celui-ci.

Avec les commandes :

```bash
$ kubectl get pods
$ kubectl get services
```

Nous nous assurons que tout fonctionne correctement et est en "Running".  
Sinon il faut utiliser la commande :

```bash
$ kubectl logs <POD_NAME>
```
Pour voir ce qu'il se passe dans le pod.

---

## **6. Accès à l'application**

Si l'application tourne en local sous Windows ou autres avec Docker.  
Il faut utiliser ce lien :

```plaintext
http://localhost:30080
```

Si l'application tourne sous le cluster Kubernetes.  
Il faut utiliser ce lien :

```plaintext
http://<master-ip>:30080
```

L'ip correspondante est l'ip de la carte NAT.  
Vérifiez la configuration IP de votre Master avec la commande :

```bash
$ ip a
```

---

## **7. Conclusion**

Cette documentation fournit les étapes nécessaires pour configurer un cluster Kubernetes, déployer les services et vérifier leur bon fonctionnement.

---

## **8. Sources**

Lien vers le tutoriel utilisé pour la création du cluster Kubernetes : https://gitlab.agglo-lepuyenvelay.fr/-/snippets/1036  
(Seules les étapes présentes dans cette documentation ont été faites)

Le tuto ci-dessus n'est pas à jour sur la commande pour installer le package kubernetes.  
Il était anciennement hébergé par Google et maintenant il est hébergé par la communauté Kubernetes avec une nouvelle commande présent dans ce lien : https://kubernetes.io/blog/2023/08/15/pkgs-k8s-io-introduction/