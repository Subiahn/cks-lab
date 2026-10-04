# 트러블슈팅

환경: macOS (Apple Silicon), Multipass 1.16.4, zsh.

## `multipass exec` 가 멈춘 것처럼 보임 (CPU 99%)

**증상**: 스크립트가 `multipass exec cp1 -- cloud-init status --wait`, `multipass exec cp1 -- kubectl get node w1` 같은 줄에서 몇 분째 진행되지 않음. 직접 터미널에서 같은 명령을 치면 바로 끝남.

**관찰된 사실**: 출력을 `>/dev/null 2>&1`로 버리는 형태로 실행했을 때 `multipass exec`가 멈춘 게 아니라 **CPU를 99% 쓰며 헛돌았음**.

```
multipass exec cp1 -- kubectl get node w1 > /dev/null 2>&1  12.68s user 145.65s system 99% cpu 2:38.51 total
```

**시도했으나 효과 없었던 것**: `</dev/null`로 stdin만 막기 (같은 지점에서 다시 멈춤).

**적용한 해결**: 스크립트에서 `multipass exec` 출력을 `/dev/null`로 보내는 호출을 모두 없애고, 출력을 변수로 받아서 판단하도록 변경. 모든 `multipass` 호출은 래퍼 함수로 stdin을 막고 파이프를 거치게 함.

```bash
multipass() { command multipass "$@" </dev/null 2> >(cat >&2) | cat; }
```

이 방식으로 바꾼 뒤 `up`이 끝까지 완료됨. **근본 원인은 확인하지 못했습니다.** 직접 스크립트를 쓸 때는 `multipass exec`의 출력을 `/dev/null`로 리다이렉트하지 않는 게 안전해 보입니다.

멈췄을 때 걸린 명령만 종료하려면:

```bash
ps -o pid,etime,command -g $(ps -o pgid= -p $(pgrep -f cks-lab.sh | head -1) | tr -d ' ') | cat
kill <PID>
```

## `multipass shell` 시 `No route to host`

VM 생성 직후 SSH가 아직 준비되지 않아서 나오는 일시적 오류입니다. 잠시 후 다시 시도하세요. 스크립트는 `cloud-init status` 폴링으로 대기합니다.

## ssh 접속이 안 됨 (재시작 후)

VM IP가 바뀌었을 수 있습니다.

```bash
./cks-lab.sh ssh-config
```

## zsh에 붙여넣으면 `command not found: Name` 같은 에러

코드 블록의 `# 주석`이 같이 실행되는 경우입니다. zsh는 기본값에서 대화형 주석을 허용하지 않습니다.

```bash
setopt interactive_comments     # ~/.zshrc 에 추가하면 영구 적용
```

## OrbStack Linux 머신에서 AppArmor 불가

```
$ cat /sys/module/apparmor/parameters/enabled
cat: ...: No such file or directory
$ sudo aa-status
apparmor not present.
$ uname -r
7.0.14-orbstack-...
```

OrbStack 머신은 OrbStack이 관리하는 공유 커널을 사용하며 AppArmor가 없습니다. CKS의 AppArmor 주제를 연습하려면 자체 Ubuntu 커널을 쓰는 VM(Multipass 등)이 필요합니다.

## 스냅샷

```bash
multipass list --snapshots
```

스냅샷은 VM이 **중지된 상태에서** 만들어야 하고, 노드 쌍은 같은 이름으로 만들어야 같이 복구할 수 있습니다.
