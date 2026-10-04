# CKS 학습 계획

목표: 2027년 1월 응시. 평일 30분, 주말 3시간(토/일 각각). 약 12주.

## 핵심 방향

- "YAML 수정 줄이기"보다 **자주 나오는 패턴을 문서 위치와 함께 몸에 익히기**가 중요합니다.
- 명령어로 만들 수 있는 건 명령어로, 안 되는 건 공식 문서에서 복사해서 수정합니다.
- apiserver 등 static pod manifest를 고칠 때는 **백업(`cp`)하고, 수정 후 `crictl ps`로 복구를 확인**합니다.
- 시험은 2시간, 15~20문제입니다. 모르는 문제는 넘기고 쉬운 것부터 점수를 쌓습니다.

## 전제 조건

- **응시 시점에 CKA가 유효해야 합니다.** 만료일을 Linux Foundation 마이페이지에서 확인하세요.
- 시험 일정은 미리 예약합니다.

## 시간 배분

| 시간 | 용도 |
|---|---|
| 평일 30분 | 전 주말 실습 복습, 명령어와 문서 위치 반복, 단일 문제 1~2개 (NetworkPolicy, seccomp 적용 등) |
| 토 3시간 | 새 주제 강의(약 1시간) + 따라 하기(약 2시간) |
| 일 3시간 | **강의 없이 혼자 재실습**(2시간) + 막힌 부분 정리(1시간) |

도구 실습(Falco, Trivy, kube-bench)과 클러스터를 망가뜨렸다 복구하는 연습은 주말에 합니다.

## 주차 계획 (초안)

| 기간 | 내용 |
|---|---|
| 10월 1~2주 | CKA 감 복구 + 시험 루틴 (vim 설정, `do` 변수, 컨텍스트 전환, `crictl`, `systemctl`/`journalctl`, static pod 수정/복구) |
| 10월 3주~11월 1주 | Cluster Setup + Hardening (NetworkPolicy, kube-bench, Ingress TLS, RBAC, ServiceAccount, 바이너리 검증, API 접근 제한) |
| 11월 2~3주 | System Hardening (AppArmor, seccomp, 불필요한 서비스/패키지/포트 정리) |
| 11월 4주~12월 1주 | Minimize Microservice Vulnerabilities (Pod Security Admission, Secret 암호화, RuntimeClass(gVisor), SecurityContext, pod-to-pod 암호화) |
| 12월 2주 | Supply Chain Security (Trivy, 이미지 정책, ImagePolicyWebhook, 정적 분석) |
| 12월 3주 | Monitoring/Logging/Runtime Security (Falco, Audit Policy, 컨테이너 불변성) |
| 12월 4주 | killer.sh 1회차 + 오답 정리 |
| 1월 1주 | 약한 도메인 반복, 북마크/검색 키워드 정리 |
| 1월 2주 | killer.sh 2회차 + 직전 점검 |

도메인이 밀리면 12월 4주 이전의 여유 기간을 버퍼로 씁니다.

> **주의**: 위 도메인 이름은 예전 커리큘럼 기준입니다. 현재 커리큘럼은 도메인 구성이 바뀌었고(pod-to-pod 암호화에 Cilium, Istio 언급 등) 변경 사항이 있을 수 있으니, CNCF 공식 커리큘럼 PDF와 강의 범위를 한 번 대조하세요.

## killer.sh

- CKS 등록 시 세션 2회 포함, 각 세션은 활성화 후 36시간 유효합니다.
- 실전보다 어렵게 나오므로 시간 압박과 약한 영역을 확인하는 용도로 씁니다.
- 한 번은 중간 진단, 한 번은 최종 점검에 씁니다. 풀이에 2시간 + 복습에 2~3시간이 필요하니 시간이 넉넉한 날에 시작합니다.

## 시험 직전 점검

- Kubernetes 버전 (공식 FAQ에서 확인)
- 허용 문서 목록
- 현재 CKS 커리큘럼 변경 사항
