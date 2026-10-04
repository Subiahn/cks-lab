# CKS Lab (macOS + Multipass)

CKS(Certified Kubernetes Security Specialist) 시험 준비용 **kubeadm 클러스터를 맥에서 한 번에 만드는 스크립트**입니다.
Multipass로 Ubuntu VM을 만들고, containerd + kubeadm + Calico까지 설치한 뒤, 시험처럼 `ssh <노드명>`으로 접속해 쓸 수 있게 구성합니다.

> 2026-10-04 기준으로 작성했습니다. 시험 환경 정보는 바뀔 수 있으니 응시 전에 [공식 문서](#공식-참고-자료)를 다시 확인하세요.

## 왜 VM인가 (kind / OrbStack이 아닌 이유)

CKS는 AppArmor, seccomp, kube-bench, Falco 같은 **커널/OS 레벨 주제**가 많습니다.

- **kind**: 노드가 컨테이너라 위 주제 대부분을 제대로 연습할 수 없음
- **OrbStack Linux 머신**: 직접 테스트한 결과 `apparmor not present` (공유 커널 `*-orbstack`, AppArmor 미지원)
- **Multipass VM**: Ubuntu 커널(`5.15.0-194-generic`)에서 `apparmor module is loaded`, 프로파일 37개 로드 확인

## 요구사항

- macOS (Apple Silicon에서 테스트: M 시리즈, 메모리 16GB)
- [Multipass](https://multipass.run) (`brew install multipass`, 테스트 버전 1.16.4)
- 여유 메모리 약 7GB (cp 4GB + worker 3GB)
- (선택) 맥의 `kubectl`

## 빠른 시작

```bash
git clone <this-repo>
cd cks-lab
chmod +x cks-lab.sh
./cks-lab.sh up        # 약 10~20분 (처음), 이어서 실행 가능
```

완료 후:

```bash
ssh cp1                # 시험처럼 노드에 접속 (맥 터미널 = base 노드 역할)
sudo -i                # 필요 시 root
k get nodes            # k alias + 자동완성
```

## 명령

| 명령 | 설명 |
|---|---|
| `./cks-lab.sh up` | 클러스터 생성. 이미 있는 VM/단계는 건너뛰고 이어서 진행 |
| `./cks-lab.sh status` | VM과 노드 상태 |
| `./cks-lab.sh ssh-config` | IP가 바뀌었을 때 ssh 설정 갱신 |
| `./cks-lab.sh restore [이름]` | 스냅샷 복구 (기본 `after-cluster`) |
| `./cks-lab.sh destroy` | VM 전부 삭제 (확인 후) |

## 구성

| 항목 | 값 |
|---|---|
| VM | `cp1` (2 CPU / 4G / 20G), `w1` (2 CPU / 3G / 20G) |
| OS | Ubuntu 22.04 (arm64) |
| Kubernetes | v1.35 (`K8S_MINOR`로 변경 가능) |
| 런타임 | containerd (`SystemdCgroup = true`), `crictl` 설정 |
| CNI | Calico v3.32.2 (NetworkPolicy 적용용) |
| Pod CIDR | `192.168.0.0/16` |

### 환경변수

```bash
K8S_MINOR=v1.36 ./cks-lab.sh up              # 다른 버전 (예: kubeadm upgrade 연습용)
WORKERS="w1 w2" ./cks-lab.sh up              # worker 2대 (16GB 맥에서는 비추천)
CALICO_VERSION=v3.32.2 SNAPSHOT=0 ./cks-lab.sh up
```

## 스냅샷

`up` 중에 두 시점의 스냅샷을 자동으로 만듭니다.

- `before-init`: 노드 설정만 끝난 상태 (kubeadm init 이전)
- `after-cluster`: 클러스터 완성 직후

```bash
multipass list --snapshots          # 확인
./cks-lab.sh restore after-cluster  # 망가뜨린 뒤 복구
```

복구하면 그 이후 작업은 모두 사라집니다.

## 시험 환경과의 대응

공식 문서([Important Instructions: CKS](https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks), 2026-10-04 확인) 기준입니다.

| 시험 환경 (공식) | 이 랩 |
|---|---|
| Kubernetes v1.35 | v1.35 |
| 지정된 노드에 `ssh <노드명>`으로 접속, `sudo -i`로 권한 상승 | 맥이 base, `ssh cp1` / `ssh w1`, `sudo -i` |
| 노드에 `kubectl`(`k` alias, 자동완성), `yq`, `curl`, `wget`, `man` 사전 설치 | 동일하게 설치 |
| 15~20 문제, 2시간, 합격 67% | - |

**의도적으로 하지 않은 것**: vim 설정, `export do="--dry-run=client -o yaml"` 같은 변수/alias.
시험 시작 직후 직접 세팅하는 연습을 하기 위해서입니다.

**공식 문서에서 확인하지 못한 것**:

- 시험 클러스터의 **CNI 종류**. 이 랩은 NetworkPolicy를 지원하는 Calico를 선택했습니다.
- 시험 노드의 **OS 종류/버전, CPU 아키텍처**. 이 랩은 Ubuntu 22.04 arm64입니다.
- 시험 노드에 Trivy, kube-bench, Falco 등이 미리 설치되어 있는지. 이 랩은 설치하지 않았으니 도메인별 학습 때 직접 설치하며 연습하세요.

## 주의

- 시험 응시 환경(내 PC)은 공식적으로 **VM에서 응시할 수 없습니다.** 이 랩은 연습용입니다.
- 쿠버네티스 버전 등은 시험 직전 [FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks)에서 다시 확인하세요.
- 스크립트는 `~/.ssh/cks_ed25519`(키), `~/.ssh/cks_config`, `~/.ssh/config` 최상단의 `Include` 한 줄, `~/.kube/cks-config`를 만듭니다. 삭제하려면 `./cks-lab.sh destroy` 후 `Include ~/.ssh/cks_config` 줄을 직접 지우세요.

## 문서

- [docs/study-plan.md](docs/study-plan.md): 학습 계획과 시간 배분
- [docs/troubleshooting.md](docs/troubleshooting.md): 겪었던 문제와 해결

## 공식 참고 자료

- [Important Instructions: CKS](https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks)
- [FAQ: CKA, CKAD & CKS](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks)
- [시험 중 허용되는 자료 (CKS)](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed#certified-kubernetes-security-specialist-cks)
