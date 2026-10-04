#!/usr/bin/env bash
# CKS 실습 클러스터 원스텝 셋업 (macOS + Multipass)  -- v2
#
# v2 변경점:
#   - multipass exec 의 출력을 /dev/null 로 보내는 호출이 CPU 99%로 헛도는 문제가 있어서
#     그런 호출을 모두 제거 (출력은 변수로 받음) + multipass 래퍼(파이프 경유)
#   - cloud-init status --wait 대신 상태 폴링 (최대 5분, 진행 메시지 출력)
#   - 노드 Ready 대기도 kubectl wait 대신 직접 폴링, 진행 메시지 출력
#
# 시험 환경(LF 공식 문서 기준) 반영:
#   - Kubernetes v1.35
#   - 맥 터미널 = base 노드, 각 노드에는 `ssh <노드명>` 후 `sudo -i` 로 작업
#   - 노드에 kubectl(+ k alias, bash 자동완성), yq, curl, wget, man 설치
#   - vim 설정 / alias 등은 일부러 건드리지 않음 (시험 시작 직후 직접 세팅하는 연습용)
#
# 사용법:
#   ./cks-lab.sh up                 클러스터 생성 (이미 있으면 이어서 진행)
#   ./cks-lab.sh status             VM/노드 상태
#   ./cks-lab.sh ssh-config         IP가 바뀌었을 때 ssh 설정 갱신
#   ./cks-lab.sh restore [이름]     스냅샷 복구 (기본 after-cluster, 처음 상태는 before-init)
#   ./cks-lab.sh destroy            VM 전부 삭제
#
# 환경변수 예: K8S_MINOR=v1.36 WORKERS="w1 w2" ./cks-lab.sh up
set -euo pipefail

# multipass 호출은 항상 stdin 차단 + stdout 을 파이프로 통과시킴
multipass() { command multipass "$@" </dev/null 2> >(cat >&2) | cat; }

# ---------------- 설정 ----------------
K8S_MINOR="${K8S_MINOR:-v1.35}"
UBUNTU="${UBUNTU:-22.04}"
CP="${CP:-cp1}"
WORKERS="${WORKERS:-w1}"            # 공백으로 구분 (예: "w1 w2")
CP_CPU="${CP_CPU:-2}";  CP_MEM="${CP_MEM:-4G}"; CP_DISK="${CP_DISK:-20G}"
W_CPU="${W_CPU:-2}";    W_MEM="${W_MEM:-3G}";   W_DISK="${W_DISK:-20G}"
CALICO_VERSION="${CALICO_VERSION:-v3.32.2}"   # custom-resources 기본 Pod CIDR = 192.168.0.0/16
POD_CIDR="192.168.0.0/16"
SNAPSHOT="${SNAPSHOT:-1}"           # 1이면 스냅샷 생성
SSH_KEY="$HOME/.ssh/cks_ed25519"
KUBECONFIG_OUT="$HOME/.kube/cks-config"
ALL_NODES="$CP $WORKERS"

# ---------------- 유틸 ----------------
log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_multipass() { type -P multipass >/dev/null || die "multipass 가 없어요: brew install multipass"; }

vm_exists() { local out; out="$(multipass info "$1" 2>/dev/null)" && [ -n "$out" ]; }

run() { local n="$1"; shift; multipass exec "$n" -- "$@"; }

node_ip() { local out; out="$(run "$1" hostname -I)"; printf '%s\n' "$out" | awk '{print $1}'; }

wait_ready() {
  local n="$1" i st
  for i in $(seq 1 60); do
    st="$(multipass exec "$n" -- cloud-init status 2>/dev/null || true)"
    case "$st" in
      *done*|*error*|*degraded*) return 0 ;;
    esac
    echo "  $n 초기화 대기 중... ($i/60)"
    sleep 5
  done
  die "$n 초기화 대기 timeout"
}

wait_all() { local n; for n in $ALL_NODES; do wait_ready "$n"; done; }

snapshot_all() {
  local name="$1" n out
  [ "$SNAPSHOT" = "1" ] || return 0
  log "스냅샷 '$name' 생성 (VM을 잠시 중지해요)"
  multipass stop $ALL_NODES
  for n in $ALL_NODES; do
    if out="$(multipass snapshot "$n" --name "$name" 2>&1)"; then
      echo "  $n.$name 생성"
    else
      warn "$n.$name 생성 실패(이미 있을 수 있어요): $out"
    fi
  done
  multipass start $ALL_NODES
  wait_all
}

# ---------------- 노드 공통 설정 스크립트 (VM 안에서 실행) ----------------
write_node_script() {
  cat >"$1" <<'NODE_EOF'
#!/usr/bin/env bash
set -euo pipefail
K8S_MINOR="${K8S_MINOR:-v1.35}"
export DEBIAN_FRONTEND=noninteractive

echo "[node] swap off"
swapoff -a
sed -i '/\sswap\s/ s/^/#/' /etc/fstab

echo "[node] modules & sysctl"
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat >/etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo "[node] packages"
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl wget gpg containerd \
  bash-completion man-db manpages

echo "[node] containerd (SystemdCgroup=true)"
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "[node] kubeadm/kubelet/kubectl ${K8S_MINOR}"
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

echo "[node] yq"
ARCH="$(dpkg --print-architecture)"
curl -fsSL -o /usr/local/bin/yq \
  "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}"
chmod +x /usr/local/bin/yq

echo "[node] k alias + kubectl completion (시험 환경과 동일하게)"
if ! grep -q '# cks-lab k alias' /etc/bash.bashrc; then
  cat >>/etc/bash.bashrc <<'EOF'
# cks-lab k alias
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  alias k=kubectl
  complete -o default -F __start_kubectl k
fi
EOF
fi
echo "[node] done"
NODE_EOF
}

node_ready_for_k8s() {
  local out
  out="$(run "$1" bash -c 'command -v kubeadm; command -v yq' 2>/dev/null || true)"
  printf '%s\n' "$out" | grep -q kubeadm && printf '%s\n' "$out" | grep -q yq
}

setup_nodes() {
  local tmp n
  tmp="$(mktemp)"; write_node_script "$tmp"
  for n in $ALL_NODES; do
    if node_ready_for_k8s "$n"; then
      echo "  $n: 이미 설정됨, 건너뜀"; continue
    fi
    log "$n 노드 설정 (3~5분, apt 로그가 흘러요)"
    multipass transfer "$tmp" "$n:/tmp/node-setup.sh"
    run "$n" sudo K8S_MINOR="$K8S_MINOR" bash /tmp/node-setup.sh
  done
  rm -f "$tmp"
}

# ---------------- 클러스터 ----------------
cp_initialized() {
  local out
  out="$(run "$CP" sudo ls /etc/kubernetes/admin.conf 2>/dev/null || true)"
  printf '%s\n' "$out" | grep -q admin.conf
}

init_cp() {
  if cp_initialized; then
    echo "  $CP: 이미 kubeadm init 됨, 건너뜀"; return 0
  fi
  local ip; ip="$(node_ip "$CP")"
  log "kubeadm init ($CP, $ip)"
  run "$CP" sudo kubeadm init --pod-network-cidr="$POD_CIDR" --apiserver-advertise-address="$ip"
  run "$CP" bash -c 'mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config'
  # sudo -i (root) 에서도 kubectl 이 바로 동작하도록
  run "$CP" sudo bash -c 'mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config'
}

node_joined() {
  local out
  out="$(run "$CP" kubectl get nodes -o name 2>/dev/null || true)"
  printf '%s\n' "$out" | grep -qx "node/$1"
}

join_workers() {
  local w join
  for w in $WORKERS; do
    if node_joined "$w"; then
      echo "  $w: 이미 조인됨, 건너뜀"; continue
    fi
    log "$w 조인"
    join="$(run "$CP" sudo kubeadm token create --print-join-command)"
    run "$w" sudo bash -c "$join"
  done
}

calico_installed() {
  local out
  out="$(run "$CP" kubectl get ns -o name 2>/dev/null || true)"
  printf '%s\n' "$out" | grep -qx "namespace/calico-system"
}

install_cni() {
  if calico_installed; then
    echo "  Calico 이미 설치됨, 건너뜀"; return 0
  fi
  local base="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests" out
  log "Calico ${CALICO_VERSION} 설치"
  # 버전에 따라 operator-crds.yaml 이 별도로 있을 수 있어요 (없으면 무시)
  out="$(run "$CP" kubectl apply --server-side --force-conflicts -f "$base/operator-crds.yaml" 2>&1 || true)"
  run "$CP" kubectl apply --server-side --force-conflicts -f "$base/tigera-operator.yaml"
  run "$CP" kubectl apply -f "$base/custom-resources.yaml"
}

wait_nodes_ready() {
  log "모든 노드 Ready 대기 (최대 10분)"
  local total i out ready
  total="$(printf '%s\n' $ALL_NODES | wc -l | tr -d ' ')"
  for i in $(seq 1 60); do
    out="$(run "$CP" kubectl get nodes --no-headers 2>/dev/null || true)"
    ready="$(printf '%s\n' "$out" | awk '$2=="Ready"' | wc -l | tr -d ' ')"
    echo "  Ready $ready/$total ($i/60)"
    if [ "$ready" -ge "$total" ]; then
      run "$CP" kubectl get nodes -o wide
      return 0
    fi
    sleep 10
  done
  warn "노드가 Ready 가 되지 않았어요. 'ssh $CP' 후 'k get pods -A' 로 확인하세요."
}

# ---------------- 맥 쪽 설정 (base 노드 역할) ----------------
setup_ssh() {
  log "ssh 설정 (맥 = base 노드, 'ssh <노드명>' 으로 접속)"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  [ -f "$SSH_KEY" ] || ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C cks-lab >/dev/null
  local pub n ip cfg="$HOME/.ssh/cks_config"
  pub="$(cat "$SSH_KEY.pub")"
  : >"$cfg"
  for n in $ALL_NODES; do
    run "$n" bash -c "mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && (grep -qF '$pub' ~/.ssh/authorized_keys || echo '$pub' >> ~/.ssh/authorized_keys)"
    ip="$(node_ip "$n")"
    cat >>"$cfg" <<EOF
Host $n
  HostName $ip
  User ubuntu
  IdentityFile $SSH_KEY
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR

EOF
  done
  touch "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
  if ! grep -qF 'Include ~/.ssh/cks_config' "$HOME/.ssh/config"; then
    { echo 'Include ~/.ssh/cks_config'; echo; cat "$HOME/.ssh/config"; } >"$HOME/.ssh/config.tmp"
    mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
  fi
}

export_kubeconfig() {
  mkdir -p "$HOME/.kube"
  run "$CP" sudo cat /etc/kubernetes/admin.conf >"$KUBECONFIG_OUT"
  chmod 600 "$KUBECONFIG_OUT"
}

# ---------------- 명령 ----------------
cmd_up() {
  need_multipass
  local n
  for n in $ALL_NODES; do
    if vm_exists "$n"; then
      echo "  $n: 이미 존재"
    else
      log "$n VM 생성"
      if [ "$n" = "$CP" ]; then
        multipass launch "$UBUNTU" -n "$n" -c "$CP_CPU" -m "$CP_MEM" -d "$CP_DISK"
      else
        multipass launch "$UBUNTU" -n "$n" -c "$W_CPU" -m "$W_MEM" -d "$W_DISK"
      fi
    fi
  done
  wait_all
  setup_nodes

  if ! cp_initialized; then
    snapshot_all before-init
  fi

  init_cp
  join_workers
  install_cni
  wait_nodes_ready
  setup_ssh
  export_kubeconfig
  snapshot_all after-cluster
  setup_ssh   # 재시작 후 IP가 바뀌었을 수 있어서 갱신

  cat <<EOF

완료! 시험처럼 사용하는 방법:
  ssh $CP            # 노드 접속 (맥 터미널 = base)
  sudo -i            # 필요 시 root
  k get nodes        # k alias + 자동완성 동작

스냅샷: before-init(클러스터 만들기 직전), after-cluster(완성 직후)
  ./cks-lab.sh restore after-cluster
IP 가 바뀌어 ssh 가 안 되면: ./cks-lab.sh ssh-config
EOF
}

cmd_status() {
  need_multipass
  multipass list
  if [ -f "$KUBECONFIG_OUT" ]; then
    KUBECONFIG="$KUBECONFIG_OUT" kubectl get nodes -o wide || true
  fi
}

cmd_ssh_config() { need_multipass; wait_all; setup_ssh; export_kubeconfig; }

cmd_restore() {
  need_multipass
  local snap="${1:-after-cluster}" n
  log "스냅샷 '$snap' 으로 복구"
  multipass stop $ALL_NODES || true
  for n in $ALL_NODES; do
    multipass restore --destructive "$n.$snap"
  done
  multipass start $ALL_NODES
  wait_all
  setup_ssh
  export_kubeconfig
}

cmd_destroy() {
  need_multipass
  printf 'VM(%s)을 모두 삭제합니다. 계속할까요? [y/N] ' "$ALL_NODES"
  read -r ans
  [ "$ans" = "y" ] || { echo "취소"; exit 0; }
  multipass delete --purge $ALL_NODES || true
  rm -f "$HOME/.ssh/cks_config" "$KUBECONFIG_OUT"
}

case "${1:-up}" in
  up)         cmd_up ;;
  status)     cmd_status ;;
  ssh-config) cmd_ssh_config ;;
  restore)    shift; cmd_restore "$@" ;;
  destroy)    cmd_destroy ;;
  *) echo "usage: $0 {up|status|ssh-config|restore [snapshot]|destroy}"; exit 1 ;;
esac
